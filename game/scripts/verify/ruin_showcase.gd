class_name RuinShowcase
extends Node3D


func build(planet: Planet) -> void:
	var up: Vector3 = planet.site["direction"]
	var forward: Vector3 = planet.site["forward"]
	transform = Transform3D(Basis.looking_at(forward, up), up * (planet.surface_radius(up) + 18.0))
	var floor_mesh: BoxMesh = BoxMesh.new()
	floor_mesh.size = Vector3(132, 0.4, 120)
	var floor_instance: MeshInstance3D = MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.position.y = -0.25
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("b8b5a5")
	floor_instance.material_override = material
	add_child(floor_instance)
	var placements: Array[Dictionary] = []
	var index: int = 0
	for piece: String in RuinMeshes.recipes():
		var position_value: Vector3 = Vector3((index % 9 - 4) * 14.0, 0, (index / 9 - 3.5) * 14.0)
		var moisture: float = planet.noise.moisture(up)
		var moss: float = smoothstep(0.45, 0.8, moisture)
		placements.append({"piece": piece, "transform": Transform3D(Basis.IDENTITY, position_value), "moss": moss, "sand": smoothstep(0.45, 0.25, moisture), "awake": 0.5 if index % 3 == 0 else 0.0, "collision": true})
		var label: Label3D = Label3D.new()
		label.text = piece
		label.font_size = 32
		label.pixel_size = 0.012
		label.position = position_value + Vector3(0, 0.025, 5.5)
		label.rotation.x = -PI * 0.5
		label.modulate = Color(0.15, 0.18, 0.16)
		add_child(label)
		index += 1
	var builder: RuinBuilder = RuinBuilder.new()
	add_child(builder)
	builder.build(placements)
