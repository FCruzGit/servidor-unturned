# Caminhos e funcoes compartilhadas pelos scripts do servidor.
$Raiz          = Split-Path -Parent $PSScriptRoot
$ServidorDir   = Join-Path $Raiz 'servidor'
$ServidorExe   = Join-Path $ServidorDir 'Unturned.exe'
$ServerId      = 'Principal'
$SaveDir       = Join-Path $ServidorDir "Servers\$ServerId"
$BackupDir     = Join-Path $Raiz 'backups'
$ConfigArq     = Join-Path $Raiz 'config\servidor.json'
$UltimoMapaArq = Join-Path $Raiz 'config\ultimo-mapa.txt'

# O servidor.json (com a senha) fica fora do git; na primeira vez ele nasce do exemplo.
if (-not (Test-Path $ConfigArq)) { Copy-Item (Join-Path $Raiz 'config\servidor.exemplo.json') $ConfigArq }

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function Ler-Config {
    Get-Content $ConfigArq -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Listar-Mapas($cfg) {
    $lista = @()
    $oficiais = Join-Path $ServidorDir 'Maps'
    if (Test-Path $oficiais) {
        Get-ChildItem $oficiais -Directory | Where-Object { $_.Name -ne 'Tutorial' } | Sort-Object Name | ForEach-Object {
            $lista += [pscustomobject]@{ Nome = $_.Name; Workshop = $false; Id = $null }
        }
    }
    foreach ($w in $cfg.MapasWorkshop) {
        $lista += [pscustomobject]@{ Nome = $w.Nome; Workshop = $true; Id = [uint64]$w.Id }
    }
    return $lista
}

function Processos-Servidor {
    $alvo = $ServidorExe.ToLower()
    @(Get-Process Unturned -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.ToLower() -eq $alvo } catch { $false }
    })
}


