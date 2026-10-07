# Windows PowerShell 5.1 / PowerShell 7. No code runs when this file is imported.
Set-StrictMode -Version Latest

$script:BackendRelease = [ordered]@{
    version = '7.1.0'
    url = 'https://github.com/z3lx/genshin-unlock/releases/download/7.1.0/mod.zip'
    sha256 = '7a46202bb2e7065fc226587499850b14bd901e8d3adb2b1e89afbb15915b3ddc'
}

function Write-FpsJson {
    param([string]$Path, $Value)
    # Glaze (the native backend's JSON reader) expects UTF-8 without a BOM.
    $temp = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Read-FpsSettings {
    param([string]$Root)
    $path = Join-Path $Root 'settings.json'
    if (!(Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ schemaVersion = 1; fps = 120; gamePath = ''; backgroundThrottle = $false }
    }
    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.schemaVersion -ne 1 -or
            $settings.fps -isnot [ValueType] -or $settings.fps -is [bool] -or
            $settings.fps -lt 10 -or $settings.fps -gt 1000 -or
            [Math]::Truncate([double]$settings.fps) -ne $settings.fps -or
            $settings.gamePath -isnot [string] -or $settings.backgroundThrottle -isnot [bool]) {
            throw 'Invalid settings schema'
        }
        return $settings
    } catch {
        throw "settings.json 无法读取或配置无效，请检查该文件。详细信息：$($_.Exception.Message)"
    }
}

function Resolve-FpsGamePath {
    param([string]$Path)
    $candidate = $Path.Trim().Trim('"')
    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $matches = @(Get-ChildItem -LiteralPath $candidate -File | Where-Object { $_.Name -in @('YuanShen.exe', 'GenshinImpact.exe') })
        if ($matches.Count -ne 1) { throw '请指定 YuanShen.exe 或 GenshinImpact.exe 的完整路径。' }
        $candidate = $matches[0].FullName
    }
    if (!(Test-Path -LiteralPath $candidate -PathType Leaf) -or
        [IO.Path]::GetFileName($candidate) -notin @('YuanShen.exe', 'GenshinImpact.exe')) {
        throw "不是有效的原神客户端路径：$candidate（请选择 YuanShen.exe 或 GenshinImpact.exe，不是启动器）"
    }
    return (Get-Item -LiteralPath $candidate).FullName
}

function Find-FpsGamePath {
    $locations = @(
        'HKCU:\SOFTWARE\miHoYo\HYP\1_1\hk4e_cn',
        'HKCU:\SOFTWARE\Cognosphere\HYP\1_0\hk4e_global'
    )
    $candidates = @()
    foreach ($location in $locations) {
        if (!(Test-Path -LiteralPath $location)) { continue }
        $entry = Get-ItemProperty -LiteralPath $location
        if (!$entry.PSObject.Properties['GameInstallPath']) { continue }
        foreach ($name in @('YuanShen.exe', 'GenshinImpact.exe')) {
            $path = Join-Path ([string]$entry.GameInstallPath) $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { $candidates += $path }
        }
    }
    $candidates = @($candidates | Select-Object -Unique)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    return ''
}

function Get-FpsBackend {
    param([string]$Root)
    $path = Join-Path $Root 'backend.json'
    if (!(Test-Path -LiteralPath $path)) { return $null }
    $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.version -notmatch '^\d+\.\d+\.\d+$') { throw 'backend.json 版本号无效。' }
    $directory = Join-Path (Join-Path $Root 'backend') $manifest.version
    foreach ($name in @('loader.exe', 'plugin.dll')) {
        $file = Join-Path $directory $name
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "后端文件丢失：$name。请使用 -Mode Install 重新安装。" }
        $expected = $manifest.files.PSObject.Properties[$name]
        if (!$expected -or $expected.Value -notmatch '^[a-fA-F0-9]{64}$' -or
            (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $expected.Value) {
            throw "后端文件校验失败：$name。请使用 -Mode Install 重新安装。"
        }
    }
    return [pscustomobject]@{ directory = $directory; version = $manifest.version }
}

