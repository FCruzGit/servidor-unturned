# Levantamento de UX/UI — Painel do Servidor Unturned

Escopo: `painel/index.html` (painel web servido pelo `scripts/Painel.ps1`). A API do painel não muda; tudo abaixo é front-end.

Legenda de prioridade: **Alta** = atrapalha o uso ou causa erro; **Média** = atrito frequente; **Baixa** = acabamento.

## 1. Visão geral e hierarquia

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 1.1 | O cabeçalho mistura título, status, 6 métricas e as abas numa única linha. As métricas viram texto corrido, sem peso visual, e somem ou quebram em telas menores. | Alta | Cabeçalho só com marca, nome, status e abas. As métricas viram uma **faixa de cartões (KPIs)** na aba Painel: Mapa, Jogadores (com barra de lotação), Tempo ligado, RAM, Último save e Conexão. |
| 1.2 | O Server Code (o dado que mais se copia) aparece só como texto sublinhado tracejado. Não fica claro que dá para clicar. | Alta | Cartão "Conexão" com o código em destaque e um **botão Copiar** explícito. Com o servidor desligado, o cartão diz quando o código vai aparecer. |
| 1.3 | "Último save" mostra só a hora (ex.: 23:12:08), e é preciso fazer conta para saber se foi há pouco. | Média | Tempo relativo ("há 2 min"), com a hora exata no tooltip. |
| 1.4 | O favicon é sempre verde, mesmo com o servidor desligado. | Baixa | O favicon muda de cor conforme o estado (verde, amarelo ou cinza), então dá para ver o estado só pela aba do navegador. |

## 2. Controles do servidor

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 2.1 | Todos os botões têm o mesmo peso. Ações do ciclo de vida (Iniciar/Reiniciar/Desligar) e de manutenção (Salvar/Backup/Atualizar) ficam lado a lado, separadas só por um traço fino. | Média | Dois grupos rotulados ("Servidor" e "Manutenção"), com ícones. Iniciar fica como primário e Desligar como perigo. |
| 2.2 | O seletor de mapa não tem rótulo, e "tem save" fica colado ao nome. | Média | Rótulo "Mapa". As opções mostram "— com save" e "(Workshop)". |
| 2.3 | Confirmações usam `confirm()`/`prompt()` nativos: são feios, não explicam as consequências e no ban fazem **duas perguntas seguidas** (motivo, depois horas, em texto livre). | Alta | **Diálogos próprios** (`<dialog>`), com título, explicação e botão de perigo em vermelho. O ban vira um formulário único, com motivo e duração em lista (1 h, 24 h, 7 dias, 30 dias, permanente). |

## 3. Console

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 3.1 | Não dá para buscar no log, e achar um erro ou um jogador exige rolar milhares de linhas. | Alta | **Campo de busca** que filtra as linhas ao vivo e mostra quantas batem. |
| 3.2 | Com "rolar sozinho" ligado e o usuário rolando para cima para ler, as linhas novas chegam sem nenhum aviso. | Média | Botão flutuante **"↓ Novas linhas"** que aparece quando chega log e você não está no fim. |
| 3.3 | 18 "chips" de comandos crípticos (`irspawn todos`, `tp … …`) numa massa só, que ocupa até 3 linhas. | Média | **Ações rápidas agrupadas** (Servidor, Mundo, Spawn, Conexão, Admin), com nomes em português e o comando real no tooltip. A seção pode ser recolhida e o painel lembra a escolha. |
| 3.4 | Os checkboxes nativos no cabeçalho do console destoam do tema. | Baixa | Interruptores (switches) compactos. |
| 3.5 | Não há atalho de teclado para o campo de comando. | Baixa | Tecla **`/`** foca o comando (fora de outros campos). O placeholder avisa. |

