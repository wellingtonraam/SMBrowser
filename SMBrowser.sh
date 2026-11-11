#!/bin/bash
# ============================================================================
#  SMBrowser v2.1 - Navegador e baixador de arquivos SMB/Samba para ArkOS
#  Feito para o R36H (ArkOS 2.0). Interface propria na tela do console
#  (nao usa "dialog"), controlada pelo gamepad.
#
#  - Interface em portugues e ingles (escolha no primeiro uso)
#  - Servidores salvos em  /roms/smbrowser/servers.conf  (editavel no PC)
#  - Formulario de servidor com TESTE de conexao (usuario, senha, dominio)
#  - Teclado na tela em GRADE (letras, numeros e simbolos juntos)
#  - Marca varios arquivos, baixa pasta inteira, retoma download, B cancela
#  - Precisa de smbclient (o app oferece instalar sozinho)
# ============================================================================

VERSION="2.1"
APP_NAME="SMBrowser"
export LC_ALL=C.UTF-8 LANG=C.UTF-8

# ---------------------------------------------------------------- caminhos
if [ -n "$SMB_CONF_DIR" ]; then CONF_DIR="$SMB_CONF_DIR"
elif [ -d /roms ]; then CONF_DIR="/roms/smbrowser"
else CONF_DIR="$HOME/smbrowser"; fi
CONF="$CONF_DIR/servers.conf"
STATE="$CONF_DIR/state.conf"
GPTK="$CONF_DIR/smbrowser.gptk"
ERRLOG="$CONF_DIR/ultimo-erro.log"
TTY="${SMB_TTY:-/dev/tty1}"
WORK="$(mktemp -d /dev/shm/smbrowser.XXXXXX 2>/dev/null || mktemp -d /tmp/smbrowser.XXXXXX)"
AUTH="$WORK/auth"
LOG="$WORK/smb.log"
GPTK_PID=""
STTY_SAVE=""

# ------------------------------------------------------------------ estado
DEST="/roms"
[ -d /roms ] || DEST="$HOME"
SMB1="0"            # 1 = sempre usar SMB1/NT1 (NAS e Windows XP antigos)
UI_LANG=""          # pt | en  (vazio = perguntar no primeiro uso)

load_state() {
  [ -f "$STATE" ] && . "$STATE"
  if [ ! -d "$DEST" ]; then DEST="/roms"; [ -d /roms ] || DEST="$HOME"; fi
}
save_state() {
  mkdir -p "$CONF_DIR" 2>/dev/null
  { printf 'DEST=%q\n' "$DEST"; printf 'SMB1=%q\n' "$SMB1"; printf 'UI_LANG=%q\n' "$UI_LANG"; } > "$STATE"
}

# ----------------------------------------------------------------- terminal
CSI=$'\e['
ST_TITLE="${CSI}1;37;44m"
ST_SEL="${CSI}30;46m"
ST_FOOT="${CSI}30;47m"
ST_FIELD="${CSI}1;37;42m"
ST_RST="${CSI}0m"
H=24; W=64; MH=20

