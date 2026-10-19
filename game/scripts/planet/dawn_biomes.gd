class_name DawnBiomes
extends RefCounted

const NAMES: Array[String] = ["海洋", "海岸", "草甸", "干草地", "阔叶林", "针叶林", "湿地", "高山苔原", "雪原"]


# 群系使用连续气候参数；标签只用于查询，植物密度和地表色带在边缘平滑过渡。
static func classify(elevation: float, temperature: float, moisture: float, woodland: float) -> String:
	if elevation < 0.0:
		return "海洋"
	if elevation < 16.0:
		return "海岸"
	if elevation > 1580.0:
		return "雪原"
	if temperature < 0.24 or elevation > 1300.0:
		return "高山苔原"
	if elevation < 100.0 and moisture > 0.72:
		return "湿地"
	if moisture < 0.38:
		return "干草地"
	if woodland > 0.38 and moisture > 0.45:
		return "针叶林" if temperature < 0.50 or elevation > 750.0 else "阔叶林"
	return "草甸"


static func forest_cover(elevation: float, temperature: float, moisture: float, woodland: float) -> float:
	return woodland * smoothstep(0.34, 0.62, moisture) * smoothstep(0.24, 0.36, temperature) * (1.0 - smoothstep(1150.0, 1400.0, elevation)) * (1.0 - smoothstep(0.72, 0.88, moisture) * (1.0 - smoothstep(70.0, 120.0, elevation)))
