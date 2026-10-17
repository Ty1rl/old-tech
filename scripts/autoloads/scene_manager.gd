extends Node

signal scene_changed(key: StringName)

# &"scene_name": "res://path/to/scene_name.tscn",
const SCENES: Dictionary[StringName, String] = {}

const FADE_LAYER: int = 128

var fade_color: Color = Color.BLACK
var fade_duration: float = 0.3

## Data handed to the next scene. Replaced on every change, read it in _ready().
var params: Dictionary = {}

var _transitioning: bool = false
var _fade_rect: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var layer := CanvasLayer.new()
	layer.layer = FADE_LAYER
	add_child(layer)

	_fade_rect = ColorRect.new()
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_rect.color = Color(fade_color, 0.0)
	_fade_rect.visible = false
	layer.add_child(_fade_rect)


## Changes to a registered scene. 
## Returns false if already transitioning or the key isn't in SCENES.
func go_to(key: StringName, new_params: Dictionary = {}, fade: bool = true) -> bool:
	if _transitioning:
		return false
	if not SCENES.has(key):
		push_error("SceneManager: unknown scene key '%s'" % key)
		return false
	_change(key, SCENES[key], new_params, fade)
	return true


## Reloads the current scene, keeping the current params.
func reload_current_scene(fade: bool = true) -> bool:
	var scene: Node = get_tree().current_scene
	if _transitioning or scene == null:
		return false
	_change(&"", scene.scene_file_path, params, fade)
	return true


func get_current_scene() -> Node:
	return get_tree().current_scene


func is_transitioning() -> bool:
	return _transitioning


func get_param(param_name: StringName, default: Variant = null) -> Variant:
	return params.get(param_name, default)


func _change(key: StringName, path: String, new_params: Dictionary, fade: bool) -> void:
	_transitioning = true
	
	if fade:
		await _fade_to(1.0)
	
	params = new_params
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneManager: failed to load scene '%s'" % path)
	else:
		# The swap happens at the end of the frame.
		await get_tree().process_frame
		scene_changed.emit(key)
	
	if fade:
		await _fade_to(0.0)
	
	_transitioning = false


func _fade_to(alpha: float) -> void:
	_fade_rect.visible = true
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, fade_duration)
	await tween.finished
	_fade_rect.visible = alpha > 0.0
