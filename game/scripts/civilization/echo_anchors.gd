class_name EchoAnchors
extends RefCounted


static func bake(noise: TerrainNoise, data: CivilizationData, caves: CaveData) -> Dictionary:
	var town_up: Vector3 = data.town["direction"]
	var heading: Vector3 = town_up.direction_to(data.ladder["direction"]).slide(town_up).normalized()
	var town: Transform3D = Transform3D(Basis.looking_at(heading, town_up), town_up * (noise.radius + noise.height(town_up)))
	var up: Vector3 = data.ladder["direction"]
	var ladder: Transform3D = Transform3D(Basis.looking_at(data.ladder["forward"], up), up * (noise.radius + float(data.ladder["height"]) + 18))
	var departure: Transform3D = ladder.translated_local(Vector3(0, 0.05, -35))
	departure.basis *= Basis(Vector3.UP, PI)
	var faith: Transform3D = caves.networks[0]["frame"]
	faith.origin = caves.networks[0]["echo_anchor"]
	faith.basis *= Basis(Vector3.UP, TAU / 6 + 0.2)
	var watcher: Transform3D = BeaconTowers.tower_frame(data.beacons[-1], noise.radius).translated_local(Vector3(0, BeaconTowers.TOP, 0))
	# 从场景读取渊的位置，烘焙与运行时的栈桥朝向共用同一个来源。
	var giant: Vector3 = Vector3.ZERO
	var state: SceneState = (load("res://scenes/main.tscn") as PackedScene).get_state()
	for index: int in state.get_node_count():
		if not String(state.get_node_path(index)).ends_with("Universe/GasGiant"):
			continue
		for property: int in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == "position":
				giant = state.get_node_property_value(index, property)
	var bridge: Vector3 = (ladder.basis.inverse() * ladder.origin.direction_to(giant)).slide(Vector3.UP).normalized()
	if bridge.is_zero_approx():
		bridge = Vector3.BACK
	var ending: Transform3D = ladder * Transform3D(Basis.looking_at(bridge, Vector3.UP), bridge * 74 + Vector3.UP * LandingPads.HEIGHT)
	return {"dawn_daily": town.translated_local(Vector3(0, 0.04, 12)), "dawn_faith": faith, "dawn_departure": departure, "dawn_watcher": watcher, "dawn_ending": ending}
