# Restaura um backup de .\backups para o save do servidor (com o servidor desligado).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Comum.ps1')
$cfg = Ler-Config

if (Processos-Servidor) { Write-Host 'Desligue o servidor antes de restaurar um backup.' -ForegroundColor Red; Read-Host 'Enter para sair'; exit 1 }

$mapas = @(Get-ChildItem $BackupDir -Directory -ErrorAction SilentlyContinue | Where-Object { Get-ChildItem $_.FullName -Filter *.zip })
if (-not $mapas) { Write-Host 'Nenhum backup encontrado.' -ForegroundColor Yellow; Read-Host 'Enter para sair'; exit }

Write-Host '=== Restaurar backup ===' -ForegroundColor Cyan
for ($i = 0; $i -lt $mapas.Count; $i++) { Write-Host ('{0,2}) {1}' -f ($i + 1), $mapas[$i].Name) }
$r = Read-Host 'Mapa'
if ($r -notmatch '^\d+$' -or [int]$r -lt 1 -or [int]$r -gt $mapas.Count) { exit }
$mapaNome = $mapas[[int]$r - 1].Name

$zips = @(Get-ChildItem $mapas[[int]$r - 1].FullName -Filter *.zip | Sort-Object Name -Descending | Select-Object -First 25)
for ($i = 0; $i -lt $zips.Count; $i++) { Write-Host ('{0,2}) {1}' -f ($i + 1), $zips[$i].BaseName) }
$r = Read-Host 'Backup (1 = mais recente)'
if ($r -notmatch '^\d+$' -or [int]$r -lt 1 -or [int]$r -gt $zips.Count) { exit }
$zip = $zips[[int]$r - 1]

if ((Read-Host "Restaurar '$($zip.BaseName)' no mapa $mapaNome? O estado atual vira um backup antes. (s/n)") -ne 's') { exit }

Restaurar-Backup $mapaNome $zip.FullName $cfg
Write-Host "Backup restaurado. Ao iniciar o servidor no mapa $mapaNome ele volta desse ponto." -ForegroundColor Green
Read-Host 'Enter para sair'
