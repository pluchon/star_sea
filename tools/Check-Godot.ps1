param(
    [Parameter(Mandatory)][string[]]$GodotArgs,
    [Parameter(Mandatory)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$enginePath = 'D:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
if (@(Get-Process -Name 'Godot*', 'StarSea*' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw '已有 Godot 进程，请先关闭，再执行新的导入、运行或验证。'
}
$resolvedLogPath = [IO.Path]::GetFullPath($LogPath, $repoDirectory)
New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedLogPath) -Force | Out-Null

Push-Location -LiteralPath $repoDirectory
try {
    & $enginePath --path (Join-Path $repoDirectory 'game') @GodotArgs 2>&1 | Tee-Object -FilePath $resolvedLogPath
    $engineExitCode = $LASTEXITCODE
    $output = @(Get-Content -LiteralPath $resolvedLogPath)

    # 引擎的部分渲染错误仍返回零退出码，必须同时检查原始输出。
    $engineErrors = @($output | Select-String -Pattern '^\s*(SCRIPT ERROR:|ERROR:|Shader compilation failed)')
    if ($engineExitCode -ne 0 -or $engineErrors.Count -gt 0) {
        throw "Godot 验证失败：退出码 $engineExitCode，错误记录 $($engineErrors.Count) 条。日志：$resolvedLogPath"
    }
}
finally {
    Pop-Location
}