cleanup() {
  [ -n "$GPTK_PID" ] && kill "$GPTK_PID" 2>/dev/null
  pkill -f "gptokeyb -1 $APP_NAME.sh" 2>/dev/null
  [ -n "$STTY_SAVE" ] && stty -F "$TTY" "$STTY_SAVE" 2>/dev/null
  printf '%s' "${CSI}?25h" > "$TTY" 2>/dev/null
  rm -rf "$WORK"
  printf '\033c' > "$TTY" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

write_gptk() {
  mkdir -p "$CONF_DIR" 2>/dev/null
  cat > "$GPTK" <<'EOF'
up = up
down = down
left = left
right = right
a = enter
b = esc
x = space
y = tab
l1 = pageup
r1 = pagedown
start = enter
back = esc
EOF
}

setup_terminal() {
  if [ "$TTY" = "/dev/tty1" ]; then
    sudo chmod 666 /dev/tty1 /dev/uinput 2>/dev/null
    export TERM=linux
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
    setfont /usr/share/consolefonts/Lat7-TerminusBold20x10.psf.gz 2>/dev/null
    printf '\033c' > "$TTY"
    write_gptk
    if [ -x /opt/inttools/gptokeyb ]; then
      /opt/inttools/gptokeyb -1 "$APP_NAME.sh" -c "$GPTK" > /dev/null 2>&1 &
      GPTK_PID=$!
    fi
  fi
  exec 3>"$TTY" 4<"$TTY"
  STTY_SAVE=$(stty -F "$TTY" -g 2>/dev/null)
  stty -F "$TTY" -echo -icanon min 1 time 0 2>/dev/null
  local sz; sz=$(stty -F "$TTY" size 2>/dev/null)
  H=${sz% *}; W=${sz#* }
  [[ "$H" =~ ^[0-9]+$ ]] && (( H >= 15 )) || H=24
  [[ "$W" =~ ^[0-9]+$ ]] && (( W >= 40 )) || W=64
  MH=$(( H - 4 ))
  printf '%s' "${CSI}?25l${CSI}2J" >&3
}

# ---------------------------------------------------------- idioma (PT/EN)
# Tabela de traducao PT -> EN (ordem: frases longas primeiro). A interface e escrita em
# portugues e traduzida na hora de desenhar a tela quando UI_LANG=en.
TRR=""
TR_PT=(
  'Se baixou ROMs: reinicie o EmulationStation (Start > Opcoes > Reiniciar) para atualizar a lista de jogos.'
  'O servidor recusou a conexao (versao do SMB incompativel?). Tente ligar "SMB1 forcado" em Configuracoes.'
  'O servidor nao mostrou nenhum compartilhamento (alguns ocultam a lista). Digite o nome manualmente.'
  'Esse compartilhamento nao existe no servidor. Confira o nome (espacos e maiusculas contam).'
  'smbclient nao instalado. Conecte ao Wi-Fi (com internet) e abra o SMBrowser de novo.'
  'Coloque um deles no campo Compartilhamento (ou deixe vazio para escolher na hora).'
  'Nao achei o IP deste aparelho. Conecte ao Wi-Fi primeiro (Opcoes > Wi-Fi).'
  'Usuario ou senha incorretos (ou esse usuario nao existe no servidor).'
  'O programa smbclient (que fala com a rede) nao esta instalado.'
  'Nenhum servidor salvo ainda. Escolha [+] Adicionar servidor.'
  'Setas: mover   [OK] ou R1 salva   [Cancelar] sai sem salvar'
  'ATENCAO: pode nao caber (arquivos ja baixados nao contam).'
  'Acesso negado: esse usuario nao tem permissao aqui.'
  'A conta foi bloqueada (muitas tentativas erradas).'
  'A: digitar tecla     B: apagar (vazio = cancelar)'
  'Preencha o campo "Servidor (IP)" antes de salvar.'
  'B: cancelar (rodar de novo retoma de onde parou)'
  'A:abrir/escolher  X:usar esta pasta  B:cancelar'
  'Digitar o nome do compartilhamento manualmente?'
  'Instalar agora? Precisa de Wi-Fi com internet.'
  'A: Baixar    Y: Mudar destino    B: Cancelar'
  'Dominio ou grupo (deixe vazio se nao sabe)'
  'Preencha o campo "Servidor (IP)" primeiro.'
  'A:abrir/baixar  X:marcar  Y:menu  B:voltar'
  'X: espaco   Y: Shift   R1: confirmar (OK)'
  'Tempo esgotado: o servidor nao respondeu.'
  '[+] Digitar o nome de um compartilhamento'
  'Servidor: IP ou nome (ex: 192.168.1.112)'
  'CANCELADO (rode de novo para continuar).'
  'A:editar  X:ver senha  Y:salvar  B:sair'
  'Baixar TUDO desta pasta (com subpastas)'
  'SMB1 forcado (NAS/Windows antigo): SIM'
  'SMB1 forcado (NAS/Windows antigo): nao'
  'A conta esta desativada no servidor.'
  'A:conectar  X:editar  Y:mais  B:sair'
  'Porta 445 do servidor responde: SIM'
  'Porta 445 do servidor responde: NAO'
  'Porta 139 do servidor responde: SIM'
  'Porta 139 do servidor responde: NAO'
  'Nao consegui falar com o servidor.'
  'A conecta. X edita. Y mais opcoes.'
  'Nome do atalho (ex: Acervo Jogos)'
  'Marcar todos os arquivos da lista'
  'Nenhum servidor SMB encontrado em'
  'Compartilhamento (pasta de rede)'
  '(vazio, normalmente nao precisa)'
  'Pasta ou arquivo nao encontrado.'
  'Escolha qual pasta de rede abrir'
  'Nao listou os compartilhamentos'
  '(vazio = convidado, sem senha)'
  'Compartilhamentos encontrados:'
  'A: editar o campo selecionado'
  'Descartar o que voce digitou?'
  'Nao encontrei nenhum arquivo.'
  'Ver ultimo erro / diagnostico'
  'Nenhum erro registrado ainda.'
  'A senha expirou no servidor.'
  'SEM IP (Wi-Fi desconectado?)'
  'Filtrar por parte do nome...'
  'Procurando servidores SMB em'
  'Usuario (login do servidor)'
  '(vazio = escolher na lista)'
  'O smbclient falhou (codigo '
  'Procurar servidores na rede'
  'Nao consegui criar a pasta'
  'Rode de novo para retomar.'
  'Sem espaco no cartao para'
  'O arquivo nao foi criado.'
  '[+] Criar nova pasta aqui'
  'Escolher pasta de destino'
  'Escolha um para cadastrar'
  'Nome do compartilhamento'
  '==> CANCELAR (descartar)'
  'Tudo certo: pode salvar.'
  'Falha ao listar a pasta.'
  'Sair desta pasta de rede'
  'Ajuda: controles e dicas'
  'Filtrar (parte do nome)'
  'com acesso de convidado'
  '>>> USAR ESTA PASTA <<<'
  'smbclient nao instalado'
  'Mudar pasta de destino'
  'Servidores encontrados'
  '[+] Adicionar servidor'
  '(VAZIO - obrigatorio)'
  'Configuracoes e ajuda'
  'Excluir este servidor'
  'Testando conexao com'
  'A:escolher  B:voltar'
  ' - compartilhamentos'
  'Listando arquivos de'
  'Nome do atalho   : '
  'Servidor (IP)    : '
  'Compartilhamento : '
  'Usuario          : '
  'Senha            : '
  'Dominio/Grupo    : '
  '(igual ao servidor)'
  '.. (subir um nivel)'
  'Nome da nova pasta'
  '==> TESTAR CONEXAO'
  'IP deste aparelho:'
  'Nao consegui abrir'
  ' itens | marcados:'
  'Excluir o servidor'
  'A ou B: continuar'
  'A: Sim     B: Nao'
  'Atualizar a lista'
  'O que fazer aqui?'
  'A:abrir  B:voltar'
  '(uns 10 segundos)'
  'Pasta de destino:'
  'Falta o servidor'
  'Detalhe tecnico:'
  'Nada para baixar'
  ' arquivos, total'
  ' com esse filtro'
  'Editar servidor'
  '(este aparelho)'
  'Meus servidores'
  'Testar conexao'
  'itens marcados'
  'Desmarcar tudo'
  '(setas rolam)'
  'Novo servidor'
  'Servidor (IP)'
  'com o usuario'
  'Espaco livre:'
  'Ultimo erro ('
  'Limpar filtro'
  'Menu de acoes'
  'Conectando em'
  'Configuracoes'
  'Ja existiam:'
  'Pasta atual:'
  'SMB1 forcado'
  'mais abaixo'
  'Conectou em'
  'Incompleto:'
  'A: escolher'
  'Ultimo erro'
  'mais acima'
  '==> SALVAR'
  'Conexao OK'
  '(nada aqui'
  ' | filtro:'
  'Erro SMB:'
  'Baixados:'
  'Com erro:'
  'Resultado'
  'Baixar os'
  'convidado'
  'Baixando'
  'Destino:'
  'destino:'
  'Arquivo:'
  'Tamanho:'
  'Sem rede'
  'Procurar'
  '[x] Sair'
  'Conectar'
  'Cancelar'
  '(vazia)'
  'precisa'
  'Excluir'
  'Usuario'
  'Texto:'
  'Falhou'
  'Editar'
  'Voltar'
  'Baixar'
  'livre'
  'Lendo'
  'Ajuda'
  'Senha'
  'Sair'
  'Erro'
)
TR_EN=(
  'If you downloaded ROMs: restart EmulationStation (Start > Options > Restart) to refresh the game list.'
  'The server refused the connection (incompatible SMB version?). Try turning on "Force SMB1" in Settings.'
  'The server listed no shares (some hide the list). Type the name manually.'
  'That share does not exist on the server. Check the name (spaces and capitals matter).'
  'smbclient is not installed. Connect to Wi-Fi (with internet) and open SMBrowser again.'
  'Put one of them in the Share field (or leave it empty to pick on the spot).'
  'Could not find the IP of this device. Connect to Wi-Fi first (Options > Wi-Fi).'
  'Wrong user or password (or that user does not exist on the server).'
  'The smbclient program (which talks to the network) is not installed.'
  'No servers saved yet. Pick [+] Add server.'
  'D-pad: move  [OK] or R1: save  [Cancel]: discard'
  'WARNING: it may not fit (files already downloaded do not count).'
  'Access denied: this user has no permission here.'
  'The account is locked (too many wrong attempts).'
  'A: type key     B: delete (empty = cancel)'
  'Fill in the "Server (IP)" field before saving.'
  'B: cancel (running again resumes where it stopped)'
  'A:open/choose  X:use this folder  B:cancel'
  'Type the share name manually?'
  'Install now? Needs Wi-Fi with internet.'
  'A: Download    Y: Change destination    B: Cancel'
  'Domain or workgroup (leave empty if unsure)'
  'Fill in the "Server (IP)" field first.'
  'A:open/download  X:mark  Y:menu  B:back'
  'X: space   Y: Shift   R1: confirm (OK)'
  'Timed out: the server did not answer.'
  '[+] Type a share name'
  'Server: IP or name (e.g. 192.168.1.112)'
  'CANCELED (run again to continue).'
  'A:edit  X:show password  Y:save  B:exit'
  'Download EVERYTHING in this folder (with subfolders)'
  'Force SMB1 (old NAS/Windows): YES'
  'Force SMB1 (old NAS/Windows): no'
  'The account is disabled on the server.'
  'A:connect  X:edit  Y:more  B:quit'
  'Server port 445 answers: YES'
  'Server port 445 answers: NO'
  'Server port 139 answers: YES'
  'Server port 139 answers: NO'
  'Could not reach the server.'
  'A connects. X edits. Y more options.'
  'Shortcut name (e.g. My PC)'
  'Mark all files in the list'
  'No SMB server found on'
  'Share (network folder name)'
  '(empty, usually not needed)'
  'Folder or file not found.'
  'Choose which network folder to open'
  'Could not list the shares'
  '(empty = guest, no password)'
  'Shares found:'
  'A: edit the selected field'
  'Discard what you typed?'
  'No files found.'
  'View last error / diagnostics'
  'No error recorded yet.'
  'The password has expired on the server.'
  'NO IP (Wi-Fi disconnected?)'
  'Filter by part of the name...'
  'Searching for SMB servers on'
  'User (server login)'
  '(empty = pick from list)'
  'smbclient failed (code '
  'Find servers on the network'
  'Could not create the folder'
  'Run again to resume.'
  'Not enough space on the card for'
  'The file was not created.'
  '[+] Create new folder here'
  'Choose destination folder'
  'Pick one to register'
  'Share name'
  '==> CANCEL (discard)'
  'All good: you can save.'
  'Failed to list the folder.'
  'Leave this network folder'
  'Help: controls and tips'
  'Filter (part of the name)'
  'as guest'
  '>>> USE THIS FOLDER <<<'
  'smbclient not installed'
  'Change destination folder'
  'Servers found'
  '[+] Add server'
  '(EMPTY - required)'
  'Settings and help'
  'Delete this server'
  'Testing connection to'
  'A:choose  B:back'
  ' - shares'
  'Listing files in'
  'Shortcut name    : '
  'Server (IP)      : '
  'Share            : '
  'User             : '
  'Password         : '
  'Domain/Group     : '
  '(same as server)'
  '.. (go up one level)'
  'New folder name'
  '==> TEST CONNECTION'
  'This device IP:'
  'Could not open'
  ' items | marked:'
  'Delete the server'
  'A or B: continue'
  'A: Yes     B: No'
  'Refresh the list'
  'What to do here?'
  'A:open  B:back'
  '(about 10 seconds)'
  'Destination folder:'
  'Server missing'
  'Technical detail:'
  'Nothing to download'
  ' files, total'
  ' with this filter'
  'Edit server'
  '(this device)'
  'My servers'
  'Test connection'
  'marked items'
  'Unmark all'
  '(arrows scroll)'
  'New server'
  'Server (IP)'
  'as user'
  'Free space:'
  'Last error ('
  'Clear filter'
  'Actions menu'
  'Connecting to'
  'Settings'
  'Already existed:'
  'Current folder:'
  'Force SMB1'
  'more below'
  'Connected to'
  'Incomplete:'
  'A: choose'
  'Last error'
  'more above'
  '==> SAVE'
  'Connection OK'
  '(nothing here'
  ' | filter:'
  'SMB error:'
  'Downloaded:'
  'Errors:'
  'Result'
  'Download the'
  'guest'
  'Downloading'
  'Destination:'
  'destination:'
  'File:'
  'Size:'
  'No network'
  'Search'
  '[x] Quit'
  'Connect'
  'Cancel'
  '(empty)'
  'needs'
  'Delete'
  'User'
  'Text:'
  'Failed'
  'Edit'
  'Back'
  'Download'
  'free'
  'Reading'
  'Help'
  'Password'
  'Exit'
  'Error'
)
tr_() {
  TRR="$1"
  [ "$UI_LANG" = en ] || return 0
  local i s="$1"
  # passada unica: troca cada trecho PT por um marcador e so depois expande o EN
  # (assim o ingles ja traduzido nunca e traduzido de novo)
  for i in "${!TR_PT[@]}"; do
    [[ "$s" == *"${TR_PT[i]}"* ]] && s=${s//"${TR_PT[i]}"/$'\002'"$i"$'\003'}
  done
  while [[ "$s" =~ $'\002'([0-9]+)$'\003' ]]; do
    s=${s//"${BASH_REMATCH[0]}"/"${TR_EN[${BASH_REMATCH[1]}]}"}
  done
  TRR="$s"
}

# tr_text TEXTO -> TRR : traduz, mas deixa intactos os trechos crus entre RAW_O e RAW_C
# (saida do smbclient, nomes de arquivos/servidores)
RAW_O=$'\004'; RAW_C=$'\005'
tr_text() {
  local in="$1" out=""
  while [[ "$in" == *"$RAW_O"* ]]; do
    tr_ "${in%%"$RAW_O"*}"; out+="$TRR"
    in=${in#*"$RAW_O"}
    if [[ "$in" == *"$RAW_C"* ]]; then out+="${in%%"$RAW_C"*}"; in=${in#*"$RAW_C"}; else out+="$in"; in=""; fi
  done
  tr_ "$in"; TRR="$out$TRR"
}

# ------------------------------------------------------------- desenho
FB=""
# fbl LINHA TEXTO [ESTILO] - escreve uma linha inteira (trunca e limpa o resto)
fbl() {
  local row="$1" s="$2" st="$3" n=$(( W - 1 )) pad
  if [[ "$s" == *$'\001'* ]]; then s=${s//$'\001'/}; else tr_ "$s"; s="$TRR"; fi
  s=${s//[[:cntrl:]]/ }
  (( ${#s} > n )) && s="${s:0:n}"
  if [ -n "$st" ]; then
    pad=$(( n - ${#s} ))
    (( pad > 0 )) && s+=$(printf '%*s' "$pad" '')
    FB+="${CSI}${row};1H${st}${s}${ST_RST}"
  else
    FB+="${CSI}${row};1H${s}${CSI}K"
  fi
}
fbflush() { printf '%s' "$FB" >&3; FB=""; }
blank_rows() { local r; for (( r=$1; r<=$2; r++ )); do FB+="${CSI}${r};1H${CSI}K"; done; }

# tail_fit TEXTO N -> R  (mantem o FINAL do texto, util para caminhos)
tail_fit() { local s="$1" n="$2"; if (( ${#s} > n )); then R="...${s: -$(( n - 3 ))}"; else R="$s"; fi; }

# hr_r BYTES -> R
hr_r() {
  local b=${1:-0}
  if   (( b >= 1073741824 )); then printf -v R '%d.%d GB' $(( b/1073741824 )) $(( b%1073741824*10/1073741824 ))
  elif (( b >= 1048576 ));    then printf -v R '%d.%d MB' $(( b/1048576 ))    $(( b%1048576*10/1048576 ))
  elif (( b >= 1024 ));       then printf -v R '%d KB' $(( b/1024 ))
  else printf -v R '%d B' "$b"; fi
}
hr() { hr_r "$1"; printf '%s' "$R"; }

# safe_r NOME -> R (troca caracteres que o exFAT nao aceita)
safe_r() { R=${1//[:\?\*\"<>|\\]/_}; }
# bs CAMINHO -> R (troca / por \ para o smbclient)
bs() { R=${1//\//\\}; }

# ------------------------------------------------------------- teclas
# read_key [timeout] -> KEY (UP DOWN LEFT RIGHT PGUP PGDN HOME END ENTER ESC SPACE TAB BKSP CHAR OTHER)
# retorna 1 se estourou o tempo
KEY=""; KCH=""
read_key() {
  local t="$1" k c2 c3 c4 rc
  KEY=""; KCH=""
  if [ -n "$t" ]; then IFS= read -rsn1 -t "$t" k <&4; rc=$?
  else IFS= read -rsn1 k <&4; rc=$?; fi
  if (( rc > 128 )); then return 1; fi
  if (( rc != 0 )); then exit 0; fi   # terminal fechou
  case "$k" in
    "")      KEY=ENTER ;;
    $'\r')   KEY=ENTER ;;
    " ")     KEY=SPACE ;;
    $'\t')   KEY=TAB ;;
    $'\177'|$'\b') KEY=BKSP ;;
    $'\e')
      IFS= read -rsn1 -t 0.05 c2 <&4 || { KEY=ESC; return 0; }
      if [ "$c2" = "[" ] || [ "$c2" = "O" ]; then
        IFS= read -rsn1 -t 0.05 c3 <&4
        case "$c3" in
          A) KEY=UP ;; B) KEY=DOWN ;; C) KEY=RIGHT ;; D) KEY=LEFT ;;
          [0-9])
            IFS= read -rsn1 -t 0.05 c4 <&4
            case "$c3" in 5) KEY=PGUP ;; 6) KEY=PGDN ;; 1|7) KEY=HOME ;; 4|8) KEY=END ;; *) KEY=OTHER ;; esac ;;
          *) KEY=OTHER ;;
        esac
      else KEY=OTHER; fi ;;
    *)
      if [[ "$k" == [[:print:]] ]]; then KEY=CHAR; KCH="$k"; else KEY=OTHER; fi ;;
  esac
  return 0
}
flush_input() { local d; while IFS= read -rsn1 -t 0.02 d <&4; do :; done; }

# ---------------------------------------------------------------- menu
# Entrada: M_TITLE M_SUB M_FOOT M_ITEMS[] M_SEL M_TOP.  Saida: M_KEY (A/B/X/Y) e M_SEL
M_TITLE=""; M_SUB=""; M_FOOT=""; M_ITEMS=(); M_SEL=0; M_TOP=0; M_KEY=""
menu() {
  local n=${#M_ITEMS[@]} rows=$MH i idx ind
  if (( n == 0 )); then M_KEY=B; return 0; fi
  while true; do
    (( M_SEL < 0 )) && M_SEL=0
    (( M_SEL >= n )) && M_SEL=$(( n - 1 ))
    (( M_SEL < M_TOP )) && M_TOP=$M_SEL
    (( M_SEL >= M_TOP + rows )) && M_TOP=$(( M_SEL - rows + 1 ))
    (( M_TOP < 0 )) && M_TOP=0
    fbl 1 " $APP_NAME v$VERSION  |  $M_TITLE" "$ST_TITLE"
    fbl 2 " $M_SUB"
    for (( i=0; i<rows; i++ )); do
      idx=$(( M_TOP + i ))
      if (( idx >= n )); then fbl $(( 3 + i )) ""
      elif (( idx == M_SEL )); then fbl $(( 3 + i )) ">${M_ITEMS[idx]}" "$ST_SEL"
      else fbl $(( 3 + i )) " ${M_ITEMS[idx]}"; fi
    done
    ind=""
    (( M_TOP > 0 )) && ind+="  ^ mais acima"
    (( M_TOP + rows < n )) && ind+="  v mais abaixo"
    fbl $(( H - 1 )) " $(( M_SEL + 1 ))/$n$ind"
    fbl "$H" " $M_FOOT" "$ST_FOOT"
    fbflush
    read_key
    case "$KEY" in
      UP)   (( M_SEL-- )); (( M_SEL < 0 )) && M_SEL=$(( n - 1 )) ;;
      DOWN) (( M_SEL++ )); (( M_SEL >= n )) && M_SEL=0 ;;
      LEFT|PGUP)  (( M_SEL -= rows )); (( M_SEL < 0 )) && M_SEL=0 ;;
      RIGHT|PGDN) (( M_SEL += rows )); (( M_SEL >= n )) && M_SEL=$(( n - 1 )) ;;
      HOME) M_SEL=0 ;;
      END)  M_SEL=$(( n - 1 )) ;;
      ENTER) M_KEY=A; return 0 ;;
      ESC)   M_KEY=B; return 0 ;;
      SPACE) M_KEY=X; return 0 ;;
      TAB)   M_KEY=Y; return 0 ;;
    esac
  done
}

