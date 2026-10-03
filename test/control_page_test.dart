import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:controle_led/main.dart';

void main() {
  testWidgets('Without hardware, demo enables controls and power can be switched off', (tester) async {
    await tester.pumpWidget(const LedApp());
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
    await tester.tap(find.text('Experimentar demonstração'));
    await tester.pump();
    expect(find.text('Demonstração • sem enviar comandos'), findsOneWidget);
    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Small screen does not overflow and Alexa limitations are reachable', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const LedApp());
    await tester.tap(find.byTooltip('Sobre Alexa'));
    await tester.pumpAndSettle();
    expect(find.text('Alexa no protótipo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
