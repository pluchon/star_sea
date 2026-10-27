extends SceneTree

const CHECKS: PackedStringArray = ["stuck", "placement", "models", "water", "mainline", "walk-performance", "tour", "sky-horizon"]


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var check: String = ""
	var directory: String = ProjectSettings.globalize_path("res://../test-output/version")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--check="):
			check = argument.trim_prefix("--check=")
		elif argument.begins_with("--out="):
			directory = argument.trim_prefix("--out=")
	if not CHECKS.has(check):
		push_error("未知版本检查：" + check)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var report: Dictionary
	if check == "models":
		report = ModelChecks.assets()
	elif check == "placement":
		var context: VersionContext = VersionContext.new()
		context.open(self, directory)
		await process_frame
		var runtime: Dictionary = await RuntimePlacementSources.collect(context)
		report = PlacementChecks.run(runtime["sources"])
		report["runtime_collection"] = {"passed": runtime["passed"], "failures": runtime["failures"], "models": runtime["sources"].size()}
		report["passed"] = bool(report["passed"]) and bool(runtime["passed"])
		report["coverage_complete"] = bool(report["coverage_complete"]) and bool(runtime["passed"])
		await context.close()
	elif check == "water":
		report = WaterMouthChecks.run()
	else:
		var context: VersionContext = VersionContext.new()
		context.open(self, directory)
		await process_frame
		match check:
			"stuck": report = await StuckChecks.run(context)
			"mainline": report = await MainlineBot.run(context)
			"walk-performance": report = await WalkPerformanceChecks.run(context)
			"tour": report = await TourShots.run(context)
			"sky-horizon": report = await SkyHorizonReview.run(context)
		await context.close()
	report["check"] = check
	report["completed_at"] = Time.get_datetime_string_from_system()
	report["engine"] = Engine.get_version_info()["string"]
	var error: Error = VerificationMetrics.write_json(directory.path_join(check + ".json"), report)
	print(JSON.stringify({"check": check, "passed": report.get("passed", false), "report": directory.path_join(check + ".json")}))
	quit(0 if error == OK and bool(report.get("passed", false)) else 1)
