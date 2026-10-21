param(
    [switch]$SkipBuild,
    [ValidateSet('dawn', 'all')][string]$Scope = 'dawn'
)

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repoDirectory 'test-output/acceptance'
$logDirectory = Join-Path $outputDirectory 'logs'
$releaseDirectory = Join-Path $outputDirectory 'release'
$executable = Join-Path $repoDirectory 'build/StarSea/StarSea.console.exe'
New-Item -ItemType Directory -Path $logDirectory, $releaseDirectory -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
[pscustomobject]@{ passed = $false; status = 'running'; checks = @() } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8

function Invoke-SourceCheck {
    param([string]$Name, [string[]]$EngineArguments, [string]$Report)
	$started = [DateTime]::UtcNow
    if ($EngineArguments -contains '--') { $EngineArguments += '--scope=' + $Scope }
    & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs $EngineArguments -LogPath (Join-Path $logDirectory "$Name.log") | Out-Null
    $sourcePath = Join-Path $repoDirectory $Report
	if ((Get-Item -LiteralPath $sourcePath).LastWriteTimeUtc -lt $started) { throw "$Name 没有生成本次报告。" }
    $data = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    if (-not $data.passed) { throw "$Name 检查未通过。" }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $outputDirectory "$Name.json") -Force
    $results.Add([pscustomobject]@{ name = $Name; passed = $true })
    Write-Output "$Name 通过"
}

