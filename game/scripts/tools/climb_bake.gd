extends SceneTree


func _initialize() -> void:
	var noise: TerrainNoise = TerrainNoise.new(20261019, 40000.0, 0)
	var layout: HydrologyData = load(ClimbLayout.LAYOUT_PATH) as HydrologyData
	var climbs: Dictionary = ClimbLayout.generate(noise)
	if climbs.is_empty():
		quit(1)
		return
	layout.metadata["climbs"] = climbs
	var error: Error = ResourceSaver.save(layout, ClimbLayout.LAYOUT_PATH)
	print(JSON.stringify({"passed": error == OK, "zones": layout.metadata["climbs"]["zones"].size()}))
	quit(0 if error == OK else 1)
