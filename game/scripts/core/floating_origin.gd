class_name FloatingOrigin
extends Node

@export var threshold: float = 2000.0
@export var universe_path: NodePath
@export var player_path: NodePath

var recenter_count: int = 0
@onready var _universe: Node3D = get_node(universe_path) as Node3D
@onready var _player: Node3D = get_node(player_path) as Node3D


func _physics_process(_delta: float) -> void:
	var offset: Vector3 = _player.global_position
	if offset.length() > threshold:
		var actor: StarSeaPlayer = _player as StarSeaPlayer
		if actor != null and actor.mode == StarSeaPlayer.Mode.WALK and offset.length() < threshold * 2:
			var planet: Planet = actor.current_planet()
			var ladder: SkyLadder = planet.get_node_or_null("SkyLadder") as SkyLadder
			# 原点平移会表现为 AnimatableBody 的瞬时运动；角色离开平台后再平移。
			# 只延后正常阈值附近的行程；远距离读档或验证定位仍立即归零。
			if ladder != null:
				var local: Vector3 = ladder.to_local(actor.global_position)
				if Vector2(local.x, local.z).length() < 120 and local.y > -20 and local.y < ladder.balcony_height + 60:
					return
		_universe.global_position -= offset
		_player.global_position -= offset
		recenter_count += 1


func true_position() -> Vector3:
	return _player.global_position - _universe.global_position
