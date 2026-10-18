# Instala ou atualiza o servidor dedicado do Unturned (Steam app 1110390) via SteamCMD.
$ErrorActionPreference = 'Stop'
$Raiz      = Split-Path -Parent $PSScriptRoot
$SteamCmd  = Join-Path $Raiz 'steamcmd'
$Servidor  = Join-Path $Raiz 'servidor'
$Exe       = Join-Path $SteamCmd 'steamcmd.exe'

if (-not (Test-Path $Exe)) {
    Write-Host 'Baixando SteamCMD (Valve)...' -ForegroundColor Cyan
    New-Item -ItemType Directory -Force $SteamCmd | Out-Null
    $zip = Join-Path $SteamCmd 'steamcmd.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $SteamCmd -Force
    Remove-Item $zip
}

New-Item -ItemType Directory -Force $Servidor | Out-Null
Write-Host 'Instalando/atualizando servidor dedicado do Unturned...' -ForegroundColor Cyan
# "validate" confere todos os arquivos do servidor (lento): so na primeira instalacao ou depois de uma tentativa que falhou.
# O SteamCMD as vezes sai com codigo 7/8 na primeira execucao (auto-atualizacao); tenta de novo.
$validar = -not (Test-Path (Join-Path $Servidor 'Unturned.exe'))
for ($i = 1; $i -le 3; $i++) {
    $extra = if ($validar) { @('validate') } else { @() }
    & $Exe +force_install_dir "$Servidor" +login anonymous +app_update 1110390 @extra +quit
    $validar = $true
    if (Test-Path (Join-Path $Servidor 'Unturned.exe')) { if ($LASTEXITCODE -eq 0) { break } }
    Write-Host "SteamCMD saiu com codigo $LASTEXITCODE, tentando de novo ($i/3)..." -ForegroundColor Yellow
}

if (-not (Test-Path (Join-Path $Servidor 'Unturned.exe'))) { throw 'Falha ao instalar o servidor.' }
Write-Host 'Servidor instalado/atualizado com sucesso.' -ForegroundColor Green
