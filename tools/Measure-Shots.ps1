param(
    [string]$OutputDirectory = 'test-output\p1\shots',
    [ValidateSet('dawn', 'all')][string]$Scope = 'dawn',
    [Alias('Shots')][string[]]$ShotNames = @()
)

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$outputPath = [IO.Path]::GetFullPath($OutputDirectory, $repoDirectory)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$shots = @('s1_space', 's2_high', 's3_ground_day', 's4_ground_sunset', 's5_ground_night', 's6_shore', 's7_ember', 's8_frost', 's9_woodland', 's10_highland', 's11_orbit', 's12_ruin', 's13_tree_detail', 's14_third_person', 's15_relief_map', 's16_terrace', 's17_valley','s18_meadow','s19_broadleaf','s20_wetland','s21_drygrass','s22_tundra','s23_ship_parked','s24_ship_low','s25_waterfall','s28_canyon','s29_ruin_kit')
$shots += @('s49_range_from_spawn','s50_horn_peak','s51_canyon_rim','s52_canyon_floor','s53_mountain_pass','s54_glide_canyon','s55_glide_range','s56_climb_route')
$shots += @('s70_spawn_north','s71_spawn_east','s72_spawn_south','s73_spawn_west','s74_pass_view','s75_volcano','s76_oblique_3km','s77_canyon_far')
$shots += @('s30_town_plaza','s31_town_overview','s32_terraces','s33_cemetery','s34_old_road')
$shots += @('s35_beacon_top','s36_beacon_chain_night')
$shots += @('s37_temple_gate','s38_temple_hall')
$shots += @('s41_ladder_from_spawn','s42_ladder_night','s43_ladder_base','s44_ladder_balcony','s45_ladder_from_orbit','s60_ladder_break')
$shots += @('s46_echo_plaza','s47_echo_temple','s48_journal','s61_light_path')
if ($ShotNames.Count -gt 0) { $shots = @($ShotNames) }
if ($Scope -eq 'dawn') { $shots = @($shots | Where-Object { $_ -notin @('s7_ember','s8_frost') }) }
$rows = [Collections.Generic.List[string]]::new()
$rows.Add('| 机位 | 平均帧间隔 ms | P95 ms | CPU 监控读数 ms | GPU 平均 ms | 达标 |')
$rows.Add('| --- | ---: | ---: | ---: | ---: | --- |')
$allPassed = $true
foreach ($shot in $shots) {
    & (Join-Path $PSScriptRoot 'Run-Game.ps1') -GameArgs @("--shot=$shot", "--out=$outputPath", "--scope=$Scope")
    $report = Get-Content -LiteralPath (Join-Path $outputPath "$shot.json") -Raw | ConvertFrom-Json
    if (-not $report.performance_passed) { $allPassed = $false }
    $rows.Add(('| {0} | {1:F2} | {2:F2} | {3:F2} | {4:F2} | {5} |' -f $shot, $report.frame_ms.mean, $report.frame_ms.p95, $report.cpu_ms.mean, $report.gpu_ms.mean, $report.performance_passed))
}
$rows | Set-Content -LiteralPath (Join-Path $outputPath 'summary.md') -Encoding utf8
$rows | ForEach-Object { Write-Output $_ }
if (-not $allPassed) { throw '部分机位未达到性能预算，完整报告已经保留。' }
