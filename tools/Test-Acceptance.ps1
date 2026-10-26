param(
    [switch]$SkipBuild,
    [ValidateSet('dawn', 'all')][string]$Scope = 'dawn',
    [string[]]$OnlyChecks = @(),
    [string]$ReportDirectory = 'test-output/acceptance'
)

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$outputDirectory = [IO.Path]::GetFullPath($ReportDirectory, $repoDirectory)
$logDirectory = Join-Path $outputDirectory 'logs'
$releaseDirectory = Join-Path $outputDirectory 'release'
$executable = Join-Path $repoDirectory 'build/StarSea/StarSea.console.exe'
New-Item -ItemType Directory -Path $logDirectory, $releaseDirectory -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
$matchedChecks = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[pscustomobject]@{ passed = $false; status = 'running'; checks = @() } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8

function Save-AcceptanceSummary {
    param([string]$Status = 'running')
    $failed = @($results | Where-Object { -not $_.passed })
    [pscustomobject]@{ passed = $Status -eq 'passed'; status = $Status; scope = $Scope; full_suite = $OnlyChecks.Count -eq 0; selected_checks = $OnlyChecks; completed_at = [DateTimeOffset]::Now.ToString('o'); failures = $failed; checks = @($results.ToArray()) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8
}

function Invoke-AcceptanceItem {
    param([string]$Name, [scriptblock]$Action)
    if ($OnlyChecks.Count -gt 0 -and $Name -notin $OnlyChecks) { return }
    [void]$matchedChecks.Add($Name)
    try {
        & $Action
        $results.Add([pscustomobject]@{ name = $Name; passed = $true })
        Write-Output "$Name 通过"
    }
    catch {
        $results.Add([pscustomobject]@{ name = $Name; passed = $false; error = $_.Exception.Message })
        Write-Warning "$Name 未通过：$($_.Exception.Message)"
    }
    Save-AcceptanceSummary
}

function Read-FreshReport {
    param([string]$Path, [DateTime]$Started)
    if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).LastWriteTimeUtc -lt $Started) { throw "没有生成本次报告：$Path" }
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Invoke-SourceCheck {
    param([string]$Name, [string[]]$EngineArguments, [string]$Report)
    Invoke-AcceptanceItem $Name {
        $started = [DateTime]::UtcNow
        # 子作用域直接使用 += 会丢失父作用域中的数组；先复制，再追加范围。
        $checkArguments = @($EngineArguments)
        if ($checkArguments -contains '--') { $checkArguments += '--scope=' + $Scope }
        $engineFailure = $null
        try { & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs $checkArguments -LogPath (Join-Path $logDirectory "$Name.log") | Out-Null }
        catch { $engineFailure = $_.Exception.Message }
        $sourcePath = Join-Path $repoDirectory $Report
        $data = Read-FreshReport $sourcePath $started
        # 失败报告也保留；后续独立检查继续执行，汇总仍保持失败。
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $outputDirectory "$Name.json") -Force
        if ($engineFailure) { throw $engineFailure }
        if (-not $data.passed) { throw "$Name 检查未通过。" }
    }
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
    Invoke-AcceptanceItem $Name {
        if (-not $script:releaseReady) { throw '本次构建失败，跳过旧包，避免将旧二进制记成本次验收。' }
        if (@(Get-Process -Name 'Godot*', 'StarSea*' -ErrorAction SilentlyContinue).Count -gt 0) { throw '已有 Godot 或 StarSea 进程，无法执行独立验收。' }
        $started = [DateTime]::UtcNow
        $reportPath = $null
        $releaseArguments = @($GameArguments)
        foreach ($argument in $releaseArguments) {
            if ($argument -like '--acceptance=*') { $reportPath = Join-Path $releaseDirectory ($argument.Substring(13) + '.json') }
            if ($argument -like '--shot=*') { $reportPath = Join-Path (Join-Path $releaseDirectory 'shots') ($argument.Substring(7) + '.json') }
            if ($argument -like '--descent=*') { $reportPath = $argument.Substring(10) }
            if ($argument -like '--walk=*') { $reportPath = $argument.Substring(7) }
        }
        $releaseArguments += "--scope=$Scope"
        $logPath = Join-Path $logDirectory "$Name.log"
        if ($Startup) { & $executable --quit-after 180 2>&1 | Set-Content -LiteralPath $logPath -Encoding utf8 }
        else { & $executable -- @releaseArguments 2>&1 | Set-Content -LiteralPath $logPath -Encoding utf8 }
        $code = $LASTEXITCODE
        $errors = @(Select-String -LiteralPath $logPath -Pattern '^\s*(SCRIPT ERROR:|ERROR:|WARNING:|Shader compilation failed)')
        if ($reportPath) {
            $data = Read-FreshReport $reportPath $started
            foreach ($field in @('passed', 'performance_passed', 'landing_passed', 'upload_budget_passed')) {
                if ($data.PSObject.Properties.Name -contains $field -and -not $data.$field) { throw "$Name 的 $field 未通过，报告：$reportPath" }
            }
        }
        if ($code -ne 0 -or $errors.Count -gt 0) { throw "$Name 失败：退出码 $code，错误或警告 $($errors.Count) 条。见 $logPath" }
    }
}

