param(
    [string[]]$GameArgs = @()
)

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$enginePath = 'D:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $enginePath)) {
    throw "找不到指定版本的 Godot：$enginePath"
}
$logPath = Join-Path $repoDirectory 'test-output\p1\logs\run-game.log'
& (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs (@('--') + $GameArgs) -LogPath $logPath
