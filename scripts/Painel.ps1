# Painel web do servidor Unturned (http://localhost:<PortaPainel>).
# Faz o papel do executor + vigia: sobe o servidor sem janela, manda comandos pelo module (modulo-autosave\PainelModule.cs),
# mostra o log, faz os backups periodicos e reabre o servidor se ele cair. Rode pelo "Painel do Servidor.vbs" (sem janela).
param([switch]$SemNavegador)
$ErrorActionPreference = 'Stop'

# Os scripts compartilhados usam Write-Host; aqui nao ha console, entao vira evento do painel.
function Write-Host {
    param([Parameter(Position = 0, ValueFromPipeline = $true)]$Object, $ForegroundColor, $BackgroundColor, [switch]$NoNewline)
    process { if ($null -ne $Object -and "$Object".Trim()) { Evento "$Object" $ForegroundColor } }
}

. (Join-Path $PSScriptRoot 'Comum.ps1')

$PainelWeb    = Join-Path $Raiz 'painel'
$PainelDados  = Join-Path $SaveDir 'Painel'
$CmdDir       = Join-Path $PainelDados 'cmd'
$StatusArq    = Join-Path $PainelDados 'status.json'
$PainelLog    = Join-Path $PainelDados 'painel.log'
$AtualLog     = Join-Path $PainelDados 'atualizacao.log'
$Marcador     = Join-Path $SaveDir 'autosave-ultimo.txt'
$LogServidor  = Join-Path $ServidorDir "Logs\Server_$ServerId.log"
New-Item -ItemType Directory -Force $CmdDir | Out-Null
# O registro do painel so cresce: passando de 2 MB, a versao anterior vira painel.log.1
if ((Test-Path $PainelLog) -and (Get-Item $PainelLog).Length -gt 2MB) { Move-Item $PainelLog "$PainelLog.1" -Force }

$Eventos = New-Object System.Collections.Generic.List[object]
function Evento([string]$msg, $cor = $null) {
    $tipo = switch -Regex ("$cor") { '^Red' { 'erro' } 'Yellow' { 'aviso' } 'Green' { 'ok' } default { 'info' } }
    $e = [ordered]@{ hora = (Get-Date).ToString('s'); tipo = $tipo; texto = ($msg.Trim() -replace '^\[\d\d:\d\d:\d\d\]\s*', '') }
    $Eventos.Add($e)
    if ($Eventos.Count -gt 200) { $Eventos.RemoveAt(0) }
    try { Add-Content -Path $PainelLog -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $e.texto) -Encoding UTF8 } catch {}
}

# Um painel por vez: se ja tem um aberto, so abre o navegador nele.
$cfg = Ler-Config
$Porta = if ($cfg.PortaPainel) { [int]$cfg.PortaPainel } else { 8090 }
$Url = "http://localhost:$Porta/"
$mutex = New-Object System.Threading.Mutex($false, 'Local\PainelServidorUnturned')
if (-not $mutex.WaitOne(0)) { if (-not $SemNavegador) { Start-Process $Url }; exit }

# ---------------- Estado ----------------
$S = @{
    Estado          = 'parado'   # parado | atualizando | iniciando | rodando | parando | aguardando-reinicio
    Proc            = $null
    Mapa            = $null
    Inicio          = $null
    Sessao          = 0
    ProcAtualizacao = $null
    MapaPendente    = $null
    PararPedido     = $false
    ReiniciarCom    = $null       # mapa para abrir depois de desligar (reiniciar / trocar mapa)
    ParandoDesde    = $null
    ReinicioEm      = $null
    Quedas          = 0
    UltimoBackup    = Get-Date
    UltimoSave      = [datetime]::MinValue
    BackupManualEm  = $null
    ServerCode      = $null
    LogPos          = 0L
    Ponte           = $false
}

# O navegador pede o status a cada 2 s; a lista de mapas (pastas no disco) so e refeita a cada 15 s.
$MapasCache = @{ Valor = $null; Em = [datetime]::MinValue }
function Mapas-Disponiveis {
    if (-not $MapasCache.Valor -or ((Get-Date) - $MapasCache.Em).TotalSeconds -gt 15) {
        $MapasCache.Valor = @(Listar-Mapas $cfg | ForEach-Object {
            [ordered]@{ nome = $_.Nome; workshop = $_.Workshop; temSave = (Test-Path (Join-Path $SaveDir "Level\$($_.Nome)")) }
        })
        $MapasCache.Em = Get-Date
    }
    $MapasCache.Valor
}
function Invalidar-Mapas { $MapasCache.Valor = $null }