# ---------------------------------------------------- telas de texto
# draw_text TITULO TEXTO RODAPE [TOPO]
draw_text() {
  local title="$1" text="$2" foot="$3" top="${4:-0}" i rows=$(( H - 4 ))
  TXT_LINES=()
  tr_text "$text"; text="$TRR"
  mapfile -t TXT_LINES < <(printf '%s\n' "$text" | fold -s -w $(( W - 3 )))
  fbl 1 " $APP_NAME v$VERSION  |  $title" "$ST_TITLE"
  fbl 2 ""
  for (( i=0; i<rows; i++ )); do fbl $(( 3 + i )) $'\001'" ${TXT_LINES[top+i]}"; done
  if (( ${#TXT_LINES[@]} > rows )); then fbl $(( H - 1 )) " (setas rolam)  $(( top + 1 ))-$(( top + rows ))/${#TXT_LINES[@]}"
  else fbl $(( H - 1 )) ""; fi
  fbl "$H" " $foot" "$ST_FOOT"
  fbflush
}

# textbox TITULO TEXTO RODAPE -> TB_KEY (A B X Y)
TB_KEY=""
textbox() {
  local title="$1" text="$2" foot="$3" top=0 n rows=$(( H - 4 ))
  while true; do
    draw_text "$title" "$text" "$foot" "$top"
    n=${#TXT_LINES[@]}
    read_key
    case "$KEY" in
      UP)   (( top > 0 )) && (( top-- )) ;;
      DOWN) (( top + rows < n )) && (( top++ )) ;;
      PGUP|LEFT)  top=$(( top - rows )); (( top < 0 )) && top=0 ;;
      PGDN|RIGHT) (( top + rows < n )) && top=$(( top + rows )) ;;
      ENTER) TB_KEY=A; return 0 ;;
      ESC)   TB_KEY=B; return 0 ;;
      SPACE) TB_KEY=X; return 0 ;;
      TAB)   TB_KEY=Y; return 0 ;;
    esac
  done
}
msgbox()  { textbox "$1" "$2" "A ou B: continuar"; }
confirm() { textbox "$1" "$2" "A: Sim     B: Nao"; [ "$TB_KEY" = A ]; }
info()    { FB=""; fbl 1 " $APP_NAME v$VERSION" "$ST_TITLE"; blank_rows 2 "$H"; fbl 5 "  $1"; fbflush; }

