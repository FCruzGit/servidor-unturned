# Servidor Unturned (Hard, com autosave e backups)

## Painel web (recomendado)

Dê dois cliques em **`Painel do Servidor.vbs`**. Abre o painel no navegador (`http://localhost:8090`) e nenhuma janela de console aparece: o servidor roda em modo silencioso.

Pelo painel você:
- escolhe o mapa e **inicia / desliga / reinicia / troca de mapa** (desligar sempre salva antes);
- vê o **console** ao vivo e digita comandos (`say`, `players`, `admin`, `day`...), com histórico (setas ↑/↓);
- vê os **jogadores online** (com botões de kick/ban), o **código do servidor** (clique para copiar), RAM e tempo ligado;
- faz **save** e **backup** na hora, **restaura backups** e **edita a configuração**;
- **atualiza** o servidor pelo SteamCMD.

O painel também é a vigia: faz os backups periódicos e reabre o servidor se ele cair. Fechar a aba do navegador não desliga nada; para encerrar o painel use "fechar o painel" no rodapé. Se o painel for aberto com o servidor já rodando, ele assume a vigia. O painel só aceita conexões deste PC. A porta fica em `PortaPainel` no `config\servidor.json`. O registro do painel fica em `servidor\Servers\Principal\Painel\painel.log`.

### Spawn fixo (setspawn)

O module do servidor adiciona um spawn fixo por mapa. Com ele definido, quem entra **pela primeira vez** no mapa e quem **renasce depois de morrer** vai para lá. Quem escolhe renascer na própria cama continua na cama; para mudar isso, desligue `SpawnRespeitaCama` na configuração.

| Comando (console do painel, ou chat de admin com `/`) | O que faz |
|---|---|
| `setspawn` | No chat: usa a sua posição |
| `setspawn <jogador>` | Usa a posição do jogador (no painel: botão **Spawn aqui**) |
| `setspawn <x> <y> <z>` | Coordenadas |
| `verspawn` / `delspawn` | Mostra / remove o spawn |
| `irspawn <jogador>` / `irspawn todos` | Leva jogador(es) ao spawn agora |

O spawn fica salvo em `Level\<mapa>\setspawn.txt` e entra nos backups do mapa.

### Outros comandos do module

| Comando | O que faz |
|---|---|
| `player <jogador>` (ou `jogador`) | Dados do jogador: posição, local mais próximo, vida/fome/sede, XP, ping, item na mão, veículo (botão **Dados** no painel) |
| `tp <jogador> <destino>` (ou `teleportar`) | Teleporta. Destino: outro jogador, `spawn`, nome de local do mapa ou `x y z`. `tp todos <destino>` leva todos |

O console do painel sugere comandos e nomes de jogadores enquanto você digita (Tab ou Enter completa).

### Regras de jogo alteradas no `Config.txt`

Zumbis em dobro (`Spawn_Chance 0.6`; o Hard padrão é 0.3) e skills: personagens novos começam com tudo zerado e perdem todas as skills ao morrer (`Lose_Skills_PvE/PvP 0`, `Skillset_Prevents_Skill_Loss False`, `Prevent_Level_Skill_Overrides True`). Loot aumentado: itens no chão `Items Spawn_Chance 0.6` (Hard 0.15) e `Respawn_Time 120` (Hard 150); zumbis `Loot_Chance 0.85` (Hard 0.3) e `Max_Drops 2` (padrão 1). Menos zumbis rápidos (sprinters): `Sprinter_Chance 0.07` (Hard 0.175). O arquivo original ficou em `Config.txt.antes-painel`.

### Comandos do painel

`/conexao` (Server Code, IPs, porta e senha), `/mostrar_senha` e `/definir_senha NOVA`.

## Pelo console (modo antigo)

1. Dê dois cliques em **`Iniciar Servidor.bat`**.
2. Escolha o mapa pelo número. Se só apertar **Enter**, ele abre o último mapa usado.
3. O servidor abre numa **janela própria** ("Unturned - <mapa>"). Os comandos (`save`, `players`, `say`, `admin`...) são digitados nessa janela.
4. Para desligar: digite `shutdown` na janela do servidor, aperte **Ctrl+C** nela ou feche a janela. Em todos esses casos ele **salva antes de sair**.

Para entrar no jogo: **Play → Connect** com `127.0.0.1` e a porta 27015 (no mesmo PC). Para amigos, use o **Server Code** que aparece na janela do servidor (não precisa abrir portas no roteador).

## O save nunca se perde

- **Cada mapa tem o seu save** e ele sempre continua de onde parou. Trocar de mapa não apaga o save do outro.
- **Autosave**: um module próprio (`modulo-autosave`) salva o mundo a cada 5 minutos. Por padrão, o Unturned só salva quando o servidor é desligado.
- **Backups** em `backups\<mapa>\` (zip):
  - `antes-de-iniciar`: toda vez que o servidor sobe;
  - `periodico`: a cada 30 minutos, logo depois de um autosave;
  - `ao-desligar`: quando o servidor fecha.
  São mantidos os 30 mais recentes de cada tipo, por mapa.
- **`Restaurar Backup.bat`**: volta um mapa para um backup escolhido (com o servidor desligado). Antes de restaurar, ele faz um backup do estado atual.
- Se o servidor **cair**, a janela "Vigia" reabre o servidor sozinha.

## Configuração: `config\servidor.json`

O `servidor.json` guarda a senha e por isso fica fora do git. Na primeira execução ele é criado a partir do `config\servidor.exemplo.json`.

| Campo | O que faz |
|---|---|
| `Nome`, `Senha`, `MaxJogadores`, `Porta` | Dados básicos do servidor |
| `Owner_SteamID64` | O seu SteamID64, para ter admin no chat (`/give`, etc.) |
| `PvP` | `false` = PvE |
| `Cheats` | Libera comandos de cheat para admins |
| `Internet` | `true` = servidor de internet, `false` = só LAN |
| `GSLT` | Token opcional para o servidor aparecer na lista pública ([gerar aqui](https://steamcommunity.com/dev/managegameservers), app 304930) |
| `AutosaveMinutos`, `BackupACadaMinutos`, `BackupsMantidosPorMapa` | Frequência do autosave e dos backups |
| `AtualizarAoIniciar` | Atualiza o servidor via SteamCMD antes de abrir (mantém a versão igual à do jogo) |
| `MapasWorkshop` | Mapas da Workshop que aparecem no menu (`Nome` = nome exato do mapa, `Id` = ID da Workshop) |
| `ModsWorkshop` | IDs de mods da Workshop para carregar sempre |

A dificuldade é **Hard** (`Mode Hard`). Para ajustar detalhes (loot, zumbis, fome...), edite `servidor\Servers\Principal\Config.txt`. Nesse arquivo, uma linha sem valor usa o padrão do Hard.

## Estrutura

- `servidor\`: servidor dedicado oficial (Steam app 1110390), instalado pelo SteamCMD
- `servidor\Servers\Principal\`: saves (`Level\<mapa>`, `Players\...`) e configuração
- `steamcmd\`: SteamCMD
- `scripts\`: scripts do executor
- `modulo-autosave\`: código do module de autosave (compilado sozinho na hora de iniciar)
- `Instalar ou Atualizar.bat`: só atualiza o servidor, sem abrir