# Compila (quando preciso) e copia o module de autosave para servidor\Modules\UtAutosave.
function Instalar-ModuloAutosave {
    $src     = Join-Path $Raiz 'modulo-autosave'
    $destino = Join-Path $ServidorDir 'Modules\UtAutosave'
    $dll     = Join-Path $destino 'UtAutosave.dll'
    $cs      = @(Get-ChildItem $src -Filter *.cs | ForEach-Object FullName)
    $managed = Join-Path $ServidorDir 'Unturned_Data\Managed'
    New-Item -ItemType Directory -Force $destino | Out-Null
    Copy-Item (Join-Path $src 'Autosave.module') $destino -Force
    # Recompila se o fonte mudou ou o jogo atualizou (Assembly-CSharp mais novo que a dll)
    $ac = Join-Path $managed 'Assembly-CSharp.dll'
    $maisNovo = @($cs + $ac | ForEach-Object { (Get-Item $_).LastWriteTime } | Sort-Object)[-1]
    if ((Test-Path $dll) -and (Get-Item $dll).LastWriteTime -gt $maisNovo) { return }
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $refs = 'Assembly-CSharp.dll', 'UnityEngine.dll', 'UnityEngine.CoreModule.dll', 'netstandard.dll', 'com.rlabrecque.steamworks.net.dll', 'UnityEngine.PhysicsModule.dll' |
        ForEach-Object { Join-Path $managed $_ } | Where-Object { Test-Path $_ } | ForEach-Object { "/r:`"$_`"" }
    $saida = & $csc /noconfig /nologo /target:library /optimize /nostdlib /r:"$managed\mscorlib.dll" /r:"$managed\System.dll" /r:"$managed\System.Core.dll" @refs /out:"$dll" @cs 2>&1
    if ($LASTEXITCODE -ne 0) { $saida | Write-Host -ForegroundColor Red; throw 'Falha ao compilar o module de autosave.' }
    Write-Host 'Module de autosave compilado.' -ForegroundColor DarkGreen
}

function Escrever-Commands($cfg, $mapa) {
    $dir = Join-Path $SaveDir 'Server'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $l = @(
        "Name $($cfg.Nome)",
        "Map $($mapa.Nome)",
        'Mode Hard',
        "Port $($cfg.Porta)",
        "MaxPlayers $($cfg.MaxJogadores)",
        "Perspective $($cfg.Perspectiva)"
    )
    if (-not $cfg.PvP)          { $l += 'PvE' }
    if ($cfg.Cheats)            { $l += 'Cheats' }
    if ($cfg.Senha)             { $l += "Password $($cfg.Senha)" }
    if ($cfg.Owner_SteamID64)   { $l += "Owner $($cfg.Owner_SteamID64)" }
    if ($cfg.GSLT)              { $l += "GSLT $($cfg.GSLT)" }
    # Commands.dat e regerado a cada inicio a partir de config\servidor.json
    [IO.File]::WriteAllLines((Join-Path $dir 'Commands.dat'), [string[]]$l)
}

function Escrever-Workshop($cfg, $mapa) {
    New-Item -ItemType Directory -Force $SaveDir | Out-Null
    $arq = Join-Path $SaveDir 'WorkshopDownloadConfig.json'
    $ids = @()
    if ($mapa.Workshop) { $ids += $mapa.Id }
    foreach ($m in $cfg.ModsWorkshop) { $ids += [uint64]$m }
    $json = if (Test-Path $arq) { Get-Content $arq -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    $json | Add-Member -NotePropertyName File_IDs -NotePropertyValue ([uint64[]]$ids) -Force
    [IO.File]::WriteAllText($arq, ($json | ConvertTo-Json -Depth 5))
}

# Arquivos que entram no backup de um mapa: lista de @(FileInfo ou $null para pasta vazia, caminho dentro do zip).
function Itens-Backup([string]$mapaNome) {
    $itens = New-Object System.Collections.Generic.List[object]
    function Adicionar([string]$origem, [string]$noZip) {
        if (-not (Test-Path -LiteralPath $origem)) { return }
        $item = Get-Item -LiteralPath $origem -Force
        if (-not $item.PSIsContainer) { $itens.Add(@($item, $noZip)); return }
        $base = $item.FullName.TrimEnd('\').Length + 1
        $filhos = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -Force)
        foreach ($f in $filhos) {
            $rel = $noZip + '/' + $f.FullName.Substring($base).Replace('\', '/')
            if (-not $f.PSIsContainer) { $itens.Add(@($f, $rel)) }
            elseif (-not (Get-ChildItem -LiteralPath $f.FullName -Force | Select-Object -First 1)) { $itens.Add(@($null, "$rel/")) }
        }
    }
    Adicionar (Join-Path $SaveDir "Level\$mapaNome") "Level/$mapaNome"
    # Dados dos jogadores ficam em Players\<steamid_personagem>\<mapa>; entram so os deste mapa
    Get-ChildItem (Join-Path $SaveDir 'Players') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Adicionar (Join-Path $_.FullName $mapaNome) "Players/$($_.Name)/$mapaNome"
    }
    foreach ($p in 'Server', 'Config.txt', 'WorkshopDownloadConfig.json') { Adicionar (Join-Path $SaveDir $p) $p }
    return ,$itens   # "," para nao desmontar a lista quando so ha um item
}

# Backups automaticos de inicio/desligamento sao pulados se nada mudou desde o ultimo backup do mapa
# (ex.: reiniciar gera "ao-desligar" e logo depois "antes-de-iniciar" com o mesmo conteudo).
$MotivosPulaveis = 'antes-de-iniciar', 'ao-desligar'

function Fazer-Backup([string]$mapaNome, [string]$motivo, $cfg) {
    $level = Join-Path $SaveDir "Level\$mapaNome"
    if (-not (Test-Path $level)) { return }   # mapa ainda sem save
    try {
        $destDir = Join-Path $BackupDir $mapaNome
        New-Item -ItemType Directory -Force $destDir | Out-Null
        $itens = Itens-Backup $mapaNome
        $assinaturaArq = Join-Path $destDir '.assinatura'
        $assinatura = ($itens | ForEach-Object { if ($_[0]) { '{0}|{1}|{2}' -f $_[1], $_[0].Length, $_[0].LastWriteTimeUtc.Ticks } else { $_[1] } }) -join "`n"
        $md5 = [Security.Cryptography.MD5]::Create()
        $assinatura = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($assinatura))).Replace('-', '')
        $md5.Dispose()
        if ($motivo -in $MotivosPulaveis -and (Test-Path $assinaturaArq) -and ([IO.File]::ReadAllText($assinaturaArq).Trim() -eq $assinatura)) {
            Write-Host ("[{0}] Backup '{1}' dispensado: o save de {2} nao mudou desde o ultimo backup." -f (Get-Date -Format 'HH:mm:ss'), $motivo, $mapaNome) -ForegroundColor DarkGray
            return
        }
        $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $zip = Join-Path $destDir "$stamp`_$motivo.zip"
        # Zipa direto dos arquivos do save (sem copiar para uma pasta temporaria antes)
        $fs = [IO.File]::Open($zip, 'CreateNew')
        try {
            $arc = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($it in $itens) {
                    $entrada = $arc.CreateEntry($it[1], [IO.Compression.CompressionLevel]::Optimal)
                    if (-not $it[0]) { continue }
                    $entrada.LastWriteTime = $it[0].LastWriteTime
                    # ReadWrite: o servidor pode estar com o arquivo aberto
                    $src = [IO.File]::Open($it[0].FullName, 'Open', 'Read', 'ReadWrite')
                    $dst = $entrada.Open()
                    try { $src.CopyTo($dst) } finally { $dst.Dispose(); $src.Dispose() }
                }
            } finally { $arc.Dispose() }
        } catch { $fs.Dispose(); Remove-Item $zip -Force -ErrorAction SilentlyContinue; throw } finally { $fs.Dispose() }
        [IO.File]::WriteAllText($assinaturaArq, $assinatura)
        $manter = if ($cfg -and $cfg.BackupsMantidosPorMapa) { [int]$cfg.BackupsMantidosPorMapa } else { 30 }
        # Rotaciona por tipo, para os backups "antes-de-iniciar" nao serem empurrados pelos periodicos
        Get-ChildItem $destDir -Filter "*_$motivo.zip" | Sort-Object Name -Descending | Select-Object -Skip $manter | Remove-Item -Force
        Write-Host ("[{0}] Backup salvo: backups\{1}\{2}" -f (Get-Date -Format 'HH:mm:ss'), $mapaNome, (Split-Path $zip -Leaf)) -ForegroundColor DarkGreen
    } catch {
        Write-Host "Falha ao fazer backup: $_" -ForegroundColor Red
    }
}