# ------------------------------------------------ teclado na tela (grade)
OSK_L=('`1234567890-=' 'qwertyuiop[]\' "asdfghjkl;'" 'zxcvbnm,./')
OSK_U=('~!@#$%^&*()_+' 'QWERTYUIOP{}|' 'ASDFGHJKL:"' 'ZXCVBNM<>?')

# osk TITULO INICIAL [secret] -> OSK_RESULT ; retorna 1 se cancelado
OSK_RESULT=""
osk() {
  local title="$1" text="$2" secret="$3"
  local sh=0 r=0 c=0 cl=0 reveal=0 i j n row keys ch disp fw lm gap rp lab line act
  local -a acts
  if [ "$secret" = secret ]; then acts=(Espaco Apagar Limpar Shift Ver OK Cancelar)
  else acts=(Espaco Apagar Limpar Shift OK Cancelar); fi
  gap=1; (( H >= 22 )) && gap=2
  lm=$(( (W - 1 - 13 * 4) / 2 )); (( lm < 0 )) && lm=0
  while true; do
    # linha atual do teclado e coluna (limitada ao tamanho da linha)
    if (( r < 4 )); then
      if (( sh == 0 )); then keys="${OSK_L[r]}"; else keys="${OSK_U[r]}"; fi
      n=${#keys}
    else n=${#acts[@]}; fi
    cl=$c; (( cl >= n )) && cl=$(( n - 1 ))

    if [ "$secret" = secret ] && (( reveal == 0 )); then disp=${text//?/*}; else disp=$text; fi
    fw=$(( W - 6 ))
    (( ${#disp} + 1 > fw )) && disp="<${disp: -$(( fw - 2 ))}"

    fbl 1 " $APP_NAME v$VERSION  |  $title" "$ST_TITLE"
    fbl 2 ""
    fbl 3 " Texto:"
    fbl 4 $'\001'"  ${disp}_" "$ST_FIELD"
    fbl 5 ""
    # linhas de teclas
    for (( i=0; i<4; i++ )); do
      if (( sh == 0 )); then row="${OSK_L[i]}"; else row="${OSK_U[i]}"; fi
      rp=$(( 6 + i * gap ))
      line="${CSI}${rp};1H$(printf '%*s' "$lm" '')"
      for (( j=0; j<${#row}; j++ )); do
        ch="${row:j:1}"
        if (( r == i && cl == j )); then line+="${ST_SEL} ${ch} ${ST_RST} "
        else line+=" ${ch}  "; fi
      done
      FB+="${line}${CSI}K"
      (( gap == 2 )) && FB+="${CSI}$(( rp + 1 ));1H${CSI}K"
    done
    # linha de acoes
    rp=$(( 6 + 4 * gap ))
    line="${CSI}${rp};1H$(printf '%*s' 1 '')"
    for (( j=0; j<${#acts[@]}; j++ )); do
      lab="${acts[j]}"
      [ "$lab" = Shift ] && case "$sh" in 1) lab="Shift 1x" ;; 2) lab="CAPS" ;; esac
      [ "$lab" = Ver ] && (( reveal )) && lab="Ocultar"
      if [ "$UI_LANG" = en ]; then
        case "$lab" in Espaco) lab=Space ;; Apagar) lab=Delete ;; Limpar) lab=Clear ;; Ver) lab=Show ;; Ocultar) lab=Hide ;; Cancelar) lab=Cancel ;; esac
      fi
      if (( r == 4 && cl == j )); then line+="${ST_SEL}[${lab}]${ST_RST} "
      else line+="[${lab}] "; fi
    done
    FB+="${line}${CSI}K"
    blank_rows $(( rp + 1 )) $(( H - 3 ))
    fbl $(( H - 2 )) " A: digitar tecla     B: apagar (vazio = cancelar)"
    fbl $(( H - 1 )) " X: espaco   Y: Shift   R1: confirmar (OK)"
    fbl "$H" " Setas: mover   [OK] ou R1 salva   [Cancelar] sai sem salvar" "$ST_FOOT"
    fbflush

    read_key
    case "$KEY" in
      UP)    r=$(( (r + 4) % 5 )) ;;
      DOWN)  r=$(( (r + 1) % 5 )) ;;
      LEFT)  c=$(( (cl + n - 1) % n )) ;;
      RIGHT) c=$(( (cl + 1) % n )) ;;
      ENTER)
        if (( r < 4 )); then
          text+="${keys:cl:1}"; (( sh == 1 )) && sh=0
        else
          act="${acts[cl]}"
          case "$act" in
            Espaco) text+=" " ;;
            Apagar) text="${text%?}" ;;
            Limpar) text="" ;;
            Shift)  sh=$(( (sh + 1) % 3 )) ;;
            Ver)    reveal=$(( 1 - reveal )) ;;
            OK)     OSK_RESULT="$text"; return 0 ;;
            Cancelar) return 1 ;;
          esac
        fi ;;
      ESC)   if [ -z "$text" ]; then return 1; fi; text="${text%?}" ;;
      PGUP|BKSP) text="${text%?}" ;;
      PGDN)  OSK_RESULT="$text"; return 0 ;;
      SPACE) text+=" " ;;
      TAB)   sh=$(( (sh + 1) % 3 )) ;;
      CHAR)  text+="$KCH" ;;
    esac
  done
}

# ------------------------------------------------------------ servidores
SV_NAME=(); SV_HOST=(); SV_SHARE=(); SV_USER=(); SV_DOM=(); SV_PASS=()

load_servers() {
  SV_NAME=(); SV_HOST=(); SV_SHARE=(); SV_USER=(); SV_DOM=(); SV_PASS=()
  [ -f "$CONF" ] || return 0
  local v2=0 n h s u d p line
  grep -q '^#SMBROWSER-CONF-2' "$CONF" 2>/dev/null && v2=1
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    if (( v2 )); then IFS='|' read -r n h s u d p <<<"$line"
    else IFS='|' read -r n h u d p <<<"$line"; s=""; fi
    [ -z "$h" ] && continue
    [ -z "$n" ] && n="$h"
    SV_NAME+=("$n"); SV_HOST+=("$h"); SV_SHARE+=("$s"); SV_USER+=("$u"); SV_DOM+=("$d"); SV_PASS+=("$p")
  done < "$CONF"
}

save_servers() {
  mkdir -p "$CONF_DIR" 2>/dev/null
  {
    echo "#SMBROWSER-CONF-2"
    echo "# SMBrowser - saved servers / servidores salvos. One line per server / uma linha por servidor:"
    echo "# name|server|share|user|domain|password   (nome|servidor|compartilhamento|usuario|dominio|senha)"
    echo "# share may include a subfolder / pode ter subpasta: Games/Roms. Empty user = guest / vazio = convidado."
    echo "# The password may contain any character (always last) / A senha pode ter qualquer caractere."
    local i
    for i in "${!SV_NAME[@]}"; do
      echo "${SV_NAME[i]}|${SV_HOST[i]}|${SV_SHARE[i]}|${SV_USER[i]}|${SV_DOM[i]}|${SV_PASS[i]}"
    done
  } > "$CONF"
  chmod 600 "$CONF" 2>/dev/null
  return 0
}