try {
    & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless', '--import') -LogPath (Join-Path $logDirectory 'acceptance-import.log') | Out-Null
    Invoke-AcceptanceItem 'audio-assets' {
        python (Join-Path $PSScriptRoot 'Check-Audio.py')
        if ($LASTEXITCODE -ne 0) { throw '音频素材检查失败。' }
    }
    Invoke-SourceCheck 'hydrology' @('--headless', '--script', 'res://scripts/verify/hydrology_checks.gd', '--', '--check=hydrology') 'test-output/wanderer/hydrology_checks.json'
    Invoke-SourceCheck 'landforms' @('--headless', '--script', 'res://scripts/verify/landform_checks.gd', '--', '--check=landforms') 'test-output/wanderer/landform_checks.json'
    Invoke-SourceCheck 'ruin-kit' @('--headless', '--script', 'res://scripts/verify/ruin_kit_checks.gd', '--', '--check=ruins') 'test-output/wanderer/ruin_kit_checks.json'
    Invoke-SourceCheck 'ship' @('--script', 'res://scripts/verify/ship_checks.gd', '--', '--check=ship') 'test-output/wanderer/ship_checks.json'
    Invoke-SourceCheck 'traversal' @('--headless', '--script', 'res://scripts/verify/traversal_checks.gd', '--', '--check=traversal') 'test-output/wanderer/traversal_checks.json'
    Invoke-SourceCheck 'climb-routes' @('--headless', '--script', 'res://scripts/verify/climb_route_checks.gd', '--', '--check=climb-routes') 'test-output/wanderer/climb_route_checks.json'
    Invoke-SourceCheck 'glide-routes' @('--headless', '--script', 'res://scripts/verify/glide_route_checks.gd', '--', '--check=glide-routes') 'test-output/wanderer/glide_route_checks.json'
    Invoke-SourceCheck 'civilization' @('--headless', '--script', 'res://scripts/verify/civilization_checks.gd', '--', '--check=civilization') 'test-output/wanderer/civilization_checks.json'
    Invoke-SourceCheck 'caves' @('--headless', '--script', 'res://scripts/verify/cave_checks.gd', '--', '--check=caves') 'test-output/wanderer/cave_checks.json'
    Invoke-SourceCheck 'echoes' @('--script', 'res://scripts/verify/echo_checks.gd', '--', '--check=echo') 'test-output/wanderer/echo_checks.json'
    Invoke-AcceptanceItem 'ship-mix' {
        python (Join-Path $PSScriptRoot 'Check-Audio.py') --ship-recordings (Join-Path $repoDirectory 'test-output/wanderer/audio')
        if ($LASTEXITCODE -ne 0) { throw '飞船实际混音检查失败。' }
    }
    Invoke-SourceCheck 'echo-ground' @('--headless', '--script', 'res://scripts/verify/echo_ground_checks.gd', '--', '--check=echo-ground') 'test-output/wanderer/echo_ground_checks.json'
    Invoke-SourceCheck 'journal' @('--script', 'res://scripts/verify/journal_checks.gd', '--', '--check=journal') 'test-output/wanderer/journal_checks.json'
    Invoke-SourceCheck 'music' @('--script', 'res://scripts/verify/music_checks.gd', '--', '--check=music') 'test-output/wanderer/music_checks.json'
    Invoke-SourceCheck 'ecology' @('--headless', '--script', 'res://scripts/verify/ecology_checks.gd') 'test-output/p4/ecology_checks.json'
    Invoke-SourceCheck 'ecology-runtime' @('--headless', '--script', 'res://scripts/verify/ecology_runtime_checks.gd', '--', '--check=ecology_runtime') 'test-output/p4/ecology_runtime_checks.json'
    Invoke-SourceCheck 'camera' @('--script', 'res://scripts/verify/camera_checks.gd', '--', '--check=camera') 'test-output/p3/camera_checks.json'
    Invoke-SourceCheck 'surfaces' @('--headless', '--script', 'res://scripts/verify/surface_checks.gd', '--', '--check=surfaces') 'test-output/p2/surface_checks.json'
    Invoke-SourceCheck 'completion' @('--script', 'res://scripts/verify/completion_checks.gd', '--', '--check=completion') 'test-output/p2/completion_checks.json'
    $script:releaseReady = [bool]$SkipBuild
    if (-not $SkipBuild) {
        Invoke-AcceptanceItem 'build' {
            & (Join-Path $PSScriptRoot 'Build-Game.ps1') | Out-Null
            $script:releaseReady = $true
        }
    }
    Invoke-Release 'release-assets' @('--acceptance=assets', "--out=$releaseDirectory")
    Invoke-Release 'release-core' @('--acceptance=core', "--out=$releaseDirectory")
    Invoke-Release 'release-earth' @('--acceptance=earth', "--out=$releaseDirectory")
    Invoke-AcceptanceItem 'music-mix' {
        python (Join-Path $PSScriptRoot 'Check-Audio.py') --music-recording (Join-Path $releaseDirectory 'dawn_music_mix.wav')
        if ($LASTEXITCODE -ne 0) { throw '音乐实际播放录制检查失败。' }
    }
    Invoke-Release 'release-world' @('--acceptance=world', "--out=$releaseDirectory")
    Invoke-Release 'release-audio' @('--acceptance=audio', "--out=$releaseDirectory")
    Invoke-AcceptanceItem 'ambient-mix' {
        python (Join-Path $PSScriptRoot 'Check-Audio.py') --recordings $releaseDirectory --scope $Scope
        if ($LASTEXITCODE -ne 0) { throw '实际混音检查失败。' }
    }
    $shots = @('s1_space','s2_high','s3_ground_day','s4_ground_sunset','s5_ground_night','s6_shore','s7_ember','s8_frost','s9_woodland','s10_highland','s11_orbit','s12_ruin','s13_tree_detail','s14_third_person','s15_relief_map','s16_terrace','s17_valley','s18_meadow','s19_broadleaf','s20_wetland','s21_drygrass','s22_tundra','s23_ship_parked','s24_ship_low','s25_waterfall','s28_canyon','s29_ruin_kit')
    if ($Scope -eq 'dawn') { $shots = @($shots | Where-Object { $_ -notin @('s7_ember', 's8_frost') }) }
    $shots += @('s49_range_from_spawn','s50_horn_peak','s51_canyon_rim','s52_canyon_floor','s53_mountain_pass')
    $shots += @('s70_spawn_north','s71_spawn_east','s72_spawn_south','s73_spawn_west','s74_pass_view','s75_volcano','s76_oblique_3km','s77_canyon_far')
    $shots += @('s54_glide_canyon','s55_glide_range','s56_climb_route')
    $shots += @('s30_town_plaza','s31_town_overview','s32_terraces','s33_cemetery','s34_old_road')
    $shots += @('s35_beacon_top','s36_beacon_chain_night')
    $shots += @('s37_temple_gate','s38_temple_hall')
    $shots += @('s41_ladder_from_spawn','s42_ladder_night','s43_ladder_base','s44_ladder_balcony','s45_ladder_from_orbit','s60_ladder_break','s46_echo_plaza','s47_echo_temple','s48_journal','s61_light_path','s61b_echo_ending','s60b_ladder_view')
    $shotDirectory = Join-Path $releaseDirectory 'shots'
    foreach ($shot in $shots) {
        Invoke-Release "release-$shot" @("--shot=$shot", "--out=$shotDirectory")
    }
    $descentPath = Join-Path $releaseDirectory 'descent.json'
    Invoke-AcceptanceItem 'cold-cache' { Backup-ApplicationCache }
    Invoke-Release 'release-descent' @("--descent=$descentPath")
    $walkPath = Join-Path $releaseDirectory 'walk.json'
    Invoke-Release 'release-walk' @("--walk=$walkPath")
    Invoke-Release 'release-startup' @() -Startup
    Invoke-AcceptanceItem 'archive-hash' {
    if (-not $script:releaseReady) { throw '本次构建失败。' }
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
    }
    $unknownChecks = @($OnlyChecks | Where-Object { -not $matchedChecks.Contains($_) })
    if ($unknownChecks.Count -gt 0) {
        $results.Add([pscustomobject]@{ name = 'selection'; passed = $false; error = '未知验收项目：' + ($unknownChecks -join ', ') })
    }
    $failed = @($results | Where-Object { -not $_.passed })
    if ($failed.Count -gt 0) { throw "验收结束，$($failed.Count) 项未通过，详见 summary.json。" }
    Save-AcceptanceSummary 'passed'
    if ($OnlyChecks.Count -gt 0) { Write-Output '已选项目全部通过（定向复查）。' }
    else { Write-Output '全部自动验收通过。' }
}
catch {
    Save-AcceptanceSummary 'failed'
    throw
}
