extends Node

# 输入集中注册，避免手写项目文件中的事件序列化格式。
const KEYS: Dictionary[String, Key] = {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"jump_up": KEY_SPACE,
	"descend": KEY_CTRL,
	"run": KEY_SHIFT,
	"toggle_fly": KEY_F,
	"toggle_help": KEY_H,
	"toggle_perf": KEY_F3,
	"screenshot": KEY_F12,
	"time_fast": KEY_T,
	"release_mouse": KEY_ESCAPE,
}


func _ready() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = KEYS[action]
		InputMap.action_add_event(action, event)
