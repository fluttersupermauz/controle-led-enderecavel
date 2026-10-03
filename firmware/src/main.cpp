#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <WiFiUdp.h>
#include <WiFiManager.h>
#include <LittleFS.h>
#include <Adafruit_NeoPixel.h>
#include <ArduinoJson.h>
#define ESPALEXA_MAXDEVICES 1
#include <Espalexa.h>

constexpr uint8_t LED_PIN = D2; // GPIO4 -> 74AHCT125 -> DIN
constexpr uint16_t MAX_LEDS = 300;
constexpr uint8_t OUTPUT_CAP = 128; // Prototype ceiling: 50% of electrical brightness.
uint16_t ledCount = 30;
uint8_t brightness = 96, red = 255, green = 96, blue = 24;
bool powerOn = false;
String effect = "solid";
String chipId;
Adafruit_NeoPixel pixels(30, LED_PIN, NEO_GRB + NEO_KHZ800);
ESP8266WebServer server(80);
WiFiUDP discovery;
Espalexa alexa;
EspalexaDevice* alexaDevice = nullptr;
unsigned long lastFrame = 0;
uint16_t frame = 0;
bool repaint = true;

bool validEffect(const String& name) {
  return name == "solid" || name == "rainbow" || name == "pulse" || name == "chase";
}

String stateJson() {
  StaticJsonDocument<256> doc;
  doc["power"] = powerOn; doc["brightness"] = brightness;
  doc["red"] = red; doc["green"] = green; doc["blue"] = blue;
  doc["effect"] = effect; doc["ledCount"] = ledCount;
  String result; serializeJson(doc, result); return result;
}

String infoJson() {
  StaticJsonDocument<256> doc;
  doc["protocol"] = "ledctrl-v1";
  doc["name"] = "Fita LED";
  doc["id"] = chipId;
  doc["firmware"] = "0.1.0";
  doc["ip"] = WiFi.localIP().toString();
  doc["port"] = 80;
  String result; serializeJson(doc, result); return result;
}

void syncAlexa() {
  if (!alexaDevice) return;
  alexaDevice->setValue(powerOn ? brightness : 0);
  alexaDevice->setColor(red, green, blue);
}

void alexaChanged(EspalexaDevice* device) {
  powerOn = device->getValue() > 0;
  if (powerOn) brightness = device->getValue();
  const auto changed = device->getLastChangedProperty();
  if (changed == EspalexaDeviceProperty::hs || changed == EspalexaDeviceProperty::xy ||
      changed == EspalexaDeviceProperty::ct) {
    const auto rgb = device->getRGB();
    red = (rgb >> 16) & 0xff; green = (rgb >> 8) & 0xff; blue = rgb & 0xff;
    effect = "solid";
  }
  repaint = true;
}

void handleWrite() {
  const String body = server.arg("plain");
  if (body.length() > 1024) { server.send(413, "application/json", "{\"error\":\"body too large\"}"); return; }
  StaticJsonDocument<512> doc;
  if (deserializeJson(doc, body) || !doc["power"].is<bool>() ||
      !doc["brightness"].is<int>() || !doc["red"].is<int>() ||
      !doc["green"].is<int>() || !doc["blue"].is<int>() ||
      !doc["ledCount"].is<int>() || !doc["effect"].is<const char*>()) {
    server.send(400, "application/json", "{\"error\":\"invalid state\"}"); return;
  }
  int count = doc["ledCount"], br = doc["brightness"], r = doc["red"], g = doc["green"], b = doc["blue"];
  const String nextEffect = doc["effect"].as<String>();
  if (count < 1 || count > MAX_LEDS || br < 1 || br > 255 ||
      r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255 || !validEffect(nextEffect)) {
    server.send(400, "application/json", "{\"error\":\"state out of range\"}"); return;
  }
  if (count != ledCount) {
    // Clear the old physical tail before reducing the pixel buffer.
    pixels.clear(); pixels.show();
    pixels.updateLength(count);
    if (!pixels.getPixels()) {
      server.send(500, "application/json", "{\"error\":\"pixel allocation failed\"}");
      ESP.restart(); return;
    }
    ledCount = count;
    File config = LittleFS.open("/ledcount", "w");
    if (config) { config.print(ledCount); config.close(); }
  }
  powerOn = doc["power"]; brightness = br; red = r; green = g; blue = b;
  effect = nextEffect; frame = 0; repaint = true; syncAlexa();
  server.send(200, "application/json", stateJson());
}

