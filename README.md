# SMBrowser

**🇬🇧 [English](#english) · 🇧🇷 [Português](#português-br)**

A gamepad-friendly **SMB / Samba network file browser and downloader** for ArkOS handhelds — made for the **R36H**.
*Navegador e baixador de arquivos de rede **SMB / Samba**, feito para usar só com o gamepad, para consoles portáteis com ArkOS — criado para o **R36H**.*

```
 SMBrowser v2.1  |  /Games/SNES
 6 items | marked: 2 | destination: /roms
 [x] Donkey Kong Country (USA).sfc                     3.0 MB
 [x] Super Mario World (USA).sfc                       512 KB
>    Super Metroid (JU).sfc                            3.0 MB
 3/6
 A:open/download  X:mark  Y:menu  B:back
```

---

# English

## What is it for?

Your ROMs (or any files) live on a PC, NAS, Raspberry Pi or phone sharing a folder over the network. SMBrowser lets you
connect to that share **directly from the handheld**, browse it, mark what you want and download it straight into
`/roms` — no SD card swapping, no PC in the middle.

It works with anything that speaks SMB: Windows shares, Samba on Linux, NAS boxes, routers with USB sharing, Android
SMB servers…

## Features

- **Login that actually works**: user, password and domain/workgroup in one clear form, with a **Test connection** button that tells you *why* it failed (wrong password, wrong share name, server unreachable…).
- **On-screen keyboard built for a D-pad**: letters, numbers and symbols on the *same* grid (no switching between pages). One-shot Shift, Caps, show/hide password.
- **Saved servers** with a name, address, share, user and password; connect with a single button press. Stored in a plain text file you can also edit on a PC.
- **Paste a full address** in the server field (`192.168.1.50/My Games`) and it is split into server + share for you.
- **File browser**: folders first, sizes, page jumps, filter by part of the name (handy for huge ROM lists), cursor returns to the folder you came from.
- **Mark several files** (X) and download them together, or download a **whole folder with all subfolders**.
- **Resumable downloads**: already-complete files are skipped, partial files continue where they stopped. `B` cancels safely.
- **Per-file and total progress**, speed, and free-space check before downloading.
- Automatic **SMB1 fallback** for old servers/NAS (and a manual “Force SMB1” switch).
- Find SMB servers on your network (scans for open port 445).
- **English and Portuguese (BR)** interface; asks on first run, switch any time in *Settings*.

## Requirements

- A handheld running **ArkOS** (developed on the **R36H**; other ArkOS devices that use `gptokeyb` should work too — reports welcome).
- Wi-Fi connected to the same network as the server.
- `smbclient` — the app offers to install it for you the first time (needs internet).

## Installation

1. Put the SD card in your PC and open the **EASYROMS** partition.
2. Copy **`SMBrowser.sh`** to `EASYROMS/tools/` (it appears under **Tools** in EmulationStation).
3. *(Optional)* Copy the **`smbrowser`** folder to the root of EASYROMS (`/roms/smbrowser`) with your `servers.conf` (see `servers.conf.example`). You can also just add servers inside the app.
4. Put the card back, connect Wi-Fi and open **Tools → SMBrowser**.

Alternative, over SSH (*Options → Enable Remote Services*):

```bash
scp SMBrowser.sh ark@<handheld-ip>:/opt/system/Tools/
ssh ark@<handheld-ip> "chmod +x /opt/system/Tools/SMBrowser.sh"
```

## Adding a server

*My servers → [+] Add server*, then press **A** on each field:

| Field | What to type |
|---|---|
| Shortcut name | Anything you like. If empty, the share name (or the address) is used. |
| Server (IP) | e.g. `192.168.1.50`. You may paste `192.168.1.50/Share Name` or `smb://192.168.1.50/Share`. |
| Share | The shared folder name. Subfolders allowed: `Games/Roms`. Empty = pick from a list on connect. |
| User / Password | Your login on the server. **Empty user = guest access** (no password). |
| Domain/Group | Almost always empty. |

Then **TEST CONNECTION** → **SAVE** (or press **Y** as a shortcut for Save).
On the server list: **A** connects, **X** edits, **Y** opens more options (test, delete).

## Controls

| Button | In lists | On the on-screen keyboard |
|---|---|---|
| **A** | open folder / download file | type the highlighted key |
| **B** | go back | delete a character (empty text = cancel) |
| **X** | mark / unmark | space |
| **Y** | actions menu | Shift (1×) → Caps → off |
| **R1** | page down | confirm (OK) |
| **L1** | page up | delete |
| D-pad ←/→ | page up / down | move |

**Actions menu (Y)**: download marked items · download **everything** in this folder (recursive) · mark all files · filter by name · change destination folder · refresh · leave.

## Downloading

- **A** on a file → confirmation screen (shows size, destination, free space; **Y** changes the destination) → download.
- Several files: **X** to mark, then **Y → Download the N marked items**. Marked folders are downloaded entirely.
- Files go to the destination folder (default `/roms`), keeping the folder structure for folder downloads.
- If something fails halfway, just run the same download again — it resumes.
- After downloading ROMs, **restart EmulationStation** so the game lists refresh.

## Configuration files

Everything lives in `/roms/smbrowser/` (or `~/smbrowser` if `/roms` doesn't exist):

| File | Purpose |
|---|---|
| `servers.conf` | Saved servers, one per line: `name\|server\|share\|user\|domain\|password` |
| `state.conf` | Destination folder, SMB1 switch, language |
| `smbrowser.gptk` | Button mapping used by `gptokeyb` (regenerated on every start) |
| `ultimo-erro.log` | Details of the last error (also visible in *Settings → View last error*) |

Example `servers.conf`:

```
#SMBROWSER-CONF-2
My PC|192.168.1.50|Games|myuser||mypassword
NAS|192.168.1.60|Media/Roms|guestuser|WORKGROUP|p@ss|word
```

The password is the last field, so it may contain any character (even `|`). Older v1 files (`name|host|user|domain|pass`) are read automatically and converted to the new format the next time you save.

> ⚠️ **Passwords are stored in plain text** in `servers.conf` on the SD card. Don't share that file, and **don't commit it to Git** (the included `.gitignore` already excludes it).

## How it works

SMBrowser is a single Bash script (`SMBrowser.sh`) with no dependencies besides `smbclient`:

- **UI**: a small text-mode toolkit drawn with ANSI escape codes straight on the console (`/dev/tty1`) — menus, text boxes, a grid on-screen keyboard and progress screens. It does **not** use `dialog`, which is what makes the keyboard grid and the per-button behaviour possible.
- **Input**: the script generates its own `gptokeyb` mapping (`A→Enter`, `B→Esc`, `X→Space`, `Y→Tab`, `L1/R1→PageUp/PageDown`, D-pad→arrows) and reads the resulting key codes.
- **Network**: every operation is an `smbclient` call using a temporary credentials file (`-A`) — never on the command line. Directory listings parse `ls` output; folder downloads use `recurse ON; ls` to build the full file list in a single connection.
- **Downloads**: file by file with `get` (or `reget` to resume). Progress comes from the size of the local file; `B` kills the transfer cleanly. Completed files are detected by size and skipped.
- **Compatibility**: if the server rejects the protocol negotiation, the call is retried automatically with SMB1/NT1 enabled.
- **Language**: the UI strings are written in Portuguese and translated at draw time through a PT→EN table (`TR_PT` / `TR_EN` near the top of the script). Raw `smbclient` output, file names and server names are never translated.

## Troubleshooting

| Symptom | What to do |
|---|---|
| Can't connect / unclear error | Open the server → **Test connection**. It reports the exact reason and shows whether ports 445/139 answer. |
| “Wrong user or password” | Check the user exists **on the server** (on Linux Samba: `sudo smbpasswd -a <user>`). Passwords are case-sensitive. |
| “That share does not exist” | Check the share name; spaces and capitals matter. Leave *Share* empty to pick from a list. |
| Very old server/NAS | *Settings → Force SMB1*. |
| Server unreachable | Is the handheld on Wi-Fi? Same network as the server? Try the IP address instead of a hostname. |
| Keyboard/buttons don't react | The app needs `gptokeyb` (included in ArkOS). Close and reopen the app. |

## Limitations

- Download only (no upload or delete).
- Each file is transferred in its own `smbclient` connection: huge numbers of tiny files are slower than one big file.
- File names containing `;` are not supported (a limitation of `smbclient -c`).
- Characters not allowed by exFAT (`: ? * " < > | \`) are replaced by `_` on the card.
- Passwords are stored in plain text (see warning above).

## Adding another language

Add one line to each of `TR_PT` and `TR_EN` for every Portuguese UI fragment, or fork the arrays into a new pair and switch on `UI_LANG`. Long, specific phrases go first (the table is applied longest-first).

## Contributing

Issues and pull requests are welcome — especially reports from other ArkOS devices and SMB servers.

## License

<!-- Choose a license and add a LICENSE file (e.g. MIT) -->

---

# Português (BR)

## Para que serve?

Seus jogos (ou quaisquer arquivos) ficam em um PC, NAS, Raspberry Pi ou celular que compartilha uma pasta na rede. O
SMBrowser conecta nessa pasta **direto pelo console portátil**, deixa você navegar, marcar o que quer e baixar para
`/roms` — sem tirar o cartão SD, sem PC no meio do caminho.

Funciona com qualquer coisa que fale SMB: compartilhamentos do Windows, Samba no Linux, NAS, roteadores com USB
compartilhado, servidores SMB no Android…

## Recursos

- **Login que funciona de verdade**: usuário, senha e domínio/grupo numa tela clara, com botão **Testar conexão** que diz *por que* falhou (senha errada, nome do compartilhamento errado, servidor fora do ar…).
- **Teclado na tela feito para o direcional**: letras, números e símbolos na **mesma** grade (sem trocar de página). Shift de uma tecla, Caps e ver/ocultar senha.
- **Servidores salvos** com nome, endereço, compartilhamento, usuário e senha; conecta com um botão. Ficam num arquivo de texto que você também pode editar no PC.
- **Cole o endereço completo** no campo servidor (`192.168.1.50/Meus Jogos`) e ele separa servidor + compartilhamento sozinho.
- **Navegador de arquivos**: pastas primeiro, tamanhos, pulo de página, filtro por parte do nome (ótimo para listas enormes de ROMs) e o cursor volta para a pasta de onde você saiu.
- **Marque vários arquivos** (X) e baixe juntos, ou baixe uma **pasta inteira com todas as subpastas**.
- **Downloads retomáveis**: arquivos completos são pulados, os parciais continuam de onde pararam. O `B` cancela com segurança.
- **Progresso por arquivo e total**, velocidade e verificação de espaço livre antes de baixar.
- **Fallback automático para SMB1** em servidores/NAS antigos (e uma chave manual “SMB1 forçado”).
- Procura servidores SMB na rede (varre a porta 445).
- Interface em **português (BR) e inglês**; pergunta no primeiro uso e dá para trocar a qualquer hora em *Configurações*.

## Requisitos

- Um portátil com **ArkOS** (desenvolvido no **R36H**; outros aparelhos com ArkOS que usam o `gptokeyb` devem funcionar — relatos são bem-vindos).
- Wi-Fi conectado na mesma rede do servidor.
- `smbclient` — o app oferece instalar para você na primeira vez (precisa de internet).

## Instalação

1. Coloque o cartão SD no PC e abra a partição **EASYROMS**.
2. Copie **`SMBrowser.sh`** para `EASYROMS/tools/` (aparece em **Tools** no EmulationStation).
3. *(Opcional)* Copie a pasta **`smbrowser`** para a raiz da EASYROMS (`/roms/smbrowser`) com o seu `servers.conf` (veja `servers.conf.example`). Dá para cadastrar os servidores também dentro do app.
4. Devolva o cartão, conecte o Wi-Fi e abra **Tools → SMBrowser**.

Alternativa por SSH (*Opções → Enable Remote Services*):

```bash
scp SMBrowser.sh ark@<ip-do-console>:/opt/system/Tools/
ssh ark@<ip-do-console> "chmod +x /opt/system/Tools/SMBrowser.sh"
```

## Cadastrar um servidor

*Meus servidores → [+] Adicionar servidor* e aperte **A** em cada campo:

| Campo | O que digitar |
|---|---|
| Nome do atalho | O que quiser. Se vazio, usa o nome do compartilhamento (ou o endereço). |
| Servidor (IP) | Ex.: `192.168.1.50`. Pode colar `192.168.1.50/Nome do Share` ou `smb://192.168.1.50/Share`. |
| Compartilhamento | Nome da pasta compartilhada. Aceita subpasta: `Jogos/Roms`. Vazio = escolher numa lista ao conectar. |
| Usuário / Senha | Seu login no servidor. **Usuário vazio = convidado** (sem senha). |
| Domínio/Grupo | Quase sempre vazio. |

Depois **TESTAR CONEXÃO** → **SALVAR** (ou **Y** como atalho para salvar).
Na lista de servidores: **A** conecta, **X** edita, **Y** abre mais opções (testar, excluir).

## Controles

| Botão | Nas listas | No teclado na tela |
|---|---|---|
| **A** | abrir pasta / baixar arquivo | digitar a tecla selecionada |
| **B** | voltar | apagar caractere (texto vazio = cancelar) |
| **X** | marcar / desmarcar | espaço |
| **Y** | menu de ações | Shift (1×) → Caps → desligado |
| **R1** | página abaixo | confirmar (OK) |
| **L1** | página acima | apagar |
| Direcional ←/→ | página acima / abaixo | mover |

**Menu de ações (Y)**: baixar marcados · baixar **tudo** desta pasta (recursivo) · marcar todos os arquivos · filtrar por nome · mudar pasta de destino · atualizar · sair.

## Baixando

- **A** num arquivo → tela de confirmação (mostra tamanho, destino e espaço livre; **Y** muda o destino) → baixa.
- Vários arquivos: **X** para marcar, depois **Y → Baixar os N itens marcados**. Pastas marcadas são baixadas inteiras.
- Os arquivos vão para a pasta de destino (padrão `/roms`), mantendo a estrutura de pastas nos downloads de pasta.
- Se algo falhar no meio, rode o mesmo download de novo — ele retoma.
- Depois de baixar ROMs, **reinicie o EmulationStation** para atualizar as listas de jogos.

## Arquivos de configuração

Tudo fica em `/roms/smbrowser/` (ou `~/smbrowser` se `/roms` não existir):

| Arquivo | Função |
|---|---|
| `servers.conf` | Servidores salvos, um por linha: `nome\|servidor\|compartilhamento\|usuario\|dominio\|senha` |
| `state.conf` | Pasta de destino, chave SMB1, idioma |
| `smbrowser.gptk` | Mapeamento de botões do `gptokeyb` (gerado de novo a cada abertura) |
| `ultimo-erro.log` | Detalhes do último erro (também em *Configurações → Ver último erro*) |

Exemplo de `servers.conf`:

```
#SMBROWSER-CONF-2
Meu PC|192.168.1.50|Jogos|meuusuario||minhasenha
NAS|192.168.1.60|Midia/Roms|convidado|WORKGROUP|s3nha|com|barra
```

A senha é o último campo, então pode ter qualquer caractere (até `|`). Arquivos antigos da v1 (`nome|host|usuario|dominio|senha`) são lidos automaticamente e convertidos para o formato novo na próxima vez que você salvar.

> ⚠️ **As senhas ficam em texto puro** no `servers.conf` do cartão SD. Não compartilhe esse arquivo e **não envie para o Git** (o `.gitignore` incluído já o exclui).

## Como funciona

O SMBrowser é um único script Bash (`SMBrowser.sh`), sem dependências além do `smbclient`:

- **Interface**: um pequeno kit de interface em modo texto, desenhado com códigos ANSI direto no console (`/dev/tty1`) — menus, caixas de texto, teclado em grade e telas de progresso. **Não** usa o `dialog`, e é isso que permite o teclado em grade e o comportamento de cada botão.
- **Entrada**: o script gera o próprio mapeamento do `gptokeyb` (`A→Enter`, `B→Esc`, `X→Espaço`, `Y→Tab`, `L1/R1→PageUp/PageDown`, direcional→setas) e lê os códigos de tecla resultantes.
- **Rede**: cada operação é uma chamada ao `smbclient` com um arquivo temporário de credenciais (`-A`) — nunca na linha de comando. As listagens interpretam a saída do `ls`; o download de pastas usa `recurse ON; ls` para montar a lista completa de arquivos numa única conexão.
- **Downloads**: arquivo por arquivo com `get` (ou `reget` para retomar). O progresso vem do tamanho do arquivo local; o `B` interrompe a transferência de forma limpa. Arquivos completos são detectados pelo tamanho e pulados.
- **Compatibilidade**: se o servidor recusar a negociação do protocolo, a chamada é refeita automaticamente com SMB1/NT1 habilitado.
- **Idioma**: os textos da interface estão escritos em português e são traduzidos na hora de desenhar a tela por uma tabela PT→EN (`TR_PT` / `TR_EN`, no início do script). A saída crua do `smbclient`, nomes de arquivos e nomes de servidores nunca são traduzidos.

## Solução de problemas

| Sintoma | O que fazer |
|---|---|
| Não conecta / erro confuso | Abra o servidor → **Testar conexão**. Ele diz o motivo exato e mostra se as portas 445/139 respondem. |
| “Usuário ou senha incorretos” | Confira se o usuário existe **no servidor** (no Samba do Linux: `sudo smbpasswd -a <usuario>`). A senha diferencia maiúsculas de minúsculas. |
| “Esse compartilhamento não existe” | Confira o nome; espaços e maiúsculas contam. Deixe *Compartilhamento* vazio para escolher numa lista. |
| Servidor/NAS muito antigo | *Configurações → SMB1 forçado*. |
| Servidor inacessível | O console está no Wi-Fi? Na mesma rede do servidor? Tente o IP em vez do nome do computador. |
| Teclado/botões não respondem | O app precisa do `gptokeyb` (já vem no ArkOS). Feche e abra o app de novo. |

## Limitações

- Só baixa (não envia nem apaga arquivos).
- Cada arquivo é transferido numa conexão `smbclient` própria: muitos arquivos minúsculos são mais lentos que um arquivo grande.
- Nomes de arquivo com `;` não são suportados (limitação do `smbclient -c`).
- Caracteres que o exFAT não aceita (`: ? * " < > | \`) viram `_` no cartão.
- As senhas ficam em texto puro (veja o aviso acima).

## Adicionar outro idioma

Inclua uma linha em `TR_PT` e outra em `TR_EN` para cada trecho de interface em português, ou duplique os arrays em um novo par e escolha por `UI_LANG`. Frases longas e específicas vão primeiro (a tabela é aplicada da mais longa para a mais curta).

## Contribuindo

Issues e pull requests são bem-vindos — principalmente relatos de outros aparelhos com ArkOS e de outros servidores SMB.

## Licença

<!-- Escolha uma licença e adicione um arquivo LICENSE (ex.: MIT) -->