function Backup-ApplicationCache {
	# 只移动本应用缓存；限定来源和目标，保留可恢复副本，不修改驱动缓存。
	$appDirectory = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Godot/app_userdata/StarSea'))
	$backupDirectory = [IO.Path]::GetFullPath((Join-Path $outputDirectory ('cache-backups/' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))))
	if (-not $backupDirectory.StartsWith($outputDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '缓存备份目标越界。' }
	New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
	foreach ($name in @('shader_cache', 'vulkan')) {
		$source = [IO.Path]::GetFullPath((Join-Path $appDirectory $name))
		$destination = [IO.Path]::GetFullPath((Join-Path $backupDirectory $name))
		if (-not $source.StartsWith($appDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or -not $destination.StartsWith($backupDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '缓存目录越界。' }
		if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination $destination }
	}
	Write-Output "应用缓存已备份至 $backupDirectory"
}

function Invoke-Release {
    param([string]$Name, [string[]]$GameArguments, [switch]$Startup)
    if (@(Get-Process -Name 'Godot*', 'StarSea*' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw '已有 Godot 或 StarSea 进程，无法执行独立验收。'
    }
    $GameArguments += "--scope=$Scope"
    $logPath = Join-Path $logDirectory "$Name.log"
    if ($Startup) {
        & $executable --quit-after 180 2>&1 | Set-Content -LiteralPath $logPath -Encoding utf8
    }
    else {
        & $executable -- @GameArguments 2>&1 | Set-Content -LiteralPath $logPath -Encoding utf8
    }
    $code = $LASTEXITCODE
    $errors = @(Select-String -LiteralPath $logPath -Pattern '^\s*(SCRIPT ERROR:|ERROR:|WARNING:|Shader compilation failed)')
    if ($code -ne 0 -or $errors.Count -gt 0) { throw "$Name 失败：退出码 $code，错误或警告 $($errors.Count) 条。见 $logPath" }
    $results.Add([pscustomobject]@{ name = $Name; passed = $true })
    Write-Output "$Name 通过"
}

try {
    & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless', '--import') -LogPath (Join-Path $logDirectory 'acceptance-import.log') | Out-Null
    python (Join-Path $PSScriptRoot 'Check-Audio.py')
    if ($LASTEXITCODE -ne 0) { throw '音频素材检查失败。' }
    Invoke-SourceCheck 'hydrology' @('--headless', '--script', 'res://scripts/verify/hydrology_checks.gd', '--', '--check=hydrology') 'test-output/wanderer/hydrology_checks.json'
    Invoke-SourceCheck 'landforms' @('--headless', '--script', 'res://scripts/verify/landform_checks.gd', '--', '--check=landforms') 'test-output/wanderer/landform_checks.json'
    Invoke-SourceCheck 'ruin-kit' @('--headless', '--script', 'res://scripts/verify/ruin_kit_checks.gd', '--', '--check=ruins') 'test-output/wanderer/ruin_kit_checks.json'
    Invoke-SourceCheck 'ship' @('--script', 'res://scripts/verify/ship_checks.gd', '--', '--check=ship') 'test-output/wanderer/ship_checks.json'
    Invoke-SourceCheck 'traversal' @('--headless', '--script', 'res://scripts/verify/traversal_checks.gd', '--', '--check=traversal') 'test-output/wanderer/traversal_checks.json'
    Invoke-SourceCheck 'climb-routes' @('--headless', '--script', 'res://scripts/verify/climb_route_checks.gd', '--', '--check=climb-routes') 'test-output/wanderer/climb_route_checks.json'
    Invoke-SourceCheck 'glide-routes' @('--headless', '--script', 'res://scripts/verify/glide_route_checks.gd', '--', '--check=glide-routes') 'test-output/wanderer/glide_route_checks.json'
    Invoke-SourceCheck 'civilization' @('--headless', '--script', 'res://scripts/verify/civilization_checks.gd', '--', '--check=civilization') 'test-output/wanderer/civilization_checks.json'
    python (Join-Path $PSScriptRoot 'Check-Audio.py') --ship-recordings (Join-Path $repoDirectory 'test-output/wanderer/audio')
    if ($LASTEXITCODE -ne 0) { throw '飞船实际混音检查失败。' }
    Invoke-SourceCheck 'ecology' @('--headless', '--script', 'res://scripts/verify/ecology_checks.gd') 'test-output/p4/ecology_checks.json'
    Invoke-SourceCheck 'ecology-runtime' @('--headless', '--script', 'res://scripts/verify/ecology_runtime_checks.gd', '--', '--check=ecology_runtime') 'test-output/p4/ecology_runtime_checks.json'
    Invoke-SourceCheck 'camera' @('--script', 'res://scripts/verify/camera_checks.gd', '--', '--check=camera') 'test-output/p3/camera_checks.json'
    Invoke-SourceCheck 'surfaces' @('--headless', '--script', 'res://scripts/verify/surface_checks.gd', '--', '--check=surfaces') 'test-output/p2/surface_checks.json'
    Invoke-SourceCheck 'completion' @('--script', 'res://scripts/verify/completion_checks.gd', '--', '--check=completion') 'test-output/p2/completion_checks.json'
    if (-not $SkipBuild) {
        & (Join-Path $PSScriptRoot 'Build-Game.ps1') | Out-Null
    }
    Invoke-Release 'release-assets' @('--acceptance=assets', "--out=$releaseDirectory")
    Invoke-Release 'release-core' @('--acceptance=core', "--out=$releaseDirectory")
    Invoke-Release 'release-earth' @('--acceptance=earth', "--out=$releaseDirectory")
    python (Join-Path $PSScriptRoot 'Check-Audio.py') --music-recording (Join-Path $releaseDirectory 'dawn_music_mix.wav')
    if ($LASTEXITCODE -ne 0) { throw '音乐实际播放录制检查失败。' }
    Invoke-Release 'release-world' @('--acceptance=world', "--out=$releaseDirectory")
    Invoke-Release 'release-audio' @('--acceptance=audio', "--out=$releaseDirectory")
    python (Join-Path $PSScriptRoot 'Check-Audio.py') --recordings $releaseDirectory --scope $Scope
    if ($LASTEXITCODE -ne 0) { throw '实际混音检查失败。' }
    $shots = @('s1_space','s2_high','s3_ground_day','s4_ground_sunset','s5_ground_night','s6_shore','s7_ember','s8_frost','s9_woodland','s10_highland','s11_orbit','s12_ruin','s13_tree_detail','s14_third_person','s15_relief_map','s16_terrace','s17_valley','s18_meadow','s19_broadleaf','s20_wetland','s21_drygrass','s22_tundra','s23_ship_parked','s24_ship_low','s25_waterfall','s28_canyon','s29_ruin_kit')
    if ($Scope -eq 'dawn') { $shots = @($shots | Where-Object { $_ -notin @('s7_ember', 's8_frost') }) }
    $shots += @('s49_range_from_spawn','s50_horn_peak','s51_canyon_rim','s52_canyon_floor','s53_mountain_pass')
    $shots += @('s54_glide_canyon','s55_glide_range','s56_climb_route')
    $shots += @('s30_town_plaza','s31_town_overview','s32_terraces','s33_cemetery','s34_old_road')
    $shots += @('s35_beacon_top','s36_beacon_chain_night')
    $shotDirectory = Join-Path $releaseDirectory 'shots'
    foreach ($shot in $shots) {
        Invoke-Release "release-$shot" @("--shot=$shot", "--out=$shotDirectory")
        $report = Get-Content -LiteralPath (Join-Path $shotDirectory "$shot.json") -Raw | ConvertFrom-Json
        if (-not $report.performance_passed) { throw "$shot 未达到帧时间预算。" }
    }
    $descentPath = Join-Path $releaseDirectory 'descent.json'
    Backup-ApplicationCache
    Invoke-Release 'release-descent' @("--descent=$descentPath")
    $descent = Get-Content -LiteralPath $descentPath -Raw | ConvertFrom-Json
    if (-not $descent.performance_passed -or -not $descent.landing_passed -or -not $descent.upload_budget_passed) { throw '降落检查未通过。' }
    $walkPath = Join-Path $releaseDirectory 'walk.json'
    Invoke-Release 'release-walk' @("--walk=$walkPath")
    $walk = Get-Content -LiteralPath $walkPath -Raw | ConvertFrom-Json
    if (-not $walk.passed) { throw '连续行走检查未通过。' }
    Invoke-Release 'release-startup' @() -Startup
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $repoDirectory 'build/StarSea-Windows-x64.zip'))
    try {
        $entry = @($zip.Entries | Where-Object { $_.Name -eq 'StarSea.exe' })[0]
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $archiveHash = [Convert]::ToHexString($sha.ComputeHash($stream)) }
        finally {
            $stream.Dispose()
            $sha.Dispose()
        }
    }
    finally { $zip.Dispose() }
    $binaryHash = (Get-FileHash -LiteralPath (Join-Path $repoDirectory 'build/StarSea/StarSea.exe') -Algorithm SHA256).Hash
    $manifest = Get-Content -LiteralPath (Join-Path $repoDirectory 'build/StarSea/sha256.json') -Raw | ConvertFrom-Json
    if ($binaryHash -ne $manifest.Hash -or $binaryHash -ne $archiveHash) { throw '可执行文件、清单和压缩包内容不一致。' }
    [pscustomobject]@{ passed = $true; status = 'passed'; scope = $Scope; completed_at = [DateTimeOffset]::Now.ToString('o'); binary_sha256 = $binaryHash; checks = $results } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8
    Write-Output '全部自动验收通过。'
}
catch {
    [pscustomobject]@{ passed = $false; status = 'failed'; scope = $Scope; error = $_.Exception.Message; checks = $results } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8
    throw
}