function Install-FpsBackend {
    param([string]$Root, [switch]$Latest, [string]$ArchivePath = '')
    $release = $script:BackendRelease
    if ($Latest) {
        if ($ArchivePath) { throw '-Mode Update 不能同时指定 -BackendArchive。' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $info = Invoke-RestMethod -Uri 'https://api.github.com/repos/z3lx/genshin-unlock/releases/latest' -Headers @{ 'User-Agent' = 'genshin-fps-unlimiter' } -TimeoutSec 30
        $assets = @($info.assets | Where-Object { $_.name -eq 'mod.zip' })
        if ($info.tag_name -notmatch '^\d+\.\d+\.\d+$' -or $assets.Count -ne 1 -or
            $assets[0].digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
            throw '上游发布信息缺少有效版本号或 SHA256，停止安装。'
        }
        $release = [ordered]@{
            version = [string]$info.tag_name
            url = "https://github.com/z3lx/genshin-unlock/releases/download/$($info.tag_name)/mod.zip"
            sha256 = $assets[0].digest.Substring(7)
        }
    }
    $running = @(Get-Process -Name YuanShen, GenshinImpact -ErrorAction SilentlyContinue)
    if ($running.Count) { throw '请先正常退出游戏再安装或更新后端。' }
    $cache = Join-Path $Root 'cache'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $zipPath = Join-Path $cache ("mod-$($release.version).zip")
    if ($ArchivePath) {
        $source = (Get-Item -LiteralPath $ArchivePath -ErrorAction Stop).FullName
        if ($source -ne $zipPath) { Copy-Item -LiteralPath $source -Destination $zipPath -Force }
    } elseif (!(Test-Path -LiteralPath $zipPath) -or
        (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne $release.sha256) {
        Write-Host "正在下载开源解帧后端 $($release.version)..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            Invoke-WebRequest -Uri $release.url -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
        } catch {
            throw "GitHub 下载失败。可从 README 中的发布链接手动下载 mod.zip，然后运行 -Mode Install -BackendArchive <完整路径>。详细信息：$($_.Exception.Message)"
        }
    }
    if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne $release.sha256) {
        throw 'mod.zip 的 SHA256 与上游发布值不符，停止安装。'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $backendRoot = [IO.Path]::GetFullPath((Join-Path $Root 'backend'))
    New-Item -ItemType Directory -Path $backendRoot -Force | Out-Null
    $destination = Join-Path $backendRoot $release.version
    $operationId = [Guid]::NewGuid().ToString('N')
    $staging = Join-Path $backendRoot ('.install-' + $operationId)
    $backup = Join-Path $backendRoot ('.previous-' + $operationId)
    $failed = Join-Path $backendRoot ('.failed-' + $operationId)
    # Explicitly check all computed directory-move targets are inside our backend directory.
    foreach ($path in @($destination, $staging, $backup, $failed)) {
        if (![IO.Path]::GetFullPath($path).StartsWith($backendRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw '后端安装目标超出脚本目录。'
        }
    }
    New-Item -ItemType Directory -Path $staging | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        # Extract only these two basenames; never trust archive paths.
        foreach ($name in @('loader.exe', 'plugin.dll')) {
            $entries = @($zip.Entries | Where-Object { $_.Name -ceq $name })
            if ($entries.Count -ne 1 -or $entries[0].Length -le 0 -or $entries[0].Length -gt 20MB) {
                throw "压缩包中缺少唯一有效的 $name。"
            }
        }
        $hashes = [ordered]@{}
        foreach ($name in @('loader.exe', 'plugin.dll')) {
            $entry = @($zip.Entries | Where-Object { $_.Name -ceq $name })[0]
            $target = Join-Path $staging $name
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            $hashes[$name] = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } finally { $zip.Dispose() }
    $previousMoved = $false
    $newMoved = $false
    try {
        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $backup
            $previousMoved = $true
        }
        Move-Item -LiteralPath $staging -Destination $destination
        $newMoved = $true
        Write-FpsJson -Path (Join-Path $Root 'backend.json') -Value ([ordered]@{
            version = $release.version; source = $release.url; archiveSha256 = $release.sha256; files = $hashes
        })
    } catch {
        # Keep the failed install for diagnosis and restore the previous directory without deleting it.
        if ($newMoved) { Move-Item -LiteralPath $destination -Destination $failed }
        if ($previousMoved) { Move-Item -LiteralPath $backup -Destination $destination }
        throw
    }
    Write-Host "后端 $($release.version) 已安装并通过 SHA256 校验。"
    return Get-FpsBackend -Root $Root
}

function Write-FpsBackendConfig {
    param($Backend, $Settings)
    Write-FpsJson -Path (Join-Path $Backend.directory 'loader_config.json') -Value ([ordered]@{
        gamePath = $Settings.gamePath
        overrideArgs = $false
        monitorIndex = 1
        displayMode = 'Fullscreen'
        screenWidth = 1920
        screenHeight = 1080
        mobilePlatform = $false
        additionalArgs = ''
        dllPaths = @('plugin.dll')
        suspendLoad = $false
    })
    Write-FpsJson -Path (Join-Path $Backend.directory 'plugin_config.json') -Value ([ordered]@{
        unlockFps = $true
        targetFps = [int]$Settings.fps
        autoThrottle = [bool]$Settings.backgroundThrottle
        unlockFov = $false
        targetFov = 90
        fovPresets = @(90)
        fovSmoothing = 0.125
        unlockFovKey = 'F24'
        nextFovPresetKey = 'F23'
        prevFovPresetKey = 'F22'
    })
}

function Assert-FpsGameVersion {
    param([string]$GamePath, [string]$BackendVersion)
    $ini = Join-Path ([IO.Path]::GetDirectoryName($GamePath)) 'config.ini'
    if (!(Test-Path -LiteralPath $ini)) { throw '游戏目录中缺少 config.ini，无法确认后端兼容性。请检查客户端路径。' }
    $text = Get-Content -LiteralPath $ini -Raw -Encoding UTF8
    $match = [regex]::Match($text, '(?m)^\s*game_version\s*=\s*(\d+)\.(\d+)\.\d+\s*$')
    if (!$match.Success) { throw '无法读取 config.ini 的 game_version，请先通过官方启动器完成游戏更新。' }
    $gameVersion = $match.Groups[1].Value + '.' + $match.Groups[2].Value
    $backendParts = $BackendVersion.Split('.')
    $supported = $backendParts[0] + '.' + $backendParts[1]
    if ($gameVersion -ne $supported) {
        throw "当前游戏版本 $gameVersion 与后端 $BackendVersion 不兼容。请运行 -Mode Update；若上游尚未适配，需要等待更新。"
    }
}