function Ultimo-Mapa { if (Test-Path $UltimoMapaArq) { (Get-Content $UltimoMapaArq -Raw).Trim() } else { '' } }

# status.json e lido pela vigia (1 s) e pelo navegador (2 s); so e relido do disco quando o module o reescreve.
$StatusCache = @{ Valor = $null; Em = [datetime]::MinValue }
function Ler-Status {
    try {
        $i = New-Object IO.FileInfo $StatusArq
        if (-not $i.Exists -or ([datetime]::UtcNow - $i.LastWriteTimeUtc).TotalSeconds -gt 10) { return $null }
        if ($i.LastWriteTimeUtc -ne $StatusCache.Em) {
            $StatusCache.Valor = [IO.File]::ReadAllText($StatusArq) | ConvertFrom-Json
            $StatusCache.Em = $i.LastWriteTimeUtc
        }
        $StatusCache.Valor
    } catch { $null }
}

function Servidor-Aberto { $S.Proc -and -not $S.Proc.HasExited }

function Enviar-Comando([string]$texto) {
    $texto = ($texto -replace '[\r\n]+', ' ').Trim()
    if (-not $texto) { throw 'Comando vazio.' }
    if (-not (Servidor-Aberto)) { throw 'O servidor nao esta rodando.' }
    if (-not $S.Ponte) { throw 'Este servidor foi aberto fora do painel; reinicie-o pelo painel para poder mandar comandos.' }
    $nome = '{0:D20}' -f [DateTime]::UtcNow.Ticks
    $tmp = Join-Path $CmdDir "$nome.tmp"
    [IO.File]::WriteAllText($tmp, $texto, (New-Object Text.UTF8Encoding($false)))
    Move-Item $tmp (Join-Path $CmdDir "$nome.cmd")
}

$IpPublico = @{ Valor = $null; Em = [datetime]::MinValue }
function Info-Conexao {
    $c = Ler-Config
    $lan = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.IPv4Address.IPAddress }) -join ', '
    if (((Get-Date) - $IpPublico.Em).TotalMinutes -gt 10) {
        try { $IpPublico.Valor = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 4).ToString().Trim() } catch { $IpPublico.Valor = $null }
        $IpPublico.Em = Get-Date
    }
    $codigo = if ($S.ServerCode) { $S.ServerCode } elseif (Servidor-Aberto) { '(ainda gerando, aguarde o servidor terminar de carregar)' } else { '(aparece quando o servidor estiver ligado)' }
    $l = @(
        "Server Code: $codigo   <- amigos: Play > Connect, cole o codigo (nao precisa abrir porta)",
        "Porta:       $($c.Porta) (o Unturned usa tambem $([int]$c.Porta + 1)); modo $(if ($c.Internet) { 'internet' } else { 'so LAN' })",
        "Senha:       $(if ($c.Senha) { $c.Senha } else { '(sem senha)' })",
        "Neste PC:    127.0.0.1:$($c.Porta)",
        "Rede local:  $(if ($lan) { ($lan -split ', ' | ForEach-Object { "$($_):$($c.Porta)" }) -join ', ' } else { '?' })",
        "IP publico:  $(if ($IpPublico.Valor) { "$($IpPublico.Valor):$($c.Porta) (so funciona com as portas $($c.Porta)-$([int]$c.Porta + 1) UDP abertas no roteador)" } else { '(nao consegui descobrir)' })"
    )
    $l -join "`n"
}

