class_name InlandWaters
extends WaterChunks

var river_count: int = 0
var lake_count: int = 0


func build_features(features: TerrainFeatures) -> void:
	river_count = features.hydrology.data.river_starts.size() - 1
	lake_count = features.hydrology.data.lake_levels.size()
	build(get_parent() as Planet, features.hydrology.data)
