extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	var report: Dictionary = await LadderChecks.run(self)
	VerificationMetrics.write_json("res://../test-output/wanderer/ladder_checks.json", report)
	print(JSON.stringify(report))
	quit(0 if report["passed"] else 1)