# normaliza o campo servidor: aceita 192.168.1.5, \\192.168.1.5\share, smb://ip/share/sub, ip/share
# usa/atualiza f_host f_share do chamador
normalize_addr() {
  local h="$1" rest
  h=${h#"${h%%[![:space:]]*}"}; h=${h%"${h##*[![:space:]]}"}
  h=${h#smb://}; h=${h//\\//}; h=${h#//}
  if [[ "$h" == */* ]]; then
    rest=${h#*/}; h=${h%%/*}
    rest=${rest#/}; rest=${rest%/}
    [ -n "$rest" ] && f_share="$rest"
  fi
  f_host="$h"
}

# server_form [indice] [host_pre]  -> rc 0 se salvou
LAST_SAVED=0
server_form() {
  local idx="$1" f_name="" f_host="$2" f_share="" f_user="" f_dom="" f_pass=""
  local sel=0 top=0 dirty=0 reveal=0 pw
  if [ -n "$idx" ]; then
    f_name=${SV_NAME[idx]}; f_host=${SV_HOST[idx]}; f_share=${SV_SHARE[idx]}
    f_user=${SV_USER[idx]}; f_dom=${SV_DOM[idx]}; f_pass=${SV_PASS[idx]}
  else dirty=1; fi
  while true; do
    if [ -z "$f_pass" ]; then pw="(vazia)"
    elif (( reveal )); then pw="$f_pass"
    else pw="${f_pass//?/*}"; fi
    M_ITEMS=(
      "Nome do atalho   : ${f_name:-(igual ao servidor)}"
      "Servidor (IP)    : ${f_host:-(VAZIO - obrigatorio)}"
      "Compartilhamento : ${f_share:-(vazio = escolher na lista)}"
      "Usuario          : ${f_user:-(vazio = convidado, sem senha)}"
      "Senha            : $pw"
      "Dominio/Grupo    : ${f_dom:-(vazio, normalmente nao precisa)}"
      "==> TESTAR CONEXAO"
      "==> SALVAR"
      "==> CANCELAR (descartar)"
    )
    if [ -n "$idx" ]; then M_TITLE="Editar servidor"; else M_TITLE="Novo servidor"; fi
    M_SUB="A: editar o campo selecionado"
    M_FOOT="A:editar  X:ver senha  Y:salvar  B:sair"
    M_SEL=$sel; M_TOP=$top
    menu
    sel=$M_SEL; top=$M_TOP
    case "$M_KEY" in
      B)
        if (( dirty )) && ! confirm "Sair" "Descartar o que voce digitou?"; then continue; fi
        return 1 ;;
      X) reveal=$(( 1 - reveal )) ;;
      Y) sel=7; M_KEY=A ;;
    esac
    [ "$M_KEY" = A ] || continue
    case "$sel" in
      0) osk "Nome do atalho (ex: Acervo Jogos)" "$f_name" && { f_name="${OSK_RESULT//|/ }"; dirty=1; } ;;
      1) osk "Servidor: IP ou nome (ex: 192.168.1.112)" "$f_host" && { normalize_addr "$OSK_RESULT"; dirty=1; } ;;
      2) if osk "Compartilhamento (pasta de rede)" "$f_share"; then
           f_share=${OSK_RESULT//\\//}; f_share=${f_share#/}; f_share=${f_share%/}; dirty=1
         fi ;;
      3) osk "Usuario (login do servidor)" "$f_user" && { f_user="${OSK_RESULT//|/ }"; dirty=1; } ;;
      4) osk "Senha" "$f_pass" secret && { f_pass="$OSK_RESULT"; dirty=1; } ;;
      5) osk "Dominio ou grupo (deixe vazio se nao sabe)" "$f_dom" && { f_dom="${OSK_RESULT//|/ }"; dirty=1; } ;;
      6) test_connection "$f_host" "$f_share" "$f_user" "$f_dom" "$f_pass" ;;
      7)
        if [ -z "$f_host" ]; then msgbox "Falta o servidor" "Preencha o campo \"Servidor (IP)\" antes de salvar."; sel=1; continue; fi
        if [ -z "$f_name" ]; then
          if [ -n "$f_share" ]; then f_name="${f_share##*/}"; else f_name="$f_host"; fi
        fi
        f_share=${f_share//|/ }
        if [ -z "$f_user" ]; then f_pass=""; f_dom=""; fi
        if [ -n "$idx" ]; then
          SV_NAME[idx]="$f_name"; SV_HOST[idx]="$f_host"; SV_SHARE[idx]="$f_share"
          SV_USER[idx]="$f_user"; SV_DOM[idx]="$f_dom"; SV_PASS[idx]="$f_pass"; LAST_SAVED=$idx
        else
          SV_NAME+=("$f_name"); SV_HOST+=("$f_host"); SV_SHARE+=("$f_share")
          SV_USER+=("$f_user"); SV_DOM+=("$f_dom"); SV_PASS+=("$f_pass"); LAST_SAVED=$(( ${#SV_NAME[@]} - 1 ))
        fi
        save_servers
        return 0 ;;
      8)
        if (( dirty )) && ! confirm "Cancelar" "Descartar o que voce digitou?"; then continue; fi
        return 1 ;;
    esac
  done
}

delete_server() { # indice
  local i="$1" k
  local -a n=() h=() s=() u=() d=() p=()
  for k in "${!SV_NAME[@]}"; do
    [ "$k" = "$i" ] && continue
    n+=("${SV_NAME[k]}"); h+=("${SV_HOST[k]}"); s+=("${SV_SHARE[k]}")
    u+=("${SV_USER[k]}"); d+=("${SV_DOM[k]}"); p+=("${SV_PASS[k]}")
  done
  SV_NAME=("${n[@]}"); SV_HOST=("${h[@]}"); SV_SHARE=("${s[@]}")
  SV_USER=("${u[@]}"); SV_DOM=("${d[@]}"); SV_PASS=("${p[@]}")
  save_servers
}

# ------------------------------------------------------------- SMB core
S_HOST=""; S_USER=""; SMBOPTS=(); AUTHOPT=(-N)
SMB_OUT=""; SMB_RC=0; LAST_ERR=""; EXPL=""
RE_PROTO='NT_STATUS_CONNECTION_DISCONNECTED|NT_STATUS_INVALID_NETWORK_RESPONSE|protocol negotiation failed|NT_STATUS_NOT_SUPPORTED'

prepare_auth_vals() { # host user dominio senha
  S_HOST="$1"; S_USER="$2"
  : > "$AUTH"; chmod 600 "$AUTH" 2>/dev/null
  if [ -n "$2" ]; then
    { echo "username = $2"; echo "password = $4"; [ -n "$3" ] && echo "domain = $3"; } > "$AUTH"
    AUTHOPT=(-A "$AUTH")
  else AUTHOPT=(-N); fi
  SMBOPTS=()
  [ "$SMB1" = "1" ] && SMBOPTS=(--option="client min protocol=NT1" --option="client max protocol=SMB3")
  return 0
}

# smb_raw args... -> SMB_OUT SMB_RC
smb_raw() {
  SMB_OUT=$(timeout "${SMB_TO:-60}" smbclient "$@" "${AUTHOPT[@]}" "${SMBOPTS[@]}" 2>&1 </dev/null)
  SMB_RC=$?
}
# smb_cmd SHARE "comandos"  (com retentativa automatica em SMB1)
smb_cmd() {
  smb_raw "//$S_HOST/$1" -c "$2"
  if (( SMB_RC != 0 && ${#SMBOPTS[@]} == 0 )) && [[ "$SMB_OUT" =~ $RE_PROTO ]]; then
    SMBOPTS=(--option="client min protocol=NT1" --option="client max protocol=SMB3")
    smb_raw "//$S_HOST/$1" -c "$2"
  fi
}

log_err() {
  mkdir -p "$CONF_DIR" 2>/dev/null
  { echo "== $(date '+%F %T')  server: $S_HOST  user: ${S_USER:-<guest>}  (smbclient rc=$SMB_RC)"; printf '%s\n' "$1"; } > "$ERRLOG" 2>/dev/null
}

my_ip() { ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | head -1 | cut -d/ -f1; }
port_open() { timeout 3 bash -c "exec 5<>/dev/tcp/$1/$2" 2>/dev/null; }

net_hint() { # host -> texto
  local ip p445="NAO" p139="NAO"; ip=$(my_ip)
  port_open "$1" 445 && p445="SIM"
  port_open "$1" 139 && p139="SIM"
  printf 'IP deste aparelho: %s\nPorta 445 do servidor responde: %s\nPorta 139 do servidor responde: %s' "${ip:-SEM IP (Wi-Fi desconectado?)}" "$p445" "$p139"
}

# explain TEXTO -> EXPL ; retorna 0 se reconheceu o erro
explain() {
  local t="$1"
  case "$t" in
    *LOGON_FAILURE*|*WRONG_PASSWORD*|*NO_LOGON_SERVERS*|*LOGON_TYPE_NOT_GRANTED*)
         EXPL="Usuario ou senha incorretos (ou esse usuario nao existe no servidor)." ;;
    *ACCOUNT_DISABLED*)   EXPL="A conta esta desativada no servidor." ;;
    *ACCOUNT_LOCKED_OUT*) EXPL="A conta foi bloqueada (muitas tentativas erradas)." ;;
    *PASSWORD_EXPIRED*|*PASSWORD_MUST_CHANGE*) EXPL="A senha expirou no servidor." ;;
    *ACCESS_DENIED*)      EXPL="Acesso negado: esse usuario nao tem permissao aqui." ;;
    *BAD_NETWORK_NAME*)   EXPL="Esse compartilhamento nao existe no servidor. Confira o nome (espacos e maiusculas contam)." ;;
    *OBJECT_NAME_NOT_FOUND*|*OBJECT_PATH_NOT_FOUND*) EXPL="Pasta ou arquivo nao encontrado." ;;
    *HOST_UNREACHABLE*|*CONNECTION_REFUSED*|*IO_TIMEOUT*|*NETWORK_UNREACHABLE*|*"Connection to"*"failed"*|*"Unable to connect"*)
         EXPL="Nao consegui falar com o servidor." ;;
    *"protocol negotiation failed"*|*CONNECTION_DISCONNECTED*|*INVALID_NETWORK_RESPONSE*)
         EXPL="O servidor recusou a conexao (versao do SMB incompativel?). Tente ligar \"SMB1 forcado\" em Configuracoes." ;;
    *NT_STATUS_*)         EXPL="Erro SMB: $(grep -o 'NT_STATUS_[A-Z_0-9]*' <<<"$t" | head -1)" ;;
    *) return 1 ;;
  esac
  return 0
}

# err_text -> LAST_ERR (mensagem completa com detalhes, usa SMB_OUT/SMB_RC)
err_text() {
  local raw
  raw=$(printf '%s' "$SMB_OUT" | grep -v '^[[:space:]]*$' | head -6)
  if (( SMB_RC == 124 )); then EXPL="Tempo esgotado: o servidor nao respondeu."
  elif ! explain "$SMB_OUT"; then EXPL="O smbclient falhou (codigo $SMB_RC)."; fi
  LAST_ERR="$EXPL"
  case "$EXPL" in
    "Nao consegui falar"*|"Tempo esgotado"*) LAST_ERR+=$'\n\n'"$(net_hint "$S_HOST")" ;;
  esac
  [ -n "$raw" ] && LAST_ERR+=$'\n\n'"Detalhe tecnico:"$'\n'"${RAW_O}${raw}${RAW_C}"
  log_err "$SMB_OUT"
}

