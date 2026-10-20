param([ValidateSet('ship', 'ruins', 'all')][string]$Target = 'all')

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$blenderCommand = Get-Command blender -ErrorAction SilentlyContinue
$blenderPath = if ($blenderCommand) { $blenderCommand.Source } else { 'D:\Godot\tools\blender-4.5.9-windows-x64\blender.exe' }
if (-not (Test-Path -LiteralPath $blenderPath)) { throw '找不到 Blender 4.x，请添加到 PATH。' }
Push-Location -LiteralPath $repoDirectory
try {
    if ($Target -in @('ship','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_ship.py -- --out game/models/ship
        if ($LASTEXITCODE -ne 0) { throw '飞船模型生成失败。' }
    }
    if ($Target -in @('ruins','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_ruin_kit.py -- --out game/models/ruins
        if ($LASTEXITCODE -ne 0) { throw '遗迹构件生成失败。' }
    }
}
finally { Pop-Location }
