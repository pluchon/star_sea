class_name RuntimePlacementSources
extends RefCounted


static func collect(context: VersionContext) -> Dictionary:
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	var failures: Array[String] = []
	for shot: String in ["s43_ladder_base", "s44_ladder_balcony", "s60_ladder_break"]:
		ShotCatalog.place(shot, context.player, context.planet, context.director)
		if not await context.settle():
			failures.append("摆放采集等待超时：" + shot)
			continue
		var ladder: SkyLadder = context.planet.get_node("SkyLadder") as SkyLadder
		for node: Node in ladder.find_children("*", "MeshInstance3D", true, false):
			var instance: MeshInstance3D = node as MeshInstance3D
			if instance.mesh == null:
				continue
			var material: ShaderMaterial = instance.material_override as ShaderMaterial
			if material != null and material.shader.resource_path in ["res://shaders/beacon_flare.gdshader", "res://shaders/ending_stars.gdshader"]:
				continue
			var transform_value: Transform3D = instance.global_transform
			transform_value.origin -= context.planet.global_position
			var key: String = instance.mesh.resource_path + str(transform_value)
			if seen.has(key):
				continue
			seen[key] = true
			var collisions: Array[Dictionary] = []
			for child: Node in instance.find_children("*", "CollisionShape3D", true, false):
				var shape: CollisionShape3D = child as CollisionShape3D
				if shape.shape != null and not shape.disabled:
					collisions.append({"shape": shape.shape, "transform": instance.global_transform.affine_inverse() * shape.global_transform})
			records.append({"piece": "ladder/" + str(instance.name), "transform": transform_value, "mesh": instance.mesh, "collisions": collisions, "runtime_path": str(instance.get_path())})
	return {"sources": records, "failures": failures, "passed": failures.is_empty()}
