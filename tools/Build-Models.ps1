param([ValidateSet('ship', 'ruins', 'canyon', 'explorer', 'fields', 'town_bridge', 'beacon', 'cave', 'ladder', 'all')][string]$Target = 'all', [string]$Only = '')

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$blenderCommand = Get-Command blender -ErrorAction SilentlyContinue
$blenderPath = if ($blenderCommand) { $blenderCommand.Source } else { 'D:\Godot\tools\blender-4.5.9-windows-x64\blender.exe' }
if (-not (Test-Path -LiteralPath $blenderPath)) { throw '找不到 Blender 4.x，请添加到 PATH。' }
Push-Location -LiteralPath $repoDirectory
try {
    if ($Target -in @('ladder','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_sky_ladder.py
        if ($LASTEXITCODE -ne 0) { throw '天梯模型生成失败。' }
    }
    if ($Target -in @('ship','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_ship.py -- --out game/models/ship
        if ($LASTEXITCODE -ne 0) { throw '飞船模型生成失败。' }
    }
    if ($Target -in @('ruins','all')) {
        $modelArguments = @('--out', 'game/models/ruins')
        if ($Only) { $modelArguments += @('--only', $Only) }
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_ruin_kit.py -- @modelArguments
        if ($LASTEXITCODE -ne 0) { throw '遗迹构件生成失败。' }
    }
    if ($Target -in @('canyon','all')) {
        $modelArguments = @('--out', 'game/models/landforms')
        if ($Only) { $modelArguments += @('--only', $Only) }
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_canyon.py -- @modelArguments
        if ($LASTEXITCODE -ne 0) { throw '峡谷岩石模型生成失败。' }
    }
    if ($Target -in @('ruins','town_bridge','all') -and (-not $Only -or $Only.Contains('bridge_span_gap'))) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_town_bridge.py
        if ($LASTEXITCODE -ne 0) { throw '古城断口桥跨生成失败。' }
    }
    if ($Target -in @('explorer','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_explorer.py -- --out game/models/explorer
        if ($LASTEXITCODE -ne 0) { throw '探索者模型生成失败。' }
    }
    if ($Target -in @('fields','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_fields.py -- --out game/models/vegetation
        if ($LASTEXITCODE -ne 0) { throw '稻秆模型生成失败。' }
    }
    if ($Target -in @('beacon','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_beacon.py
        if ($LASTEXITCODE -ne 0) { throw '烽火塔远景模型生成失败。' }
    }
    if ($Target -in @('cave','all')) {
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_cave_props.py
        if ($LASTEXITCODE -ne 0) { throw '洞穴提灯模型生成失败。' }
        & $blenderPath --background --python-exit-code 1 --python art/blender/build_murals.py
        if ($LASTEXITCODE -ne 0) { throw '神殿壁画模型生成失败。' }
    }
}
finally { Pop-Location }
