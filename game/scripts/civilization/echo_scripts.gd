class_name EchoScripts
extends RefCounted

const IDS: Array[String] = ["dawn_daily", "dawn_faith", "dawn_departure", "dawn_watcher"]


static func actor(pose: String, path: Array[Vector3], start: float, end: float, child: bool = false, changes: Array = []) -> Dictionary:
	return {"pose": pose, "path": path, "start": start, "end": end, "child": child, "changes": changes}


static func script_for(id: String) -> Dictionary:
	var actors: Array[Dictionary] = []
	var duration: float = 16
	var radius: float = 14
	var music: String = "echo_daily"
	match id:
		"dawn_daily":
			for i: int in 4:
				actors.append(actor("sit", [Vector3(-3 + i * 1.7, 0, -2 - sin(i) * 1.3)], 0, 16, false, [[10.0, "raise"]] if i == 1 else [[11.0 + i * 0.2, "look_up"]]))
			for i: int in 2:
				actors.append(actor("child_run", [Vector3(4, 0, 2), Vector3(-4, 0, 3), Vector3(-2, 0, -4), Vector3(4, 0, 2)], 1 + i * 0.8, 14 + i, true))
			actors.append(actor("carry", [Vector3(1, 0, 11), Vector3(2, 0, 4), Vector3(2, 0, -1)], 0, 16, false, [[8.0, "place"], [11.0, "sit"]]))
		"dawn_faith":
			duration = 15
			radius = 18
			music = "echo_faith"
			actors.append(actor("paint", [Vector3(0.21, 0, 15.05)], 0, 15, false, [[12.0, "look_up"]]))
			for i: int in 7:
				actors.append(actor("kneel", [Vector3((i % 4 - 1.5) * 2.3, 0, 1 + floori(i / 4.0) * 3)], 0, 15, false, [[12.0, "kneel_look"]]))
		"dawn_departure":
			duration = 18
			music = "echo_departure"
			for i: int in 13:
				var row: float = -10 + i * 1.6
				actors.append(actor("carry", [Vector3((i % 3 - 1) * 0.6, 0, row), Vector3((i % 2 - 0.5) * 0.6, 0, -12 if i < 12 else -2)], 0, 3 + i * 1.24, false, [[12.5, "stand"], [15.0, "walk"]] if i == 12 else []))
		"dawn_watcher":
			duration = 15
			radius = 8
			music = "echo_watcher"
			actors.append(actor("sit", [Vector3(1.4, 0, 0)], 0, 15, false, [[11.0, "place"]]))
		"dawn_ending":
			duration = 25
			radius = 6
			music = "echo_ending"
			# 桥上十七米的慢走保留约二十五秒总长，不用高速移动表现老人。
			actors.append(actor("old_walk", [Vector3(0, 0, 17), Vector3(0, 0, 1)], 0, 25, false, [[16.0, "lamp_raise"], [18.0, "lamp_place"], [22.0, "sit"]]))
	return {"duration": duration, "radius": radius, "music": music, "actors": actors}


static func sample(actor_data: Dictionary, time: float) -> Dictionary:
	var pose: String = actor_data["pose"]
	var pose_start: float = actor_data["start"]
	var stop: float = float(actor_data["end"]) - 2
	for change: Array in actor_data["changes"]:
		stop = minf(stop, float(change[0]))
		if time >= float(change[0]):
			pose = change[1]
			pose_start = change[0]
	var path: Array = actor_data["path"]
	var travel_time: float = time - float(actor_data["start"])
	var travel_duration: float = stop - float(actor_data["start"])
	if actor_data["pose"] == "old_walk":
		travel_time -= clampf(time - 5, 0, 0.8) + clampf(time - 10, 0, 1)
		travel_duration -= 1.8
		if (time >= 5 and time < 5.8) or (time >= 10 and time < 11):
			pose = "lamp_carry"
	var amount: float = clampf(travel_time / maxf(travel_duration, 0.01), 0, 1) * (path.size() - 1)
	var segment: int = mini(floori(amount), path.size() - 1)
	var at: Vector3 = path[segment]
	var forward: Vector3 = Vector3.FORWARD
	if segment < path.size() - 1:
		at = at.lerp(path[segment + 1], amount - segment)
		forward = Vector3(path[segment + 1]) - Vector3(path[segment])
	if actor_data["pose"] == "paint":
		forward = Vector3.BACK
	if actor_data["pose"] == "carry" and pose == "stand":
		forward = Vector3.BACK
	return {"position": at, "forward": forward, "pose": pose, "pose_time": time - pose_start}
