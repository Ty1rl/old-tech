extends Node

signal scene_changed(key: StringName)
signal popup_opened(key: StringName, popup: Node)
signal popup_closed(key: StringName)
signal restart_room_requested
signal transition_failed(key: StringName, reason: String)
signal transition_cancelled(key: StringName)
## Emitted at irreversible commit, while the outgoing tree is still attached.
signal scene_leaving(scene: Node, destination: StringName)
signal _transition_tick

# &"scene_name": "res://path/to/scene_name.tscn",
const SCENES: Dictionary[StringName, String] = {
	&"Main": "uid://dc1k8c1u03wl2",
	&"Game": "uid://b3ilviafr4x4r",
	&"Prototype": "res://scenes/prototype/arena.tscn",
	&"Campaign": "res://scenes/prototype/campaign.tscn"
}

# Scenes shown on top of everything.
const POPUPS: Dictionary[StringName, String] = {
	&"PauseMenu": "uid://c1f3c6w6w2oy0",
	&"Settings": "res://scenes/ui/settings.tscn",
	&"NewGame": "res://scenes/ui/new_game.tscn",
	&"RunResult": "res://scenes/ui/run_result.tscn",
	&"Developer": "res://scenes/ui/encounter_menu.tscn",
	&"Repair": "res://scenes/prototype/repair.tscn"
}

const POPUP_LAYER: int = 100
const FADE_LAYER: int = 128
const KEY_META: StringName = &"popup_key"
const LoadingScene = preload("res://scenes/loading_r/loading.tscn")

var fade_color: Color = Color.BLACK
var fade_duration: float = 0.3

var popup_dim_color: Color = Color(0.0, 0.0, 0.0, 0.5)

## Data handed to the next scene. Replaced on every change, read it in _ready().
var params: Dictionary = {}

var developer_tools: bool = developer_opt_in(OS.get_cmdline_user_args(), OS.has_feature("web"))
var _transitioning: bool = false
var _fade_rect: ColorRect
var _popup_layer: CanvasLayer
var _popups: Array[Control] = []
var _loading: Control
var _loading_status: Label
var _loading_progress: ProgressBar
var _loading_cancel: Button
var _loading_path := ""
var _cancel_requested := false
var _can_cancel := false
var _load_error := false
var _failure_focus: WeakRef
var _exiting := false
var _closing := false
var _swap_ready := false
var _swap_ready_at_usec := 0
## Last completed transition, bounded diagnostic data in microseconds (not a clock).
var last_transition_profile: Dictionary = {}


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
	_loading = LoadingScene.instantiate()
	layer.add_child(_loading)
	_loading_status = _loading.get_node("%Status")
	_loading_progress = _loading.get_node("%Progress")
	_loading_cancel = _loading.get_node("%Cancel")
	_loading_cancel.pressed.connect(_on_loading_cancel)
	get_tree().scene_changed.connect(_on_tree_ready)
	get_tree().root.close_requested.connect(_on_close_requested)


## Changes to a registered scene. 
## Returns false if already transitioning or the key isn't in SCENES.
func go_to(key: StringName, new_params: Dictionary = {}, fade: bool = true) -> bool:
	if _transitioning:
		return false
	if not SCENES.has(key):
		push_error("SceneManager: unknown scene key '%s'" % key)
		return false
	if not ResourceLoader.exists(SCENES[key]):
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
	# Repair panels carry generation tokens; explicit replacement sessions may
	# coexist briefly while an older panel exits. Menus/settings stay unique.
	if _transitioning or (key == &"Developer" and not developer_tools) or (has_popup(key) and key != &"Repair"):
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
	var previous_focus := get_viewport().gui_get_focus_owner()
	if not _popups.is_empty():
		_popups.back().process_mode = Node.PROCESS_MODE_DISABLED
		_popups.back().get_child(1).process_mode = Node.PROCESS_MODE_DISABLED
	var holder := Control.new()
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	if previous_focus:
		holder.set_meta("previous_focus", weakref(previous_focus))
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


## Returns the topmost matching CONTENT root, never its dimming wrapper.
## Empty key queries the top popup for focus management. Closing/freed nodes
## are excluded immediately, even before the deferred deletion queue drains.
func get_popup(key: StringName) -> Node:
	for i in range(_popups.size() - 1, -1, -1):
		var holder := _popups[i]
		if not is_instance_valid(holder) or holder.is_queued_for_deletion(): continue
		if not key.is_empty() and holder.get_meta(KEY_META) != key: continue
		if holder.get_child_count() < 2: continue
		var content := holder.get_child(1)
		if not content.is_queued_for_deletion(): return content
	return null


