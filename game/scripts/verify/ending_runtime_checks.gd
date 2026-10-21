extends SceneTree


func _initialize() -> void:
	_begin.call_deferred()


func _begin() -> void:
	root.unfocusable = true
	var scene: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var result: Dictionary = await EndingChecks.run(self, scene)
	VerificationMetrics.write_json("res://../test-output/wanderer/ending_checks.json", result)
	print(JSON.stringify(result))
	quit(0 if result["passed"] else 1)
