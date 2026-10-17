extends Node

signal scene_changed(key: StringName)
signal popup_opened(key: StringName, popup: Node)
signal popup_closed(key: StringName)

# &"scene_name": "res://path/to/scene_name.tscn",
const SCENES: Dictionary[StringName, String] = {
	&"Main": "uid://dc1k8c1u03wl2",
	&"Game": "uid://b3ilviafr4x4r",
	&"Prototype": "res://scenes/prototype/arena.tscn"
}

# Scenes shown on top of everything.
const POPUPS: Dictionary[StringName, String] = {
	&"PauseMenu": "uid://c1f3c6w6w2oy0"
}

const POPUP_LAYER: int = 100
const FADE_LAYER: int = 128
const KEY_META: StringName = &"popup_key"

var fade_color: Color = Color.BLACK
var fade_duration: float = 0.3

var popup_dim_color: Color = Color(0.0, 0.0, 0.0, 0.5)

## Data handed to the next scene. Replaced on every change, read it in _ready().
var params: Dictionary = {}

var _transitioning: bool = false
var _fade_rect: ColorRect
var _popup_layer: CanvasLayer
var _popups: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = POPUP_LAYER
	add_child(_popup_layer)
	
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


## Shows a popup on top of everything except the fade.
## Popups stack and each blocks input to those below it.
## Returns the instance or null if it couldn't be shown.
func push_popup(key: StringName, popup_params: Dictionary = {}) -> Node:
	if _transitioning:
		return null
	if not POPUPS.has(key):
		push_error("SceneManager: unknown popup key '%s'" % key)
		return null
	var packed := load(POPUPS[key]) as PackedScene
	if packed == null:
		push_error("SceneManager: failed to load popup '%s'" % key)
		return null
	
	var popup: Node = packed.instantiate()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	if popup.has_method(&"setup"):
		popup.call(&"setup", popup_params)
	
	# The holder owns the backdrop and the popup, so freeing it removes both.
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta(KEY_META, key)
	
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.color = popup_dim_color
	
	holder.add_child(dim)
	holder.add_child(popup)
	# Lets a popup close itself with queue_free()
	popup.tree_exited.connect(holder.queue_free)
	holder.tree_exited.connect(_on_popup_removed.bind(holder, key))
	
	_popup_layer.add_child(holder)
	_popups.append(holder)
	popup_opened.emit(key, popup)
	return popup


## Closes the top popup. Returns false if none is open.
func pop_popup() -> bool:
	if _popups.is_empty():
		return false
	var holder: Control = _popups.pop_back()
	holder.queue_free()
	return true


## Closes the topmost popup with this key. Returns false if none is open.
func close_popup(key: StringName) -> bool:
	for i: int in range(_popups.size() - 1, -1, -1):
		if _popups[i].get_meta(KEY_META) == key:
			var holder: Control = _popups.pop_at(i)
			holder.queue_free()
			return true
	return false


func clear_popups() -> void:
	while pop_popup():
		pass


## With no key, true if any popup is open.
func has_popup(key: StringName = &"") -> bool:
	if key.is_empty():
		return not _popups.is_empty()
	for holder: Control in _popups:
		if holder.get_meta(KEY_META) == key:
			return true
	return false


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
	
	clear_popups()
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


func _on_popup_removed(holder: Control, key: StringName) -> void:
	_popups.erase(holder)
	popup_closed.emit(key)
