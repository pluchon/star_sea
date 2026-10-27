param(
    [string[]]$OnlyChecks = @(),
    [string]$ReportDirectory = 'test-output/acceptance',
    [int]$MaxStuckCases = 0,
    [string]$RenderBaseline = 'test-output/version-baseline',
    [string]$PythonExecutable = 'python',
    [int]$StopAfterStuckFailures = 128,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$directory = [IO.Path]::GetFullPath($ReportDirectory, $repoDirectory)
$runDirectory = Join-Path $directory ('version-runs/' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
$names = @('stuck', 'placement', 'models', 'water', 'tour', 'render', 'sky-horizon', 'mainline', 'walk-performance', 'existing')
$unknown = @($OnlyChecks | Where-Object { $_ -notin $names })
if ($unknown.Count) { throw ('未知版本检查：' + ($unknown -join ', ')) }
$fullSuite = $OnlyChecks.Count -eq 0 -and $MaxStuckCases -eq 0 -and -not $SkipBuild

function Save-VersionSummary {
    param([string]$Status)
    $coverageComplete = $fullSuite -and $results.Count -eq $names.Count -and @($results | Where-Object { $_.coverage_complete -eq $false }).Count -eq 0
    $summary = [ordered]@{ passed = $Status -eq 'passed'; status = $Status; scope = 'version'; full_suite = $fullSuite; coverage_complete = $coverageComplete; run_directory = $runDirectory; checks = @($results.ToArray()) }
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $runDirectory 'summary.json') -Encoding utf8
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $directory 'version-summary.json') -Encoding utf8
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# 第二版检查汇总')
    $lines.Add('')
    $lines.Add("状态：$Status；选择全部项目：$fullSuite；完成全部覆盖：$coverageComplete；原始报告：$runDirectory")
    $lines.Add('')
    $lines.Add('| 检查 | 结果 | 报告或失败位置 |')
    $lines.Add('| --- | --- | --- |')
    foreach ($item in $results) {
        $label = if ($item.passed) { '通过' } else { '失败' }
        $detail = ($item.detail -replace '\r?\n', ' ' -replace '\|', '／')
        $lines.Add("| $($item.name) | $label | $($item.report)；$detail |")
    }
    $lines | Set-Content -LiteralPath (Join-Path $directory 'version-summary.md') -Encoding utf8
}

