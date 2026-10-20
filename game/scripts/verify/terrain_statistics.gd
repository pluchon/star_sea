class_name TerrainStatistics
extends RefCounted


static func collect(noise: TerrainNoise) -> Dictionary:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 20261019
	var minimum: float = INF
	var maximum: float = -INF
	var ocean_samples: int = 0
	var landforms: Dictionary = {}
	var biomes: Dictionary = {}
	for sample: int in 20000:
		var y: float = random.randf_range(-1.0, 1.0)
		var angle: float = random.randf_range(0.0, TAU)
		var horizontal: float = sqrt(maxf(1.0 - y * y, 0.0))
		var direction: Vector3 = Vector3(horizontal * cos(angle), y, horizontal * sin(angle))
		var height: float = noise.height(direction)
		var form: String = noise.landform(direction)
		landforms[form] = int(landforms.get(form, 0)) + 1
		var biome: String = noise.biome(direction)
		biomes[biome] = int(biomes.get(biome, 0)) + 1
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)
		if height < 0.0:
			ocean_samples += 1
	var ocean_ratio: float = float(ocean_samples) / 20000.0
	return {
		"seed": 20261019,
		"radius_m": noise.radius,
		"samples": 20000,
		"landforms": landforms,
		"biomes": biomes,
		"ocean_ratio": ocean_ratio,
		"minimum_height_m": minimum,
		"maximum_height_m": maximum,
		"passed": ocean_ratio >= 0.25 and ocean_ratio <= 0.55 and minimum >= -450.0 and minimum <= -380.0 and maximum >= 1800.0 and maximum <= TerrainNoise.MAX_HEIGHT,
	}
