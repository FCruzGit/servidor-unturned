# Executor do servidor Unturned: escolhe o mapa, faz backup, sobe o servidor em modo Hard
# (com o module de autosave) e fica vigiando para fazer backups e reiniciar se o servidor cair.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Comum.ps1')

$cfg = Ler-Config

function Info([string]$msg, [string]$cor = 'Cyan') {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -ForegroundColor $cor
}

# ---------- Servidor ja aberto? So volta a vigiar ----------
$jaRodando = Processos-Servidor | Select-Object -First 1
if ($jaRodando) {
    $mapaNome = if (Test-Path $UltimoMapaArq) { (Get-Content $UltimoMapaArq -Raw).Trim() } else { '?' }
    Info "O servidor ja esta aberto (mapa $mapaNome). Voltando a vigiar backups." 'Yellow'
    $mapa = [pscustomobject]@{ Nome = $mapaNome }
} else {
    if ($cfg.AtualizarAoIniciar -or -not (Test-Path $ServidorExe)) {
        & (Join-Path $PSScriptRoot 'Instalar.ps1')
    }

    # ---------- Selecao de mapa ----------
    $mapas = @(Listar-Mapas $cfg)
    $ultimo = if (Test-Path $UltimoMapaArq) { (Get-Content $UltimoMapaArq -Raw).Trim() } else { '' }
    $padrao = [Math]::Max(0, [Array]::IndexOf(@($mapas | ForEach-Object Nome), $ultimo))

    Write-Host ''
    Write-Host '=== Servidor Unturned - dificuldade HARD ===' -ForegroundColor Cyan
    for ($i = 0; $i -lt $mapas.Count; $i++) {
        $m = $mapas[$i]
        $tags = @()
        if ($m.Workshop) { $tags += 'workshop' }
        if (Test-Path (Join-Path $SaveDir "Level\$($m.Nome)")) { $tags += 'tem save' }
        $txt = '{0} {1,2}) {2}' -f $(if ($i -eq $padrao) { '>' } else { ' ' }), ($i + 1), $m.Nome
        if ($tags) { $txt += "  [$($tags -join ', ')]" }
        Write-Host $txt -ForegroundColor $(if ($i -eq $padrao) { 'Green' } else { 'Gray' })
    }
    Write-Host ''
    $resp = (Read-Host "Numero do mapa (Enter = $($mapas[$padrao].Nome))") -replace '[^\d]', ''
    $idx = $padrao
    if ($resp -match '^\d+$' -and [int]$resp -ge 1 -and [int]$resp -le $mapas.Count) { $idx = [int]$resp - 1 }
    $mapa = $mapas[$idx]
    Set-Content -Path $UltimoMapaArq -Value $mapa.Nome -Encoding UTF8
    Info "Mapa: $($mapa.Nome)" 'Green'

    Instalar-ModuloAutosave
    Fazer-Backup $mapa.Nome 'antes-de-iniciar' $cfg
    Escrever-Commands $cfg $mapa
    Escrever-Workshop $cfg $mapa
}

$host.UI.RawUI.WindowTitle = "Vigia do servidor Unturned - $($mapa.Nome)"
$modo = if ($cfg.Internet) { 'InternetServer' } else { 'LanServer' }
$marcador = Join-Path $SaveDir 'autosave-ultimo.txt'
$logServidor = Join-Path $ServidorDir "Logs\Server_$ServerId.log"

function Abrir-Servidor {
    $env:UT_AUTOSAVE_MINUTOS  = [string]$cfg.AutosaveMinutos
    $env:UT_AUTOSAVE_MARCADOR = $marcador
    # "start" pelo cmd (como o ServerHelper.bat oficial) para o servidor ganhar a propria janela de console:
    # e nela que se digitam comandos, e fechar essa janela faz o servidor salvar antes de sair.
    # Start-Process (e nao "cmd /c" direto) para o servidor nao herdar os handles desta janela.
    Start-Process cmd.exe -WindowStyle Hidden -ArgumentList "/c start `"Unturned - $($mapa.Nome)`" /D `"$ServidorDir`" `"$ServidorExe`" -batchmode -nographics +$modo/$ServerId"
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        $p = Processos-Servidor | Select-Object -First 1
        if ($p) { return $p }
    }
    throw 'O servidor nao abriu.'
}

Write-Host ''
Write-Host 'O servidor roda na OUTRA janela ("Unturned - ...").' -ForegroundColor Yellow
Write-Host '  - Comandos (save, players, say, admin...) sao digitados la.' -ForegroundColor Yellow
Write-Host '  - Para desligar: digite  shutdown  la, aperte Ctrl+C la ou feche aquela janela (ele salva antes).' -ForegroundColor Yellow
Write-Host "  - O mundo e salvo sozinho a cada $($cfg.AutosaveMinutos) min; backup em .\backups a cada $($cfg.BackupACadaMinutos) min." -ForegroundColor Yellow
Write-Host '  - Esta janela e so a vigia: pode fechar que o servidor continua (mas sem os backups periodicos).' -ForegroundColor Yellow
Write-Host ''

$quedas = 0
while ($true) {
    $proc = if ($jaRodando) { $jaRodando } else { Abrir-Servidor }
    $jaRodando = $null
    $inicio = Get-Date
    Info "Servidor rodando (PID $($proc.Id))." 'Green'

    $ultimoBackup = Get-Date
    $ultimoSave = if (Test-Path $marcador) { (Get-Item $marcador).LastWriteTime } else { [datetime]::MinValue }

    while (-not $proc.HasExited) {
        Start-Sleep -Seconds 2
        # Backup logo apos um autosave (arquivos consistentes), respeitando o intervalo configurado
        if (Test-Path $marcador) {
            $t = (Get-Item $marcador).LastWriteTime
            if ($t -ne $ultimoSave) {
                $ultimoSave = $t
                if (((Get-Date) - $ultimoBackup).TotalMinutes -ge $cfg.BackupACadaMinutos - 0.1) {
                    Start-Sleep -Seconds 2
                    Fazer-Backup $mapa.Nome 'periodico' $cfg
                    $ultimoBackup = Get-Date
                }
            }
        }
    }

    Start-Sleep -Seconds 1
    Fazer-Backup $mapa.Nome 'ao-desligar' $cfg

    # Desligamento normal (shutdown, Ctrl+C, fechar janela) termina o log com "Finished quitting".
    $fim = if (Test-Path $logServidor) { (Get-Content $logServidor -Tail 15) -join "`n" } else { '' }
    if ($fim -match 'Finished quitting' -and $fim -notmatch '(?i)workshop.*update|update.*detected') {
        Info 'Servidor desligado normalmente. Mundo salvo e backup feito.' 'Green'
        break
    }

    if (((Get-Date) - $inicio).TotalMinutes -gt 10) { $quedas = 0 }
    $quedas++
    if ($quedas -gt 5) { Info 'O servidor caiu muitas vezes seguidas; desisti. Veja servidor\Logs.' 'Red'; break }
    Info 'O servidor fechou sem desligamento normal (queda ou atualizacao). Reabrindo em 10 s... (feche esta janela para cancelar)' 'Yellow'
    Start-Sleep -Seconds 10
    if ($cfg.AtualizarAoIniciar) { & (Join-Path $PSScriptRoot 'Instalar.ps1') ; Instalar-ModuloAutosave }
}

Write-Host ''
Read-Host 'Enter para fechar'
