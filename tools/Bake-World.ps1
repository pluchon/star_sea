param()

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Check-Godot.ps1') -GodotArgs @('--headless','--script','res://scripts/tools/world_bake.gd','--','--check=bake-world') -LogPath 'test-output/wanderer/logs/bake.log'
