# Controle LED

Protótipo com cliente Flutter para Android e firmware próprio para NodeMCU ESP8266.
Controla fita **WS2812B RGB 5 V**, inicialmente 30 LEDs, pelo Wi-Fi de casa.
Não requer servidor externo para o aplicativo. Não há assinatura ou serviço pago neste protótipo.

## Usar pelo celular

1. Abra a última release do repositório e baixe `controle-led.apk` (Android ARM64).
2. Abra o arquivo e, se o Android pedir, permita a instalação por esse aplicativo de origem.
3. Abra **Controle LED** e toque em **Experimentar demonstração** para testar sem hardware.
4. Com a placa preparada no mesmo Wi-Fi, toque em **Buscar ESP8266 no Wi-Fi**.
5. Se o roteador bloquear descoberta por broadcast, informe o IP da placa.

O Samsung S23 FE é ARM64. O APK usa assinatura de teste gerada pelo ambiente de compilação;
uma atualização pode exigir desinstalar a versão anterior. Para distribuição permanente, configurar
uma chave de assinatura privada em GitHub Secrets; nunca colocá-la neste repositório público.

## Recursos

- Descoberta UDP do firmware do projeto; verifica a identidade HTTP antes de conectar.
- Conexão manual por IPv4 privado, leitura do estado e confirmação de comandos.
- Ligar/desligar, brilho, cores predefinidas e tonalidade livre.
- Cor fixa, arco-íris, respiração e luz em movimento.
- Quantidade entre 1 e 300 LEDs; configuração salva na flash da placa.
- Demonstração explicitamente identificada, sem enviar comandos.
- Leitura a cada três segundos para refletir mudanças feitas pela Alexa.
- Estado inicial da placa desligado; limite elétrico de brilho em 50% nesta versão.

## Fita e ligação de referência

Para economizar em teste interno, usar WS2812B RGB 5 V IP30, de 10 a 30 LEDs.
A densidade e o comprimento não são fixos no software. IP30 não é apropriada para água.

| Ligação | Destino |
| --- | --- |
| Fonte 5 V positiva | +5 V da fita |
| Fonte GND | GND da fita e GND do NodeMCU |
| NodeMCU D2 (GPIO4) | Entrada do conversor 74AHCT125 |
| Saída do conversor | Resistor 330 Ω em série, depois DIN da fita |
| 74AHCT125 VCC/GND | 5 V/GND; habilitar o canal usado conforme datasheet |

Alimentar o NodeMCU por USB durante testes. **Não alimentar a fita pelo pino 3V3 da placa.**
O conversor recebe 5 V e converte o sinal lógico de 3,3 V. Instalar um capacitor de
500–1000 µF, pelo menos 6,3 V, entre +5 V/GND junto à entrada da fita, respeitando polaridade.
Para 30 LEDs, uma fonte regulada de **5 V / 3 A** oferece margem para o consumo tradicional
de até 60 mA por LED e para a montagem. Dimensionar fonte, fios e injeção de alimentação
novamente se ampliar. O limite de brilho por software não substitui esse dimensionamento.

## Preparar a placa

O APK é instalado pelo celular; ele **não grava automaticamente o firmware via USB**.
A primeira gravação precisa de um gravador ESP8266 compatível, normalmente em computador.
Uma alternativa Android por USB OTG depende do adaptador, do chip USB serial da placa e
do aplicativo de gravação e ainda não foi validada neste projeto.

- Compilar com PlatformIO: `pio run --project-dir firmware`.
- Gravar: `pio run --project-dir firmware --target upload`.
- O CI também publica `firmware.bin` para NodeMCU ESP8266 com 4 MB; a primeira gravação
  do binário usa endereço flash `0x00000`.
- Na primeira inicialização, conectar o celular ao Wi-Fi `LED-Setup-<id>`.
- Senha inicial do portal: `ledprototipo` (senha pública apenas para bancada).
- Se o portal não abrir, acessar `http://192.168.4.1`, selecionar a rede 2,4 GHz da casa e
  informar as credenciais **nesse portal**, nunca no repositório nem na conversa.
- O portal encerra após três minutos se não configurado e a placa reinicia.
- Voltar o celular para o Wi-Fi da casa e buscar a placa no app.

## Alexa: experimental

O firmware usa **Espalexa**, que emula uma lâmpada Hue por SSDP/HTTP. Não é uma integração
Matter, nem uma skill certificada pela Amazon. O modelo do Echo e as condições da rede
precisam ser validados fisicamente. Alexa no celular sozinha não substitui um Echo compatível
para essa descoberta local. Em geral, o serviço de voz Alexa também requer internet.

Com um Echo compatível no mesmo Wi-Fi, pedir “Alexa, descobrir dispositivos”. O nome é
**Fita LED**. Testar ligar/desligar, brilho e cor. Efeitos são configurados no app; um comando de
cor pela Alexa seleciona cor fixa. O app não depende da Alexa para funcionar.

## Protocolo local

| Operação | Protocolo |
| --- | --- |
| Descoberta | Broadcast UDP porta 4210, texto `LEDCTRL_DISCOVER_V1` |
| Resposta | JSON com `protocol: ledctrl-v1`, nome, id e porta 80 |
| Identidade | `GET /api/info` |
| Estado | `GET /api/state` |
| Alterar | `PUT /api/state`, JSON completo; devolve estado confirmado |

```json
{"power":true,"brightness":96,"red":255,"green":96,"blue":24,"effect":"solid","ledCount":30}
```

O HTTP é local e sem autenticação neste protótipo. Usar uma rede confiável e não encaminhar
portas do roteador para a placa. Rede de convidados com isolamento pode impedir descoberta,
controle e Alexa. O firmware não oferece TLS, acesso remoto, atualização OTA nem provisionamento pelo app.

## Desenvolvimento e verificações

Flutter fixado em 3.35.4 e PlatformIO 6.1.18 no GitHub Actions.
`bash tool/bootstrap.sh` gera o projeto Android e instala o manifesto com acesso HTTP local.
Depois executar `flutter analyze`, `flutter test` e `flutter build apk --release --target-platform android-arm64`.

O workflow compila app e firmware e só publica uma release se ambos concluírem.
Os testes cobrem modo demo, telas pequenas, rejeição de dispositivo incompatível, validação
de estado e protocolo PUT. Não substituem teste em Android real, fita, placa e Echo.

Referências: [Flutter Android](https://docs.flutter.dev/deployment/android),
[Espalexa](https://github.com/Aircoookie/Espalexa),
[alimentação NeoPixel](https://learn.adafruit.com/adafruit-neopixel-uberguide/powering-neopixels),
[conversão de nível lógico](https://learn.adafruit.com/adafruit-neopixel-uberguide/basic-connections).

O [guia visual de montagem](docs/MONTAGEM.md) conserva o esquema detalhado e a pinagem do conversor.
