class_name TourShots
extends RefCounted

const SHOTS: Dictionary = {"spawn": "s3_ground_day", "road": "s34_old_road", "town": "s30_town_plaza", "hall": "s38_temple_hall", "beacon": "s35_beacon_top", "ladder": "s43_ladder_base", "ring": "s44_ladder_balcony"}


static func run(context: VersionContext) -> Dictionary:
	var results: Array[Dictionary] = []
	for id: String in SHOTS:
		ShotCatalog.place(SHOTS[id], context.player, context.planet, context.director)
		if not await context.settle():
			results.append({"scene": id, "passed": false, "error": "场景加载超时"})
			continue
		var basis_value: Basis = context.player.global_basis
		var pitch: float = context.player.head_pitch()
		await context.tree.create_timer(2.2).timeout
		for view: String in ["forward", "backward", "overhead"]:
			context.player.global_basis = basis_value
			context.player.set_head_pitch(pitch)
			var name: String = "tour/" + Time.get_date_string_from_system() + "/" + id
			var pair: Dictionary = await RenderReviewCapture.run(context, name) if view == "forward" else {}
			var path: String = pair["screenshot"] if view == "forward" else await RenderReviewCapture.view(context, name, view)
			var record: Dictionary = {"scene": id, "shot": SHOTS[id], "view": view, "passed": not path.is_empty(), "screenshot": path}
			if view == "forward":
				record.merge(pair)
			results.append(record)
	var canonical: String = ProjectSettings.globalize_path("res://../test-output/tour/" + Time.get_date_string_from_system() + "/" + context.output.get_file())
	DirAccess.make_dir_recursive_absolute(canonical)
	for record: Dictionary in results:
		for key: String in ["screenshot", "no_outline", "ground_mask"]:
			if record.has(key) and not str(record[key]).is_empty():
				var copy_error: Error = DirAccess.copy_absolute(record[key], canonical.path_join(str(record[key]).get_file()))
				if copy_error != OK:
					record["passed"] = false
					record["copy_error"] = copy_error
	return {"passed": results.size() == 21 and results.all(func(value: Dictionary) -> bool: return bool(value["passed"])), "shots": results, "canonical_directory": canonical, "human_visual_review_required": true}
