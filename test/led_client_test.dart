import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:controle_led/led_client.dart';

void main() {
  test('Public hosts and invalid state cannot become local control targets', () {
    expect(isLocalAddress('8.8.8.8'), false);
    expect(isLocalAddress('example.com'), false);
    expect(isLocalAddress('172.32.1.1'), false);
    expect(isLocalAddress('192.168.31.89'), true);
    expect(isLocalAddress('172.16.1.1'), true);
    expect(() => LedState.fromJson({...const LedState().toJson(), 'ledCount': 0}), throwsFormatException);
    expect(() => LedState.fromJson({...const LedState().toJson(), 'brightness': 999}), throwsFormatException);
  });

  test('A different HTTP device is rejected instead of receiving LED commands', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.write(jsonEncode({'name': 'Other device', 'id': 'other'}));
      request.response.close();
    });
    try {
      await expectLater(LedClient(port: server.port).identify('127.0.0.1'), throwsFormatException);
    } finally { await server.close(force: true); }
  });

  test('LED write uses PUT and consumes the confirmed state returned by firmware', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final expected = const LedState(power: true, effect: 'rainbow', ledCount: 10);
    server.listen((request) async {
      expect(request.method, 'PUT');
      expect(request.uri.path, '/api/state');
      final sent = jsonDecode(await utf8.decoder.bind(request).join());
      expect(sent['effect'], 'rainbow');
      request.response.write(jsonEncode(expected.copyWith(brightness: 80).toJson()));
      await request.response.close();
    });
    try {
      final result = await LedClient(port: server.port).write('127.0.0.1', expected);
      expect(result.power, true); expect(result.brightness, 80);
      expect(result.ledCount, 10);
    } finally { await server.close(force: true); }
  });
}