# Comandos do proprio painel (com "/"), que funcionam mesmo com o servidor desligado.
# Os demais vao para o servidor; um "/" no comeco e tirado (o console do Unturned nao usa).
function Comando-Painel([string]$texto) {
    $texto = ($texto -replace '[\r\n]+', ' ').Trim()
    if ($texto -notmatch '^/(\S+)\s*(.*)$') { Enviar-Comando $texto; return $null }
    $nome = $Matches[1].ToLower(); $arg = $Matches[2].Trim()
    switch ($nome) {
        'definir_senha' {
            if (-not $arg) { throw 'Uso: /definir_senha NOVA_SENHA' }
            if ($arg -match '\s') { throw 'A senha nao pode ter espacos.' }
            $json = [IO.File]::ReadAllText($ConfigArq)
            $valor = ConvertTo-Json -InputObject $arg
            $novo = [regex]::Replace($json, '"Senha"\s*:\s*"(?:[^"\\]|\\.)*"', { param($m) "`"Senha`": $valor" })
            if ($novo -eq $json -and $json -notmatch '"Senha"') { throw 'Campo Senha nao encontrado no config\servidor.json.' }
            Salvar-Config $novo
            $extra = if (Servidor-Aberto) { ' Reinicie o servidor para valer.' } else { ' Vale no proximo inicio.' }
            return "Senha do servidor alterada para: $arg.$extra"
        }
        'mostrar_senha' {
            $s = (Ler-Config).Senha
            return $(if ($s) { "Senha do servidor: $s" } else { 'O servidor esta sem senha.' })
        }
        'conexao' { return (Info-Conexao) }
        default { Enviar-Comando $texto.Substring(1); return $null }
    }
}

# ---------------- Ciclo de vida do servidor ----------------
function Iniciar([string]$mapaNome) {
    if (Servidor-Aberto) { throw 'O servidor ja esta rodando.' }
    if ($S.Estado -eq 'atualizando') { throw 'Aguarde a atualizacao terminar.' }
    $script:cfg = Ler-Config
    $mapa = Listar-Mapas $cfg | Where-Object Nome -eq $mapaNome | Select-Object -First 1
    if (-not $mapa) { throw "Mapa '$mapaNome' nao encontrado." }
    Set-Content -Path $UltimoMapaArq -Value $mapa.Nome -Encoding UTF8
    Invalidar-Mapas
    $S.Mapa = $mapa.Nome
    $S.PararPedido = $false
    $S.ReiniciarCom = $null
    if ($cfg.AtualizarAoIniciar -or -not (Test-Path $ServidorExe)) {
        Atualizar $mapa.Nome
    } else {
        Preparar-E-Abrir
    }
}

function Atualizar($mapaDepois) {
    if (Servidor-Aberto) { throw 'Desligue o servidor antes de atualizar.' }
    Evento 'Atualizando o servidor pelo SteamCMD...'
    $S.MapaPendente = $mapaDepois
    $S.Estado = 'atualizando'
    $S.ProcAtualizacao = Start-Process powershell.exe -PassThru -WindowStyle Hidden `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'Instalar.ps1')`"" `
        -RedirectStandardOutput $AtualLog -RedirectStandardError "$($AtualLog).err"
}

function Preparar-E-Abrir {
    $mapa = Listar-Mapas $cfg | Where-Object Nome -eq $S.Mapa | Select-Object -First 1
    try {
        Evento "Preparando o mapa $($mapa.Nome)..."
        Instalar-ModuloAutosave
        Fazer-Backup $mapa.Nome 'antes-de-iniciar' $cfg
        Escrever-Commands $cfg $mapa
        Escrever-Workshop $cfg $mapa
        Get-ChildItem $CmdDir -File | Remove-Item -Force
        if (Test-Path $StatusArq) { Remove-Item $StatusArq -Force }
        $env:UT_AUTOSAVE_MINUTOS  = [string]$cfg.AutosaveMinutos
        $env:UT_AUTOSAVE_MARCADOR = $Marcador
        $env:UT_PAINEL_DIR        = $PainelDados
        $env:UT_OCULTAR_CONSOLE   = '1'
        $env:UT_SPAWN_CAMA        = $(if ($cfg.SpawnRespeitaCama -eq $false) { '0' } else { '1' })
        $modo = if ($cfg.Internet) { 'InternetServer' } else { 'LanServer' }
        $p = Start-Process $ServidorExe -PassThru -WindowStyle Hidden -WorkingDirectory $ServidorDir `
            -ArgumentList "-batchmode -nographics +$modo/$ServerId"
        Adotar $p $true
        $S.Estado = 'iniciando'
        Evento "Servidor abrindo no mapa $($mapa.Nome) (PID $($p.Id))." 'Green'
    } catch {
        $S.Estado = 'parado'
        Evento "Falha ao abrir o servidor: $($_.Exception.Message)" 'Red'
    }
}

function Adotar($p, [bool]$ponte) {
    $S.Proc = $p
    $S.Inicio = try { $p.StartTime } catch { Get-Date }
    $S.Sessao++
    $S.Ponte = $ponte
    $S.ServerCode = $null
    $S.LogPos = 0L
    $S.UltimoBackup = Get-Date
    $S.UltimoSave = if (Test-Path $Marcador) { (Get-Item $Marcador).LastWriteTime } else { [datetime]::MinValue }
}

function Parar([string]$reiniciarCom = $null) {
    if (-not (Servidor-Aberto)) {
        if ($S.Estado -eq 'aguardando-reinicio') { $S.Estado = 'parado'; Evento 'Reinicio automatico cancelado.' 'Yellow'; return }
        throw 'O servidor nao esta rodando.'
    }
    Enviar-Comando 'shutdown'
    $S.PararPedido = $true
    $S.ReiniciarCom = $reiniciarCom
    $S.ParandoDesde = Get-Date
    $S.Estado = 'parando'
    Evento $(if ($reiniciarCom) { "Reiniciando (mapa $reiniciarCom)..." } else { 'Desligando o servidor (salvando o mundo)...' })
}

function Servidor-Fechou {
    $S.Proc = $null
    Invalidar-Mapas
    Start-Sleep -Seconds 1
    Fazer-Backup $S.Mapa 'ao-desligar' $cfg
    $fim = if (Test-Path $LogServidor) { (Get-Content $LogServidor -Tail 15) -join "`n" } else { '' }
    $normal = $fim -match 'Finished quitting' -and $fim -notmatch '(?i)workshop.*update|update.*detected'

    if ($S.ReiniciarCom) { $m = $S.ReiniciarCom; $S.ReiniciarCom = $null; $S.Estado = 'parado'; Iniciar $m; return }
    if ($S.PararPedido -or $normal) {
        $S.Estado = 'parado'
        Evento 'Servidor desligado. Mundo salvo e backup feito.' 'Green'
        return
    }
    if (((Get-Date) - $S.Inicio).TotalMinutes -gt 10) { $S.Quedas = 0 }
    $S.Quedas++
    if ($S.Quedas -gt 5) { $S.Estado = 'parado'; Evento 'O servidor caiu muitas vezes seguidas; desisti. Veja servidor\Logs.' 'Red'; return }
    $S.Estado = 'aguardando-reinicio'
    $S.ReinicioEm = (Get-Date).AddSeconds(10)
    Evento 'O servidor fechou sem desligamento normal (queda ou atualizacao). Reabrindo em 10 s...' 'Yellow'
}

# Le o que o servidor escreveu no log desde a ultima vez (para achar o Server Code desta sessao).
function Ler-NovoLog {
    if ($S.ServerCode -or -not $S.Inicio -or -not (Test-Path $LogServidor)) { return }   # o codigo sai uma vez por sessao
    $fs = [IO.File]::Open($LogServidor, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        if ($fs.Length -lt $S.LogPos) { $S.LogPos = 0L }
        $fs.Position = $S.LogPos
        $txt = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd()
        $S.LogPos = $fs.Length
    } finally { $fs.Close() }
    $inicioUtc = $S.Inicio.ToUniversalTime().AddSeconds(-5)
    foreach ($m in [regex]::Matches($txt, '\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] Server Code: (\d+)')) {
        $t = [datetime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss', $null)
        if ($t -ge $inicioUtc) { $S.ServerCode = $m.Groups[2].Value }
    }
}

function Tick {
    switch ($S.Estado) {
        'atualizando' {
            if ($S.ProcAtualizacao.HasExited) {
                $ok = Test-Path $ServidorExe
                Evento $(if ($ok) { 'Atualizacao concluida.' } else { 'Falha ao instalar o servidor (veja o log da atualizacao).' }) $(if ($ok) { 'Green' } else { 'Red' })
                $S.Estado = 'parado'
                if ($ok -and $S.MapaPendente) { $S.MapaPendente = $null; Preparar-E-Abrir }
            }
        }
        'aguardando-reinicio' {
            if ((Get-Date) -ge $S.ReinicioEm) { $S.Estado = 'parado'; Iniciar $S.Mapa }
        }
        default {
            if (-not $S.Proc) { break }
            if ($S.Proc.HasExited) { Servidor-Fechou; break }
            $st = Ler-Status
            if ($st) { $S.Ponte = $true }
            if ($S.Estado -eq 'iniciando' -and (($st -and $st.carregado) -or (-not $S.Ponte -and ((Get-Date) - $S.Inicio).TotalSeconds -gt 20))) {
                $S.Estado = 'rodando'
                Evento 'Servidor pronto para receber jogadores.' 'Green'
            }
            # Backup periodico logo apos um autosave (arquivos consistentes)
            if (Test-Path $Marcador) {
                $t = (Get-Item $Marcador).LastWriteTime
                if ($t -ne $S.UltimoSave) {
                    $S.UltimoSave = $t
                    if (((Get-Date) - $S.UltimoBackup).TotalMinutes -ge $cfg.BackupACadaMinutos - 0.1) {
                        Start-Sleep -Seconds 2
                        Fazer-Backup $S.Mapa 'periodico' $cfg
                        $S.UltimoBackup = Get-Date
                    }
                }
            }
            if ($S.BackupManualEm -and (Get-Date) -ge $S.BackupManualEm) {
                $S.BackupManualEm = $null
                Fazer-Backup $S.Mapa 'manual' $cfg
            }
            Ler-NovoLog
        }
    }
}

# ---------------- API ----------------
function Ler-Log([long]$pos) {
    if (-not (Test-Path $LogServidor)) { return [ordered]@{ pos = 0; texto = ''; reset = $true } }
    $fs = [IO.File]::Open($LogServidor, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        $reset = $false
        if ($pos -lt 0 -or $pos -gt $fs.Length) { $pos = [Math]::Max(0L, $fs.Length - 96KB); $reset = $true }
        $n = [int][Math]::Min(512KB, $fs.Length - $pos)
        $buf = New-Object byte[] $n
        $fs.Position = $pos
        $lidos = 0
        while ($lidos -lt $n) { $r = $fs.Read($buf, $lidos, $n - $lidos); if ($r -le 0) { break }; $lidos += $r }
        # So devolve linhas completas
        $fimLinha = if ($lidos -gt 0) { [Array]::LastIndexOf($buf, [byte]10, $lidos - 1) } else { -1 }
        $usar = if ($lidos -gt 0 -and $fimLinha -ge 0) { $fimLinha + 1 } else { 0 }
        $txt = [Text.Encoding]::UTF8.GetString($buf, 0, $usar)
        if ($reset -and $pos -gt 0) { $txt = $txt.Substring([Math]::Min($txt.Length, $txt.IndexOf("`n") + 1)) }
        return [ordered]@{ pos = $pos + $usar; texto = $txt; reset = $reset }
    } finally { $fs.Close() }
}

function Status-Atual {
    $st = if (Servidor-Aberto) { Ler-Status } else { $null }
    $mem = $null
    if (Servidor-Aberto) { try { $S.Proc.Refresh(); $mem = [math]::Round($S.Proc.WorkingSet64 / 1MB) } catch {} }
    $atual = ''
    if ($S.Estado -eq 'atualizando' -and (Test-Path $AtualLog)) { $atual = (Get-Content $AtualLog -Tail 12 -ErrorAction SilentlyContinue) -join "`n" }
    [ordered]@{
        estado        = $S.Estado
        mapa          = $S.Mapa
        pid           = $(if (Servidor-Aberto) { $S.Proc.Id } else { $null })
        inicio        = $(if ($S.Inicio -and (Servidor-Aberto)) { $S.Inicio.ToString('o') } else { $null })
        memoriaMB     = $mem
        ponte         = $S.Ponte
        serverCode    = $S.ServerCode
        jogadores     = @($(if ($st) { $st.jogadores } else { @() }))
        spawn         = $(if ($st) { $st.spawn } else { $null })
        max           = $(if ($st) { $st.max } else { $cfg.MaxJogadores })
        sessao        = $S.Sessao
        parandoHa     = $(if ($S.Estado -eq 'parando') { [int]((Get-Date) - $S.ParandoDesde).TotalSeconds } else { 0 })
        reinicioEm    = $(if ($S.Estado -eq 'aguardando-reinicio') { $S.ReinicioEm.ToString('o') } else { $null })
        ultimoAutosave = $(if ($S.UltimoSave -gt [datetime]::MinValue) { $S.UltimoSave.ToString('o') } else { $null })
        atualizacao   = $atual
        ultimoMapa    = Ultimo-Mapa
        mapas         = @(Mapas-Disponiveis)
        servidor      = [ordered]@{ nome = $cfg.Nome; porta = $cfg.Porta; internet = [bool]$cfg.Internet; autosave = $cfg.AutosaveMinutos; backup = $cfg.BackupACadaMinutos; senha = [bool]$cfg.Senha }
        eventos       = @($Eventos | Select-Object -Last 80)
    }
}

function Listar-Backups {
    @(Get-ChildItem $BackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        $arqs = @(Get-ChildItem $_.FullName -Filter *.zip | Sort-Object Name -Descending | ForEach-Object {
            $motivo = if ($_.BaseName -match '^\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d_(.+)$') { $Matches[1] } else { '' }
            [ordered]@{ nome = $_.Name; data = $_.LastWriteTime.ToString('o'); tamanhoMB = [math]::Round($_.Length / 1MB, 1); motivo = $motivo }
        })
        if ($arqs) { [ordered]@{ mapa = $_.Name; arquivos = $arqs } }
    })
}

function Restaurar($mapaNome, $arquivo) {
    if ((Servidor-Aberto) -or (Processos-Servidor)) { throw 'Desligue o servidor antes de restaurar um backup.' }
    if ($S.Estado -ne 'parado') { throw 'Aguarde o painel ficar parado.' }
    if ($mapaNome -match '[\\/]|\.\.' -or $arquivo -match '[\\/]|\.\.' -or $arquivo -notlike '*.zip') { throw 'Backup invalido.' }
    $zip = Join-Path $BackupDir "$mapaNome\$arquivo"
    if (-not (Test-Path $zip)) { throw 'Backup nao encontrado.' }
    Restaurar-Backup $mapaNome $zip $cfg
    Invalidar-Mapas
    Evento "Backup $arquivo restaurado no mapa $mapaNome." 'Green'
}

function Salvar-Config([string]$texto) {
    $novo = $texto | ConvertFrom-Json   # valida
    foreach ($c in 'Nome', 'Porta', 'MaxJogadores') { if (-not $novo.$c) { throw "Campo obrigatorio: $c" } }
    [IO.File]::WriteAllText($ConfigArq, $texto, (New-Object Text.UTF8Encoding($false)))
    $script:cfg = Ler-Config
    Invalidar-Mapas
    Evento 'Configuracao salva. Vale a partir do proximo inicio do servidor.' 'Green'
}

function Responder($ctx, $obj, [int]$codigo = 200) {
    $json = ConvertTo-Json -InputObject $obj -Depth 8 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $ctx.Response.StatusCode = $codigo
    $ctx.Response.ContentType = 'application/json; charset=utf-8'
    $ctx.Response.Headers['Cache-Control'] = 'no-store'
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Tratar($ctx) {
    $req = $ctx.Request
    $rota = $req.Url.AbsolutePath
    if ($req.HttpMethod -eq 'GET' -and $rota -eq '/') {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $PainelWeb 'index.html'))
        $ctx.Response.ContentType = 'text/html; charset=utf-8'
        $ctx.Response.Headers['Cache-Control'] = 'no-store'
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        return
    }
    $corpo = $null
    if ($req.HttpMethod -eq 'POST') {
        # Bloqueia sites de fora tentando mandar comandos pelo navegador (CSRF)
        $origem = $req.Headers['Origin']
        if ($req.Headers['X-Painel'] -ne '1' -or ($origem -and $origem.TrimEnd('/') -ne $Url.TrimEnd('/') -and $origem -ne "http://127.0.0.1:$Porta")) {
            Responder $ctx @{ erro = 'Proibido.' } 403; return
        }
        $texto = (New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)).ReadToEnd()
        if ($texto) { $corpo = $texto | ConvertFrom-Json }
    }
    $r = switch ("$($req.HttpMethod) $rota") {
        'GET /api/status'     { Status-Atual }
        'GET /api/log'        { Ler-Log ([long]($(if ($req.QueryString['pos']) { $req.QueryString['pos'] } else { -1 }))) }
        'GET /api/backups'    { @{ backups = @(Listar-Backups) } }
        'GET /api/comandos'   {
            $arq = Join-Path $PainelDados 'comandos.json'
            $srv = if (Test-Path $arq) { @([IO.File]::ReadAllText($arq) | ConvertFrom-Json) } else { @() }
            @{ servidor = [object[]]@($srv | Where-Object { $_ }); painel = @(
                @{ c = '/conexao'; info = 'Mostra Server Code, IPs, porta e senha'; help = '/conexao' },
                @{ c = '/mostrar_senha'; info = 'Mostra a senha do servidor'; help = '/mostrar_senha' },
                @{ c = '/definir_senha'; info = 'Troca a senha do servidor (vale ao reiniciar)'; help = '/definir_senha <nova senha>' }) }
        }
        'GET /api/config'     { @{ texto = [IO.File]::ReadAllText($ConfigArq) } }
        'POST /api/iniciar'   { Iniciar $corpo.mapa; @{ ok = $true } }
        'POST /api/parar'     { Parar; @{ ok = $true } }
        'POST /api/reiniciar' { $m = if ($corpo.mapa) { $corpo.mapa } else { $S.Mapa }; Parar $m; @{ ok = $true } }
        'POST /api/forcar'    {
            if (-not (Servidor-Aberto)) { throw 'O servidor nao esta rodando.' }
            $S.PararPedido = $true; $S.ReiniciarCom = $null
            Evento 'Forcando o fechamento do servidor (perde o que nao foi salvo).' 'Yellow'
            Stop-Process -Id $S.Proc.Id -Force; @{ ok = $true }
        }
        'POST /api/comando'   { $msg = Comando-Painel $corpo.texto; @{ ok = $true; mensagem = $msg } }
        'POST /api/salvar'    { Enviar-Comando 'save'; Evento 'Salvando o mundo...'; @{ ok = $true } }
        'POST /api/backup'    {
            if (Servidor-Aberto) { Enviar-Comando 'save'; $S.BackupManualEm = (Get-Date).AddSeconds(5); Evento 'Salvando o mundo e fazendo backup...' }
            else { $m = if ($corpo.mapa) { $corpo.mapa } else { Ultimo-Mapa }; Fazer-Backup $m 'manual' $cfg }
            @{ ok = $true }
        }
        'POST /api/restaurar' { Restaurar $corpo.mapa $corpo.arquivo; @{ ok = $true } }
        'POST /api/config'    { Salvar-Config $corpo.texto; @{ ok = $true } }
        'POST /api/atualizar' { if ($S.Estado -ne 'parado') { throw 'Desligue o servidor antes de atualizar.' }; Atualizar $null; @{ ok = $true } }
        'POST /api/sair'      { $script:Rodando = $false; Evento 'Painel fechado.'; @{ ok = $true } }
        default               { $null }
    }
    if ($null -eq $r) { Responder $ctx @{ erro = 'Nao encontrado.' } 404 } else { Responder $ctx $r }
}

# ---------------- Laco principal ----------------
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($Url)
try { $listener.Start() } catch { Evento "Nao consegui abrir a porta $Porta do painel: $($_.Exception.Message)" 'Red'; exit 1 }
Evento "Painel aberto em $Url" 'Green'

$jaAberto = Processos-Servidor | Select-Object -First 1
if ($jaAberto) {
    $S.Mapa = Ultimo-Mapa
    Adotar $jaAberto $false
    $S.Estado = 'rodando'
    Evento "O servidor ja estava aberto (mapa $($S.Mapa), PID $($jaAberto.Id)); o painel assumiu a vigia." 'Yellow'
}

if (-not $SemNavegador) { Start-Process $Url }

$Rodando = $true
$proximoTick = Get-Date
$tarefa = $listener.GetContextAsync()
while ($Rodando) {
    if ($tarefa.Wait(250)) {
        $ctx = $tarefa.Result
        try { Tratar $ctx }
        catch { try { Responder $ctx @{ erro = $_.Exception.Message } 400 } catch {} }
        finally { try { $ctx.Response.Close() } catch {} }
        if ($Rodando) { $tarefa = $listener.GetContextAsync() }
    }
    if ((Get-Date) -ge $proximoTick) {
        $proximoTick = (Get-Date).AddSeconds(1)
        try { Tick } catch { Evento "Erro na vigia: $($_.Exception.Message)" 'Red' }
    }
}
Start-Sleep -Milliseconds 300
$listener.Stop()
$mutex.ReleaseMutex()
