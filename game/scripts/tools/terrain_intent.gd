class_name TerrainIntent
extends RefCounted

# 仅供意图导出与保护区复查，游戏高度查询不使用原始公式。
var _noise: TerrainNoise


func _init() -> void:
	_noise = TerrainNoise.new(20261019, 40000.0, 0, false, false)


func low_frequency(direction: Vector3) -> float:
	var point: Vector3 = direction * _noise.radius
	var continent: float = _noise._continent.get_noise_3dv(point)
	var land: float = smoothstep(-0.35, 0.0, continent)
	var mountain_mask: float = smoothstep(0.10, 0.60, continent)
	var ridge: float = (_noise._mountain.get_noise_3dv(point) + 1.0) * 0.5
	var mountain: float = pow(ridge, 1.65) * mountain_mask * 2100.0
	var upland: float = smoothstep(-0.02, 0.60, continent) * 340.0
	var foothills: float = absf(_noise._hills.get_noise_3dv(point * 0.28)) * 260.0 * smoothstep(-0.12, 0.28, continent)
	return lerpf(-420.0, 40.0, land) + mountain + upland + foothills


# 原始晨地形仅用于导出出生区保护基准，不参与游戏运行时查询。
func original_height(direction: Vector3) -> float:
	var point: Vector3 = direction * _noise.radius
	var continent: float = _noise._continent.get_noise_3dv(point)
	var land: float = smoothstep(-0.35, 0.0, continent)
	var mountain_mask: float = smoothstep(0.10, 0.60, continent)
	var ridge: float = (_noise._mountain.get_noise_3dv(point) + 1.0) * 0.5
	var mountain: float = pow(ridge, 1.65) * mountain_mask * 2100.0
	var upland: float = smoothstep(-0.02, 0.60, continent) * 340.0
	var foothills: float = absf(_noise._hills.get_noise_3dv(point * 0.28)) * 260.0 * smoothstep(-0.12, 0.28, continent)
	var hills: float = _noise._hills.get_noise_3dv(point) * 75.0 * land
	var detail: float = _noise._detail.get_noise_3dv(point) * 1.8
	# 高地沟谷使用连续等值线下切，海岸与低地不受影响；三种地形查询仍共用本函数。
	var drainage: float = absf(_noise._drainage.get_noise_3dv(point))
	# 低处沟谷为 V 形；高山上的沟谷底部展宽成冰川 U 形谷，两壁更陡。
	var glacial: float = smoothstep(700.0, 1300.0, mountain + upland)
	var valley: float = lerpf(1.0 - smoothstep(0.015, 0.13, drainage), 1.0 - smoothstep(0.075, 0.13, drainage), glacial)
	var geology: float = _noise._geology.get_noise_3dv(point) * 0.5 + 0.5
	var highland: float = mountain + upland + foothills
	var erosion: float = valley * smoothstep(150.0, 900.0, mountain + upland) * lerpf(90.0, 210.0, smoothstep(0.35, 0.65, geology)) * (1.0 + glacial * 0.25)
	# 台地保留宽阔台面与圆缓坡肩，只改变高地，不在出生低地制造台阶。
	var terrace_mask: float = smoothstep(0.56, 0.74, geology) * smoothstep(160.0, 500.0, highland)
	var tier: float = highland / 180.0
	var terraced: float = (floorf(tier) + smoothstep(0.32, 0.90, fposmod(tier, 1.0))) * 180.0
	var plateau: float = (terraced - highland) * terrace_mask * 0.75
	# 宽阔盆地与起伏山麓采用不同尺度，盆地边缘连续过渡到现有大陆。
	var basin: float = smoothstep(0.42, 0.23, geology) * smoothstep(0.03, 0.20, continent) * (1.0 - smoothstep(180.0, 650.0, highland)) * 70.0
	var coastal_bluff: float = smoothstep(0.50, 0.68, geology) * smoothstep(-0.10, 0.01, continent) * (1.0 - smoothstep(0.06, 0.17, continent)) * smoothstep(80.0, 220.0, highland) * 65.0
	return lerpf(-420.0, 40.0, land) + highland + hills + detail + plateau + coastal_bluff - erosion - basin
