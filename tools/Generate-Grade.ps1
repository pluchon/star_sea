$ErrorActionPreference = 'Stop'
# 色板与运行时共用资源，避免生成脚本另存一套颜色。
& (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless', '--script', 'res://scripts/tools/generate_grade.gd') -LogPath 'test-output/render/grade-generation.log'
