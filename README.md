# TomTom START (Linux ARM): guia para criar aplicativos próprios

> Documento de conhecimento escrito a partir de testes reais feitos no aparelho e da leitura do firmware dele.
> Objetivo: permitir que qualquer pessoa ou IA entenda este sistema e crie aplicativos para ele, sem repetir as descobertas.
> Data: 29/10/2026. Idioma: português.

## Como ler este documento

Cada afirmação tem um nível de confiança. Procure estas etiquetas:

| Etiqueta | Significado |
|---|---|
| **[VERIFICADO]** | Foi testado no aparelho real e funcionou (ou os logs do aparelho mostram o fato). |
| **[LIDO NO FIRMWARE]** | Foi lido nos scripts ou binários extraídos do firmware, mas nunca testado. |
| **[HIPÓTESE]** | Dedução razoável, sem confirmação. Trate com cuidado. |
| **[NÃO TESTADO]** | Existe no sistema, mas ninguém tentou usar. |

Regra de ouro para quem for continuar: **teste primeiro com um script que sempre termine abrindo o navegador original** (veja a seção 12). Nenhum teste feito até aqui exigiu mexer no firmware, no kernel ou no bootloader.

## Sumário

1. [Resumo em 12 linhas](#1-resumo-em-12-linhas)
2. [Hardware](#2-hardware)
3. [Software do aparelho](#3-software-do-aparelho)
4. [Boot e como rodar código próprio (o arquivo `ttn`)](#4-boot-e-como-rodar-código-próprio-o-arquivo-ttn)
5. [Tela (framebuffer)](#5-tela-framebuffer)
6. [Toque (touchscreen)](#6-toque-touchscreen)
7. [GPS](#7-gps)
   - [7b. Som](#7b-som-devdsp) e [7c. Sensores e ADC](#7c-sensores-e-leituras-brutas-adc)
8. [USB, disco e o modo "conectar ao PC"](#8-usb-disco-e-o-modo-conectar-ao-pc)
9. [Ferramentas disponíveis e limites do shell](#9-ferramentas-disponíveis-e-limites-do-shell)
10. [Padrões de projeto que funcionaram](#10-padrões-de-projeto-que-funcionaram)
11. [Como criar um aplicativo novo, passo a passo](#11-como-criar-um-aplicativo-novo-passo-a-passo)
12. [Segurança e recuperação](#12-segurança-e-recuperação)
13. [O que não foi possível e o que falta](#13-o-que-não-foi-possível-e-o-que-falta)
14. [Histórico dos testes](#14-histórico-dos-testes)
15. [Folha de consulta rápida](#15-folha-de-consulta-rápida)
16. [Apêndice A: código completo](#apêndice-a-código-completo)
17. [Apêndice B: como inspecionar o firmware](#apêndice-b-como-inspecionar-o-firmware)
18. [Apêndice C: gerar imagens para a tela](#apêndice-c-gerar-imagens-para-a-tela)
19. [Apêndice D: launcher v10](#apêndice-d-launcher-v10-não-testado-no-aparelho)

---

## 1. Resumo em 12 linhas

1. O aparelho é um **TomTom START** (modelo interno 70): ARM926EJ-S a 264 MHz, 64 MB de RAM, tela de 480x272 com toque, memória interna de 1,9 GB.
2. Roda **Linux 2.6.13** com um userland mínimo (busybox 1.00, shell `ash`). Tudo roda como root.
3. O programa de fábrica é o arquivo `PNDNavigator` que fica **no disco que o PC enxerga**. O firmware o executa na inicialização.
4. **Se existir um arquivo chamado `ttn` na raiz do disco, o sistema o executa no lugar do `PNDNavigator`.** Esse é o ponto de entrada para código próprio **[VERIFICADO]**.
5. Sem PC Linux e sem o toolchain antigo da TomTom, **não dá para compilar** programas. Tudo o que foi feito é **shell script + imagens pré-desenhadas**.
6. A tela é um framebuffer `/dev/fb`: 480x272, 16 bits (RGB565). Desenhar é `cat imagem.raw > /dev/fb`. **Troca de página sem piscar funciona**: `echo "0,272" > /sys/class/graphics/fb0/pan` **[VERIFICADO]**.
7. O toque vem de `/dev/input/event0` (eventos padrão do Linux). Os eixos X e Y são **invertidos** em relação à tela; já existe uma fórmula de calibração **[VERIFICADO]**.
8. O GPS entrega texto NMEA em `/var/run/gpspipe` **[VERIFICADO]**.
9. O disco "aparecer no PC" **não pode ser feito por script**: é o programa original que aciona isso, e o aparelho reinicia para uma etapa fora do Linux. Por isso o original deve continuar no aparelho **[VERIFICADO]**.
10. Também é o original que trata do botão de ligar e da proteção da bateria **[HIPÓTESE]**. Os scripts próprios sempre devolvem o controle a ele.
11. Já existem prontos e testados: um **launcher** (`ttn`), um **menu de aplicativos** (`meunav`) com **lanterna** e **jogo da velha**.
12. O que serve bem para scripts: menus, jogos de tabuleiro, quebra-cabeças, ferramentas simples e animações curtas com quadros pré-desenhados e troca de página. O que **não** serve: jogos de ação com muitos objetos, mapas com rotas. Cada programa externo (inclusive `echo`, `[` e `test`) custa ~23 ms (seção 9.4).

---

## 2. Hardware

### 2.1 Tabela resumo

| Item | Valor | Confiança |
|---|---|---|
| Modelo | TomTom START (`modelid` 70, `familyname` TomTom START, `usbname` START) | VERIFICADO (`/proc/barcelona`) |
| Placa (campo "Hardware" do cpuinfo) | "TomTom GO", revisão 10020 | VERIFICADO |
| SoC | Samsung S3C2412 (ARM926EJ-S, ARMv5TEJ) | VERIFICADO |
| Clocks | núcleo 264 MHz, memória 132 MHz, periféricos 66 MHz | VERIFICADO (dmesg) |
| RAM | 64 MB; o kernel deixa ~54 MB disponíveis; ~50 MB livres com o sistema rodando | VERIFICADO (`meminfo`) |
| Tela | 480x272, 16 bits (RGB565), `tfttype` 22 | VERIFICADO |
| Toque | resistivo/ADC via driver "TomTom GO Touchscreen Input Driver" em `/dev/input/event0` | VERIFICADO |
| Armazenamento principal | MMC interna de ~1,9 GB (`/dev/mmcblk0`, 1953792 KiB), formatada em FAT16, montada em `/mnt/sdcard` | VERIFICADO |
| Flash NOR | EON EN39SL800 (JEDEC); partição `mtd0` montada em `/mnt/flash` (sistema de arquivos `ngffs`, ~256 KB) | VERIFICADO |
| Slot de cartão SD | **Não tem** (`sdslot` 0, `internalflash` 1) | VERIFICADO |
| Bluetooth | `bluetooth` 0 (o kernel tem a pilha, o hardware não) | VERIFICADO (flag) |
| USB host | `usbhost` 0 | VERIFICADO (flag) |
| Sensor de luz | `lightsensor` 0 | VERIFICADO (flag) |
| GPS | Global Locate, `gpstype` 130, `gldetected` 1, porta `ttySAC1` | VERIFICADO |
| Botões físicos | Só o de ligar (`onoff` 192). Nenhum evento de teclado: só existe o dispositivo de toque | VERIFICADO |
| Áudio | `/dev/dsp` (driver CoolSound, codec Realtek ALC5628). **Toca áudio cru escrito com `cat`.** Padrão ao abrir: **16000 Hz, 2 canais**, volume 117 (mensagens do kernel). Formato de amostra: 16 bits com sinal, estéreo (ver 7b) | VERIFICADO (toca) / VERIFICADO por exclusão (16 bits) |
| Sensores | **Quase todos ausentes neste modelo**: `acc0_*`, `gadc0`, `baro0`, `temp0`, `gyro`, `gyro2` e `compass` dão erro "No such device". `/dev/acc` devolve só zeros (sem acelerômetro). `/dev/adc` devolve 32 bytes de leituras brutas (veja 7c). `light_sensor` = 0 | VERIFICADO |
| Bateria | Driver "TomTom GO Battery Driver". `read` em `/dev/battery` dá "Invalid argument" (precisa de `ioctl`, indisponível por shell) | VERIFICADO (leitura direta não funciona) |
| Backlight (brilho) | `/sys/class/backlight/s3c/`: `brightness` (leitura e escrita, de 0 a **100**; valor padrão **30**), `max_brightness` (100) e `power` (leitura e escrita). Escrever `brightness` retorna sucesso; a diferença visível entre 30 e 25 é imperceptível | VERIFICADO (escrita aceita) |
| Relógio (RTC) | `/dev/rtc`, `/proc/driver/rtc`, comando `hwclock`. A data está errada (2001). Tem alarme, desligado | VERIFICADO (leitura) |

### 2.2 Flags de hardware (`/proc/barcelona/*`)

O kernel expõe características do aparelho em arquivos de texto. Valores lidos neste aparelho:

```
a2dp 0, bluetooth 0, btchip 0, canrecordaudio 0, codectype 1, cputype 4,
deadreckoning 0, dockdev ttySAC0, docking 0, familyname TomTom START,
gldetected 1, gprsmodem 0, gpsdev ttySAC1, gpsephemeris 1, gpstype 130,
handsfree 0, harddisk 0, headphoneconnector 0, hs_sdcard 0, hsmmc 0,
internalflash 1, lightsensor 0, loquendo 1, lowbutton 0, modelid 70,
modelname TomTom START, onoff 192, pnp 1, rdstmc 1, rebootonsdremoval 1,
remote 0, resetstate 0, sdcard 1, sdslot 0, sixbuttonui 1, tfttype 22,
tomtomwork 0, tsfets 0, usbhost 0, usbname START, usbslavetype 0
```

O script de boot exporta cada um como variável de ambiente `hw_<nome>` (por exemplo `hw_gpstype=130`), e elas ficam disponíveis para o `ttn` **[LIDO NO FIRMWARE]**.

---

## 3. Software do aparelho

### 3.1 Versões

| Item | Valor |
|---|---|
| Software TomTom | 9.541 (campo do `ttgo.bif`) |
| Kernel | Linux 2.6.13-tt1493118, compilado com gcc 3.3.4 em 11/02/2014 (`uname`: `armv5tejl`) |
| Arquitetura dos programas | ARM **OABI** (não EABI). Um compilador moderno gera EABI e o resultado **provavelmente não roda** neste kernel antigo **[HIPÓTESE]** |
| libc | glibc 2.3.x (`libc-2.3.2`), com `ld-linux.so.2` |
| Shell e utilitários | busybox v1.00 (`ash`) |
| Ramdisk | de 2018 (7,8 MB, em formato cpio "newc") |

### 3.2 Arquivos que ficam no disco (o que o PC enxerga)

Raiz do disco, lista observada:

| Item | O que é |
|---|---|
| `PNDNavigator` (~8 MB) | **O programa de fábrica** (executável ARM). Faz a interface, a navegação, o USB e a energia. |
| `ttsystem` (~4,5 MB) | Imagem de boot: cabeçalho + kernel + ramdisk (veja 3.3). **Não mexer.** |
| `ttgo.bif`, `install.bif` | Descrições do aparelho e da instalação (versão, lista de recursos). |
| `data*.chk`, `mctx.dat`, `settings.dat`, `signpost_li.txt` | Dados do mapa e de configurações da TomTom (formato proprietário). |
| `bin/` | Binários que o sistema usa. Por exemplo `bin/glgps` (daemon do GPS). O ramdisk tem atalhos que apontam para cá. **Não apagar.** |
| `LoquendoTTS/`, `sounds/`, `cp/`, `ephem/`, `gns/`, `itn/`, `licences/`, `logging/`, `program/`, `script/`, `statdata/`, `TomTom-Cfg/`, `contacts/` | Dados e componentes da TomTom. |
| `ttn` | **Ponto de entrada de código próprio** (criado por nós). |
| `launcher/`, `meunav/`, `launcher_log/` | Arquivos do projeto próprio (telas, aplicativos, registros). |

Arquivos de controle que o `PNDNavigator` procura no disco (nomes encontrados no binário, nunca testados): `autousbconnect.dat`, `nousbconnect.dat`, `forceusbconnect.dat`, `usecmdlog.dat` **[LIDO NO FIRMWARE]**.

### 3.3 Estrutura do `ttsystem` (para quem quiser inspecionar)

**[VERIFICADO por extração]**

- Começa com um cabeçalho de texto `TTBLT` seguido de código ARM (um "stub" de boot).
- **Não é criptografado.**
- Contém dois blocos gzip: o primeiro é o **kernel**; o segundo é um arquivo **cpio newc** com o ramdisk (o sistema de arquivos inicial).
- Neste arquivo (versão 9.541), os blocos gzip começam nos deslocamentos 13732 (kernel) e 1186680 (ramdisk). Esses números **valem só para este arquivo**.
- Receita de extração no [Apêndice B](#apêndice-b-como-inspecionar-o-firmware).

Conteúdo relevante do ramdisk: `/init`, `/etc/rc` (o script de boot), `rc.glgps`, `rc.usbkill`, `rc.suspend`, `rc.resume`, `rc.autosuicide`, o `busybox` e utilitários da TomTom como `ttpnpd`, `launchserver`, `cbee_gen`, `milisleep`, `ttcalib`.

### 3.4 Processos em execução (lista observada)

```
init (sh /init), syslogd, launchserver /var/run/launchsock,
/mnt/sdcard/bin/glgps normal   (GPS), cbee_gen (GPS), /bin/ttpnpd (daemon "PnP"),
e o programa do usuário (o ttn, ou o PNDNavigator)
```

---

## 4. Boot e como rodar código próprio (o arquivo `ttn`)

### 4.1 Fluxo de boot

1. O bootloader (fora do Linux) carrega o `ttsystem` do disco.
2. O kernel sobe e executa `/init`, que roda `/etc/rc` **[LIDO NO FIRMWARE]**.
3. O `rc` monta `/proc`, `/sys`, `tmpfs` (`/tmp`, `/var/run`, `/dev/shm`), a flash em `/mnt/flash` e o disco em `/mnt/sdcard` (vfat, opção `sync`).
4. O `rc` exporta as variáveis `hw_*`, inicia os serviços (syslogd, launchserver, GPS, ttpnpd) e chama o "navegador".
5. Para iniciar o navegador, o `rc` executa `/bin/ttn`, que é um atalho para `/mnt/sdcard/PNDNavigator` **[LIDO NO FIRMWARE]**.

### 4.2 O arquivo `ttn` (o ponto de entrada de código próprio)

O ramdisk contém o arquivo `/etc/debug`, e com ele o `rc` entra num modo no qual, **se existir `/mnt/sdcard/ttn`, ele é executado no lugar do `PNDNavigator`** **[VERIFICADO em todos os testes]**.

Regras do arquivo (todas aprendidas na prática):

| Regra | Motivo |
|---|---|
| Nome exato: `ttn`, sem extensão, na **raiz** do disco | É o que o `rc` procura |
| Primeira linha `#!/bin/sh` | O sistema o executa diretamente |
| **Quebras de linha Unix (LF)**, nunca CRLF | Com CRLF o shell falha |
| Todos os arquivos do disco são executáveis | A montagem vfat usa as permissões padrão do `rc` |
| **Termine sempre com `exec /mnt/sdcard/PNDNavigator`** | Devolve o controle ao programa original, que trata USB, energia e bateria |
| Para desfazer tudo | Apagar o arquivo `ttn` |

### 4.3 O que acontece se o script simplesmente terminar

**[LIDO NO FIRMWARE, NÃO TESTADO]** O `rc` tem um laço principal: quando o programa de usuário termina, ele para o daemon PnP, desmonta o disco, espera e recomeça tudo, executando o `ttn` de novo. Todos os nossos scripts evitam esse caminho terminando com `exec ... PNDNavigator`. Se for testá-lo, tenha uma forma de sair do laço.

### 4.4 Gancho oficial `ttntools`

**[LIDO NO FIRMWARE, NÃO TESTADO]** Se existir `/mnt/sdcard/ttntools/ttntool.sh`, o `rc` o executa antes do navegador. Não foi usado porque o `ttn` já resolve.

### 4.5 Saída do `ttn` e registros

Com o `ttn` rodando, a saída padrão vai para `/dev/null`. **Para depurar, grave arquivos no disco** (por exemplo na pasta `launcher_log/`) e leia no PC. Veja a seção 12.

---

## 5. Tela (framebuffer)

**[VERIFICADO]**

| Propriedade | Valor |
|---|---|
| Dispositivo | `/dev/fb` (driver `s3c24xx-lcd`) |
| Resolução visível | 480x272 |
| Formato | **16 bits por pixel, RGB565, little-endian** (5 bits de vermelho, 6 de verde, 5 de azul) |
| Tamanho virtual | 480x544 (duas "páginas" de 272 linhas); só a primeira é visível |
| Bytes por linha | 960 |
| Tamanho de uma tela cheia | 261.120 bytes |
| Origem | canto superior esquerdo; sem rotação nem espelhamento |

### 5.1 Como desenhar

Tela inteira:

```sh
cat /mnt/sdcard/launcher/menu.raw > /dev/fb
```

Parte da tela (faixas de linhas completas), com `dd`:

```sh
# desenha 77 linhas a partir da linha 154
dd if=faixa.raw of=/dev/fb bs=960 seek=154 count=77 conv=notrunc 2> /dev/null
```

Como as linhas são sequenciais na memória, **uma faixa horizontal de largura total é um bloco contínuo** e pode ser escrito de uma vez. Isso é a base do jogo da velha: cada faixa do tabuleiro é uma imagem pré-desenhada (técnica das "faixas", seção 10.3). Escrever um **retângulo parcial** (que não ocupa a largura toda) exigiria uma chamada `dd` por linha e fica lento.

### 5.1b Troca de página (`pan`): animação sem piscar [VERIFICADO]

O framebuffer tem 544 linhas virtuais (duas páginas de 272). Atributos de `/sys/class/graphics/fb0/`: `bits_per_pixel`, `blank`, `color_map`, `console`, `cursor`, `dev`, `mode`, `modes`, `name`, `pan`, `virtual_size` (`stride` e `rotate` não existem).

```sh
FS=/sys/class/graphics/fb0
# escreve a imagem na página escondida (linhas 272 a 543)
dd if=quadro.raw of=/dev/fb bs=960 seek=272 count=272 conv=notrunc 2> /dev/null
# mostra a página 2 de uma vez
echo "0,272" > $FS/pan
# volta à página 1
echo "0,0" > $FS/pan
```

O teste real mostrou a página azul (escondida) e depois a vermelha: **funciona**. **Atenção:** neste busybox o `echo` **não é comando interno** (`type echo` mostra `/bin/echo`), então cada troca de página cria um processo e custa **~23 ms** (o custo é o do processo; a escrita no `sysfs` em si é desprezível). O valor atual de `pan` é lido com `cat` (`0,0`).

Receita para animação: escreva o próximo quadro na página escondida, troque com `pan`, repita alternando. O custo é o do `dd` do quadro (veja 9.4). Desenhar direto na página visível pisca; usar a página escondida não.

**Valores intermediários são aceitos** **[VERIFICADO]**: `echo "0,1" > pan` e `echo "0,7" > pan` retornaram sucesso, então dá para posicionar a janela em **qualquer linha de 0 a 272**, o que permite **rolagem vertical por hardware** (deslizar de uma tela para outra). O deslocamento **horizontal não é aceito** (`echo "8,0" > pan` falhou). Uma varredura de **273 passos de 1 linha** (da página vermelha para a azul) levou 6,35 s, ou **43 passos por segundo** (um processo `echo` por passo), e **o dono confirmou que desliza suave**.

### 5.1c Apagar a tela e brilho

**Brilho [VERIFICADO]** — `/sys/class/backlight/s3c/`: `brightness` (leitura e escrita, de 0 a 100, padrão **30**), `max_brightness` (100), `power`.
- `echo 100 > brightness` e `echo 5 > brightness` mudam o brilho de forma **bem visível** (confirmado pelo dono). A diferença entre 30 e 25 é imperceptível.
- Restaure sempre o valor original ao terminar (`ORIG=$(cat brightness)` no início).

**`blank` — NÃO USE [VERIFICADO]**:
- `echo 1`, `2` e `3` em `fb0/blank` **falham** (retorno de erro). Só o valor **4** é aceito.
- `echo 4 > blank` **apaga a tela**, mas `echo 0 > blank` **não a religou**: segundo o dono, a tela não voltou sozinha. O script de teste terminou com a tela apagada.
- `echo 4 > /sys/class/backlight/s3c/power` e depois `echo 0` retornaram sucesso, mas a ordem dos testes impede saber o efeito isolado.
- **Brilho 1 e brilho 0 deixam a tela escura, e `echo 30 > brightness` a restaura [VERIFICADO pelo dono]**. É a forma recomendada de "apagar" a tela.
- No teste do `blank 4`, a tela só voltou quando o dono tocou nela no fim do teste; não ficou claro se foi o toque ou o redesenho do menu que a religou.

### 5.2 Armadilhas

- Um arquivo de **32 bits por pixel** (522.240 bytes) ocupa as duas páginas e a tela fica com cores erradas. Sempre converta para RGB565.
- O formato é **little-endian**: o byte baixo vem primeiro.
- Sem `conv=notrunc`, o `dd` pode tentar truncar a saída. Em dispositivos de caractere isso é ignorado, mas mantenha a opção por segurança (ela é necessária se você simular o framebuffer com um arquivo comum).
- A troca de página **se faz com `pan` pelo sysfs** (seção 5.1b); não precisa de `ioctl`.

---

## 6. Toque (touchscreen)

### 6.1 Dispositivo

**[VERIFICADO]**

- O único dispositivo de entrada é **`/dev/input/event0`** ("TomTom GO Touchscreen Input Driver", `Phys=tsinput/input0`).
- `/dev/input/event1` a `event3` não existem (erro "No such device").
- `/dev/ts` e `/dev/tsraw` existem como arquivos mas **não funcionam** ("No such device or address"): são números de driver que o kernel não registra. Não use.
- Capacidades: tipos de evento SYN, KEY e ABS; tecla `BTN_TOUCH`; eixos `ABS_X`, `ABS_Y` e `ABS_PRESSURE`.

### 6.2 Formato dos eventos

Cada evento tem **16 bytes**, na ordem do ARM (little-endian), no formato `struct input_event` do Linux 32 bits:

| Bytes | Campo | Observação |
|---|---|---|
| 0 a 3 | segundos | |
| 4 a 7 | microssegundos | |
| 8 a 9 | tipo | 0 = SYN, 1 = KEY, 3 = ABS |
| 10 a 11 | código | para ABS: 0 = X, 1 = Y, 24 (0x18) = pressão |
| 12 a 15 | valor | com sinal |

Um toque gera cerca de **33 amostras por segundo** (uma a cada ~30 ms; medido num toque de 3 s): `ABS_X`, `ABS_Y` e um `SYN` por amostra, e `ABS_PRESSURE` só ao tocar e ao soltar. **A pressão só tem dois valores: 1023 (tocando) e 0 (solto).** Não existe pressão analógica nem como distinguir toque leve de forte **[VERIFICADO em 10 toques]**.

Com o dedo parado, as amostras oscilam cerca de ±8 unidades em X e ±12 em Y (aprox. ±4 a ±5 pixels). Para detectar "toque parado" ou "arrastar", use uma tolerância dessa ordem.

### 6.3 Coordenadas e calibração

Os valores brutos vão de cerca de 85 a 937 em X e 112 a 876 em Y (faixa de 0 a 1023). O aparelho guarda a calibração de fábrica em `/mnt/flash/sysfile/cal` (16 bytes: quatro números de 32 bits, aqui 80, 947, 130 e 872). Os dois primeiros combinam com o nosso ajuste em X; em Y há diferença de cerca de 7%, então **a nossa fórmula (abaixo) continua sendo a melhor aproximação empírica**. **Os dois eixos são invertidos** em relação à tela:

- X alto = esquerda da tela; X baixo = direita.
- Y alto = parte de cima; Y baixo = parte de baixo.

Fórmula usada (obtida tocando nos 4 cantos e no centro da imagem de calibração) **[VERIFICADO]**:

```
sx = 16 + (919 - X) * 448 / 822     (limitado a 0..479)
sy = 16 + (855 - Y) * 240 / 707     (limitado a 0..271)
```

Precisão: erro de cerca de **±10 pixels**; o centro errou ~10 px na vertical. **Faça botões grandes (50 px ou mais).**

### 6.4 Como ler um toque a partir do shell (o método que funciona)

O shell antigo não consegue ler eventos binários em tempo real de forma simples. O método validado:

1. Um processo em segundo plano grava todos os eventos num arquivo: `cat /dev/input/event0 >> /tmp/ev.log &`
2. Para **esperar o começo** de um toque, um `dd` bloqueante: `dd if=/dev/input/event0 of=/dev/null bs=16 count=1`
3. Para **esperar o fim**, consulta-se o tamanho de `/tmp/ev.log` (`wc -c`) até ele ficar igual por 4 leituras seguidas (~150 a 300 ms).
4. Pega-se o trecho do registro (em unidades de 16 bytes), decodifica-se com `hexdump -v | awk`, tira-se a média das amostras do meio (descartando as primeiras e últimas, que são ruidosas) e aplica-se a fórmula.

O decodificador em `awk` está no [Apêndice A](#a4-decodificador-de-toque-awk). A saída dele é `botão sx sy rawx rawy amostras`.

Detalhes importantes:
- `hexdump -v` (sem opções) imprime 8 palavras de 16 bits em hexadecimal por linha de 16 bytes. O decodificador depende exatamente desse formato **[VERIFICADO no aparelho]**.
- A opção `-e` do `hexdump` **funciona** (`printf 'abcd' | hexdump -e '1/4 "%u\n"'` imprime `1684234849`). Dá para decodificar os eventos direto em decimal, sem passar pelo hexadecimal. O decodificador do projeto continua usando o formato padrão, que também funciona.
- Esse método tem custo de alguns processos por toque: a resposta leva **cerca de meio segundo ou mais** (estimado, não medido).

### 6.5 Responder ao toque sem esperar soltar (análise dos dados reais)

O primeiro pacote de um toque tem sempre quatro eventos nesta ordem: `ABS_X`, `ABS_Y`, `ABS_PRESSURE` (1023) e `SYN` **[VERIFICADO]**. Por isso dá para decodificar a posição assim que chegam esses 64 bytes, **sem esperar o dedo soltar**, e só depois esperar a soltura (para não repetir o toque).

Comparando, nos 10 contatos reais gravados, a coordenada do **primeiro pacote** com a **média do contato inteiro**:
- Em **toques simples** (5 contatos): diferença de 1 a 11 pixels (média ~6 px).
- Em **arrastes**: diferenças de 32 a 70 pixels, naturalmente, porque o dedo se moveu.

Conclusão: para botões grandes (50 px ou mais), responder ao primeiro pacote é seguro e reduz a espera depois do toque. Para arrastar, use a média ou as amostras seguintes.

**Medido no aparelho (Teste 11, 10 toques simples)** **[VERIFICADO]**:

| Modo | Tempo do primeiro evento até a resposta desenhada |
|---|---|
| Responder no instante do toque (primeiro pacote) | **0,18 a 0,28 s (média 0,22 s)**: ~50 ms esperando os 4 eventos, ~100 ms decodificando (`dd`, `hexdump`, `awk`) e ~30 a 70 ms desenhando |
| Responder só depois de soltar | 0,64 a 1,12 s (média 0,77 s) |

O dono percebeu **claramente** a diferença (a resposta imediata foi a mais rápida). A coordenada do primeiro pacote ficou a **no máximo 4 pixels** da média do toque inteiro (média de 1,4 px em X e 1,8 px em Y). Portanto, **responder ao primeiro pacote é a forma correta para botões**.

---

## 7. GPS

**[VERIFICADO]**

- O daemon `glgps` (Global Locate) é iniciado pelo `rc` antes do programa do usuário.
- Ele cria uma **fila nomeada** `/var/run/gpspipe` que entrega **texto NMEA**, aproximadamente uma vez por segundo.
- Mensagens observadas: `$GPGGA`, `$GPRMC`, `$GPGSV`, `$GPGSA` (padrão) e `$PGLOR` (proprietárias da Global Locate).
- Leitura simples (bloqueia até haver dados): `cat /var/run/gpspipe`
- Em ambiente fechado o teste mostrou **zero satélites usados** (sem posição), mas com 1 satélite à vista (sinal ~35). Portanto o hardware responde, e posição só se confirma ao ar livre.
- Nas últimas linhas do teste, o chip passou a informar uma **data e hora UTC reais** (enquanto o relógio interno do aparelho mostra 2001). Isso sugere que dá para ajustar o relógio a partir do `$GPRMC` **[HIPÓTESE, não testado]**.

Cuidados:
- **Só um leitor por vez**: se você ler o `gpspipe` enquanto o programa original roda, pode roubar linhas dele **[HIPÓTESE]**.
- Para parar/iniciar o GPS: `/etc/rc.glgps stop` e `/etc/rc.glgps start`. O script `/etc/rc.usbkill` para o GPS (e o motor de voz) antes de liberar o disco **[VERIFICADO]**. Ao religar, aparece a mensagem inofensiva `mknod: /var/run/gpspipe: File exists`.
- O script `rc.glgps` precisa da variável `hw_gpstype` (já exportada pelo `rc`).

## 7b. Som (`/dev/dsp`)

**[VERIFICADO que toca]**

- `cat arquivo.raw > /dev/dsp` **toca** o áudio. O driver é o CoolSound com o codec Realtek ALC5628.
- A cada abertura do `/dev/dsp` o kernel registra `oss f 16000, c 2` e `oss volume 117`: o padrão é **16000 Hz, 2 canais**, volume 117 (a escala do volume não foi determinada).
- No teste, cinco arquivos de formatos diferentes tocaram sem erro: 8 bits mono 8 kHz, e 16 bits em estéreo 44,1 kHz, mono 22,05 kHz, estéreo 22,05 kHz e mono 44,1 kHz. O dono relatou bipes limpos nas duas rodadas (a contagem exata de bipes ele não lembrou).
- **Conclusão (por exclusão): o driver usa amostras de 16 bits com sinal, little-endian, estéreo, a 16 kHz** (64.000 bytes por segundo). Se fosse 8 bits, os arquivos de 16 bits seriam lidos como pares (byte baixo, byte alto) e o canal esquerdo viraria ruído, com muito chiado; o dono ouviu tudo limpo. O arquivo de 8 bits estéreo também soou limpo porque, lido como 16 bits, o byte alto domina e sai um tom limpo, só com o dobro da frequência e metade da duração. O nível de confiança é médio-alto, porque a memória do dono sobre o que ouviu foi vaga.
- Mudar volume ou formato exigiria `ioctl` do OSS (impossível por shell). O volume do aparelho é o que o driver aplica por padrão.
- A reprodução roda com `cat` em segundo plano e pode ser encerrada com `kill` depois do tempo esperado (o diagnóstico usa 3,8 s por som).

Gerar um tom no PC no formato provável (Python 3):

```python
import math, struct
rate, freq, amp = 16000, 880, 7000          # amplitude moderada (o máximo é 32767)
n = int(rate * 0.25)                         # um bipe de 0,25 s
bipe = b''.join(struct.pack('<hh', v, v) for v in
                (int(amp * math.sin(2 * math.pi * freq * i / rate)) for i in range(n)))  # L e R iguais
silencio = b'\x00\x00\x00\x00' * int(rate * 0.15)
open('bipe.raw', 'wb').write(bipe + silencio)
```

## 7c. Sensores e leituras brutas (ADC)

**[VERIFICADO]** Leituras feitas com `dd`, esperando 0,7 s no máximo:

| Dispositivo | Resultado |
|---|---|
| `/dev/acc` | 28 bytes: **zeros** e um carimbo de tempo. Sem dados de acelerômetro |
| `/dev/acc0_x`, `acc0_y`, `acc0_z`, `acc0_aux`, `gadc0`, `baro0`, `temp0`, `gyro`, `gyro2` | "No such device or address": **não existem neste modelo** |
| `/dev/compass` | "No such device" |
| `/dev/gadc1`, `/dev/gadc2` | Abrem, mas a leitura bloqueia (sem dados) |
| `/dev/battery` | "Invalid argument" na leitura direta (precisa de `ioctl`) |
| `/dev/adc` | **32 bytes** de leituras brutas de 10 bits |

Conteúdo lido de `/dev/adc` (16 palavras de 16 bits, little-endian): `587, 641, 375, 0, 0, 0, 0, 0, 0, 0, 1023, 1023, 0, 0, 1023, 1023`. O significado de cada canal **não foi determinado** (possíveis candidatos: tensão da bateria, toque, temperatura). Em `/sys/devices/platform/tomtomgo-adc/light_sensor` o valor é 0.

---

## 8. USB, disco e o modo "conectar ao PC"

### 8.1 O que se sabe

**[VERIFICADO]**

- O kernel tem um driver de estados USB ("usbmode"). Ao plugar o cabo num PC, o log do kernel (`dmesg`) mostra a sequência `IDLE -> DEVICE_DETECT -> DEVICE`. A linha final termina com `==> USB_STATE_DEVICE`. Ao desplugar, a linha termina com `==> USB_STATE_IDLE`.
- Só ligar o cabo **não** faz o disco aparecer no PC. O aparelho **desligado** com o cabo ligado também **não** vira disco (informado pelo dono do aparelho).
- No programa original, o aparelho mostra uma pergunta ("conectar ao PC?"). Ao confirmar, **o aparelho reinicia** e só então o PC enxerga o disco. Essa tela de disco continua funcionando mesmo com todos os arquivos do aparelho apagados (informado pelo dono).
- Um script próprio consegue parar o GPS, **desmontar o disco** (`umount` retornou sucesso) e **remontá-lo** depois. Mas, com o disco desmontado e o cabo ligado, **o PC não o enxergou**.

### 8.2 Conclusão

A exposição do disco ao PC é feita **fora do Linux** (muito provavelmente pelo bootloader, depois de um reinício solicitado pelo programa original). Isso **não pode ser replicado só com shell**, porque o pedido ao bootloader exige uma chamada de sistema que as ferramentas disponíveis não fazem **[HIPÓTESE]**.

**Consequência prática: o `PNDNavigator` precisa continuar no aparelho**, e todo código próprio deve ter um caminho de volta a ele.

### 8.3 Como o projeto trata isso

O launcher abre o original automaticamente quando detecta `==> USB_STATE_DEVICE` no `dmesg` (PC conectado), então o aviso "conectar ao PC?" aparece normalmente. Um carregador de carro não dispara esse estado **[HIPÓTESE]**.

### 8.2b Estado do USB e da energia por sysfs [VERIFICADO (leitura)]

- `cat /sys/devices/platform/tomtomgo-usbmode/mode` mostra o estado atual do USB: `USB_STATE_IDLE` em repouso (e, pelo que o `dmesg` registrou, `USB_STATE_DEVICE` com um PC conectado). **É mais simples e barato que ler o `dmesg`.** O arquivo aceita escrita (`rw-rw-rw-`), mas o efeito de escrever não foi testado.
- `cat /sys/devices/platform/tomtomgo-buspower/vbus` lê `0` sem alimentação externa (também gravável; efeito não testado).
- `cat /sys/power/state` lista os estados de suspensão disponíveis: `standby mem disk`. `/sys/devices/platform/power/state` lê `0`.

### 8.4b Suspensão, energia, brilho e memória (pesquisa no firmware)

**[LIDO NO FIRMWARE, NÃO TESTADO]**

- Quem suspende e retoma o aparelho é o **programa original**: ele chama `/etc/rc.suspend` (para o GPS e o Bluetooth) antes de suspender e `/etc/rc.resume` (religa o GPS e pede ao `ttpnpd` para reler o hardware) depois. Esses scripts carregam, se existirem, os arquivos `/mnt/sdcard/etc/rc.suspend` e `/mnt/sdcard/etc/rc.resume`: **ganchos oficiais para estender a suspensão**.
- O kernel só suporta os estados de energia `mem` e `standby` (mensagem do driver `s3c24xx-pm`). Se `/sys/power/state` existir, o aparelho seria suspenso com `echo mem > /sys/power/state`. Isso ainda não foi testado (o teste de diagnóstico só **lê** esse arquivo).
- O brilho da tela usa a classe padrão do kernel `backlight` (o driver registra um dispositivo `backlight_s3c` e valida o nível: mensagem "Invalid backlight level"). O esperado é `/sys/class/backlight/<nome>/brightness` e `max_brightness`.
- O sistema define `vm.panic_on_oom = 1`: **se a memória acabar, o kernel entra em pânico e o aparelho reinicia.** Mantenha os programas pequenos e não gere arquivos enormes em `/tmp`.
- O programa original tem uma opção de desligar automaticamente ao perder a alimentação (`KFeatureAutoShutdownOnPowerLoss`). Um programa próprio que não faça isso pode manter o aparelho ligado até a bateria acabar.

### 8.4 Regra de segurança de dados

Nunca escreva no disco (pelo aparelho ou pelo PC) enquanto o outro lado o estiver usando. Antes de desplugar, ejete o disco no PC.

---

## 9. Ferramentas disponíveis e limites do shell

### 9.1 Programas

Lista completa dos programas encontrados no diretório `/bin` do ramdisk **[LIDO NO FIRMWARE]** (busybox 1.00 e utilitários da TomTom):

```
[  a2dpd aascan apnd ash awk blueserver btserver busybox cat cbee_gen chgrp chmod chown clear clmapp
cmp cp csrinit cut date dd df dirname dmesg dos2unix du echo env expr false flash_erase free glgps
gllogarchive gltt gprscomd grep hcitool head hexdump id kill killall launchserver ln logger login
lrb lrx lrz ls lsb lsx lsz md5sum migrate_flash milisleep mkdir mknod mktemp more mount mv nc picocom
pidof ping printf ps pwd renice reset rm rmdir sdptool sed sh sirfreset sleep sort strings stty sync
tail test time top touch tr true ttcalib ttn ttpnpd ttsserver tty umount uname uniq unix2dos uptime
wc wget which ASRserver
```

Atenção com os perigosos: `flash_erase` e `migrate_flash` mexem na flash do aparelho. **Não use.**

**`milisleep N`** espera N milissegundos e imprime `Sleeping for N ms` (por isso redirecione a saída para `/dev/null`). Ele aparece funcionando nos registros do GPS (`Sleeping for 100 ms`) **[VERIFICADO]**. É a forma de esperar menos de 1 segundo, já que o `sleep` só aceita segundos inteiros.

`ttcalib` lê a calibração do toque de `/mnt/flash/sysfile/cal` ou de `/mnt/sdcard/calib.txt` **[LIDO NO FIRMWARE]**. A calibração do seu aparelho tem de ser feita de novo se você usar outro (veja a seção 6.3).

Também existe o script `/etc/showopenfiles`, que lista os processos que mantêm arquivos abertos em `/mnt/sdcard` (útil quando o `umount` falha).

Usados com sucesso em testes reais: `cat`, `cp`, `dd` (com `bs`, `count`, `skip`, `seek`, `conv=notrunc`), `dmesg`, `grep`, `tail`, `wc -c`, `awk`, `hexdump -v`, `expr`, `ps`, `ls -l /proc/.../fd`, `killall`, `sleep`, `milisleep`, `date`, `sync`, `mkdir`, `rm`, `kill`, `umount -f`, `mount`.

### 9.2 Recursos do shell (`ash` do busybox 1.00, de 22/01/2008)

Resultados do teste de diagnóstico **[VERIFICADO no aparelho]**:

| Recurso | Resultado |
|---|---|
| Funções, `case`, `while`, `if`, `. arquivo` | Funcionam |
| `$(comando)`, `wait $!`, `( ... ) &`, here-doc com delimitador entre aspas | Funcionam |
| **Aritmética `$(( ))`** | **Funciona** (`$((2+3*4))` dá 14). Muito mais rápida que `expr`: não cria processo. (Nossos primeiros scripts usam `expr` por cautela; é desnecessário.) |
| `${#v}` (tamanho) | Funciona |
| `${v:1:2}` (substring) | **Não funciona** ("Bad substitution"). Use `expr substr`, `awk` ou `cut` |
| `kill -0 PID` | Funciona |
| `printf '\101\377'` (octal) e `printf '\x41'` (hex) | Funcionam e geram bytes |
| `printf '%d' 0x10` | Dá 16 |
| `expr substr hello 2 3` e `expr length hello` | Funcionam |
| `sleep` com fração | Não. Use `milisleep` |
| `sort`, `uniq`, `which`, `uname`, `date +%s` | Funcionam |
| `time` | Não gerou saída útil; use `/proc/uptime` para medir tempo |
| `/dev/urandom` | Funciona (bom para sorteios em jogos) |
| Aritmética: `$((7%3))`, `$((1<<3))`, `$((10/3))`, `$((-5+2))` | Dão 1, 8, 3 e -3 |
| **`[ ... ]`, `test`, `echo`, `printf` e `expr` são programas externos** | **[VERIFICADO com `type`]**: `[` é `/bin/[`, `test` é `/bin/test`, `echo` é `/bin/echo`, `printf` é `/bin/printf`, `expr` é `/bin/expr`. Cada chamada cria um processo (~22 ms). **`kill`, `read` e `case` são internos**. Um laço `while [ $i -lt N ]` custa 22,7 ms por volta; com `case` e `$(( ))` custa **0,3 ms** |
| `printf '\000A'` | **Gera o byte zero** (`00 41`) |
| `dd if=/dev/zero bs=1 count=3` | Gera zeros |
| `tr '\377' '\000'` | Converte um byte em zero (`61 ff 62` vira `61 00 62`) |
| `hwclock -r` | Funciona (lê o relógio de hardware, hoje 2001) |
| `date -s` | **Aceita** `MMDDhhmmAAAA` (com ou sem `-s`), `MMDDhhmmAAAA.ss`, `AAAA.MM.DD-hh:mm:ss` e só `hh:mm:ss` (por exemplo `date -s "2026.10.31-12:00:00"`). **Rejeita** `AAAA-MM-DD hh:mm[:ss]`. Mostrar a data funciona com `date "+%Y-%m-%d %H:%M:%S"`. O teste foi desfeito logo após (a hora voltou ao valor anterior, com perda de alguns segundos) |

Lista de programas do próprio busybox (v1.00), conferida com `busybox` sem argumentos: `[, ash, awk, busybox, cat, chgrp, chmod, chown, clear, cmp, cp, cut, date, dd, df, dirname, dmesg, dos2unix, du, echo, env, expr, false, fdisk, free, getty, grep, hdparm, head, hexdump, hwclock, id, ifconfig, insmod, kill, killall, klogd, ln, logger, login, logread, losetup, ls, lsmod, md5sum, mkdir, mknod, mktemp, more, mount, mv, nc, pidof, ping, printf, ps, pwd, renice, reset, rm, rmdir, rmmod, sed, sh, sleep, sort, strings, stty, sync, sysctl, syslogd, tail, test, top, touch, tr, true, tty, umount, uname, uniq, unix2dos, uptime, wc, wget, which`. Destaques: `hwclock` (relógio de hardware), `insmod`/`rmmod`/`lsmod` (módulos de kernel), `ifconfig`, `fdisk`, `sysctl`.

### 9.3 `awk`

**[VERIFICADO]** Funcionam: funções, arrays, `split`, `substr`, `index`, `tolower`, `length`, `printf` (inclusive `%05.1f` e `%c`), `rand()` e `srand()` (determinístico com a mesma semente), `system("comando")` e `"comando" | getline`. É a melhor ferramenta de "lógica" disponível: o decodificador de toque e a inteligência do jogo da velha são programas `awk`.

**`printf "%c"` gera bytes de qualquer valor de 1 a 255** (testado com 1, 200, 255), **mas o byte 0 (NUL) não sai**: o `awk` corta a saída daquela chamada de `printf` no primeiro NUL. O teste de gradiente confirmou: faltaram exatamente 320 bytes, que eram os zeros. Consequência para gráficos gerados no aparelho: **nunca emita pixels com um byte zero** (inclui o preto puro `0x0000` e o vermelho puro `0xF800`). Use cores "quase": preto `0x0821`, vermelho `0xF801`. Bytes zero soltos podem vir do shell (`printf '\000'`, `dd if=/dev/zero`, `tr`), mas não do `awk`.

**Strings com escapes octais funcionam no `awk`**: `"\041\010"` vira os bytes `21 08` (um pixel). Foi com isso que se montou uma faixa de 77 linhas (73.920 bytes).

**O `awk` é lento em laços, mas bom em montar strings e imprimi-las** **[VERIFICADO]**:

| Teste | Tempo |
|---|---|
| 300.000 somas num laço | 9,35 s (cerca de 32 mil operações por segundo) |
| Faixa de 77 linhas montada **pixel a pixel** (36.960 `sprintf`) | **7,94 s** (muito lento) |
| Faixa de 77 linhas montando **uma linha pronta e imprimindo 77 vezes** | **0,16 s** |
| O mesmo, enviado direto à tela com `awk ... \| dd` | **0,20 s** |

Regra: **monte cada linha uma vez (com `substr` e concatenação) e repita**; evite laços por pixel.

### 9.4 Desempenho

Medido no aparelho com `/proc/uptime` (Teste 10, laços com `case` e `$(( ))`, sem custo de medição):

| Operação | Custo medido |
|---|---|
| Rodar **qualquer programa externo** (`echo`, `[`, `test`, `expr`, `wc`, `awk`, `sh -c`) | **≈ 22 a 26 ms** |
| Volta de laço com `case` e `$(( ))` (sem processos) | **0,3 ms** (cerca de 3.000 voltas por segundo) |
| Volta de laço com `[ ... ]` | 22,7 ms |
| `test` chamado isoladamente | 21,7 ms |
| Tela cheia com `cat arquivo.raw > /dev/fb` | **43 ms** do disco, 45 ms da memória (sem diferença) |
| `dd` de uma página inteira (`bs=960 count=272` ou `bs=261120 count=1`) | 46 a 48 ms (o tamanho do bloco **não importa**) |
| `echo "0,y" > .../pan` | **23 ms** (é o processo `echo`) |
| Faixa de 77 linhas com `dd` | ≈ 31 ms |
| Sprite de 32 linhas, um `dd` por linha com offsets pré-calculados | ≈ 0,73 s |
| Rolagem por `pan` | 43 passos de 1 linha por segundo |
| **Animação com duas páginas** (um `dd` de tela cheia + um `echo > pan`) | **14,9 quadros por segundo** (quadros no disco) e 14,6 (na memória) |
| Quadrado vermelho gerado pelo `awk` e enviado por `dd` (faixa de 77 linhas) | 8 quadros por segundo (~126 ms por quadro) |
| `milisleep 100` | ≈ 100 ms + ~13 ms do processo |

Regras práticas:
- **Orçamento por quadro**: a 10 quadros por segundo sobram ~100 ms, ou seja, **quatro processos externos** por quadro.
- Para quadros inteiros, o limite prático é **cerca de 15 quadros por segundo** (um `dd` de 47 ms mais um `echo` de 23 ms). Ler o quadro do disco ou da memória dá o mesmo resultado (o disco tem cache).
- Para ir mais rápido, **atualize só uma faixa** (custo proporcional à área) em vez da tela inteira.
- Faça **toda a lógica de jogo em shell puro**, com `case` e `$(( ))`: 0,3 ms por volta é muito mais rápido que qualquer programa externo.
- Prefira `$(( ))` a `expr`, e junte cálculos pesados em **um único `awk`** (mas o `awk` em laço é lento; veja 9.3).
- **Desenhar por faixas** (largura total) e **por quadros inteiros** é barato; **desenhar retângulos parciais linha a linha é caro** (cada linha custa um `dd`).
- O disco é montado com `sync`, então **escritas no disco são lentas**; evite registrar em arquivo dentro de laços.
- O sistema reinicia se a memória acabar (`vm.panic_on_oom = 1`); ~38 a 45 MB ficam livres.

---

## 10. Padrões de projeto que funcionaram

### 10.1 Arquitetura do projeto

```
/ (raiz do disco)
├── ttn                    launcher (ponto de entrada). Menu de 3 botões + guardas de segurança
├── PNDNavigator           programa original (NÃO apagar)
├── launcher/              telas do launcher: menu.raw, nao_instalado.raw, gps.raw
├── launcher_log/          registros gravados pelo launcher (log.txt, taps.txt, gps.txt...)
└── meunav/                "meu navegador": menu de aplicativos próprios
    ├── run.sh             menu (lanterna / jogo da velha / voltar)
    ├── lib.sh             funções: show, wait_tap
    ├── menu.raw, white.raw
    ├── lanterna.sh
    ├── calc.sh            calculadora (toque rápido); calc/disp.awk desenha o visor, calc/pad.raw é o teclado
    ├── arquivos.sh        navegador de arquivos (somente leitura); arq/render.awk escreve texto na tela, arq/foot_*.raw são os rodapés
    ├── velha.sh
    └── velha/             ttt.awk (lógica), band_XYZ.raw (27 faixas), bar.raw, win/lose/draw.raw
```

Fluxo: `ttn` desenha o menu do launcher; o botão 1 executa `meunav/run.sh`; o botão 2 abre o original; o botão 3 grava 25 s do GPS.

### 10.2 Guardas de segurança do launcher

O launcher roda o menu num processo em segundo plano e um **vigia** (outro processo) controla o tempo:

| Situação | O que acontece |
|---|---|
| Faltam arquivos de tela | Abre o original na hora e registra quais faltavam |
| Sem nenhum toque por 60 s no menu | Abre o original |
| Dentro de um aplicativo sem toque por 300 s | Encerra o aplicativo e abre o original |
| Cabo ligado a um PC (`==> USB_STATE_DEVICE`) | Abre o original, que cuida do disco |
| Toque no botão "NAVEGADOR ORIGINAL" | Abre o original |

**Launcher v9 (preparado, não testado):** além do que a v8 faz, encerra **todos** os processos dos aplicativos (a biblioteca `lib.sh` registra o PID de cada script em `/tmp/apppids`) em vez de só o primeiro, e **volta a página da tela para `0,0`** antes de abrir o original. Isso evita que um aplicativo "órfão" continue desenhando por cima do original e que a tela fique deslocada se um aplicativo for encerrado enquanto mostrava a segunda página.

Mecanismo: arquivos-sinal em `/tmp`: `busy` (existe enquanto um aplicativo roda), `act` (criado a cada toque, o vigia o apaga e zera o tempo), `appid` (PID do aplicativo, para poder encerrá-lo).

### 10.3 Técnica das "faixas" para desenhar estado

Para mostrar um estado que muda (tabuleiro do jogo da velha), não se desenham pixels isolados. A tela é dividida em **faixas horizontais de largura total**; para cada combinação possível do conteúdo de uma faixa existe uma imagem pré-desenhada. Para redesenhar, escreve-se a faixa com um `dd` (seção 5.1).

Exemplo: o tabuleiro tem 3 faixas de 77 linhas com 3 casas cada (cada casa é vazia, X ou O): são `3^3 = 27` imagens por faixa (as mesmas servem para as três faixas) = 27 arquivos de ~74 KB. Mais uma barra "SAIR" de 41 linhas, nas linhas 231 a 271.

Regra geral: **o conteúdo precisa ser contínuo em linhas completas**. Se um valor estiver em colunas diferentes, o número de combinações cresce, mas continua viável (centenas de arquivos pequenos). Tempo de uma faixa: um `dd` com 77 gravações de 960 bytes.

### 10.4 Convenção de toque nos aplicativos

- A função `wait_tap` (em `lib.sh`) bloqueia até um toque e define `SX` e `SY` em pixels, ou `-1` se a leitura falhou (o aplicativo deve ignorar esse toque com `continue`).
- Ela também cria `/tmp/act`, avisando o vigia de que há atividade.
- Divida a tela em **zonas grandes** e decida pela posição: por exemplo, três faixas: `sy < 91`, `sy < 182`, resto. A tela cheia tem 272 linhas.

### 10.5 Lógica em `awk`

O jogo da velha usa um `awk` puro: recebe o tabuleiro (9 dígitos: 0 vazio, 1 X, 2 O) e a casa jogada, e devolve o novo tabuleiro e o estado (`.` segue, `X`, `O`, `D` empate, `-` jogada inválida). O oponente usa uma heurística simples (ganhar, bloquear, centro, cantos, laterais). Foi testado com 400 partidas aleatórias, sem jogadas inválidas.

---

### 10.6 Animação com quadros pré-desenhados e `pan`

Receita (baseada em medidas reais; a velocidade final do laço completo está em teste):

1. Gere os quadros (480x272, RGB565) no PC e copie para o aparelho.
2. No script, alterne duas páginas: escreva o quadro seguinte na página escondida com **um** `dd` (`bs=960 seek=<0 ou 272> count=272 conv=notrunc`) e troque com `echo "0,<0 ou 272>" > .../pan`.
3. Faça a contagem com `$(( ))` e as condições com `case` (sem processo).

**Medido (Teste 10)**: 80 quadros em 5,4 s, ou **14,9 quadros por segundo**, com `dd` de 261.120 bytes e um `echo > pan` por quadro. A animação da bolinha **foi fluida** nas duas versões (quadros no disco e na memória), segundo o dono. Ler da memória não ganha nada, e o tamanho do bloco do `dd` também não. O gargalo é a cópia de 261 KB para o framebuffer (~20 ms) mais os dois processos (~46 ms).

### 10.7 Toque rápido (`wait_tap_fast`) [PREPARADO, NÃO TESTADO]

Descrito em `meunav/lib.sh`. Em vez de esperar o dedo soltar (método da seção 6.4), ele:

1. Lê **4 eventos direto do dispositivo** (`dd if=/dev/input/event0 bs=16 count=4`), que são exatamente o primeiro pacote do toque (X, Y, pressão, SYN). Se a janela não for um pacote de toque novo (por exemplo, o dedo ainda apoiado do toque anterior), ela é **descartada** e ele lê de novo. Assim não precisa detectar a soltura.
2. Converte os dois valores hexadecimais para pixels **só com aritmética do shell** (`$((0x...))`; se o shell não aceitar, usa `printf '%d'`).
3. Aplica a calibração da seção 6.3.

Custo esperado: um `dd` (que já estava esperando), um `hexdump` (~25 ms) e o desenho: **cerca de 100 ms** do toque à resposta **[estimativa; a calculadora grava os tempos reais em `calc_log/` para confirmar]**.

Limitações conhecidas: um toque feito nos ~60 ms logo depois de uma janela descartada pode ser perdido; toques muito rápidos em sequência (menos de ~0,3 s) não são garantidos. Para menus e calculadoras isso é aceitável.

### 10.8 Texto qualquer na tela (fonte de bitmap em `awk`) [PREPARADO, NÃO TESTADO NO APARELHO]

Para mostrar nomes de arquivos e textos arbitrários, o projeto usa `meunav/arq/render.awk`:

1. **Fonte**: 95 caracteres ASCII (32 a 126), cada um numa célula de **9x15 pixels**, gerada no PC a partir da fonte DejaVu Sans Mono Bold (corpo 14) e gravada **dentro do próprio programa `awk`** como uma única cadeia de "0" e "1" (12.825 caracteres, uma máscara de 9 bits por linha de cada letra). Não há arquivo de fonte para ler.
2. **Uma linha de pixels de um texto** é montada concatenando as máscaras da linha correspondente de cada letra (com `substr`) e depois trocando, **de uma vez**, todos os "1" pela cor do texto e todos os "0" pela cor do fundo com duas chamadas de `gsub`. Isso evita o laço por pixel, que seria muito lento (veja 9.3).
3. **Cores** sem byte zero nem quebra de linha: fundo `0x0821`, azul-marinho `0x2113`, branco `0xFFFF`, amarelo `0xFFE0`, cinza `0xAD75`.
4. O programa produz **238 linhas** de 960 bytes (cabeçalho de 34 linhas e 204 linhas de conteúdo). O resto da tela (o rodapé de 34 linhas, com botões) é uma imagem pronta concatenada depois.

Caracteres fora do ASCII (acentos) viram `?`. Estimativa: cerca de 0,3 a 0,5 s para montar uma tela com 6 linhas de 51 caracteres **[HIPÓTESE; o aparelho ainda não mediu]**. Verificado só no PC: tamanho certo (261.120 bytes por tela completa) e nenhum byte zero.

### 10.9 Navegador de arquivos (`arquivos.sh`) [PREPARADO, NÃO TESTADO NO APARELHO]

- **Somente leitura**: não apaga, não renomeia, não escreve.
- Começa em `/mnt/sdcard`; dá para subir até `/` e ver `/proc`, `/sys`, `/etc`, `/bin` (útil para pesquisa).
- Lista com `ls -l`, ordena (pastas primeiro) e mostra 6 linhas por tela, cada uma com 34 pixels de altura (alvo de toque confortável). Pastas em amarelo, arquivos em branco com o tamanho, arquivos especiais (dispositivos, atalhos) em cinza.
- Rodapé: **▲ ▼** (páginas), **SUBIR**, **SAIR**.
- Tocar numa **pasta** entra nela. Tocar num **arquivo** abre o visualizador de texto (10 linhas por página; controles ▲ ▼ TOPO FECHAR; lê só os primeiros 64 KB e troca bytes não imprimíveis por ponto). Um arquivo `.raw` de **261.120 bytes** é mostrado como imagem (um toque volta).
- A leitura roda em segundo plano com limite de tempo (cerca de 2 s), para **não travar em arquivos que bloqueiam** (como `/proc/kmsg`).
- Desenha numa **página escondida** e troca com `pan` (sem piscar). Ao sair, `pan` volta para `0,0`.
- O toque usa `wait_tap` (testado). Depois de validar a calculadora, basta trocar `TAPFN=wait_tap_fast` no começo do arquivo.

### 10.10 Sistema de aplicativos instalados automaticamente (launcher v10) [PREPARADO; TESTADO SÓ EM SIMULAÇÃO]

Substitui o menu fixo do `meunav`. A ideia: **para instalar um aplicativo basta copiar dois itens para a pasta `apps/`**; o `ttn` descobre sozinho, mostra o ícone na tela inicial e anota tudo em `data/appList.txt`.

**Layout de pastas na raiz do disco**

```
/ttn                       launcher v10 (descobre os aplicativos e monta a tela inicial)
/apps/NOME.sh              script principal do aplicativo
/apps/NOME/                pasta do aplicativo (arquivos dele); apps/NOME/icon.raw = ícone
/data/appList.txt          lista gerada pelo ttn a cada inicialização
/data/lib.sh               biblioteca para os aplicativos (show, wait_tap, wait_tap_fast)
/data/home.awk             monta uma página da tela inicial (contém a fonte 9x15)
/data/bar.rows             barra inferior com as setas de página
/data/icon_original.rows   ícone do menu original (o único aplicativo embutido)
/data/icon_default.rows    ícone "?" para aplicativos sem ícone válido
/data/cache/icons/         ícones já convertidos (criado pelo ttn)
```

**Regras do aplicativo**
- `apps/NOME.sh` é executado com `sh`. Não precisa ter permissão especial. Para voltar à tela inicial, o script **termina**.
- O ttn exporta **`APPDIR`** (pasta `apps/NOME`), **`DATA`** (pasta `data`) e **`SD`** (raiz do disco). Comece o script com `. ${DATA:-/mnt/sdcard/data}/lib.sh` para ter `show ARQUIVO.raw` e `wait_tap` (define `SX` e `SY`; `SX=-1` se a leitura falhou) ou `wait_tap_fast`.
- `NOME` sem espaços e sem o caractere `|`. Na tela aparecem os **13 primeiros caracteres**.
- Um `.sh` sem pasta também aparece (com o ícone "?"). A pasta é opcional se o aplicativo não precisa de arquivos.
- Enquanto um aplicativo roda, o launcher o encerra se ficar **5 minutos sem toque** (cada `wait_tap` conta como atividade); `lib.sh` registra o PID para que o launcher possa encerrar também os processos filhos.

**`icon.raw`**: **80x80 pixels, RGB565 little-endian, exatamente 12.800 bytes**, como todas as imagens `.raw` do projeto. Se faltar ou tiver outro tamanho, aparece o ícone "?" e o motivo vai para `launcher_log/log.txt`. No PC: `ferramentas/criar_icone.py imagem.png apps/NOME/icon.raw`. Recomenda-se fundo escuro e cantos arredondados (a tela inicial é quase preta, cor `0x0821`).

**`data/appList.txt`**: um aplicativo por linha, campos separados por `|`; linhas que começam com `#` são comentário:

```
nome|/mnt/sdcard/apps/nome.sh|/mnt/sdcard/apps/nome/icon.raw|tamanho_do_icone|carimbo_do_icone
```

`tamanho_do_icone` é 0 se não há `icon.raw`. `carimbo_do_icone` é a data do arquivo (usada para saber se o ícone mudou). O ícone embutido do menu original **não** entra na lista; o ttn o coloca sempre em primeiro. A lista é regravada só se mudou.

**O que o ttn faz a cada inicialização**
1. **Descobre**: `ls -l apps/` (procura os `.sh`) e `ls -l apps/*/icon.raw` (tamanho e data de cada ícone), junta tudo num `awk`, ordena por nome e grava `data/appList.txt`.
2. **Converte os ícones** que mudaram: o `awk` não consegue ler bytes zero nem quebras de linha de arquivos binários, então cada `icon.raw` é lido com `hexdump -v -e '160/1 "%u " "\n"'` e regravado em `data/cache/icons/NOME.rows` no **formato "rows"**: 80 linhas de 160 bytes terminadas em `\n`, com **byte 0 trocado por 1 e byte 10 por 11** (diferença de uma unidade na cor, imperceptível). É feito **uma única vez por ícone** (cerca de 1 s cada, estimativa) e guardado junto com `tamanho|carimbo` (`NOME.stamp`).
3. **Monta as páginas** com `home.awk` (grade de **4 colunas x 2 linhas = 8 itens por página**, cada célula de 120x112 pixels com o ícone de 80x80 e o nome abaixo, mais uma barra inferior de 48 linhas com ◀, `pagina/total` e ▶). Cada página é um quadro completo de 261.120 bytes, guardado em memória (`/tmp/home_N.raw`); trocar de página é só um `cat` (~45 ms). Se uma página sair com tamanho errado, o ttn abre o menu original.
4. **Espera o toque**: toque num ícone roda o aplicativo; ◀ e ▶ trocam de página; o ícone **ORIGINAL** abre o menu original da TomTom.

**Segurança (herdada do launcher v9)**: se faltar algum arquivo essencial de `data/`, abre o original na hora; sem toque por 60 s, ou com o cabo num PC (`USB_STATE_DEVICE`), abre o original; ao sair volta a página da tela para `0,0` e encerra todos os processos dos aplicativos.

**Migração dos aplicativos anteriores**: `lanterna`, `velha` (jogo da velha), `calculadora`, `arquivos` e `diagnostico` (o diagnóstico 4) foram movidos para `apps/` com ícones novos, e ganharam um aplicativo de exemplo, `ola`. As pastas antigas `meunav/` e `launcher/` deixam de ser usadas. O botão "TESTE GPS" do launcher antigo não foi portado.

**Verificado em simulação no PC** (não no aparelho): descoberta e ordenação, geração de `appList.txt` (sem regravar se não mudou), conversão idêntica byte a byte ao esperado, ícone inválido ou ausente trocado pelo "?", duas páginas, variáveis `APPDIR`/`DATA`/`SD` chegando ao aplicativo, mudança de página, retorno ao original. **Ainda não medidos no aparelho**: tempo de preparo e a conversão com o `hexdump -e` e o `awk` reais.

## 11. Como criar um aplicativo novo, passo a passo

> **A partir do launcher v10, use o procedimento da seção 10.10** (arquivos em `apps/`). O texto abaixo descreve o menu antigo (`meunav`).

Pré-requisitos: o launcher (`ttn`), a pasta `meunav/` com `lib.sh` e `run.sh`, e Python com Pillow no seu PC para gerar imagens (Apêndice C).

1. **Projete as telas.** A tela é 480x272. Desenhe com Python/Pillow e converta para RGB565 (Apêndice C). Use botões grandes e textos de 30 px ou mais.
2. **Escreva o aplicativo** como um script `meunav/meuapp.sh`:

```sh
#!/bin/sh
. /mnt/sdcard/meunav/lib.sh          # traz show e wait_tap
show /mnt/sdcard/meunav/minha_tela.raw
while true; do
  wait_tap                            # define SX e SY
  if [ $SX -lt 0 ]; then continue; fi
  if [ $SY -ge 231 ]; then break; fi  # exemplo: tocar embaixo = sair
  # ... sua lógica aqui ...
done
```

3. **Registre no menu.** Gere uma nova `menu.raw` com mais um botão e acrescente um ramo no `run.sh` (um `elif [ $SY -lt ... ]; then sh $M/meuapp.sh`).
4. **Copie para o aparelho**: use o modo "conectar ao PC" do programa original, copie os arquivos e ejete o disco no PC antes de desplugar.
5. **Teste.** Reinicie sem o cabo no PC, entre pelo botão MEU NAVEGADOR.
6. **Se algo falhar**: leia `launcher_log/log.txt`. Para depurar o seu aplicativo, grave mensagens em arquivos dentro dessa pasta.

Boas práticas:
- Nunca bloqueie sem um caminho de saída: o vigia encerra o aplicativo após 5 min sem toque, mas é melhor ter um botão SAIR.
- Escreva pouco no disco (montagem `sync` é lenta).
- Não dependa de data/hora: o relógio interno está errado (2001).
- Prefira lógica em `awk` e desenho por faixas.
- Teste a lógica no PC antes (o `awk` e o `sh` funcionam igual; simule o framebuffer com um arquivo, como foi feito para o jogo da velha).

---

## 12. Segurança e recuperação

### 12.1 Princípios

1. Faça **backup completo do disco** antes de tudo (já feito neste projeto).
2. **Nunca apague nem renomeie** `PNDNavigator`, `ttsystem`, a pasta `bin` e os `*.chk`.
3. Todo script próprio termina com `exec /mnt/sdcard/PNDNavigator` e tem tempo máximo.
4. Nunca escreva no disco enquanto ele está conectado ao PC.
5. Para desfazer qualquer coisa: apague o arquivo `ttn` (e, se quiser, as pastas próprias).

### 12.2 Riscos conhecidos

| Risco | Observação |
|---|---|
| Perder o acesso ao disco | O modo disco só é aberto pelo programa original (ou, segundo o dono, quando o sistema não carrega). **Aparelho desligado com cabo não vira disco.** Por isso o launcher sempre devolve o controle ao original |
| Botão de ligar e bateria | Tratados pelo original **[HIPÓTESE]**. Um programa próprio que fique rodando indefinidamente pode não desligar nem proteger a bateria |
| Corrupção do disco | Ao escrever dele enquanto o PC o usa, ou ao desplugar sem ejetar |
| Instalar o OpenTom completo | Troca o `ttsystem` (boot). Sem slot de cartão, uma falha pode deixar o aparelho sem recuperação conhecida. **Não é necessário**: o `ttn` já executa código próprio sem alterar o boot |
| Gravar entrada em `usecmdlog.dat` ou outros arquivos de controle | Não testado |
| Esgotar a memória | O sistema reinicia (`vm.panic_on_oom = 1`) |
| `flash_erase` e `migrate_flash` | Alteram a flash do aparelho: não use |

### 12.3 Como depurar

- Grave sempre em `launcher_log/` (leia depois no PC).
- Úteis: `ps`, `ls -l /proc/<pid>/fd`, `dmesg`, `cat /proc/mounts`, `cat /proc/interrupts`, `cat /proc/barcelona/*`.
- Salve registros primeiro em `/tmp` (memória) e copie para o disco no fim se for desmontá-lo.

---

## 13. O que não foi possível e o que falta

| Tema | Situação |
|---|---|
| **Compilar programas** | Exige o toolchain antigo da TomTom (gcc 3.3.4, OABI) num Linux (ou WSL). O dono do aparelho não tem acesso a isso por ora. Com ele seria possível: framebuffer rápido, toque em tempo real, jogos de ação, SDL |
| **Navit (navegador GPS livre)** | A documentação oficial descreve um plugin para TomTom, mas os links de download testados (`~xenos1984/...` e o artefato de CI `navitom_plugin.zip`) **não funcionaram**. Há uma página de downloads em `download.navit-project.org` que lista pacotes para TomTom, não confirmados |
| **Mapas e rotas próprios** | Os `*.chk` são do formato proprietário da TomTom. Um navegador próprio precisaria de mapa próprio (OpenStreetMap) e de código compilado |
| **Som** | **Toca** áudio cru com `cat arquivo > /dev/dsp`. O padrão ao abrir é 16 kHz, 2 canais e amostras de 16 bits com sinal, volume 117. Mudar volume ou formato exigiria `ioctl` (impossível por shell) |
| **Sensores** | Não há acelerômetro (só zeros), giroscópio, barômetro, bússola nem termômetro neste modelo. O sensor de luz lê 0. A bateria não pode ser lida diretamente (`ioctl`) |
| **Relógio** | O relógio interno está errado (2001). O GPS fornece hora UTC real (sem fixar posição). O comando `hwclock` existe e a leitura funciona (`hwclock -r`), então dá para gravar a hora no relógio de hardware. `date -s` aceita `AAAA.MM.DD-hh:mm:ss` e `MMDDhhmmAAAA[.ss]` (veja 9.2). Falta gravar no relógio de hardware (`hwclock -w`) e ajustar a hora a partir do `$GPRMC` do GPS |
| **Brilho da tela** | `/sys/class/backlight/s3c/brightness` (0 a 100, padrão 30) **funciona** (100 e 5 foram bem visíveis; 1 e 0 deixam a tela escura e voltam ao restaurar) |
| **Apagar a tela** | `blank` só aceita o valor 4, que apaga mas **não é desfeito** por `echo 0` (a tela não voltou). **Não use.** Para escurecer, use `brightness` |
| **Suspender** | `/sys/power/state` lista `standby mem disk`. Não foi testado (risco de não acordar sem o botão de ligar) |
| **Entrar no modo disco por script** | Não é possível (seção 8) |
| **Plugin pelo `SDKRegistry`** | O programa original tem suporte (nome `SdkRegistry` no binário) para mostrar ícones de programas externos no menu dele. Não foi testado |

Ideias viáveis só com scripts e imagens: jogo da memória, 2048, calculadora, bloco de notas com teclado na tela, visualizador de imagens, quebra-cabeça de números, jogo "forca" com palavras fixas, ficha técnica do aparelho (lendo `/proc`).

---

## 14. Histórico dos testes

| Teste | O que testou | Resultado |
|---|---|---|
| Análise de arquivos | `ttgo.bif`, `ttsystem`, `PNDNavigator`, extração do ramdisk | Identificou modelo, kernel, boot, mecanismo do `ttn` |
| Teste 1 | `ttn` simples gravando informações e abrindo o original | **Executou**: confirmou que código próprio roda |
| Teste 2 | Imagens de 16 e 32 bits no framebuffer; `/dev/ts` | 16 bits correto; 32 bits fica com cores erradas; `/dev/ts` não funciona |
| Teste 3 | Gravar eventos de toque | Dispositivo é `event0`; eixos invertidos; calibração por cantos |
| Teste 4 | Menu com botões e decodificador | **Funcionou** em todos os 5 toques; confirmou `hexdump`/`awk` no aparelho |
| Launcher v5 a v7 | Menu permanente; guardas; erro de arquivo ausente | v6 só mostrou a logo (faltava `menu.raw` em `launcher/`); v7 acrescentou conferência de arquivos e registros; **funcionou** |
| Teste 5 | Cabo ligado sem o original | Kernel detectou o PC, mas o disco não apareceu |
| Teste 6 | Desmontar o disco com o cabo ligado | `umount` ok, remontagem ok, **mas o PC não viu o disco** |
| Teste GPS | Ler `/var/run/gpspipe` | NMEA recebido; sem posição dentro de casa |
| Launcher v8 + `meunav` | Menu de aplicativos, lanterna, jogo da velha | **Funcionou** |
| Pesquisa estática 2 | Leitura de `rc.suspend`/`rc.resume`, `milisleep`, `ttcalib`, atributos do framebuffer e do backlight no kernel | Achou `milisleep`, ganchos de suspensão, `pan` e `blank` do fb, classe `backlight` |
| Teste 8 (diagnóstico) | Bateria automática: fotografia do sistema, capacidades do shell, velocidades, troca de página, apagar tela, brilho, sensores, som, toque bruto, pixels gerados | **Executado (138 s)**. Troca de página funciona; `blank=1` falha; brilho aceita escrita (efeito invisível entre 30 e 25); som toca; sensores quase todos ausentes; `$(( ))` e `hexdump -e` funcionam; `awk` não emite NUL; medidas de velocidade obtidas |
| Teste 9 (diagnóstico 2) | Brilho em 100 e 5, apagar a tela, som em 16 kHz estéreo, rolagem e animação com `pan`, bytes zero, `hwclock`, velocidade do `awk` | **Executado (137 s)**. Brilho funciona; `blank 4` apagou a tela e ela **não voltou sozinha** (por isso as observações visuais seguintes não foram feitas); `pan` aceita qualquer linha, não aceita horizontal; `[ ]` custa ~22 ms por volta; `awk` monta faixa de 77 linhas em 0,16 s se repetir uma linha pronta; `printf '\000'`, `dd` e `tr` geram zeros; `hwclock -r` funciona |
| Teste 10 (diagnóstico 3) | Custo dos laços (`case` contra `[ ]`), `dd` com bloco grande, custo do `pan`, rolagem de pixel em pixel, animação (disco contra memória), quadrado gerado pelo `awk`, brilho 1 e 0, som identificado na tela, `date -s` com restauração | **Executado (90 s)**. `[`, `test`, `echo`, `printf` e `expr` são externos (`type`); laço com `case` custa 0,3 ms contra 22,7 ms de `[ ]`; `pan` custa 23 ms por causa do `echo`; animação a 14,9 quadros por segundo (disco e memória iguais); rolagem suave a 43 passos por segundo; quadrado gerado pelo `awk` a 8 quadros por segundo; brilho 1 e 0 escurecem a tela e restauram; os 4 sons saíram limpos; `date -s "AAAA-MM-DD hh:mm:ss"` é inválido |
| Teste 11 (diagnóstico 4) | Latência do toque (resposta ao tocar contra resposta depois de soltar) e formatos de `date -s` | **Executado**. Resposta no instante do toque: 0,22 s em média, contra 0,77 s depois de soltar (o dono sentiu clara diferença); coordenada do primeiro pacote a ≤ 4 px da média; `date -s` aceita `MMDDhhmmAAAA[.ss]`, `AAAA.MM.DD-hh:mm:ss` e `hh:mm:ss` |
| Calculadora + toque rápido | Aplicativo novo que usa `wait_tap_fast` (lê o primeiro pacote direto do dispositivo) e desenha o visor com `awk` | **Preparado, ainda não executado** |
| Navegador de arquivos + launcher v9 | Aplicativo de arquivos com texto na tela (fonte 9x15 em `awk`), visualizador de texto e imagem, desenho em página escondida; launcher que encerra todos os processos dos aplicativos | **Preparado, ainda não executado** (testado só no PC: navegação, paginação, visualizador e renderização) |
| Sistema de aplicativos (launcher v10) | O `ttn` descobre `apps/NOME.sh` + `apps/NOME/icon.raw`, converte os ícones, grava `data/appList.txt` e monta uma tela inicial com grade de ícones e o ícone ORIGINAL embutido | **Preparado, ainda não executado** (testado só em simulação no PC) |

---

## 15. Folha de consulta rápida

```
ENTRADA DE CÓDIGO     arquivo /mnt/sdcard/ttn (sem extensão, LF, #!/bin/sh) ... termine com exec /mnt/sdcard/PNDNavigator
TELA                  480x272, RGB565 little-endian, 960 bytes/linha, 261120 bytes
 desenhar tela cheia  cat arquivo.raw > /dev/fb
 desenhar faixa       dd if=f.raw of=/dev/fb bs=960 seek=<linha> count=<linhas> conv=notrunc
TOQUE                 /dev/input/event0, evento de 16 bytes: u32 s, u32 us, u16 tipo, u16 codigo, s32 valor
 tipos                0 SYN, 1 KEY (330 BTN_TOUCH), 3 ABS (0 X, 1 Y, 24 pressão 0/1023)
 calibração           sx = 16 + (919-X)*448/822 ; sy = 16 + (855-Y)*240/707
 ler                  cat event0 >> /tmp/ev.log & ; dd bs=16 count=1 espera ; hexdump -v | awk -f decode.awk
GPS                   cat /var/run/gpspipe  (NMEA)   | /etc/rc.glgps stop|start
USB                   PC conectado = dmesg termina em "==> USB_STATE_DEVICE" ; disco só via programa original
SHELL                 ash/busybox 1.00: $(( )) ok, awk ok; sem ${v:1:2}, sem arrays; sleep inteiro, milisleep N p/ ms
 EXTERNOS             [ test echo printf expr são programas (~22 ms cada); internos: case kill read : . eval exec wait type
 PÁGINA               echo "0,272" > /sys/class/graphics/fb0/pan (mostra a 2a página) ; echo "0,0" > ... (volta)
 BRILHO               cat /sys/class/backlight/s3c/brightness (0..100, padrão 30) ; echo 100 > ... funciona ; NUNCA use fb0/blank
 LAÇOS                use case no lugar de [ ] (cada [ ] custa ~22 ms) e $(( )) no lugar de expr
 ZEROS                printf '\000', dd if=/dev/zero ou tr; o awk não emite NUL
 SOM                  cat arquivo.raw > /dev/dsp   (padrão 16 kHz, 2 canais)
 USB                  cat /sys/devices/platform/tomtomgo-usbmode/mode  (USB_STATE_IDLE / ..._DEVICE)
 CUSTO                programa externo ~25 ms ; $(...) ~47 ms ; tela cheia ~47 ms ; faixa 77 linhas ~31 ms
 AWK                  printf "%c" ok de 1 a 255, mas NUL (0) é cortado
PROIBIDO              apagar PNDNavigator, ttsystem, bin/ ; escrever no disco com o PC conectado
DESFAZER              apagar o arquivo ttn
```

---

## Apêndice A: código completo

Tudo abaixo foi **executado no aparelho** (versão v8 do launcher e o pacote `meunav`).

### A.1 `ttn` (launcher v8)

```sh
#!/bin/sh
# Launcher: menu com MEU NAVEGADOR / NAVEGADOR ORIGINAL / TESTE GPS.
# Sem toque por 60 s (ou 5 min dentro de um aplicativo), ou ao ligar o cabo num PC, abre o navegador original
# (ele cuida do USB, do desligar e da bateria).

OUT=/mnt/sdcard/launcher_log
D=/mnt/sdcard/launcher
APP=/mnt/sdcard/meunav
IDLE=60
BUSYIDLE=300
mkdir -p $OUT
echo "inicio $(date)" > $OUT/log.txt
rm -f $OUT/taps.txt /tmp/busy /tmp/act

# confere se as telas existem; se faltar alguma, registra e abre o original na hora
ls -l /mnt/sdcard > $OUT/raiz_disco.txt 2>&1
ls -l $D > $OUT/pasta_launcher.txt 2>&1
FALTA=""
for f in menu.raw nao_instalado.raw gps.raw; do
  if [ ! -f $D/$f ]; then
    FALTA="$FALTA $f"
  fi
done
echo "arquivos faltando:$FALTA" >> $OUT/log.txt
if [ -n "$FALTA" ]; then
  sync
  exec /mnt/sdcard/PNDNavigator
fi

# decodificador dos eventos de toque (calibrado nos testes 3 e 4)
cat > /tmp/decode.awk <<'AWK'
function h(s,  i,n,c){n=0;s=tolower(s);for(i=1;i<=length(s);i++){c=index("0123456789abcdef",substr(s,i,1))-1;n=n*16+c}return n}
NF>=9 { t=h($6); c=h($7); v=h($8)+65536*h($9);
  if(t==3&&c==0) x=v; else if(t==3&&c==1) y=v;
  else if(t==0&&c==0&&x!=""&&y!="") {n++; X[n]=x; Y[n]=y}
}
END {
  if(n==0){print "0 0 0 0 0 0"; exit}
  a=1;b=n; if(n>6){a=3;b=n-2}
  sx=0;sy=0;m=0; for(i=a;i<=b;i++){sx+=X[i];sy+=Y[i];m++}
  rx=sx/m; ry=sy/m
  px=16+(919-rx)*448/822; py=16+(855-ry)*240/707
  if(px<0)px=0; if(px>479)px=479; if(py<0)py=0; if(py>271)py=271
  if(py<91) btn=1; else if(py<182) btn=2; else btn=3
  printf "%d %d %d %d %d %d\n", btn, px, py, rx, ry, n
}
AWK

size() { set -- $(wc -c < /tmp/ev.log); echo $1; }

loop() {
  : > /tmp/ev.log
  cat /dev/input/event0 >> /tmp/ev.log 2> $OUT/ev_erro.txt &
  CATPID=$!
  cat $D/menu.raw > /dev/fb 2>> $OUT/fb_erro.txt
  echo "menu desenhado rc=$? $(date)" >> $OUT/log.txt
  while true; do
    S0=$(size)
    # espera o comeco de um toque (bloqueia ate chegar um evento)
    dd if=/dev/input/event0 of=/dev/null bs=16 count=1 2> /dev/null
    : > /tmp/act
    # espera soltar: tamanho do registro estavel por 4 leituras seguidas
    prev=-1; same=0
    while [ $same -lt 4 ]; do
      cur=$(size)
      if [ "$cur" = "$prev" ]; then same=$(expr $same + 1); else same=0; fi
      prev=$cur
    done
    S1=$prev
    A=$(expr $S0 / 16)
    L=$(expr $S1 - $S0)
    B=$(expr $L / 16)
    R=$(dd if=/tmp/ev.log bs=16 skip=$A count=$B 2> /dev/null | hexdump -v | awk -f /tmp/decode.awk)
    set -- $R
    BTN=$1
    echo "$(date) btn=$1 sx=$2 sy=$3 rawx=$4 rawy=$5 amostras=$6" >> $OUT/taps.txt
    case "$BTN" in
      1)
        : > /tmp/busy
        if [ -f $APP/run.sh ]; then
          sh $APP/run.sh &
          echo $! > /tmp/appid
          wait $!
          rm -f /tmp/appid
        else
          cat $D/nao_instalado.raw > /dev/fb
          sleep 2
        fi
        rm -f /tmp/busy
        : > /tmp/act
        cat $D/menu.raw > /dev/fb
        ;;
      2)
        break
        ;;
      3)
        : > /tmp/busy
        cat $D/gps.raw > /dev/fb
        cat /var/run/gpspipe > $OUT/gps.txt 2> $OUT/gps_erro.txt &
        GP=$!
        sleep 25
        kill $GP 2> /dev/null
        ls -l /var/run > $OUT/var_run.txt 2>&1
        ps > $OUT/ps.txt 2>&1
        cat /var/run/gps_version.txt > $OUT/gps_version.txt 2>&1
        sync
        rm -f /tmp/busy
        : > /tmp/act
        cat $D/menu.raw > /dev/fb
        ;;
    esac
  done
  kill $CATPID 2> /dev/null
}

loop &
LP=$!

# vigia: sem nenhum toque por $IDLE s, encerra o menu e segue para o navegador original
(
  i=0
  b=0
  while [ $i -lt $IDLE ]; do
    sleep 1
    if [ -f /tmp/busy ]; then
      # dentro de um aplicativo: cada toque zera a contagem; sem toque por $BUSYIDLE s, volta ao original
      if [ -f /tmp/act ]; then
        rm -f /tmp/act
        b=0
      else
        b=$(expr $b + 1)
      fi
      i=0
      if [ $b -ge $BUSYIDLE ]; then
        i=$IDLE
      fi
    elif [ -f /tmp/act ]; then
      rm -f /tmp/act
      i=0
      b=0
    else
      i=$(expr $i + 1)
      b=0
    fi
    # cabo ligado a um PC (estado USB_STATE_DEVICE): entrega para o original, que faz o disco aparecer no PC
    if [ ! -f /tmp/busy ]; then
      ULAST=$(dmesg | grep "usbmode:\[" | tail -1)
      case "$ULAST" in
        *"==> USB_STATE_DEVICE") i=$IDLE ;;
      esac
    fi
  done
  echo "vigia encerrou o menu: i=$i b=$b ULAST=$ULAST $(date)" >> $OUT/log.txt
  if [ -f /tmp/appid ]; then
    kill $(cat /tmp/appid) 2> /dev/null
  fi
  kill $LP 2> /dev/null
) &
WD=$!

wait $LP
kill $WD 2> /dev/null
if [ -f /tmp/appid ]; then
  kill $(cat /tmp/appid) 2> /dev/null
fi
killall dd 2> /dev/null
killall cat 2> /dev/null
rm -f /tmp/busy /tmp/act /tmp/appid

echo "fim $(date)" >> $OUT/log.txt
sync

exec /mnt/sdcard/PNDNavigator
```

### A.2 `meunav/lib.sh`

```sh
# Funcoes comuns dos aplicativos do MEU NAVEGADOR.
# Usa o registro de toques /tmp/ev.log (mantido pelo launcher) e o decodificador /tmp/decode.awk.

size() { set -- $(wc -c < /tmp/ev.log); echo $1; }

# mostra uma tela inteira (arquivo .raw de 480x272, 16 bits)
show() { cat $1 > /dev/fb; }

# espera um toque; define SX e SY em pixels (0..479, 0..271), ou -1 se a leitura falhou
wait_tap() {
  S0=$(size)
  dd if=/dev/input/event0 of=/dev/null bs=16 count=1 2> /dev/null
  : > /tmp/act
  prev=-1; same=0
  while [ $same -lt 4 ]; do
    cur=$(size)
    if [ "$cur" = "$prev" ]; then same=$(expr $same + 1); else same=0; fi
    prev=$cur
  done
  S1=$prev
  A=$(expr $S0 / 16)
  L=$(expr $S1 - $S0)
  B=$(expr $L / 16)
  R=$(dd if=/tmp/ev.log bs=16 skip=$A count=$B 2> /dev/null | hexdump -v | awk -f /tmp/decode.awk)
  set -- $R
  if [ "$6" = "0" ]; then
    SX=-1; SY=-1
  else
    SX=$2; SY=$3
  fi
}
```

### A.3 `meunav/run.sh`, `lanterna.sh` e `velha.sh`

`run.sh`:

```sh
#!/bin/sh
# MEU NAVEGADOR: menu de aplicativos.
. /mnt/sdcard/meunav/lib.sh
M=/mnt/sdcard/meunav
while true; do
  show $M/menu.raw
  wait_tap
  if [ $SX -lt 0 ]; then
    continue
  fi
  if [ $SY -lt 91 ]; then
    sh $M/lanterna.sh
  elif [ $SY -lt 182 ]; then
    sh $M/velha.sh
  else
    break
  fi
done
```

`lanterna.sh`:

```sh
#!/bin/sh
# Lanterna: tela toda branca. Toque para sair.
. /mnt/sdcard/meunav/lib.sh
show /mnt/sdcard/meunav/white.raw
wait_tap
```

`velha.sh`:

```sh
#!/bin/sh
# Jogo da velha: voce e o X (toque numa casa); o aparelho joga de O. Toque em SAIR (embaixo) para voltar.
. /mnt/sdcard/meunav/lib.sh
G=/mnt/sdcard/meunav/velha

# desenha uma faixa de 77 linhas do tabuleiro ($1 = faixa 0..2, $2 = estado das 3 casas)
draw_band() {
  RW=$(expr $1 \* 77)
  dd if=$G/band_$2.raw of=/dev/fb bs=960 seek=$RW count=77 conv=notrunc 2> /dev/null
}

draw_all() {
  set -- $(echo $1 | awk '{print substr($0,1,3), substr($0,4,3), substr($0,7,3)}')
  draw_band 0 $1
  draw_band 1 $2
  draw_band 2 $3
  dd if=$G/bar.raw of=/dev/fb bs=960 seek=231 count=41 conv=notrunc 2> /dev/null
}

BOARD=000000000
draw_all $BOARD
while true; do
  wait_tap
  if [ $SX -lt 0 ]; then
    continue
  fi
  if [ $SY -ge 231 ]; then
    break
  fi
  CC=$(expr $SX / 160)
  RR=$(expr $SY / 77)
  MV=$(expr $RR \* 3 + $CC)
  set -- $(awk -v b=$BOARD -v m=$MV -f $G/ttt.awk)
  BOARD=$1
  ST=$2
  draw_all $BOARD
  case "$ST" in
    X) show $G/win.raw; sleep 2; BOARD=000000000; draw_all $BOARD ;;
    O) show $G/lose.raw; sleep 2; BOARD=000000000; draw_all $BOARD ;;
    D) show $G/draw.raw; sleep 2; BOARD=000000000; draw_all $BOARD ;;
  esac
done
```

`velha/ttt.awk`:

```awk
# Jogo da velha: recebe -v b=<9 digitos 0/1/2> -v m=<casa 0..8>; imprime "<novo tabuleiro> <status>"
# 1 = X (voce), 2 = O (aparelho). status: - (jogada invalida), . (segue), X, O, D (empate)
function line(a,b2,c2,p){return c[a]==p&&c[b2]==p&&c[c2]==p}
function win(p){return line(0,1,2,p)||line(3,4,5,p)||line(6,7,8,p)||line(0,3,6,p)||line(1,4,7,p)||line(2,5,8,p)||line(0,4,8,p)||line(2,4,6,p)}
function full(  i){for(i=0;i<9;i++)if(c[i]=="0")return 0;return 1}
function tryp(p,  i){for(i=0;i<9;i++)if(c[i]=="0"){c[i]=p;if(win(p)){c[i]="0";return i}c[i]="0"}return -1}
function pick(  r,i,o){r=tryp("2");if(r>=0)return r;r=tryp("1");if(r>=0)return r;split("4 0 2 6 8 1 3 5 7",o," ");for(i=1;i<=9;i++)if(c[o[i]]=="0")return o[i]}
BEGIN{
  for(i=0;i<9;i++)c[i]=substr(b,i+1,1)
  st="."
  if(m<0||m>8||c[m]!="0"){print b,"-";exit}
  c[m]="1"
  if(win("1"))st="X"
  else if(full())st="D"
  else{mv=pick();c[mv]="2";if(win("2"))st="O";else if(full())st="D"}
  out="";for(i=0;i<9;i++)out=out c[i]
  print out,st
}
```

### A.4 Decodificador de toque (awk)

Este é o programa que o launcher grava em `/tmp/decode.awk`. Entrada: saída do `hexdump -v` de um trecho do registro de eventos. Saída: `botão sx sy rawx rawy amostras`. O "botão" depende da divisão do launcher (3 faixas); os aplicativos só usam `sx` e `sy`.

```awk
function h(s,  i,n,c){n=0;s=tolower(s);for(i=1;i<=length(s);i++){c=index("0123456789abcdef",substr(s,i,1))-1;n=n*16+c}return n}
NF>=9 { t=h($6); c=h($7); v=h($8)+65536*h($9);
  if(t==3&&c==0) x=v; else if(t==3&&c==1) y=v;
  else if(t==0&&c==0&&x!=""&&y!="") {n++; X[n]=x; Y[n]=y}
}
END {
  if(n==0){print "0 0 0 0 0 0"; exit}
  a=1;b=n; if(n>6){a=3;b=n-2}
  sx=0;sy=0;m=0; for(i=a;i<=b;i++){sx+=X[i];sy+=Y[i];m++}
  rx=sx/m; ry=sy/m
  px=16+(919-rx)*448/822; py=16+(855-ry)*240/707
  if(px<0)px=0; if(px>479)px=479; if(py<0)py=0; if(py>271)py=271
  if(py<91) btn=1; else if(py<182) btn=2; else btn=3
  printf "%d %d %d %d %d %d\n", btn, px, py, rx, ry, n
}
```

---

## Apêndice B: como inspecionar o firmware

Receita (Python 3) para extrair o kernel e o ramdisk do `ttsystem` e listar/gravar os arquivos do ramdisk. Funciona para o `ttsystem` da versão 9.541. Para outras versões, localize os blocos gzip procurando o início `1f 8b 08`.

```python
import zlib, re, os

d = open('ttsystem','rb').read()
print(d[:5])                                      # b'TTBLT'
offs = [m.start() for m in re.finditer(b'\x1f\x8b\x08', d)]
print(offs)                                       # aqui: [13732, 1186680]

kernel = zlib.decompressobj(31).decompress(d[offs[0]:])
initrd = zlib.decompressobj(31).decompress(d[offs[1]:])   # cpio "newc"

# extrai o cpio newc (sem precisar do comando cpio)
p = 0
while initrd[p:p+6] == b'070701':
    h = initrd[p:p+110]
    f = lambda i: int(h[6+8*i:14+8*i], 16)
    mode, size, namesz = f(1), f(6), f(11)
    name = initrd[p+110:p+110+namesz-1].decode('latin1')
    ds = (p+110+namesz+3) & ~3
    data = initrd[ds:ds+size]
    p = (ds+size+3) & ~3
    if name == 'TRAILER!!!': break
    t = mode & 0o170000
    if t == 0o040000: os.makedirs(name, exist_ok=True)
    elif t == 0o100000:
        os.makedirs(os.path.dirname(name) or '.', exist_ok=True)
        open(name,'wb').write(data)
    elif t == 0o120000:
        try: os.symlink(data.decode('latin1'), name)
        except OSError: pass
```

Depois de extrair, leia `etc/rc` (o script de boot), `etc/rc.glgps`, `etc/rc.usbkill` e rode `strings` nos binários (`PNDNavigator`, `bin/ttpnpd`) para descobrir nomes de arquivos de controle e caminhos de sistema.

---

## Apêndice C: gerar imagens para a tela

Requer Python 3 e Pillow (`pip install pillow`). Gera um `.raw` no formato certo (480x272, RGB565 little-endian).

```python
from PIL import Image, ImageDraw, ImageFont
import struct

W, H = 480, 272
FONT = "DejaVuSans-Bold.ttf"          # ajuste o caminho da sua fonte

def to565(img):
    px = img.convert('RGB').load()
    w, h = img.size
    out = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            out += struct.pack('<H', ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
    return bytes(out)

def ctext(d, box, txt, font, fill):   # texto centralizado numa caixa
    x0, y0, x1, y1 = box
    bb = d.textbbox((0, 0), txt, font=font)
    d.text(((x0 + x1 - (bb[2] - bb[0])) // 2 - bb[0],
            (y0 + y1 - (bb[3] - bb[1])) // 2 - bb[1]), txt, font=font, fill=fill)

# exemplo: menu com 3 botões (zonas de toque: sy < 91, sy < 182, resto)
img = Image.new('RGB', (W, H), (25, 25, 30))
d = ImageDraw.Draw(img)
f = ImageFont.truetype(FONT, 34)
for box, cor, txt in [((10, 8, 470, 82),   (230, 170, 20),  "LANTERNA"),
                      ((10, 98, 470, 172), (120, 60, 170),  "JOGO"),
                      ((10, 188, 470, 262),(90, 90, 100),   "VOLTAR")]:
    d.rounded_rectangle(box, radius=14, fill=cor)
    ctext(d, box, txt, f, (255, 255, 255))
open('menu.raw', 'wb').write(to565(img))         # tem que dar 261120 bytes
```

Para uma **faixa** (como as do jogo da velha), crie uma imagem de largura 480 e altura N, converta com `to565` e grave com `seek=<linha inicial>` e `count=N` (seção 5.1).

Para **testar sem o aparelho**, copie um arquivo de 261120 bytes para simular `/dev/fb`, rode os mesmos `dd` com `of=` apontando para ele e converta o arquivo de volta para PNG (o inverso de `to565`).

---

## Apêndice D: launcher v10 (não testado no aparelho)

Código completo do `ttn` v10 (descrito na seção 10.10). Os demais arquivos: `data/home.awk` (monta uma página da tela inicial; contém a fonte 9x15 como cadeia de "0" e "1", gerada a partir do mesmo arquivo de máscaras de `arq/render.awk`), `data/lib.sh` (igual ao do Apêndice A, com `wait_tap_fast` e o registro de PID) e as imagens no formato "rows".

```sh
#!/bin/sh
# Launcher v10: tela inicial com os aplicativos da pasta apps/.
#   apps/NOME.sh        script principal do aplicativo
#   apps/NOME/          pasta do aplicativo (arquivos dele); apps/NOME/icon.raw = icone 80x80, RGB565 (12800 bytes)
#   data/appList.txt    lista gerada por este launcher a cada inicializacao
# O unico icone fixo e "ORIGINAL" (menu original da TomTom). Sem toque por 60 s, ou com o cabo num PC,
# abre o original (ele cuida do USB, do desligar e da bateria).

SD=${SD:-/mnt/sdcard}
FB=${FB:-/dev/fb}
EV=${EV:-/dev/input/event0}
FSYS=${FSYS:-/sys/class/graphics/fb0}
APPS=$SD/apps
DATA=$SD/data
OUT=$SD/launcher_log
IDLE=${IDLE:-60}
BUSYIDLE=300
OLDIFS=$IFS

mkdir -p $OUT $APPS $DATA/cache/icons
echo "inicio $(date)" > $OUT/log.txt
rm -f /tmp/busy /tmp/act /tmp/appid /tmp/apppids
log() { echo "$1" >> $OUT/log.txt; }

go_original() {
  echo "0,0" > $FSYS/pan 2> /dev/null
  sync
  exec $SD/PNDNavigator
}

# arquivos essenciais do launcher; se faltar algum, abre o original na hora
FALTA=""
for f in home.awk bar.rows icon_original.rows icon_default.rows lib.sh; do
  if [ ! -f $DATA/$f ]; then
    FALTA="$FALTA $f"
  fi
done
log "arquivos essenciais faltando:$FALTA"
case "$FALTA" in ?*) go_original ;; esac

# decodificador dos eventos de toque (calibrado nos testes 3 e 4)
cat > /tmp/decode.awk <<'AWK'
function h(s,  i,n,c){n=0;s=tolower(s);for(i=1;i<=length(s);i++){c=index("0123456789abcdef",substr(s,i,1))-1;n=n*16+c}return n}
NF>=9 { t=h($6); c=h($7); v=h($8)+65536*h($9);
  if(t==3&&c==0) x=v; else if(t==3&&c==1) y=v;
  else if(t==0&&c==0&&x!=""&&y!="") {n++; X[n]=x; Y[n]=y}
}
END {
  if(n==0){print "0 0 0 0 0 0"; exit}
  a=1;b=n; if(n>6){a=3;b=n-2}
  sx=0;sy=0;m=0; for(i=a;i<=b;i++){sx+=X[i];sy+=Y[i];m++}
  rx=sx/m; ry=sy/m
  px=16+(919-rx)*448/822; py=16+(855-ry)*240/707
  if(px<0)px=0; if(px>479)px=479; if(py<0)py=0; if(py>271)py=271
  printf "%d %d %d %d %d %d\n", 0, px, py, rx, ry, n
}
AWK

size() { set -- $(wc -c < /tmp/ev.log); echo $1; }

# encerra o aplicativo e todos os processos que ele registrou (a biblioteca lib.sh grava o PID em /tmp/apppids)
killapps() {
  if [ -f /tmp/appid ]; then
    kill $(cat /tmp/appid) 2> /dev/null
  fi
  if [ -f /tmp/apppids ]; then
    kill $(cat /tmp/apppids) 2> /dev/null
  fi
}

# ---------------------------------------------------------------- 1. descobre os aplicativos e grava data/appList.txt
scan_apps() {
  ls -l "$APPS" > /tmp/ls_apps.txt 2>&1
  ls -l "$APPS"/*/icon.raw > /tmp/ls_icons.txt 2>&1
  awk -v apps="$APPS" '
    function rest(  t){ t=$0; sub(/^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +/,"",t); return t }
    FNR==NR { if(NF>=9 && $1 ~ /^-/){ nm=rest(); if(nm ~ /\.sh$/){ sub(/\.sh$/,"",nm); sh[nm]=1 } } next }
    { if(NF>=9 && $1 ~ /^-/){ p=rest(); sub(apps "/","",p); sub(/\/icon\.raw$/,"",p); isz[p]=$5; st[p]=$6 "_" $7 "_" $8 } }
    END{ for(n in sh){ s=(n in isz)?isz[n]:0; t=(n in isz)?st[n]:"-"; print n "|" apps "/" n ".sh|" apps "/" n "/icon.raw|" s "|" t } }
  ' /tmp/ls_apps.txt /tmp/ls_icons.txt | sort > /tmp/appList.new
  { echo "# nome|script|icone|tamanho_do_icone|carimbo_do_icone  (gerado pelo ttn a cada inicializacao)"; cat /tmp/appList.new; } > /tmp/appList.out
  if cmp /tmp/appList.out $DATA/appList.txt > /dev/null 2>&1; then
    log "appList.txt sem mudancas"
  else
    cp /tmp/appList.out $DATA/appList.txt
    sync
    log "appList.txt atualizado"
  fi
}

# ---------------------------------------------------------------- 2. converte os icones (so quando mudam) e monta a lista da tela inicial
prepare_entries() {
  echo "ORIGINAL|$DATA/icon_original.rows|ORIGINAL|" > /tmp/home_entries.txt
  while read LINE; do
    case "$LINE" in '#'*|'') continue ;; esac
    IFS='|'; set -- $LINE; IFS=$OLDIFS
    NAME=$1; SCRIPT=$2; ICON=$3; ISZ=$4; STAMP=$5
    ROWS=$DATA/icon_default.rows
    case "$ISZ" in
      12800)
        CK=$DATA/cache/icons/$NAME
        OLD=""
        read OLD < $CK.stamp 2> /dev/null
        case "$OLD" in
          "$ISZ|$STAMP") ROWS=$CK.rows ;;
          *)
            hexdump -v -e '160/1 "%u " "\n"' "$ICON" 2> /dev/null | awk '{ s=""; for(i=1;i<=NF;i++){ v=$i; if(v==0) v=1; else if(v==10) v=11; s=s sprintf("%c",v) } print s }' > $CK.rows.tmp
            set -- $(wc -l < $CK.rows.tmp)
            case "$1" in
              80) mv $CK.rows.tmp $CK.rows; echo "$ISZ|$STAMP" > $CK.stamp; ROWS=$CK.rows; log "icone convertido: $NAME" ;;
              *) rm -f $CK.rows.tmp; log "icone invalido (a conversao falhou): $NAME" ;;
            esac ;;
        esac ;;
      0) ;;
      *) log "icone com tamanho errado ($ISZ bytes, o certo e 12800): $NAME" ;;
    esac
    echo "$NAME|$ROWS|$SCRIPT|$NAME" >> /tmp/home_entries.txt
  done < /tmp/appList.new
}

# ---------------------------------------------------------------- 3. monta as paginas da tela inicial (em memoria)
compose_pages() {
  set -- $(wc -l < /tmp/home_entries.txt)
  NENT=$1
  NPAGES=$(( (NENT + 7) / 8 ))
  p=0
  while :; do
    case $p in $NPAGES) break ;; esac
    awk -v page=$p -v pages=$NPAGES -v barfile=$DATA/bar.rows -f $DATA/home.awk /tmp/home_entries.txt > /tmp/home_$p.raw
    set -- $(wc -c < /tmp/home_$p.raw)
    case "$1" in 261120) ;; *) log "pagina $p com tamanho errado ($1); abrindo o original"; go_original ;; esac
    p=$((p + 1))
  done
}

read T0 _ < /proc/uptime
scan_apps
prepare_entries
compose_pages
read T1 _ < /proc/uptime
log "aplicativos encontrados: $((NENT - 1)); paginas: $NPAGES; preparo de $T0 a $T1 (uptime)"

# ---------------------------------------------------------------- 4. toque
lw_tap() {
  while :; do
    case "$SIM" in
      ?*) read SX SY <&3 || exit 0; : > /tmp/act; break ;;
    esac
    S0=$(size)
    dd if=$EV of=/dev/null bs=16 count=1 2> /dev/null
    : > /tmp/act
    prev=-1; same=0
    while :; do
      cur=$(size)
      case $cur in $prev) same=$((same + 1)) ;; *) same=0 ;; esac
      prev=$cur
      case $same in 4) break ;; esac
    done
    S1=$prev
    R=$(dd if=/tmp/ev.log bs=16 skip=$((S0 / 16)) count=$(((S1 - S0) / 16)) 2> /dev/null | hexdump -v | awk -f /tmp/decode.awk)
    set -- $R
    case "$6" in 0) continue ;; esac
    SX=$2; SY=$3
    break
  done
}

run_app() { # $1 = script, $2 = nome
  APPDIR=$APPS/$2
  export APPDIR DATA SD
  : > /tmp/busy
  rm -f /tmp/apppids
  sh "$1" &
  echo $! > /tmp/appid
  wait $!
  rm -f /tmp/appid /tmp/apppids /tmp/busy
  : > /tmp/act
  log "app encerrado: $2 $(date)"
}

loop() {
  : > /tmp/ev.log
  cat $EV >> /tmp/ev.log 2> $OUT/ev_erro.txt &
  CATPID=$!
  PAGE=0
  cat /tmp/home_$PAGE.raw > $FB
  while true; do
    lw_tap
    case $((SY >= 224)) in
      1)
        case $((SX < 120)) in
          1) case $((PAGE > 0)) in 1) PAGE=$((PAGE - 1)); cat /tmp/home_$PAGE.raw > $FB ;; esac ;;
        esac
        case $((SX >= 360)) in
          1) case $((PAGE + 1 < NPAGES)) in 1) PAGE=$((PAGE + 1)); cat /tmp/home_$PAGE.raw > $FB ;; esac ;;
        esac ;;
      *)
        IDX=$((PAGE * 8 + (SY / 112) * 4 + SX / 120 + 1))
        case $((IDX <= NENT)) in
          1)
            SCRIPT=$(awk -F'|' -v n=$IDX 'NR==n{print $3}' /tmp/home_entries.txt)
            ANAME=$(awk -F'|' -v n=$IDX 'NR==n{print $4}' /tmp/home_entries.txt)
            echo "$(date) toque ($SX,$SY) item $IDX: $ANAME $SCRIPT" >> $OUT/taps.txt
            case "$SCRIPT" in
              ORIGINAL) break ;;
              *) run_app "$SCRIPT" "$ANAME"; cat /tmp/home_$PAGE.raw > $FB ;;
            esac ;;
        esac ;;
    esac
  done
  kill $CATPID 2> /dev/null
}

rm -f $OUT/taps.txt
loop &
LP=$!

# vigia: sem toque por $IDLE s (ou $BUSYIDLE s dentro de um aplicativo), ou com o cabo num PC, abre o original
(
  i=0
  b=0
  while [ $i -lt $IDLE ]; do
    sleep 1
    if [ -f /tmp/busy ]; then
      if [ -f /tmp/act ]; then
        rm -f /tmp/act
        b=0
      else
        b=$(expr $b + 1)
      fi
      i=0
      if [ $b -ge $BUSYIDLE ]; then
        i=$IDLE
      fi
    elif [ -f /tmp/act ]; then
      rm -f /tmp/act
      i=0
      b=0
    else
      i=$(expr $i + 1)
      b=0
    fi
    # cabo ligado a um PC (estado USB_STATE_DEVICE): entrega para o original, que faz o disco aparecer no PC
    if [ ! -f /tmp/busy ]; then
      ULAST=$(dmesg | grep "usbmode:\[" | tail -1)
      case "$ULAST" in
        *"==> USB_STATE_DEVICE") i=$IDLE ;;
      esac
    fi
  done
  echo "vigia encerrou a tela inicial: i=$i b=$b ULAST=$ULAST $(date)" >> $OUT/log.txt
  killapps
  kill $LP 2> /dev/null
) &
WD=$!

wait $LP
kill $WD 2> /dev/null
killapps
killall dd 2> /dev/null
killall cat 2> /dev/null
rm -f /tmp/busy /tmp/act /tmp/appid /tmp/apppids
log "fim $(date)"
go_original
```