# test_connection HOST SHARE USER DOM PASS
test_connection() {
  local host="$1" share="$2" first out
  if [ -z "$host" ]; then msgbox "Testar conexao" "Preencha o campo \"Servidor (IP)\" primeiro."; return; fi
  prepare_auth_vals "$host" "$3" "$4" "$5"
  info "Testando conexao com $host ..."
  first=${share%%/*}
  if [ -n "$first" ]; then
    smb_cmd "$first" "ls"
    if (( SMB_RC == 0 )); then
      local quem="acesso de convidado"; [ -n "$3" ] && quem="o usuario $3"
      msgbox "Conexao OK" "Conectou em //$host/$first com $quem!"$'\n\n'"Tudo certo: pode salvar."
    else
      err_text
      msgbox "Falhou" "$LAST_ERR"
    fi
  else
    if list_shares; then
      local s lst=""
      for s in "${SHARES[@]}"; do lst+="  - $s"$'\n'; done
      msgbox "Conexao OK" "Conectou em $host. Compartilhamentos encontrados:"$'\n\n'"$lst"$'\n'"Coloque um deles no campo Compartilhamento (ou deixe vazio para escolher na hora)."
    else
      msgbox "Falhou" "$LAST_ERR"
    fi
  fi
  flush_input
}

# list_shares -> SHARES[] (rc 1 = erro em LAST_ERR)
SHARES=()
list_shares() {
  local line
  SHARES=()
  SMB_TO=30 smb_raw -L "//$S_HOST"
  parse_shares
  if (( ${#SHARES[@]} == 0 && ${#SMBOPTS[@]} == 0 )) && [[ "$SMB_OUT" =~ $RE_PROTO ]] && [[ "$SMB_OUT" != *LOGON_FAILURE* ]]; then
    SMBOPTS=(--option="client min protocol=NT1" --option="client max protocol=SMB3")
    SMB_TO=30 smb_raw -L "//$S_HOST"
    parse_shares
  fi
  if (( ${#SHARES[@]} == 0 )); then
    err_text
    if [[ "$SMB_OUT" != *NT_STATUS_* ]] && (( SMB_RC == 0 )); then
      LAST_ERR="O servidor nao mostrou nenhum compartilhamento (alguns ocultam a lista). Digite o nome manualmente."
    fi
    return 1
  fi
  return 0
}
parse_shares() {
  local line
  SHARES=()
  while IFS= read -r line; do
    line=${line%$'\r'}
    if [[ "$line" =~ ^[[:space:]]+(.*[^[:space:]])[[:space:]]+Disk([[:space:]]|$) ]]; then
      [[ "${BASH_REMATCH[1]}" == *\$ ]] && continue
      SHARES+=("${BASH_REMATCH[1]}")
    fi
  done <<<"$SMB_OUT"
}

# ----- listagem de pasta
E_TYPE=(); E_NAME=(); E_SIZE=(); E_SZS=()
RE_LS='^[[:space:]]{2}(.*[^[:space:]])[[:space:]]+([0-9]+)[[:space:]]+[A-Za-z]{3}[[:space:]]+[A-Za-z]{3}[[:space:]]+[0-9]+[[:space:]]+[0-9]{1,2}:[0-9]{2}:[0-9]{2}[[:space:]]+[0-9]{4}$'
RE_ATTR='^(.*[^[:space:]])[[:space:]]+([ADHSRN]+)$'

# list_dir SHARE CAMINHO -> E_TYPE/E_NAME/E_SIZE/E_SZS (pastas primeiro)
list_dir() {
  local share="$1" path="$2" target line nm sz at ty rows="" t n s
  E_TYPE=(); E_NAME=(); E_SIZE=(); E_SZS=(); LAST_ERR=""
  if [ -n "$path" ]; then bs "$path"; target="$R\\*"; else target='*'; fi
  smb_cmd "$share" "ls \"$target\""
  while IFS= read -r line; do
    line=${line%$'\r'}
    if [[ "$line" =~ $RE_LS ]]; then
      nm="${BASH_REMATCH[1]}"; sz="${BASH_REMATCH[2]}"; at=""; ty=1
      if [[ "$nm" =~ $RE_ATTR ]]; then nm="${BASH_REMATCH[1]}"; at="${BASH_REMATCH[2]}"; fi
      [[ "$nm" == "." || "$nm" == ".." ]] && continue
      [[ "$at" == *D* ]] && ty=0
      rows+="$ty"$'\t'"$nm"$'\t'"$sz"$'\n'
    fi
  done <<<"$SMB_OUT"
  if [ -z "$rows" ]; then
    case "$SMB_OUT" in *NO_SUCH_FILE*|*NO_MORE_FILES*) return 0 ;; esac
    if (( SMB_RC != 0 )) || explain "$SMB_OUT"; then err_text; return 1; fi
    return 0
  fi
  while IFS=$'\t' read -r t n s; do
    E_TYPE+=("$t"); E_NAME+=("$n"); E_SIZE+=("$s")
    if [ "$t" = 0 ]; then E_SZS+=(""); else hr_r "$s"; E_SZS+=("$R"); fi
  done < <(printf '%s' "$rows" | sort -t$'\t' -k1,1n -k2,2f)
  return 0
}

# list_tree SHARE CAMINHO -> T_DIR[] T_NAME[] T_SIZE[] (so arquivos, recursivo)
T_DIR=(); T_NAME=(); T_SIZE=()
list_tree() {
  local share="$1" path="$2" base="" cmd="" line hdr cur="" nm sz at
  T_DIR=(); T_NAME=(); T_SIZE=(); LAST_ERR=""
  if [ -n "$path" ]; then bs "$path"; base="$R"; cmd="cd \"$R\"; "; fi
  cmd+="recurse ON; ls"
  smb_cmd "$share" "$cmd"
  if (( SMB_RC != 0 )); then err_text; return 1; fi
  while IFS= read -r line; do
    line=${line%$'\r'}
    if [[ "$line" == \\* ]]; then
      hdr=${line#\\}
      if [ -n "$base" ]; then hdr=${hdr#"$base"}; hdr=${hdr#\\}; fi
      cur=${hdr//\\//}
      continue
    fi
    if [[ "$line" =~ $RE_LS ]]; then
      nm="${BASH_REMATCH[1]}"; sz="${BASH_REMATCH[2]}"; at=""
      if [[ "$nm" =~ $RE_ATTR ]]; then nm="${BASH_REMATCH[1]}"; at="${BASH_REMATCH[2]}"; fi
      [[ "$nm" == "." || "$nm" == ".." || "$at" == *D* ]] && continue
      T_DIR+=("$cur"); T_NAME+=("$nm"); T_SIZE+=("$sz")
    fi
  done <<<"$SMB_OUT"
  return 0
}

# ------------------------------------------------------------- download
J_DIR=(); J_NAME=(); J_SIZE=(); J_REL=(); J_TOT=0
jobs_reset() { J_DIR=(); J_NAME=(); J_SIZE=(); J_REL=(); J_TOT=0; }
job_add() { J_DIR+=("$1"); J_NAME+=("$2"); J_SIZE+=("$3"); J_REL+=("$4"); J_TOT=$(( J_TOT + $3 )); }

# add_folder_jobs SHARE CAMINHO_DA_PASTA
add_folder_jobs() {
  local share="$1" fpath="$2" base k rel rd
  info "Listando arquivos de /$share/$fpath ..."
  list_tree "$share" "$fpath" || return 1
  base=${fpath##*/}; [ -z "$base" ] && base="$share"
  safe_r "$base"; base="$R"
  for k in "${!T_NAME[@]}"; do
    rel="$base"
    [ -n "${T_DIR[k]}" ] && rel+="/${T_DIR[k]//[:\?\*\"<>|\\]/_}"
    rd="$fpath"; [ -n "${T_DIR[k]}" ] && rd="${rd:+$rd/}${T_DIR[k]}"
    job_add "$rd" "${T_NAME[k]}" "${T_SIZE[k]}" "$rel"
  done
  return 0
}

PG_IDX=0; PG_N=0; PG_DONE=0; PG_TOT=0
bar() { # pct largura -> R
  local p=$1 w=$2 f i s=""
  (( p > 100 )) && p=100
  f=$(( p * w / 100 ))
  for (( i=0; i<w; i++ )); do (( i < f )) && s+="#" || s+="."; done
  printf -v R '[%s] %3d%%' "$s" "$p"
}

draw_progress() { # nome cur size el spd destino
  local name="$1" cur="$2" size="$3" el="$4" spd="$5" dest="$6" pct=0 tp=0 bw=$(( W - 12 ))
  (( size > 0 )) && pct=$(( cur * 100 / size ))
  (( PG_TOT > 0 )) && tp=$(( (PG_DONE + cur) * 100 / PG_TOT ))
  FB=""
  fbl 1 " $APP_NAME v$VERSION  |  Baixando $PG_IDX/$PG_N" "$ST_TITLE"
  blank_rows 2 "$H"
  fbl 4 " $name"
  bar "$pct" "$bw"; fbl 6 " $R"
  fbl 7 " $(hr "$cur") / $(hr "$size")   ~$(hr "$spd")/s   ${el}s"
  if (( PG_N > 1 )); then
    bar "$tp" "$bw"; fbl 9 " Total:"; fbl 10 " $R"
    fbl 11 " $(hr "$(( PG_DONE + cur ))") / $(hr "$PG_TOT")"
  fi
  tail_fit "$dest" $(( W - 12 )); fbl 13 " Destino: $R"
  fbl "$H" " B: cancelar (rodar de novo retoma de onde parou)" "$ST_FOOT"
  fbflush
}

# dl_one SHARE DIR NOME TAMANHO PASTA_LOCAL -> 0 ok, 1 erro, 2 ja existe, 130 cancelado
dl_one() {
  local share="$1" dir="$2" name="$3" size="${4:-0}" ldir="$5"
  local ln f verb="get" cur=0 cur0=0 pid t0=$SECONDS el spd free outtxt cmd
  safe_r "$name"; ln="$R"; f="$ldir/$ln"
  mkdir -p "$ldir" 2>/dev/null || { LAST_ERR="Nao consegui criar a pasta $ldir"; return 1; }
  if [ -f "$f" ]; then
    cur=$(stat -c %s "$f" 2>/dev/null || echo 0)
    if (( size > 0 && cur == size )); then return 2; fi
    if (( cur > size )); then rm -f "$f"; cur=0
    elif (( cur > 0 )); then verb="reget"; fi
  fi
  cur0=$cur
  free=$(df -Pk "$ldir" 2>/dev/null | awk 'NR==2{print $4*1024}')
  if [[ "$free" =~ ^[0-9]+$ ]] && (( size - cur0 > free )); then
    LAST_ERR="Sem espaco no cartao para \"${RAW_O}${name}${RAW_C}\": precisa $(hr $(( size - cur0 ))), livre $(hr "$free")."
    return 1
  fi
  cmd=""; if [ -n "$dir" ]; then bs "$dir"; cmd="cd \"$R\"; "; fi
  cmd+="lcd \"$ldir\"; $verb \"$name\" \"$ln\""
  : > "$LOG"
  ( SMB_TO=0 smb_cmd "$share" "$cmd"; printf '%s\n%s' "$SMB_RC" "$SMB_OUT" > "$LOG" ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    cur=$(stat -c %s "$f" 2>/dev/null || echo 0)
    el=$(( SECONDS - t0 )); spd=0
    (( el > 0 )) && spd=$(( (cur - cur0) / el ))
    (( spd < 0 )) && spd=0
    draw_progress "$name" "$cur" "$size" "$el" "$spd" "$ldir"
    if read_key 1 && [ "$KEY" = ESC ]; then
      pkill -f "smbclient //$S_HOST/" 2>/dev/null
      kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      return 130
    fi
  done
  wait "$pid" 2>/dev/null
  SMB_RC=$(head -1 "$LOG" 2>/dev/null); SMB_RC=${SMB_RC:-1}
  SMB_OUT=$(tail -n +2 "$LOG" 2>/dev/null)
  if [[ "$SMB_OUT" == *NT_STATUS_* ]]; then err_text; return 1; fi
  if [ ! -f "$f" ]; then LAST_ERR="O arquivo nao foi criado. ${RAW_O}${SMB_OUT:0:160}${RAW_C}"; return 1; fi
  cur=$(stat -c %s "$f" 2>/dev/null || echo 0)
  if (( size > 0 && cur != size )); then
    LAST_ERR="Incompleto: $(hr "$cur") / $(hr "$size"). Rode de novo para retomar."
    return 1
  fi
  return 0
}

# run_jobs SHARE - confirma e executa J_*
run_jobs() {
  local share="$1" n=${#J_NAME[@]} k rc ok=0 skip=0 fail=0 canc=0 lasterr="" lastfile="" free txt
  if (( n == 0 )); then msgbox "Nada para baixar" "Nao encontrei nenhum arquivo."; return 1; fi
  while true; do
    mkdir -p "$DEST" 2>/dev/null
    free=$(df -Pk "$DEST" 2>/dev/null | awk 'NR==2{print $4*1024}')
    if (( n == 1 )); then txt="Arquivo: ${RAW_O}${J_NAME[0]}${RAW_C}"$'\n'"Tamanho: $(hr "$J_TOT")"
    else txt="$n arquivos, total $(hr "$J_TOT")"; fi
    txt+=$'\n\n'"Destino: $DEST"$'\n'"Espaco livre: $(hr "${free:-0}")"
    if [[ "$free" =~ ^[0-9]+$ ]] && (( J_TOT > free )); then txt+=$'\n\n'"ATENCAO: pode nao caber (arquivos ja baixados nao contam)."; fi
    textbox "Baixar" "$txt" "A: Baixar    Y: Mudar destino    B: Cancelar"
    case "$TB_KEY" in
      B) return 1 ;;
      Y) pick_dir "$DEST" ;;
      *) break ;;
    esac
  done
  PG_N=$n; PG_TOT=$J_TOT; PG_DONE=0
  for (( k=0; k<n; k++ )); do
    PG_IDX=$(( k + 1 ))
    dl_one "$share" "${J_DIR[k]}" "${J_NAME[k]}" "${J_SIZE[k]}" "$DEST${J_REL[k]:+/${J_REL[k]}}"; rc=$?
    case "$rc" in
      0)   ok=$(( ok + 1 )); PG_DONE=$(( PG_DONE + J_SIZE[k] )) ;;
      2)   skip=$(( skip + 1 )); PG_DONE=$(( PG_DONE + J_SIZE[k] )) ;;
      130) canc=1; break ;;
      *)   fail=$(( fail + 1 )); lasterr="$LAST_ERR"; lastfile="${J_NAME[k]}" ;;
    esac
  done
  sync
  flush_input
  txt="Baixados: $ok"$'\n'"Ja existiam: $skip"$'\n'"Com erro: $fail"
  (( canc )) && txt+=$'\n'"CANCELADO (rode de novo para continuar)."
  txt+=$'\n\n'"Destino: $DEST"
  (( ok > 0 )) && txt+=$'\n\n'"Se baixou ROMs: reinicie o EmulationStation (Start > Opcoes > Reiniciar) para atualizar a lista de jogos."
  (( fail > 0 )) && txt+=$'\n\n'"Ultimo erro (${RAW_O}${lastfile}${RAW_C}):"$'\n'"$lasterr"
  msgbox "Resultado" "$txt"
  return 0
}