func get_current_scene() -> Node:
	return get_tree().current_scene


func is_transitioning() -> bool:
	return _transitioning


func get_param(param_name: StringName, default: Variant = null) -> Variant:
	return params.get(param_name, default)


# Whole-graph worker loading is unsafe for this preload graph, including quit.
# Dependency hints let us load small resources between frames on the main thread.
const ResourceSteps = preload("res://scenes/loading_r/resource_steps.gd")


static func developer_opt_in(user_args: PackedStringArray, web: bool) -> bool:
	return not web and user_args.has("--developer")


# Speech terminal signals are synchronous, even on disabled nodes. Pause only
# the outgoing scene/popup receivers; global audio lifetime observers stay live.
func _suspend_scene_speech(scene: Node) -> Array[Dictionary]:
	var suspended: Array[Dictionary] = []
	if scene == null: return suspended
	for connection: Dictionary in AudioManager.get_signal_connection_list(&"speech_finished"):
		var callback: Callable = connection.callable
		var receiver := callback.get_object()
		if not receiver is Node: continue
		var owned: bool = receiver == scene or scene.is_ancestor_of(receiver)
		for holder in _popups:
			owned = owned or holder == receiver or holder.is_ancestor_of(receiver)
		if owned:
			AudioManager.disconnect(&"speech_finished", callback)
			suspended.append(connection)
	return suspended