## 4. Jogadores, spawn e eventos

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 4.1 | Cada jogador tem 5 botões do mesmo tamanho, e **Ban fica colado em Kick**, o que facilita o clique errado. | Alta | Ações de rotina à esquerda (Dados, Definir spawn aqui, Levar ao spawn). Kick e Ban ficam separados à direita, só com ícone e tooltip, com Ban em vermelho. |
| 4.2 | O ping é só um número cinza. | Média | Ponto colorido (bom < 80 ms, médio < 150 ms, ruim). |
| 4.3 | A lista não tem identidade visual, e nomes parecidos se confundem. | Baixa | Avatar com a inicial e uma cor fixa por jogador. |
| 4.4 | A lista é redesenhada a cada 2 s mesmo sem mudança, o que pode "roubar" o clique no meio de uma ação. | Média | Só redesenha quando o conteúdo muda. |
| 4.5 | O cartão Spawn mostra sempre um parágrafo longo de ajuda. | Baixa | Coordenadas em destaque e a ajuda em "Como definir o spawn?", recolhível. |
| 4.6 | A atualização do SteamCMD aparece só como texto bruto. | Média | **Barra de progresso** com a porcentagem lida do log, além do texto. |
| 4.7 | Os eventos não têm ícone por tipo. | Baixa | Ícone por tipo (ok, aviso, erro, info). |

## 5. Backups

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 5.1 | O botão **Restaurar** fica ativo com o servidor ligado e só falha depois de clicar. | Alta | Restaurar fica desabilitado com o servidor ligado, com um aviso explicando o motivo. |
| 5.2 | Para trocar de mapa é preciso abrir um `<select>`, e não dá para ver quantos backups cada mapa tem. | Média | **Abas de mapa** com contador. |
| 5.3 | Não há resumo (quantos backups, espaço usado, qual o mais recente). | Média | Três cartões de resumo. |
| 5.4 | A data aparece só absoluta, e os tipos têm todos a mesma cor. | Baixa | Tempo relativo mais a data, e cores por tipo (manual, periódico, ao desligar…). |
| 5.5 | Não dá para fazer backup a partir desta aba. | Baixa | Botão **Backup agora** na própria aba. |

## 6. Configuração

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 6.1 | São 18 campos numa lista única, sem agrupamento. | Alta | **Seções em cartões**: Servidor, Regras do jogo, Rede e conexão, Saves e backups, Administração, Workshop. |
| 6.2 | O botão Salvar fica só no topo e **não há indicação de alterações pendentes**. Clicar de novo na aba recarregava e **descartava o que foi digitado**. | Alta | Uma **barra fixa "Alterações não salvas"** aparece no rodapé ao editar. Trocar de aba não descarta nada, e o navegador avisa antes de fechar a página com alterações pendentes. |
| 6.3 | A senha aparece em texto puro, e o GSLT fica oculto sem como ver. | Média | Campo de senha com botão **mostrar/ocultar**. |
| 6.4 | Não há validação: porta 0 ou máximo de jogadores vazio só falhavam no servidor. | Média | Validação no próprio campo (obrigatórios, faixas de porta e jogadores), com destaque do campo inválido. |
| 6.5 | Checkboxes com o texto "Ligado/Desligado" ao lado. | Baixa | Interruptores. |

## 7. Acessibilidade, responsividade e feedback

| # | Problema | Prioridade | Solução aplicada |
|---|---|---|---|
| 7.1 | No celular as métricas viram texto corrido em 3 linhas, sem hierarquia. As abas ficam desalinhadas à direita, o separador sobra solto entre os botões e os checkboxes do console quebram em duas linhas. | Média | Layout pensado para telas estreitas: KPIs em 2 colunas, abas ocupando a largura toda, botões em grade e busca do console em linha própria. A tabela de backups ganha rolagem própria. |
| 7.2 | Os botões não mostram foco ao navegar pelo teclado. | Média | `:focus-visible` em todos os controles. |
| 7.3 | As abas não usam semântica de abas e não ficam na URL, então recarregar volta sempre ao Painel. | Média | `role="tab"`/`aria-selected` e aba na URL (`#backups`, `#config`). |
| 7.4 | Os toasts não são anunciados por leitores de tela e um novo substitui o anterior. | Baixa | `aria-live`, ícone por tipo e pilha de até 3. |
| 7.5 | O estado é indicado só pela cor do ponto. | Baixa | O texto do estado continua junto, e os KPIs repetem a informação. |

## Fora do escopo (sugestões futuras)

- Gráfico de RAM e jogadores ao longo do tempo (precisa guardar o histórico no `Painel.ps1`).
- Botão para baixar um backup ou abrir a pasta dele (precisa de uma rota nova na API).
- Editor do `Config.txt` (loot, zumbis) dentro do painel.
