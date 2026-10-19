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
		_universe.global_position -= offset
		_player.global_position -= offset
		recenter_count += 1


func true_position() -> Vector3:
	return _player.global_position - _universe.global_position