func _suspend_scope_processing(scene: Node) -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	var pending: Array[Node] = []
	if scene != null: pending.append(scene)
	pending.append_array(_popups)
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		# Explicit ALWAYS children otherwise keep processing under a disabled root.
		if node == scene or node.process_mode != Node.PROCESS_MODE_INHERIT:
			saved.append({"node": weakref(node), "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	return saved


func _resume_scope_processing(saved: Array[Dictionary]) -> void:
	for entry in saved:
		var node: Node = entry.node.get_ref()
		if is_instance_valid(node): node.process_mode = int(entry.mode)


func _resume_scene_speech(suspended: Array[Dictionary]) -> void:
	for connection in suspended:
		var callback: Callable = connection.callable
		if callback.is_valid() and not AudioManager.is_connected(&"speech_finished", callback):
			AudioManager.connect(&"speech_finished", callback, int(connection.flags))


func _prepare_scene_exit(scene: Node, destination: StringName) -> void:
	if scene == null: return
	scene_leaving.emit(scene, destination)
	# Existing campaign hook cancels ordinary and forced-rewind teaching without
	# awarding completion. Owners may also cancel through scene_leaving.
	if scene.has_method(&"_cancel_active_teaching_controllers"):
		scene.call(&"_cancel_active_teaching_controllers")
	AudioManager.stop_dialogue()


func _on_close_requested() -> void:
	_closing = true
	cancel_transition()
	var scene := get_tree().current_scene
	_suspend_scene_speech(scene)
	_suspend_scope_processing(scene)
	_prepare_scene_exit(scene, &"")


func _on_tree_ready() -> void:
	_swap_ready = true
	_swap_ready_at_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	_transition_tick.emit()


func _exit_tree() -> void:
	_exiting = true
	_cancel_requested = true
	# Wake suspended transition/fade states so their retained resources release
	# before the autoload disappears, including direct engine quit mid-load.
	_transition_tick.emit()


func _on_loading_cancel() -> void:
	if _load_error:
		_load_error = false
		_loading.hide()
		var focus: Control = _failure_focus.get_ref() if _failure_focus != null else null
		if is_instance_valid(focus) and focus.is_inside_tree(): focus.grab_focus()
		_failure_focus = null
	else:
		cancel_transition()


## Cancels before scene ownership is committed. Never interrupts _ready halfway.
func cancel_transition() -> bool:
	if not _transitioning or not _can_cancel or _cancel_requested: return false
	_cancel_requested = true
	_loading_cancel.disabled = true
	_loading_status.text = "Returning…"
	return true


func _present_loading() -> void:
	if _exiting: return
	await _transition_tick
	if _exiting: return
	# A full rendered frame lies between these ticks. This also remains wakeable
	# on teardown, unlike awaiting a renderer signal after rendering has stopped.
	if DisplayServer.get_name() != "headless": await _transition_tick


func _change(key: StringName, path: String, new_params: Dictionary, fade: bool) -> void:
	_transitioning = true
	_cancel_requested = false
	_can_cancel = true
	_load_error = false
	_failure_focus = null
	_loading.hide()
	var next_params := new_params.duplicate(true)
	var previous_params := params
	var old_scene := get_tree().current_scene
	var suspended_speech := _suspend_scene_speech(old_scene)
	var old_state: int = GameState.state
	var focused := get_viewport().gui_get_focus_owner()
	var previous_focus: WeakRef = weakref(focused) if focused != null else null
	var was_disabled: bool = focused.disabled if focused is BaseButton else false
	var suspended_processing := _suspend_scope_processing(old_scene)
	var profile := {"key": String(key), "path": path, "fade": fade}
	var started := Time.get_ticks_usec()
	if fade: await _fade_to(1.0)
	if _exiting: return
	profile.fade_out_usec = Time.get_ticks_usec() - started
	_loading_status.text = "Loading museum…" if key in [&"Campaign", &"Prototype"] else "Loading…"
	_loading_progress.indeterminate = true
	_loading_progress.value = 0
	_loading_progress.show()
	_loading_cancel.text = "Cancel"
	_loading_cancel.disabled = _cancel_requested
	_loading.show()
	_loading_cancel.grab_focus()
	# Present feedback before parsing or constructing anything. No campaign is
	# loaded/instantiated by the manager until an explicit go_to/start_play call.
	await _present_loading()
	if _exiting: return
	var mark := Time.get_ticks_usec()
	var failure := ""
	var packed: PackedScene
	if not _cancel_requested:
		_loading_path = path
		# A live cached root already owns its dependency graph. Do not sweep stale
		# hints again (including assets removed from that graph).
		packed = ResourceLoader.get_cached_ref(path) as PackedScene
		profile.cached_root = packed != null
		var steps: Array = []
		if packed == null and (key in [&"Campaign", &"Prototype"] or path == SCENES[&"Campaign"] or path == SCENES[&"Prototype"]):
			steps = ResourceSteps.STEPS
		# Keep weak-cache dependencies alive until the root scene owns its graph.
		var retained: Array[Resource] = []
		var slice_started := Time.get_ticks_usec()
		var largest_step := 0
		var largest_path := ""
		var loaded_steps := 0
		for step_path in steps:
			if _cancel_requested: break
			if not ResourceLoader.exists(step_path): continue # Hints may age at integration.
			var step_started := Time.get_ticks_usec()
			var resource := ResourceLoader.load(step_path)
			var elapsed := Time.get_ticks_usec() - step_started
			if elapsed > largest_step:
				largest_step = elapsed
				largest_path = step_path
			if resource != null: retained.append(resource)
			loaded_steps += 1
			if Time.get_ticks_usec() - slice_started >= 8000:
				await _transition_tick
				if _exiting: return
				slice_started = Time.get_ticks_usec()
		profile.resource_steps = loaded_steps
		profile.largest_resource_step_usec = largest_step
		profile.largest_resource_path = largest_path
		if not _cancel_requested and packed == null:
			var root_started := Time.get_ticks_usec()
			packed = ResourceLoader.load(path) as PackedScene
			profile.root_resource_usec = Time.get_ticks_usec() - root_started
			if packed == null: failure = "Could not open the room."
	profile.resource_wait_usec = Time.get_ticks_usec() - mark
	_loading_path = ""
	_can_cancel = false
	if not _cancel_requested and failure.is_empty():
		_loading_status.text = "Preparing the room…"
		_loading_progress.indeterminate = false
		_loading_progress.value = 1
		_loading_cancel.disabled = true
		await _present_loading()
	if _exiting: return
	# Recheck after the last yield, before committing ownership/params.
	if not _cancel_requested and failure.is_empty() and get_tree().current_scene != old_scene:
		failure = "The scene changed while loading."
	if not _cancel_requested and failure.is_empty():
		# Scene-tree creation and _ready stay on the main thread, measured separately.
		params = next_params
		mark = Time.get_ticks_usec()
		var instance := packed.instantiate()
		profile.instantiate_usec = Time.get_ticks_usec() - mark
		if instance == null:
			failure = "Could not create the room."
		else:
			var next_process := instance.process_mode
			instance.process_mode = Node.PROCESS_MODE_DISABLED
			_prepare_scene_exit(old_scene, key)
			clear_popups()
			mark = Time.get_ticks_usec()
			_swap_ready = false
			var err := get_tree().change_scene_to_node(instance)
			if err != OK:
				instance.free()
				failure = "Could not enter the room."
			else:
				while not _swap_ready and not _exiting: await _transition_tick
				if _exiting: return
				profile.swap_ready_usec = _swap_ready_at_usec - mark
				scene_changed.emit(key)
				# Include graphics work since the native ready signal, even if the
				# next manager tick arrives after the first blocking render.
				mark = _swap_ready_at_usec
				await _present_loading()
				if _exiting: return
				profile.first_draw_wait_usec = Time.get_ticks_usec() - mark
				_loading.hide()
				mark = Time.get_ticks_usec()
				if fade: await _fade_to(0.0)
				profile.fade_in_usec = Time.get_ticks_usec() - mark
				if is_instance_valid(instance): instance.process_mode = next_process
	if _cancel_requested or not failure.is_empty():
		params = previous_params
		GameState.change_state(old_state)
		_loading.hide()
		if fade: await _fade_to(0.0)
		var focus: Control = previous_focus.get_ref() if previous_focus != null else null
		if is_instance_valid(focus) and focus.is_inside_tree():
			if focus is BaseButton: focus.disabled = was_disabled
			focus.grab_focus()
		if not failure.is_empty():
			_load_error = true
			_failure_focus = previous_focus
			_loading_status.text = failure + " Please try again."
			_loading_progress.hide()
			_loading_cancel.text = "Back"
			_loading_cancel.disabled = false
			_loading.show()
			_loading_cancel.grab_focus()
	profile.status = "cancelled" if _cancel_requested else ("failed" if not failure.is_empty() else "completed")
	profile.total_usec = Time.get_ticks_usec() - started
	last_transition_profile = profile
	_transitioning = false
	if (_cancel_requested or not failure.is_empty()) and not _closing and is_instance_valid(old_scene) and get_tree().current_scene == old_scene:
		_resume_scene_speech(suspended_speech)
		_resume_scope_processing(suspended_processing)
	if _cancel_requested: transition_cancelled.emit(key)
	if not failure.is_empty(): transition_failed.emit(key, failure)


func _fade_to(alpha: float) -> void:
	if _exiting: return
	_fade_rect.visible = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, fade_duration)
	while tween.is_running() and not _exiting: await _transition_tick
	if _exiting:
		tween.kill()
		return
	_fade_rect.visible = alpha > 0.0


func _on_popup_removed(holder: Control, key: StringName) -> void:
	_popups.erase(holder)
	if not _popups.is_empty():
		_popups.back().process_mode = Node.PROCESS_MODE_ALWAYS
		_popups.back().get_child(1).process_mode = Node.PROCESS_MODE_ALWAYS
	if holder.has_meta("previous_focus"):
		var focus: Control = holder.get_meta("previous_focus").get_ref()
		if is_instance_valid(focus) and focus.is_inside_tree():
			focus.grab_focus.call_deferred()
	popup_closed.emit(key)


func play_key(sandbox: bool = false) -> StringName:
	return &"Campaign" if not sandbox and ResourceLoader.exists(SCENES[&"Campaign"]) else &"Prototype"

func start_play(sandbox: bool = false, difficulty: StringName = &"easy", skip_tutorials: bool = false) -> bool:
	if _transitioning or difficulty not in [&"easy", &"hard"]:
		return false
	var accepted := go_to(play_key(sandbox), {"new_run": true, "difficulty": difficulty, "skip_tutorials": skip_tutorials})
	if accepted:
		GameState.start_game()
	return accepted

func return_main() -> void:
	if go_to(&"Main"):
		GameState.open_menu()

func request_restart_room() -> void:
	# Campaign owns checkpoints. The isolated sandbox has no room controller.
	if restart_room_requested.get_connections().size() > 0:
		restart_room_requested.emit()
	else:
		if reload_current_scene():
			GameState.start_game()

func show_run_result(won: bool) -> void:
	GameState.end_game()
	clear_popups()
	push_popup(&"RunResult", {"won": won})
