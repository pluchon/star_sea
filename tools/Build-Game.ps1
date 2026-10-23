param()

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repoDirectory 'build/StarSea'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
& (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless', '--export-release', 'Windows Desktop', (Join-Path $outputDirectory 'StarSea.exe')) -LogPath 'test-output/p2/logs/export.log'
$licensesDirectory = Join-Path $outputDirectory 'licenses'
New-Item -ItemType Directory -Path $licensesDirectory -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $repoDirectory 'game/licenses') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $licensesDirectory -Force
}
Copy-Item -LiteralPath (Join-Path $repoDirectory 'game/audio/music/来源.md') -Destination (Join-Path $licensesDirectory '音乐来源.md') -Force
@'
星海尽头

双击 StarSea.exe 开始漂流。首次进入地表时会等待附近碰撞生成。
WASD 移动，鼠标环顾，Shift 加速，空格上升或跳跃，Ctrl 下降。
F 降落／登船；步行时远离飞船，按住 F 1.2 秒召唤。
驾驶时离地不超过 40 米、速度低于 30 米／秒，可以在平整陆地降落。
V 切换第一、第三人称；M 展开晨的全球地形图，滚轮缩放、拖动平移。
T 加速时间，H 帮助，F3 性能，F12 截图，Esc 暂停菜单。

菜单包含画面、声音与操作设置；退出时自动保存旅程。
存档、设置与截图位于 %APPDATA%\Godot\app_userdata\StarSea\。
本版本需要 Windows 64 位与支持 Vulkan 的显卡。
包含用户提供的个人游玩音乐，不商用、不公开分发；来源与用途见 licenses。
'@ | Set-Content -LiteralPath (Join-Path $outputDirectory '说明.txt') -Encoding utf8
Get-FileHash -LiteralPath (Join-Path $outputDirectory 'StarSea.exe') -Algorithm SHA256 |
    Select-Object Algorithm, Hash | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $outputDirectory 'sha256.json') -Encoding utf8
Compress-Archive -LiteralPath $outputDirectory -DestinationPath (Join-Path $repoDirectory 'build/StarSea-Windows-x64.zip') -CompressionLevel Optimal -Force
