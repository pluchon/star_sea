class_name LandingPads
extends RefCounted

const HEIGHT: float = 6160.0
const HORIZONTAL_SCALE: float = 38.0 / 22.0
const DOCK_OFFSET: float = 54.0 * HORIZONTAL_SCALE
const BRIDGE_START: float = 44.0 * HORIZONTAL_SCALE
const BRIDGE_END: float = 74.0 * HORIZONTAL_SCALE
const RADIUS: float = 14.0 * HORIZONTAL_SCALE


static func frame(planet: Planet) -> Transform3D:
	var data: CivilizationData = planet.noise.features.civilization.data
	var up: Vector3 = data.ladder["direction"]
	return Transform3D(Basis.looking_at(data.ladder["forward"], up), up * (planet.radius + float(data.ladder["height"]) + 18))


static func near(planet: Planet, point: Vector3, vertical: float = 40) -> Dictionary:
	if planet.profile != 0 or planet.noise.features.civilization == null:
		return {}
	var transform_value: Transform3D = frame(planet)
	var center: Vector3 = transform_value * Vector3(0, HEIGHT, -DOCK_OFFSET)
	var delta: Vector3 = point - center
	var up: Vector3 = transform_value.basis.y
	if delta.slide(up).length() <= RADIUS and absf(delta.dot(up)) <= vertical:
		return {"center": center, "up": up, "frame": transform_value}
	return {}


static func landing(pad: Dictionary) -> Transform3D:
	return Transform3D(Transform3D(pad["frame"]).basis, Vector3(pad["center"]) + Vector3(pad["up"]) * StarSeaShip.FOOT_HEIGHT)


static func on_platform(planet: Planet, point: Vector3) -> bool:
	if planet.profile != 0 or planet.noise.features.civilization == null:
		return false
	var at: Vector3 = frame(planet).affine_inverse() * point
	return absf(at.y - HEIGHT) < 80 and Vector2(at.x, at.z).length() < 150


static func balcony_height(planet: Planet) -> float:
	return float(planet.noise.features.civilization.data.ladder.get("balcony_height", 240.0))