# ---------------------------------------------------- escolher destino
pick_dir() { # inicio -> DEST (rc 0 se escolheu)
  local cur="${1:-/roms}" d sel=0 top=0 k
  local -a subs=()
  [ -d "$cur" ] || cur="/roms"; [ -d "$cur" ] || cur="/"
  while true; do
    subs=()
    M_ITEMS=(">>> USAR ESTA PASTA <<<" ".. (subir um nivel)" "[+] Criar nova pasta aqui")
    while IFS= read -r d; do subs+=("$d"); M_ITEMS+=($'\001'"[D] ${d##*/}"); done \
      < <(find "$cur" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort -f)
    tail_fit "$cur" $(( W - 12 ))
    M_TITLE="Escolher pasta de destino"; M_SUB="Pasta atual: $R"
    M_FOOT="A:abrir/escolher  X:usar esta pasta  B:cancelar"
    M_SEL=$sel; M_TOP=$top
    menu
    sel=$M_SEL; top=$M_TOP
    case "$M_KEY" in
      B) return 1 ;;
      X) DEST="$cur"; save_state; return 0 ;;
      A)
        case "$sel" in
          0) DEST="$cur"; save_state; return 0 ;;
          1) [ "$cur" != "/" ] && cur="$(dirname "$cur")"; sel=0; top=0 ;;
          2) if osk "Nome da nova pasta" ""; then
               if [ -n "$OSK_RESULT" ]; then safe_r "$OSK_RESULT"; mkdir -p "$cur/$R" 2>/dev/null || msgbox "Erro" "Nao consegui criar a pasta."; fi
             fi ;;
          *) k=$(( sel - 3 )); cur="${subs[k]}"; sel=0; top=0 ;;
        esac ;;
    esac
  done
}

