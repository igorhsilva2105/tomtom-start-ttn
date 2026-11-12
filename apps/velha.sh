#!/bin/sh
# Jogo da velha: voce e o X (toque numa casa); o aparelho joga de O. Toque em SAIR (embaixo) para voltar.
. ${DATA:-/mnt/sdcard/data}/lib.sh
G=${APPDIR:-/mnt/sdcard/apps/velha}

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
