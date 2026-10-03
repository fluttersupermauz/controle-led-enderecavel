import 'dart:async';
import 'dart:convert';
import 'dart:io';

const effects = <String, String>{
  'solid': 'Cor fixa',
  'rainbow': 'Arco-íris',
  'pulse': 'Respiração',
  'chase': 'Luz em movimento',
};

bool isLocalAddress(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null || address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  return bytes[0] == 10 ||
      bytes[0] == 127 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);
}

class LedState {
  const LedState({
    this.power = false,
    this.brightness = 96,
    this.red = 255,
    this.green = 96,
    this.blue = 24,
    this.effect = 'solid',
    this.ledCount = 30,
  });
  final bool power;
  final int brightness, red, green, blue, ledCount;
  final String effect;

  factory LedState.fromJson(Map<String, dynamic> json) {
    int readInt(String name, int max, {int min = 0}) {
      final value = json[name];
      if (value is! int || value < min || value > max) {
        throw const FormatException('Estado inválido recebido da placa.');
      }
      return value;
    }

    if (json['power'] is! bool || !effects.containsKey(json['effect'])) {
      throw const FormatException('Estado inválido recebido da placa.');
    }
    return LedState(
      power: json['power'] as bool,
      brightness: readInt('brightness', 255, min: 1),
      red: readInt('red', 255),
      green: readInt('green', 255),
      blue: readInt('blue', 255),
      effect: json['effect'] as String,
      ledCount: readInt('ledCount', 300, min: 1),
    );
  }

  LedState copyWith({bool? power, int? brightness, int? red, int? green,
      int? blue, String? effect, int? ledCount}) => LedState(
    power: power ?? this.power,
    brightness: brightness ?? this.brightness,
    red: red ?? this.red,
    green: green ?? this.green,
    blue: blue ?? this.blue,
    effect: effect ?? this.effect,
    ledCount: ledCount ?? this.ledCount,
  );

  Map<String, dynamic> toJson() => {
    'power': power, 'brightness': brightness, 'red': red, 'green': green,
    'blue': blue, 'effect': effect, 'ledCount': ledCount,
  };
}

class LedDevice {
  const LedDevice(this.host, this.name, this.id);
  final String host, name, id;
}

class LedClient {
  LedClient({this.port = 80, this.timeout = const Duration(seconds: 4)});
  final int port;
  final Duration timeout;

  Future<Map<String, dynamic>> _request(String host, String path,
      {Map<String, dynamic>? data}) async {
    if (!isLocalAddress(host)) {
      throw const FormatException('Informe um IP da rede local, como 192.168.1.50.');
    }
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await (() async {
        final request = await client.openUrl(data == null ? 'GET' : 'PUT',
            Uri(scheme: 'http', host: host, port: port, path: path));
        request.followRedirects = false;
        if (data != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(data));
        }
        final response = await request.close();
        final bytes = <int>[];
        await for (final part in response) {
          bytes.addAll(part);
          if (bytes.length > 8192) {
            throw const FormatException('Resposta muito grande.');
          }
        }
        if (response.statusCode != 200) {
          throw HttpException('A placa recusou o comando (${response.statusCode}).');
        }
        final result = jsonDecode(utf8.decode(bytes));
        if (result is! Map<String, dynamic>) {
          throw const FormatException('Resposta inválida.');
        }
        return result;
      })().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Future<LedDevice> identify(String host) async {
    final info = await _request(host, '/api/info');
    if (info['protocol'] != 'ledctrl-v1' || info['name'] is! String || info['id'] is! String) {
      throw const FormatException('Este dispositivo não usa o firmware Controle LED.');
    }
    return LedDevice(host, info['name'] as String, info['id'] as String);
  }

  Future<LedState> read(String host) async =>
      LedState.fromJson(await _request(host, '/api/state'));
  Future<LedState> write(String host, LedState value) async =>
      LedState.fromJson(await _request(host, '/api/state', data: value.toJson()));

  Future<List<LedDevice>> discover() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final candidates = <String>{};
    StreamSubscription<RawSocketEvent>? listener;
    try {
      socket.broadcastEnabled = true;
      listener = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? packet;
        while ((packet = socket.receive()) != null) {
          try {
            final message = jsonDecode(utf8.decode(packet!.data));
            if (message is Map && message['protocol'] == 'ledctrl-v1' &&
                isLocalAddress(packet.address.address)) {
              candidates.add(packet.address.address);
            }
          } on FormatException {
            // Ignore unrelated UDP messages on the shared LAN.
          }
        }
      });
      final message = utf8.encode('LEDCTRL_DISCOVER_V1');
      for (var attempt = 0; attempt < 3; attempt++) {
        socket.send(message, InternetAddress('255.255.255.255'), 4210);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    } finally {
      await listener?.cancel();
      socket.close();
    }
    final devices = await Future.wait(candidates.map((host) async {
      try { return await identify(host); } catch (_) { return null; }
    }));
    return devices.whereType<LedDevice>().toList();
  }
}
