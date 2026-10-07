#requires -Version 5.1
<#
.SYNOPSIS
原神自定义帧率启动脚本，Windows x64，使用 z3lx/genshin-unlock 后端。
.EXAMPLE
.\fps-unlock.ps1 -Fps 144 -GamePath 'D:\Games\Genshin Impact game\YuanShen.exe'
.EXAMPLE
.\fps-unlock.ps1 -Mode Configure -Fps 165
.EXAMPLE
.\fps-unlock.ps1 -Mode Install -BackendArchive 'C:\Downloads\mod.zip'
#>
[CmdletBinding()]
param(
    [ValidateSet('Launch', 'Configure', 'Install', 'Update', 'Status')]
    [string]$Mode = 'Launch',
    [ValidateRange(10, 1000)]
    [int]$Fps = 120,
    [string]$GamePath = '',
    [switch]$BackgroundThrottle,
    [string]$BackendArchive = '',
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FpsUnlock.Core.ps1')

try {
    if (![Environment]::Is64BitOperatingSystem) { throw '只支持 64 位 Windows。' }
    if ($BackendArchive -and $Mode -ne 'Install') { throw '-BackendArchive 仅用于 -Mode Install。' }
    if ($Mode -in @('Install', 'Update')) {
        $settings = Read-FpsSettings -Root $PSScriptRoot
        $backend = Install-FpsBackend -Root $PSScriptRoot -Latest:($Mode -eq 'Update') -ArchivePath $BackendArchive
        Write-FpsBackendConfig -Backend $backend -Settings $settings
        return
    }
    $settings = Read-FpsSettings -Root $PSScriptRoot
    $backend = Get-FpsBackend -Root $PSScriptRoot
    if ($Mode -eq 'Status') {
        Write-Host ("帧率上限：{0} FPS`n游戏路径：{1}`n后台降至 10 FPS：{2}" -f $settings.fps, $settings.gamePath, $settings.backgroundThrottle)
        if ($backend) { Write-Host "后端版本：$($backend.version)（文件校验通过）" }
        else { Write-Host '后端尚未安装。' }
        return
    }
    if (@(Get-Process -Name YuanShen, GenshinImpact -ErrorAction SilentlyContinue).Count) {
        throw '原神正在运行。请先正常退出游戏，再修改设置或通过本脚本启动。'
    }
    if ($PSBoundParameters.ContainsKey('Fps')) { $settings.fps = $Fps }
    elseif ($Mode -eq 'Launch' -and !$NonInteractive) {
        $inputFps = Read-Host "输入帧率上限 10-1000，直接回车使用 $($settings.fps) FPS"
        if ($inputFps.Trim()) {
            $parsed = 0
            if (![int]::TryParse($inputFps, [ref]$parsed) -or $parsed -lt 10 -or $parsed -gt 1000) {
                throw '帧率上限必须为 10 到 1000 的整数。'
            }
            $settings.fps = $parsed
        }
    }
    if ($PSBoundParameters.ContainsKey('BackgroundThrottle')) { $settings.backgroundThrottle = [bool]$BackgroundThrottle }
    if ($PSBoundParameters.ContainsKey('GamePath')) { $settings.gamePath = Resolve-FpsGamePath -Path $GamePath }
    if ($Mode -eq 'Configure') {
        Write-FpsJson -Path (Join-Path $PSScriptRoot 'settings.json') -Value $settings
        if ($backend) { Write-FpsBackendConfig -Backend $backend -Settings $settings }
        Write-Host "已保存 $($settings.fps) FPS。设置将在下次启动游戏时应用。"
        return
    }
    if (!$settings.gamePath) { $settings.gamePath = Find-FpsGamePath }
    if (!$settings.gamePath -or !(Test-Path -LiteralPath $settings.gamePath -PathType Leaf)) {
        if ($NonInteractive) { throw '未找到游戏，请通过 -GamePath 指定 YuanShen.exe 或 GenshinImpact.exe。' }
        $settings.gamePath = Read-Host '输入 YuanShen.exe 或 GenshinImpact.exe 的完整路径（可带引号）'
    }
    $settings.gamePath = Resolve-FpsGamePath -Path $settings.gamePath
    if (!$backend) { $backend = Install-FpsBackend -Root $PSScriptRoot }
    Assert-FpsGameVersion -GamePath $settings.gamePath -BackendVersion $backend.version
    Write-FpsJson -Path (Join-Path $PSScriptRoot 'settings.json') -Value $settings
    Write-FpsBackendConfig -Backend $backend -Settings $settings
    Write-Host "准备以 $($settings.fps) FPS 上限启动游戏。请允许 Windows 管理员提示。"
    # Start-Process -Wait waits for descendants (including the game). Wait only for the loader.
    $process = Start-Process -FilePath (Join-Path $backend.directory 'loader.exe') -WorkingDirectory $backend.directory -Verb RunAs -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "后端退出码：$($process.ExitCode)。请查看后端提示及 README 的故障排查。" }
    # Some upstream compatibility/error dialogs exit with code 0. Do not claim FPS success.
    Start-Sleep -Seconds 1
    if (!@(Get-Process -Name YuanShen, GenshinImpact -ErrorAction SilentlyContinue).Count) {
        throw '后端已退出，但未检测到游戏进程。请查看刚才的后端提示。'
    }
    Write-Host '已检测到游戏进程。进入游戏后用帧率计确认实际 FPS，关闭游戏内垂直同步及其他帧率限制。'
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