# Extrai o zip sobrescrevendo o que existir (mais rapido que Expand-Archive; aceita "\" e "/" nos caminhos).
function Extrair-Zip([string]$zip, [string]$destino) {
    $raiz = [IO.Path]::GetFullPath($destino).TrimEnd('\') + '\'
    $arc = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $arc.Entries) {
            $alvo = [IO.Path]::GetFullPath($raiz + ($e.FullName -replace '/', '\'))
            if (-not $alvo.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { continue }   # caminho fora da pasta
            if ($e.FullName -match '[\/]$') { [void][IO.Directory]::CreateDirectory($alvo); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($alvo))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $alvo, $true)
        }
    } finally { $arc.Dispose() }
}

# Volta o mapa para o zip escolhido (servidor desligado). O estado atual vira um backup antes.
function Restaurar-Backup([string]$mapaNome, [string]$zip, $cfg) {
    Fazer-Backup $mapaNome 'antes-de-restaurar' $cfg
    $level = Join-Path $SaveDir "Level\$mapaNome"
    if (Test-Path $level) { Remove-Item $level -Recurse -Force }
    # Remove o progresso atual dos jogadores neste mapa (outros mapas nao sao tocados)
    Get-ChildItem (Join-Path $SaveDir 'Players') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $pm = Join-Path $_.FullName $mapaNome
        if (Test-Path $pm) { Remove-Item $pm -Recurse -Force }
    }
    New-Item -ItemType Directory -Force $SaveDir | Out-Null
    Extrair-Zip $zip $SaveDir
}