Save-VersionSummary 'running'
try { & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless', '--import') -LogPath (Join-Path $runDirectory 'import.log') | Out-Null }
catch {
    $results.Add([pscustomobject]@{ name = 'import'; passed = $false; report = (Join-Path $runDirectory 'import.log'); detail = $_.Exception.Message })
    Save-VersionSummary 'failed'
    throw
}
foreach ($name in $names) {
    if ($OnlyChecks.Count -gt 0 -and $name -notin $OnlyChecks) { continue }
    $started = [DateTime]::UtcNow
    $reportPath = Join-Path $runDirectory ($name + '.json')
    $executionError = ''
    $coverage = $false
    try {
        if ($name -eq 'existing') {
            $legacyDirectory = Join-Path $runDirectory 'existing'
            & (Join-Path $PSScriptRoot 'Test-Acceptance.ps1') -Scope all -SkipBuild:$SkipBuild -ReportDirectory $legacyDirectory
            $reportPath = Join-Path $legacyDirectory 'summary.json'
        }
        elseif ($name -eq 'render') {
            $tourReport = Join-Path $runDirectory 'tour.json'
            # 定向复查可使用上次巡检，但报告必须明确列出来源，不能称作本次新截图。
            if (-not (Test-Path -LiteralPath $tourReport)) {
                $tourReport = Join-Path $directory 'latest-tour.json'
            }
            $previous = Join-Path $directory 'previous-render.json'
            $renderArguments = @((Join-Path $PSScriptRoot 'Review-Render.py'), '--version-tour', $tourReport, '--baseline', [IO.Path]::GetFullPath($RenderBaseline, $repoDirectory), '--output', $runDirectory)
            if (Test-Path -LiteralPath $previous) { $renderArguments += @('--previous', $previous) }
            $renderPython = $PythonExecutable
            $hasRenderDependencies = $false
            try {
                & $renderPython -c 'import numpy, PIL' 2>$null
                $hasRenderDependencies = $LASTEXITCODE -eq 0
            }
            catch { $hasRenderDependencies = $false }
            if (-not $hasRenderDependencies -and $PythonExecutable -eq 'python') {
                $bundledPython = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
                if (Test-Path -LiteralPath $bundledPython) { $renderPython = $bundledPython }
            }
            & $renderPython @renderArguments
            if ($LASTEXITCODE -ne 0) { $executionError = "画面指标未通过，退出码 $LASTEXITCODE" }
        }
        else {
            if ($name -eq 'models') {
                $fixtureStarted = [DateTime]::UtcNow
                & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless', '--script', 'res://scripts/verify/checker_fixture_checks.gd', '--', '--check=checker-fixtures') -LogPath (Join-Path $runDirectory 'checker-fixtures.log') | Out-Null
                $fixtureSource = Join-Path $repoDirectory 'test-output/version/checker-fixtures.json'
                if (-not (Test-Path -LiteralPath $fixtureSource) -or (Get-Item -LiteralPath $fixtureSource).LastWriteTimeUtc -lt $fixtureStarted) { throw '没有生成本次检查器校准报告。' }
                Copy-Item -LiteralPath $fixtureSource -Destination (Join-Path $runDirectory 'checker-fixtures.json')
                if (-not (Get-Content -LiteralPath $fixtureSource -Raw | ConvertFrom-Json).passed) { throw '检查器校准未通过，不能信任模型结论。' }
            }
            $engineArguments = @('--script', 'res://scripts/verify/version_checks.gd', '--', "--check=$name", "--out=$runDirectory", '--scope=dawn')
            if ($name -in @('placement', 'models', 'water')) { $engineArguments = @('--headless') + $engineArguments }
            if ($name -eq 'stuck') {
                # 断点放在固定目录；原始结果保存在每次独立目录，不能覆盖首次失败。
                $checkpoint = Join-Path $directory 'stuck-checkpoint.json'
                if (Test-Path -LiteralPath $checkpoint) { Copy-Item -LiteralPath $checkpoint -Destination $runDirectory }
                if ($MaxStuckCases -gt 0) { $engineArguments += "--max-cases=$MaxStuckCases" }
                $engineArguments += "--stop-after-failures=$StopAfterStuckFailures"
            }
            try { & (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs $engineArguments -LogPath (Join-Path $runDirectory ($name + '.log')) | Out-Null }
            finally {
                if ($name -eq 'stuck' -and (Test-Path -LiteralPath (Join-Path $runDirectory 'stuck-checkpoint.json'))) {
                    Copy-Item -LiteralPath (Join-Path $runDirectory 'stuck-checkpoint.json') -Destination (Join-Path $directory 'stuck-checkpoint.json') -Force
                }
            }
        }
    }
    catch { $executionError = $_.Exception.Message }
    if ($name -eq 'existing') { $reportPath = Join-Path $runDirectory 'existing/summary.json' }
    $passed = $false
    $detail = $executionError
    if (Test-Path -LiteralPath $reportPath) {
        if ((Get-Item -LiteralPath $reportPath).LastWriteTimeUtc -ge $started) {
            $data = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            $passed = [bool]$data.passed -and -not $executionError
            $coverage = if ($data.PSObject.Properties.Name -contains 'coverage_complete') { [bool]$data.coverage_complete }
                elseif ($name -eq 'mainline' -or $name -eq 'tour') { $passed }
                elseif ($name -eq 'render') { @($data.results).Count -eq 7 }
                elseif ($name -eq 'existing') { $data.status -ne 'running' -and [bool]$data.full_suite }
                else { $true }
            $locations = @($data.failure, $data.projection, $data.findings, $data.blocked, $data.failed_meshes, $data.failed_mouths, $data.results | Where-Object { $null -ne $_ })
            $detail += ' ' + ($locations | ConvertTo-Json -Depth 4 -Compress -WarningAction SilentlyContinue)
            if ($detail.Length -gt 1800) { $detail = $detail.Substring(0, 1800) + '（完整内容见原始报告）' }
            if ($name -eq 'tour') { Copy-Item -LiteralPath $reportPath -Destination (Join-Path $directory 'latest-tour.json') -Force }
            if ($name -eq 'render') { Copy-Item -LiteralPath $reportPath -Destination (Join-Path $directory 'previous-render.json') -Force }
        }
        else { $detail += ' 没有本次新报告' }
    }
    else { $detail += ' 没有生成报告' }
    $results.Add([pscustomobject]@{ name = $name; passed = $passed; coverage_complete = $coverage; report = $reportPath; detail = $detail.Trim() })
    Save-VersionSummary 'running'
    Write-Output "$name 完成：$passed"
}
$failed = @($results | Where-Object { -not $_.passed })
$status = if ($failed.Count -eq 0 -and $results.Count -gt 0) { 'passed' } else { 'failed' }
Save-VersionSummary $status
if ($status -ne 'passed') { throw "第二版检查结束，$($failed.Count) 项未通过。见 $directory/version-summary.md" }