# ---------------------------------------------------------- navegacao
# fmt_row INDICE -> R (linha da lista de arquivos)
fmt_row() {
  local i="$1" nm mk="    " w sp szs
  nm="${E_NAME[i]}"; nm=${nm//[[:cntrl:]]/?}
  [ -n "${MARK[i]}" ] && mk="[x] "
  w=$(( W - 18 ))
  if [ "${E_TYPE[i]}" = 0 ]; then nm+="/"; szs=""; else szs="${E_SZS[i]}"; fi
  (( ${#nm} > w )) && nm="${nm:0:$(( w - 1 ))}~"
  printf -v sp '%*s' $(( w - ${#nm} )) ''
  printf -v szs '%9s' "$szs"
  R=$'\001'"${mk}${nm}${sp} ${szs}"
}

browse() { # SHARE [CAMINHO_INICIAL]
  local share="$1" cur="$2" leave="" filter="" reload=1 sel=0 top=0
  local -a V=() MARK=() aid=() albl=()
  local i k nv cnt tmp ssel
  while true; do
    if (( reload )); then
      info "Lendo /$share/$cur ..."
      if ! list_dir "$share" "$cur"; then
        msgbox "Nao consegui abrir" "${LAST_ERR:-Falha ao listar a pasta.}"
        flush_input
        [ -z "$cur" ] && return 1
        if [[ "$cur" == */* ]]; then cur="${cur%/*}"; else cur=""; fi
        continue
      fi
      reload=0; MARK=(); filter=""; sel=0; top=0
    fi
    V=()
    for i in "${!E_NAME[@]}"; do
      if [ -n "$filter" ]; then tmp=${E_NAME[i],,}; [[ "$tmp" == *"${filter,,}"* ]] || continue; fi
      V+=("$i")
    done
    nv=${#V[@]}; cnt=${#MARK[@]}
    M_ITEMS=()
    if (( nv == 0 )); then M_ITEMS=("   (nada aqui${filter:+ com esse filtro})")
    else for i in "${V[@]}"; do fmt_row "$i"; M_ITEMS+=("$R"); done; fi
    if [ -n "$leave" ]; then
      for k in "${!V[@]}"; do [ "${E_NAME[${V[k]}]}" = "$leave" ] && { sel=$k; break; }; done
      leave=""
    fi
    tail_fit "/$share${cur:+/$cur}" $(( W - 24 )); M_TITLE="$R"
    M_SUB="$nv itens | marcados: $cnt | destino: $DEST${filter:+ | filtro: $filter}"
    M_FOOT="A:abrir/baixar  X:marcar  Y:menu  B:voltar"
    M_SEL=$sel; M_TOP=$top
    menu
    sel=$M_SEL; top=$M_TOP
    case "$M_KEY" in
      B)
        [ -z "$cur" ] && return 0
        leave="${cur##*/}"
        if [[ "$cur" == */* ]]; then cur="${cur%/*}"; else cur=""; fi
        reload=1 ;;
      X)
        (( nv == 0 )) && continue
        i=${V[sel]}
        if [ -n "${MARK[i]}" ]; then unset "MARK[$i]"; else MARK[i]=1; fi
        (( sel < nv - 1 )) && sel=$(( sel + 1 )) ;;
      A)
        (( nv == 0 )) && continue
        i=${V[sel]}
        if [ "${E_TYPE[i]}" = 0 ]; then
          cur="${cur:+$cur/}${E_NAME[i]}"; reload=1
        else
          jobs_reset; job_add "$cur" "${E_NAME[i]}" "${E_SIZE[i]}" ""
          run_jobs "$share"
        fi ;;
      Y)
        aid=(); albl=()
        (( cnt > 0 )) && { aid+=(dlm); albl+=("Baixar os $cnt itens marcados"); }
        aid+=(dla); albl+=("Baixar TUDO desta pasta (com subpastas)")
        aid+=(mka); albl+=("Marcar todos os arquivos da lista")
        (( cnt > 0 )) && { aid+=(mkn); albl+=("Desmarcar tudo"); }
        [ -n "$filter" ] && { aid+=(fcl); albl+=("Limpar filtro ($filter)"); }
        aid+=(flt); albl+=("Filtrar por parte do nome...")
        aid+=(dst); albl+=("Mudar pasta de destino ($DEST)")
        aid+=(rld); albl+=("Atualizar a lista")
        aid+=(out); albl+=("Sair desta pasta de rede")
        M_ITEMS=("${albl[@]}"); M_TITLE="Menu de acoes"; M_SUB="O que fazer aqui?"
        M_FOOT="A:escolher  B:voltar"; M_SEL=0; M_TOP=0
        menu
        [ "$M_KEY" = A ] || continue
        case "${aid[M_SEL]}" in
          dlm)
            jobs_reset
            for i in "${!E_NAME[@]}"; do
              [ -n "${MARK[i]}" ] || continue
              if [ "${E_TYPE[i]}" = 0 ]; then
                add_folder_jobs "$share" "${cur:+$cur/}${E_NAME[i]}" || { msgbox "Erro" "$LAST_ERR"; jobs_reset; break; }
              else job_add "$cur" "${E_NAME[i]}" "${E_SIZE[i]}" ""; fi
            done
            if (( ${#J_NAME[@]} > 0 )); then run_jobs "$share" && MARK=(); fi ;;
          dla)
            jobs_reset
            if add_folder_jobs "$share" "$cur"; then run_jobs "$share"; else msgbox "Erro" "$LAST_ERR"; flush_input; fi ;;
          mka) for i in "${V[@]}"; do [ "${E_TYPE[i]}" = 1 ] && MARK[i]=1; done ;;
          mkn) MARK=() ;;
          fcl) filter=""; sel=0; top=0 ;;
          flt) if osk "Filtrar (parte do nome)" "$filter"; then filter="$OSK_RESULT"; sel=0; top=0; fi ;;
          dst) pick_dir "$DEST" ;;
          rld) (( nv > 0 )) && leave="${E_NAME[${V[sel]}]}"; reload=1 ;;
          out) return 0 ;;
        esac ;;
    esac
  done
}

# ---------------------------------------------------- conectar servidor
connect_server() { # indice
  local i="$1" first rest sh k sel=0 top=0
  local -a items=()
  prepare_auth_vals "${SV_HOST[i]}" "${SV_USER[i]}" "${SV_DOM[i]}" "${SV_PASS[i]}"
  if [ -n "${SV_SHARE[i]}" ]; then
    first=${SV_SHARE[i]%%/*}; rest=""
    [[ "${SV_SHARE[i]}" == */* ]] && rest=${SV_SHARE[i]#*/}
    browse "$first" "$rest"
    return
  fi
  while true; do
    info "Conectando em ${SV_HOST[i]} ..."
    if list_shares; then
      M_ITEMS=()
      for sh in "${SHARES[@]}"; do M_ITEMS+=($'\001'"$sh"); done
      M_ITEMS+=("[+] Digitar o nome de um compartilhamento")
      M_TITLE="${SV_NAME[i]} - compartilhamentos"; M_SUB="Escolha qual pasta de rede abrir"
      M_FOOT="A:abrir  B:voltar"; M_SEL=$sel; M_TOP=$top
      menu
      sel=$M_SEL; top=$M_TOP
      [ "$M_KEY" = A ] || return
      if (( sel < ${#SHARES[@]} )); then browse "${SHARES[sel]}" ""
      else
        osk "Nome do compartilhamento" "" || continue
        [ -n "$OSK_RESULT" ] && browse "$OSK_RESULT" ""
      fi
    else
      flush_input
      confirm "Nao listou os compartilhamentos" "$LAST_ERR"$'\n\n'"Digitar o nome do compartilhamento manualmente?" || return
      osk "Nome do compartilhamento" "" || return
      [ -n "$OSK_RESULT" ] && browse "$OSK_RESULT" ""
    fi
  done
}

# ----------------------------------------------- achar PCs na rede (445)
scan_network() {
  local ip base tmp="$WORK/scan" i n=0 h
  local -a found=() items=()
  ip=$(my_ip)
  if [ -z "$ip" ]; then msgbox "Sem rede" "Nao achei o IP deste aparelho. Conecte ao Wi-Fi primeiro (Opcoes > Wi-Fi)."; return 1; fi
  base="${ip%.*}"; mkdir -p "$tmp"; rm -f "$tmp"/*
  info "Procurando servidores SMB em $base.0/24 (uns 10 segundos) ..."
  for i in $(seq 1 254); do
    ( timeout 1 bash -c "exec 3<>/dev/tcp/$base.$i/445" 2>/dev/null && : > "$tmp/$i" ) &
    n=$(( n + 1 )); (( n % 64 == 0 )) && wait
  done; wait
  for i in $(ls "$tmp" 2>/dev/null | sort -n); do found+=("$base.$i"); done
  if (( ${#found[@]} == 0 )); then msgbox "Procurar" "Nenhum servidor SMB encontrado em $base.0/24."; return 1; fi
  for h in "${found[@]}"; do items+=("$h$([ "$h" = "$ip" ] && echo '  (este aparelho)')"); done
  M_ITEMS=("${items[@]}"); M_TITLE="Servidores encontrados"; M_SUB="Escolha um para cadastrar"
  M_FOOT="A:escolher  B:voltar"; M_SEL=0; M_TOP=0
  menu
  [ "$M_KEY" = A ] || return 1
  server_form "" "${found[M_SEL]}"
}

# --------------------------------------------------------- configuracoes
choose_language() {
  M_ITEMS=($'\001'"Portugues (Brasil)" $'\001'"English")
  M_TITLE=$'\001'"Idioma / Language"; M_SUB=$'\001'"Escolha / Choose"; M_FOOT=$'\001'"A: OK"
  M_SEL=0; M_TOP=0; [ "$UI_LANG" = en ] && M_SEL=1
  menu
  if [ "$M_SEL" = 1 ]; then UI_LANG=en; else UI_LANG=pt; fi
  save_state
}

help_text() {
  if [ "$UI_LANG" = en ]; then
    msgbox "Help" "HOW TO USE"$'\n'"A = confirm / open / type key"$'\n'"B = back (on keyboard: delete)"$'\n'"X = mark file (in list) / space (on keyboard)"$'\n'"Y = actions menu / Shift (on keyboard)"$'\n'"R1 = confirm text on keyboard   L1/R1 or left/right = page"$'\n\n'"NEW SERVER"$'\n'"1) Add server  2) fill in Server, User and Password  3) TEST CONNECTION  4) SAVE"$'\n'"In the Server field you can paste the whole address: 192.168.1.112/Share Name"$'\n\n'"DOWNLOAD"$'\n'"A on a file downloads it. X marks several, then Y > Download marked. Y > Download EVERYTHING gets the whole folder with subfolders. Running again resumes."$'\n\n'"PROBLEMS"$'\n'"Use TEST CONNECTION in the server form: it shows the exact reason. The last error is in Settings > View last error (and in the file ultimo-erro.log, in the smbrowser folder on the card)."
    return
  fi
  msgbox "Ajuda" "COMO USAR"$'\n'"A = confirmar / abrir / digitar tecla"$'\n'"B = voltar (no teclado: apagar)"$'\n'"X = marcar arquivo (na lista) / espaco (no teclado)"$'\n'"Y = menu de acoes / Shift (no teclado)"$'\n'"R1 = confirmar texto no teclado   L1/R1 ou esquerda/direita = pagina"$'\n\n'"SERVIDOR NOVO"$'\n'"1) Adicionar servidor  2) preencha Servidor, Usuario e Senha  3) TESTAR CONEXAO  4) SALVAR"$'\n'"No campo Servidor voce pode colar o endereco todo: 192.168.1.112/Nome do Share"$'\n\n'"BAIXAR"$'\n'"A num arquivo baixa. X marca varios, depois Y > Baixar marcados. Y > Baixar TUDO baixa a pasta inteira com subpastas. Rodar de novo retoma."$'\n\n'"PROBLEMAS"$'\n'"Use TESTAR CONEXAO no formulario do servidor: ele mostra o motivo exato. O ultimo erro fica em Configuracoes > Ver ultimo erro (e no arquivo ultimo-erro.log, na pasta smbrowser do cartao)."
}

settings_menu() {
  local sel=0
  while true; do
    M_ITEMS=(
      "Pasta de destino: $DEST"
      "SMB1 forcado (NAS/Windows antigo): $([ "$SMB1" = 1 ] && echo SIM || echo nao)"
      $'\001'"Idioma / Language: $([ "$UI_LANG" = en ] && echo English || echo Portugues)"
      "Ver ultimo erro / diagnostico"
      "Ajuda: controles e dicas"
      "Voltar"
    )
    M_TITLE="Configuracoes"; M_SUB="A: escolher"; M_FOOT="A:escolher  B:voltar"
    M_SEL=$sel; M_TOP=0
    menu
    sel=$M_SEL
    [ "$M_KEY" = A ] || return
    case "$sel" in
      0) pick_dir "$DEST" ;;
      1) [ "$SMB1" = 1 ] && SMB1=0 || SMB1=1; save_state ;;
      2) choose_language ;;
      3) if [ -s "$ERRLOG" ]; then msgbox "Ultimo erro" "${RAW_O}$(cat "$ERRLOG")${RAW_C}"; else msgbox "Ultimo erro" "Nenhum erro registrado ainda."; fi ;;
      4) help_text ;;
      5) return ;;
    esac
  done
}

# --------------------------------------------------------- dependencias
check_deps() {
  if command -v smbclient >/dev/null; then return 0; fi
  if confirm "smbclient nao instalado" "O programa smbclient (que fala com a rede) nao esta instalado."$'\n\n'"Instalar agora? Precisa de Wi-Fi com internet."; then
    printf '%s' "${CSI}2J${CSI}H${CSI}?25h" >&3
    { sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y smbclient; } >&3 2>&1 </dev/null
    printf '%s' "${CSI}?25l" >&3
    flush_input
  fi
  command -v smbclient >/dev/null && return 0
  msgbox "Erro" "smbclient nao instalado. Conecte ao Wi-Fi (com internet) e abra o SMBrowser de novo."
  exit 1
}

# ----------------------------------------------------------------- main
main() {
  local sel=0 top=0 i nsv act
  mkdir -p "$CONF_DIR" 2>/dev/null
  load_state
  [ -f "$CONF" ] || save_servers
  setup_terminal
  [ -z "$UI_LANG" ] && choose_language
  check_deps
  while true; do
    load_servers
    nsv=${#SV_NAME[@]}
    M_ITEMS=()
    for i in "${!SV_NAME[@]}"; do
      M_ITEMS+=($'\001'"${SV_NAME[i]}   ${SV_USER[i]:+${SV_USER[i]}@}${SV_HOST[i]}${SV_SHARE[i]:+/${SV_SHARE[i]}}")
    done
    M_ITEMS+=("[+] Adicionar servidor")
    M_ITEMS+=("[?] Procurar servidores na rede")
    M_ITEMS+=("[*] Configuracoes e ajuda")
    M_ITEMS+=("[x] Sair")
    M_TITLE="Meus servidores"
    if (( nsv == 0 )); then M_SUB="Nenhum servidor salvo ainda. Escolha [+] Adicionar servidor."
    else M_SUB="A conecta. X edita. Y mais opcoes."; fi
    M_FOOT="A:conectar  X:editar  Y:mais  B:sair"
    M_SEL=$sel; M_TOP=$top
    menu
    sel=$M_SEL; top=$M_TOP
    if [ "$M_KEY" = B ]; then break; fi
    if (( sel < nsv )); then
      case "$M_KEY" in
        A) connect_server "$sel"; flush_input ;;
        X) server_form "$sel" && sel=$LAST_SAVED ;;
        Y)
          M_ITEMS=("Conectar" "Editar" "Testar conexao" "Excluir este servidor" "Voltar")
          M_TITLE=$'\001'"${SV_NAME[sel]}"; M_SUB="${SV_USER[sel]:-convidado}@${SV_HOST[sel]}"
          M_FOOT="A:escolher  B:voltar"; M_SEL=0; M_TOP=0
          menu
          [ "$M_KEY" = A ] || continue
          case "$M_SEL" in
            0) connect_server "$sel"; flush_input ;;
            1) server_form "$sel" && sel=$LAST_SAVED ;;
            2) test_connection "${SV_HOST[sel]}" "${SV_SHARE[sel]}" "${SV_USER[sel]}" "${SV_DOM[sel]}" "${SV_PASS[sel]}" ;;
            3) if confirm "Excluir" "Excluir o servidor \"${RAW_O}${SV_NAME[sel]}${RAW_C}\"?"; then delete_server "$sel"; sel=0; fi ;;
          esac ;;
      esac
    else
      [ "$M_KEY" = A ] || continue
      act=$(( sel - nsv ))
      case "$act" in
        0) server_form "" && sel=$LAST_SAVED ;;
        1) scan_network && sel=$LAST_SAVED ;;
        2) settings_menu ;;
        3) break ;;
      esac
    fi
  done
}

[ -n "$SMB_NO_MAIN" ] || main
