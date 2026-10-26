class_name RenderFinish
extends MeshInstance3D


func _ready() -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh = quad
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/outline.gdshader") as Shader
	# 在水面之前绘制，只叠加线条，不覆盖大气、粒子和回声。
	material.render_priority = -100
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1000000.0
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position
