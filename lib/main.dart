import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'led_client.dart';

void main() => runApp(const LedApp());

class LedApp extends StatelessWidget {
  const LedApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Controle LED', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff63efd0),
          brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xff0c1423),
      cardTheme: const CardThemeData(color: Color(0xff182336), elevation: 0),
    ),
    home: const ControlPage(),
  );
}

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});
  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> with WidgetsBindingObserver {
  final client = LedClient();
  final ipInput = TextEditingController();
  final countInput = TextEditingController(text: '30');
  LedState value = const LedState();
  LedDevice? device;
  List<LedDevice> devices = [];
  bool demo = false, busy = false, scanning = false, online = false;
  double? draggingBrightness;
  Timer? poller;
  int session = 0;
  bool active = true;
  bool get canControl => (demo || (device != null && online)) && !busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    poller = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) refresh();
  }
  @override
  void dispose() {
    session++;
    poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ipInput.dispose(); countInput.dispose();
    super.dispose();
  }

  void error(Object e) {
    if (!mounted) return;
    final text = e is FormatException ? e.message :
      e is TimeoutException ? 'A placa não respondeu. Confira o Wi-Fi e tente novamente.' :
      e is SocketException ? 'Não foi possível acessar a placa. Confira o Wi-Fi e o IP.' :
      e is HttpException ? e.message : 'Falha na comunicação com a placa.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> scan() async {
    setState(() => scanning = true);
    try {
      final result = await client.discover();
      if (!mounted) return;
      setState(() => devices = result);
      if (result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
            Text('Nenhuma placa encontrada. Você pode conectar pelo IP.')));
      }
    } catch (e) { error(e); }
    finally { if (mounted) setState(() => scanning = false); }
  }

  Future<void> connect(String host) async {
    final token = ++session;
    setState(() { busy = true; demo = false; online = false; device = null; });
    try {
      final found = await client.identify(host.trim());
      final state = await client.read(found.host);
      if (!mounted || token != session) return;
      setState(() {
        device = found; value = state; online = true;
        countInput.text = '${state.ledCount}';
      });
    } catch (e) { if (token == session) error(e); }
    finally { if (mounted && token == session) setState(() => busy = false); }
  }

  Future<void> refresh() async {
    if (!active || demo || busy || device == null) return;
    final host = device!.host;
    final token = session;
    // Serialize reads and writes: an older poll must not overwrite a new command.
    busy = true;
    try {
      final state = await client.read(host);
      if (!mounted || token != session) return;
      setState(() { value = state; online = true; });
    } catch (_) {
      if (mounted && token == session) setState(() => online = false);
    } finally {
      if (mounted && token == session) setState(() => busy = false);
    }
  }

  Future<void> send(LedState next) async {
    if (!canControl) return;
    if (demo) { setState(() => value = next); return; }
    final token = session;
    setState(() => busy = true);
    try {
      final confirmed = await client.write(device!.host, next);
      if (!mounted || token != session) return;
      setState(() { value = confirmed; online = true; });
    } catch (e) {
      if (mounted && token == session) {
        setState(() => online = false);
        error(e);
      }
    } finally { if (mounted && token == session) setState(() => busy = false); }
  }

  void startDemo() {
    session++;
    setState(() {
      demo = true; device = null; busy = false; online = false;
      value = const LedState(power: true); countInput.text = '30';
    });
  }

  void alexaHelp() => showDialog<void>(context: context, builder: (context) => AlertDialog(
    title: const Text('Alexa no protótipo'),
    content: const Text('O firmware usa Espalexa, que emula uma lâmpada Hue. '
      'Com um Echo compatível no mesmo Wi-Fi, peça: “Alexa, descobrir dispositivos”. '
      'O nome da luz será “Fita LED”. Você poderá testar ligar, desligar, brilho e cor.\n\n'
      'É uma integração experimental, sem certificação Amazon. A descoberta depende '
      'do modelo do Echo e da rede. Efeitos são selecionados pelo aplicativo. '
      'Um comando de cor na Alexa retorna ao efeito de cor fixa.'),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi'))],
  ));

  Widget panel(Widget child) => Card(child: Padding(padding: const EdgeInsets.all(20), child: child));

  @override
  Widget build(BuildContext context) {
    final color = Color.fromARGB(255, value.red, value.green, value.blue);
    final status = demo ? 'Demonstração • sem enviar comandos' :
      device == null ? 'Conecte uma placa ou experimente o app' :
      online ? '${device!.name} • ${device!.host}' : 'Placa sem resposta • tentando reconectar';
    return Scaffold(
      appBar: AppBar(title: const Text('Controle LED'), backgroundColor: Colors.transparent,
        actions: [IconButton(onPressed: alexaHelp, tooltip: 'Sobre Alexa', icon: const Icon(Icons.mic_none))]),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
          Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sua luz. Seu clima.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8), Text(status, key: const Key('status')),
            ])),
          panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('DISPOSITIVO', style: TextStyle(letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: scanning || busy ? null : scan,
              icon: scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
              label: Text(scanning ? 'Procurando na rede…' : 'Buscar ESP8266 no Wi-Fi')),
            for (final found in devices) ListTile(contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.router), title: Text(found.name), subtitle: Text(found.host),
              trailing: const Icon(Icons.chevron_right), onTap: busy ? null : () => connect(found.host)),
            const SizedBox(height: 12),
            TextField(controller: ipInput, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'IP da placa (opcional)', hintText: '192.168.1.50',
                border: const OutlineInputBorder(), suffixIcon: IconButton(tooltip: 'Conectar pelo IP',
                  onPressed: busy ? null : () => connect(ipInput.text), icon: const Icon(Icons.arrow_forward)))),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: busy ? null : startDemo, icon: const Icon(Icons.play_circle_outline),
              label: const Text('Experimentar demonstração')),
            if (busy) const LinearProgressIndicator(),
          ])),
          panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Iluminação'),
              subtitle: Text(value.power ? 'Ligada' : 'Desligada'), value: value.power,
              onChanged: canControl ? (on) => send(value.copyWith(power: on)) : null),
            const SizedBox(height: 12),
            AnimatedContainer(duration: const Duration(milliseconds: 300), height: 64,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
                color: value.power ? color.withValues(alpha: 0.12) : Colors.black26),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(12, (i) => Container(width: 14, height: 14,
                  decoration: BoxDecoration(shape: BoxShape.circle,
                    color: !value.power ? Colors.white12 : value.effect == 'rainbow' ?
                      HSVColor.fromAHSV(1, i * 30, 1, 1).toColor() : color,
                    boxShadow: value.power ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)] : [])))),
            ),
            const SizedBox(height: 20),
            Text('Brilho · ${((draggingBrightness ?? value.brightness.toDouble()) / 255 * 100).round()}%'),
            Slider(value: draggingBrightness ?? value.brightness.toDouble(), min: 1, max: 255,
              onChanged: canControl ? (v) => setState(() => draggingBrightness = v) : null,
              onChangeEnd: canControl ? (v) {
                setState(() => draggingBrightness = null);
                send(value.copyWith(brightness: v.round()));
              } : null),
            const Text('Cor'), const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              const Color(0xffff6020), Colors.redAccent, Colors.amber, Colors.greenAccent,
              Colors.cyanAccent, Colors.blueAccent, Colors.purpleAccent, Colors.white,
            ].map((c) => Semantics(label: 'Cor ${c.toARGB32().toRadixString(16)}', button: true,
              child: InkWell(onTap: canControl ? () => send(value.copyWith(
                  red: (c.r * 255).round(), green: (c.g * 255).round(), blue: (c.b * 255).round())) : null,
                borderRadius: BorderRadius.circular(24), child: Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle,
                    border: Border.all(color: color == c ? Colors.white : Colors.transparent, width: 3)))))).toList()),
            const SizedBox(height: 16),
            Text('Tonalidade livre', style: Theme.of(context).textTheme.bodySmall),
            Slider(value: pendingHue ?? HSVColor.fromColor(color).hue, max: 360,
              onChanged: canControl ? (hue) {
                // Only commit on release; preview uses the local slider state below.
                setState(() => pendingHue = hue);
              } : null,
              onChangeEnd: canControl ? (hue) {
                final c = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
                setState(() => pendingHue = null);
                send(value.copyWith(red: (c.r*255).round(), green: (c.g*255).round(), blue: (c.b*255).round()));
              } : null),
            if (pendingHue != null) Text('Tonalidade: ${pendingHue!.round()}°'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(initialValue: value.effect, key: ValueKey(value.effect),
              decoration: const InputDecoration(labelText: 'Efeito', border: OutlineInputBorder()),
              items: effects.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
              onChanged: canControl ? (effect) { if (effect != null) send(value.copyWith(effect: effect)); } : null),
          ])),
          panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Sua fita'), const SizedBox(height: 6),
            const Text('WS2812B · 5 V · quantidade ajustável', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 14),
            TextField(controller: countInput, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantidade de LEDs (1 a 300)', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: canControl ? () {
              final count = int.tryParse(countInput.text);
              if (count == null || count < 1 || count > 300) {
                error(const FormatException('Use uma quantidade entre 1 e 300 LEDs.')); return;
              }
              send(value.copyWith(ledCount: count));
            } : null, child: const Text('Aplicar quantidade')),
            const Text('A fonte e a fiação devem acompanhar a quantidade de LEDs.', style: TextStyle(fontSize: 12, color: Colors.white60)),
          ])),
          ListTile(leading: const Icon(Icons.mic_none), title: const Text('Controle com Alexa'),
            subtitle: const Text('Experimental · requer Echo compatível'), trailing: const Icon(Icons.info_outline), onTap: alexaHelp),
          const Center(child: Text('Protótipo 0.1 · controle local pelo Wi-Fi', style: TextStyle(color: Colors.white38, fontSize: 12))),
        ]),
      ))),
    );
  }
  double? pendingHue;
}