void setup() {
  Serial.begin(115200);
  chipId = String(ESP.getChipId(), HEX);
  if (LittleFS.begin()) {
    File config = LittleFS.open("/ledcount", "r");
    if (config) {
      const int count = config.readString().toInt();
      if (count >= 1 && count <= MAX_LEDS) ledCount = count;
      config.close();
    }
  }
  pixels.updateLength(ledCount); pixels.begin(); pixels.clear(); pixels.show();
  WiFi.mode(WIFI_STA);
  WiFi.hostname(("controle-led-" + chipId).c_str());
  WiFiManager wifi;
  wifi.setDebugOutput(false); // No network credentials in serial logs.
  wifi.setConfigPortalTimeout(180);
  const String apName = "LED-Setup-" + chipId;
  if (!wifi.autoConnect(apName.c_str(), "ledprototipo")) { ESP.restart(); return; }
  WiFi.setAutoReconnect(true);
  discovery.begin(4210);
  server.on("/api/info", HTTP_GET, []() { server.send(200, "application/json", infoJson()); });
  server.on("/api/state", HTTP_GET, []() { server.send(200, "application/json", stateJson()); });
  server.on("/api/state", HTTP_PUT, handleWrite);
  server.on("/", HTTP_GET, []() {
    server.send(200, "text/plain; charset=utf-8", "Controle LED ESP8266. Use o aplicativo Android. API: /api/info e /api/state.");
  });
  server.onNotFound([]() {
    if (!alexa.handleAlexaApiCall(server.uri(), server.arg(0))) {
      server.send(404, "application/json", "{\"error\":\"not found\"}");
    }
  });
  alexaDevice = new EspalexaDevice("Fita LED", alexaChanged, EspalexaDeviceType::color, 0);
  alexa.addDevice(alexaDevice); syncAlexa();
  if (!alexa.begin(&server)) server.begin();
  Serial.print("IP da placa: "); Serial.println(WiFi.localIP());
}

void loop() {
  alexa.loop();
  const int size = discovery.parsePacket();
  if (size > 0) {
    char message[64] = {};
    const int length = discovery.read(message, sizeof(message) - 1);
    if (length > 0 && String(message) == "LEDCTRL_DISCOVER_V1") {
      const String response = infoJson();
      discovery.beginPacket(discovery.remoteIP(), discovery.remotePort());
      discovery.write(reinterpret_cast<const uint8_t*>(response.c_str()), response.length());
      discovery.endPacket();
    }
  }
  const auto now = millis();
  if (repaint || (powerOn && effect != "solid" && now - lastFrame >= 35)) {
    lastFrame = now; repaint = false;
    pixels.clear();
    if (powerOn) {
      // Logical 100% is capped electrically to 50% for the initial prototype.
      uint8_t level = static_cast<uint16_t>(brightness) * OUTPUT_CAP / 255;
      if (effect == "pulse") {
        const uint16_t phase = frame % 100;
        level = static_cast<uint16_t>(level) * (phase <= 50 ? phase * 2 : (100-phase) * 2) / 100;
      }
      pixels.setBrightness(level);
      const auto color = pixels.Color(red, green, blue);
      for (uint16_t i = 0; i < ledCount; i++) {
        if (effect == "rainbow") pixels.setPixelColor(i, pixels.ColorHSV(
          static_cast<uint16_t>(i * 65536UL / ledCount + frame * 256UL), 255, 255));
        else if (effect == "chase") pixels.setPixelColor(i, i == (frame / 3) % ledCount ? color : 0);
        else pixels.setPixelColor(i, color);
      }
      frame++;
    }
    pixels.show();
  }
  delay(1);
}
