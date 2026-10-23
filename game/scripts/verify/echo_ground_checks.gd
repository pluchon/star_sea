extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	root.unfocusable = true
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var planet: Planet = scene.get_node("Universe/PlanetDawn") as Planet
	var player: StarSeaPlayer = scene.get_node("Player") as StarSeaPlayer
	var sky: SkyDirector = scene.get_node("SkyDirector") as SkyDirector
	var echoes: EchoSystem = planet.get_node("EchoSystem") as EchoSystem
	player.controls_enabled = false
	sky.time_paused = true
	echoes.frozen = true
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	var misses: Array[Dictionary] = []
	for id: String in EchoScripts.IDS + ["dawn_ending"]:
		var frame: Transform3D = echoes.anchors[id]
		player.place_at(planet.to_global(frame * Vector3(0, 2, 0)), -frame.basis.z, frame.basis.y)
		# 先让距离驱动的系统收到新位置，再判断是否完成，不能读取上一机位的空队列。
		await create_timer(0.5).timeout
		var deadline: int = Time.get_ticks_msec() + 120000
		var ready: bool = false
		var stable_since: int = -1
		while Time.get_ticks_msec() < deadline:
			await physics_frame
			ready = (planet.get_node("Terrain") as PlanetTerrain).is_settled() and (planet.get_node("CaveSystem") as CaveSystem).is_settled()
			if ready:
				if stable_since < 0:
					stable_since = Time.get_ticks_msec()
				if Time.get_ticks_msec() - stable_since >= 500:
					break
			else:
				stable_since = -1
		if not ready:
			failures.append("地形碰撞加载超时：" + id)
			continue
		# 构件创建在过程帧进行，额外等待物理世界同步，避免只看到已上传的绘制网格。
		await create_timer(1).timeout
		var script: Dictionary = EchoScripts.script_for(id)
		var maximum: float = 0
		var samples: int = 0
		var missing: int = 0
		for actor: Dictionary in script["actors"]:
			for step: int in ceili((float(actor["end"]) - float(actor["start"])) * 2) + 1:
				var time: float = minf(float(actor["start"]) + step * 0.5, float(actor["end"]))
				var at: Vector3 = frame * echoes.actor_position(id, EchoScripts.sample(actor, time)["position"])
				var up: Vector3 = at.normalized()
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(planet.to_global(at + up * 0.31), planet.to_global(at - up * 0.31), player.collision_mask, [player.get_rid()])
				var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
				samples += 1
				if hit.is_empty():
					missing += 1
					if misses.size() < 24:
						var diagnostic: Dictionary = {"id": id, "time_s": time, "path": str(actor["path"]), "anchor_local": str(EchoScripts.sample(actor, time)["position"])}
						var long_ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(planet.to_global(at + up * 30), planet.to_global(at - up * 50), player.collision_mask, [player.get_rid()])
						var nearest: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(long_ray)
						if not nearest.is_empty():
							diagnostic["surface_offset_m"] = (planet.to_local(nearest["position"]) - at).dot(up)
							diagnostic["collider"] = str((nearest["collider"] as Node).get_path())
						misses.append(diagnostic)
				else:
					maximum = maxf(maximum, planet.to_local(hit["position"]).distance_to(at))
		if missing > 0 or maximum > 0.3:
			failures.append("人物路径没有贴合真实碰撞：%s，缺失 %d，最大误差 %.4f 米" % [id, missing, maximum])
		records.append({"id": id, "samples": samples, "missing": missing, "maximum_error_m": maximum})
	var report: Dictionary = {"passed": failures.is_empty(), "failures": failures, "records": records, "misses": misses}
	VerificationMetrics.write_json("res://../test-output/wanderer/echo_ground_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
