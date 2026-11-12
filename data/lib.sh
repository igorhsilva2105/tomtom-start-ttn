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

# ---------------------------------------------------------------------------
# wait_tap_fast: responde NO INSTANTE do toque (nao espera soltar).
# Le o primeiro pacote do toque (4 eventos: X, Y, pressao, SYN) direto do dispositivo,
# converte para pixels so com o shell e define SX e SY. Define M0 (uptime no toque).
# Pacotes que nao sao de "toque novo" (dedo ainda apoiado) sao descartados.
EV=${EV:-/dev/input/event0}
HEXOK=$( (echo $((0x1f))) 2> /dev/null )
wait_tap_fast() {
  while :; do
    dd if=$EV bs=16 count=4 of=/tmp/first.bin 2> /dev/null
    hexdump -v /tmp/first.bin > /tmp/first.txt
    { read o a b c d t1 c1 x1 y1; read o a b c d t2 c2 x2 y2; read o a b c d t3 c3 x3 y3; } < /tmp/first.txt
    case "$t1$c1 $t2$c2 $t3$c3 $x3" in
      "00030000 00030001 00030018 03ff") break ;;
    esac
  done
  : > /tmp/act
  read M0 _ < /proc/uptime
  case "$HEXOK" in
    31) RX=$((0x$x1)); RY=$((0x$x2)) ;;
    *) set -- $(printf '%d %d' 0x$x1 0x$x2); RX=$1; RY=$2 ;;
  esac
  SX=$((16 + (919 - RX) * 448 / 822))
  SY=$((16 + (855 - RY) * 240 / 707))
  case $((SX < 0)) in 1) SX=0 ;; esac
  case $((SX > 479)) in 1) SX=479 ;; esac
  case $((SY < 0)) in 1) SY=0 ;; esac
  case $((SY > 271)) in 1) SY=271 ;; esac
}

# registra este processo para o launcher poder encerra-lo (e aos filhos) se precisar
echo $$ >> /tmp/apppids
