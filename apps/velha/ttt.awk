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
