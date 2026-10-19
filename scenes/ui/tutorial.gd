extends Control

# Explanations freeze via the campaign's world/action guard, not SceneTree.pause.
# Practice resumes actions but keeps crowd pressure gated until complete_lesson.
# Round S: no "Try it" confirmation. A teaching segment hands off automatically once
# its speech (and any LessonDemo visual pass) finishes. The only manual exit is a
# click-only Skip button; keyboard keys never activate it.
signal resume_requested(id: StringName)
signal lesson_completed(id: StringName)
signal blocking_changed(value: bool)
## Emitted when the player clicks Skip. A LessonDemo owning the segment handles it;
## otherwise the overlay stops the segment's speech and hands off itself.
signal skip_requested(id: StringName)

const UI = preload("res://scenes/ui/ui_style.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const BLUE: Color = ToolStyle.RING
const ORANGE: Color = ToolStyle.CONE
const YELLOW: Color = ToolStyle.BEAM
const VIOLET: Color = ToolStyle.CLOCK
const GUIDE: Color = ToolStyle.REPAIR_GUIDE
const SKIP_TEXT := "Skip"
## Card-only lessons (no LessonDemo) with no audible speech hand off after this read time.
const NO_SPEECH_READ_SECONDS := 2.6
## Exact spoken line for tutorial.time_meter (new_audio/time meter.mp3).
const TIME_METER_LINE := "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge."

# Entry format: [imperative_heading, subtle_body, lesson_key, subtle_subtitle]
const LESSONS := {
	"time_meter": ["Watch your time reserve", TIME_METER_LINE, "time_meter", "TIME RESERVE"],
	"cut": ["Hold, draw, release", "1 · Ring Cutter — draw across the blue link.", "cut", "1 · RING CUTTER"],
	"heat": ["Aim and hold", "3 · Heat Bellows — strip orange armor and push threats back.", "heat", "3 · HEAT BELLOWS"],
	"shot": ["Click to shoot", "2 · Focused Flash — aim at the yellow core.", "shot", "2 · FOCUSED FLASH"],
	"slow": ["Hold Space", "Hold Space to slow the world, shoot the target, then release.", "slow", "TIME SLOW"],
	"repair": ["Press E to repair", "Press E to open repair: spin, connect, and trace to 100%; closes when full.", "repair", "TOOL REPAIR"],
	"charge": ["Hold, then release", "2 · Focused Flash — charge until bright to pierce aligned targets.", "charge", "2 · FOCUSED FLASH · PIERCE"],
	"opening": ["Cut or heat, then shoot", "Open the blue link or orange armor, then switch to 2 for yellow.", "opening", "OPEN · THEN 2 · FOCUSED FLASH"],
	"pair": ["Click A, then B", "2 · Focused Flash — shoot A to open B before its shutter closes.", "pair", "2 · FOCUSED FLASH · PAIR"],
	"loop": ["Hold, draw, release", "1 · Ring Cutter — cut every blue support, then charge 2 on yellow.", "loop", "1 · RING CUTTER · LOOP"],
	"zigzag": ["Hold, draw, release", "1 · Ring Cutter — bend across each blue span, then charge 2 on yellow.", "zigzag", "1 · RING CUTTER · ZIGZAG"],
	"rewind": ["Scroll, then press Enter", "When a hit spends an emergency charge, scroll the wheel to an earlier safe moment and confirm.", "rewind", "EMERGENCY REWIND"],
	"final": ["Open each lock, then shoot", "Clear pair, zigzag, and loop phases, then finish the yellow core.", "final", "THE BURIAL DEVICE"],
}

var blocking := false
var practicing := false
var demo_busy := false
var waiting_for_speech := false
var active_id: StringName = &""
var learned: Dictionary = {}
var world_points: Array[Vector3] = []
var ghost: Array[Vector2] = []
var projected: Array[Vector2] = []
var offscreen: Array[bool] = []
var camera: Camera3D
var age := 0.0
var align_pattern := false
var card: PanelContainer
var heading: Label
var body_label: Label
var state_label: Label
var practice_button: Button
var accent: Color = BLUE
var audio_manager_override: Node = null
var _subtitle_text := ""
var _layout_size := Vector2(-1, -1)
var _layout_dirty := true
var _held_keys_while_blocked: Dictionary = {}
var _held_lmb_while_blocked := false
var _suppress_release_after_dismiss := false
var _bound_audio: Node = null
## True once this segment's instruction speech was observed playing.
var _teaching_speech_seen := false
## Seconds the current card has been blocking (only advances while uncovered).
var _teaching_age := 0.0
## Latched per segment so double clicks/handlers cannot finish twice.
var _skip_latched := false
## Id of the most recent segment ended by Skip (diagnostics/checks).
var last_skipped_id: StringName = &""
## Optional phase draw style set by LessonDemo (e.g. &"time" for the reserve demo).
var draw_style: StringName = &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UI.skin()
	_ensure_authored_hierarchy()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	if not GameState.settings_changed.is_connected(_on_settings_changed):
		GameState.settings_changed.connect(_on_settings_changed)
	_bind_audio_signals()
	hide()


func _exit_tree() -> void:
	var is_standalone_root_layer := get_parent() is CanvasLayer and is_inside_tree() and get_tree() != null and get_parent().get_parent() == get_tree().root
	_unbind_audio_signals()
	if GameState != null and GameState.settings_changed.is_connected(_on_settings_changed):
		GameState.settings_changed.disconnect(_on_settings_changed)
	if is_standalone_root_layer:
		var am := _get_audio_manager()
		if is_instance_valid(am):
			if am.has_method("stop_dialogue"):
				am.call("stop_dialogue")
			if am.has_method("set_music_context"):
				am.call("set_music_context", &"intro")
		get_tree().call_group(&"world_audio", &"reset_state")


func _get_audio_manager() -> Node:
	if is_instance_valid(audio_manager_override):
		return audio_manager_override
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioManager") if tree != null and tree.root != null else null


func _bind_audio_signals() -> void:
	var am := _get_audio_manager()
	if am == _bound_audio and is_instance_valid(_bound_audio):
		return
	_unbind_audio_signals()
	_bound_audio = am
	if is_instance_valid(_bound_audio):
		if _bound_audio.has_signal("speech_finished") and not _bound_audio.is_connected("speech_finished", _on_audio_speech_finished):
			_bound_audio.connect("speech_finished", _on_audio_speech_finished)
		var voice_node := _bound_audio.get_node_or_null("Voice") as AudioStreamPlayer
		if voice_node != null and not voice_node.finished.is_connected(_on_voice_player_finished):
			voice_node.finished.connect(_on_voice_player_finished)


func _unbind_audio_signals() -> void:
	if is_instance_valid(_bound_audio):
		if _bound_audio.has_signal("speech_finished") and _bound_audio.is_connected("speech_finished", _on_audio_speech_finished):
			_bound_audio.disconnect("speech_finished", _on_audio_speech_finished)
		var voice_node := _bound_audio.get_node_or_null("Voice") as AudioStreamPlayer
		if voice_node != null and voice_node.finished.is_connected(_on_voice_player_finished):
			voice_node.finished.disconnect(_on_voice_player_finished)
	_bound_audio = null


func _on_audio_speech_finished(_event: StringName, interrupted: bool = false) -> void:
	_update_practice_button_state()
	if interrupted or not is_inside_tree():
		return
	if visible and blocking and not practicing and not demo_busy and not is_instruction_speech_busy():
		_teaching_speech_seen = true
		_auto_handoff_to_practice()


func _on_voice_player_finished() -> void:
	_update_practice_button_state.call_deferred()


func is_instruction_speech_busy() -> bool:
	var am := _get_audio_manager()
	if am == null or not is_instance_valid(am):
		return false
	if am.has_method("instruction_busy"):
		return bool(am.call("instruction_busy"))
	var prefs: Dictionary = GameState.preferences() if GameState != null and GameState.has_method("preferences") else {}
	if not bool(prefs.get("sound", true)):
		return false
	if float(prefs.get("volume", 1.0)) <= 0.0001 or float(prefs.get("voice_volume", 1.0)) <= 0.0001:
		return false
	if AudioServer.get_bus_count() > 0 and AudioServer.is_bus_mute(0):
		return false
	var voice_bus := AudioServer.get_bus_index(&"Voice")
	if voice_bus >= 0 and AudioServer.is_bus_mute(voice_bus):
		return false
	if am.get("library") == null:
		return false
	var voice_player := am.get_node_or_null("Voice") as AudioStreamPlayer
	var cur_ev := String(am.get("current_event"))
	if voice_player != null and voice_player.playing and voice_player.stream != null:
		if cur_ev.begins_with("tutorial."):
			return true
		var q: Variant = am.get("_queue")
		if q is Array:
			for item in q:
				if item is Dictionary and String(item.get("event", "")).begins_with("tutorial."):
					return true
	return false


func set_demo_busy(value: bool) -> void:
	if demo_busy == value and not waiting_for_speech:
		return
	demo_busy = value
	if not value:
		waiting_for_speech = false
	_update_practice_button_state()
	queue_redraw()


func set_waiting_for_speech(value: bool) -> void:
	if waiting_for_speech == value:
		return
	waiting_for_speech = value
	_update_practice_button_state()
	queue_redraw()


func can_dismiss_normally() -> bool:
	if not visible or active_id.is_empty() or not blocking:
		return false
	if SceneManager != null and SceneManager.has_popup():
		return false
	if GameState != null and GameState.is_paused():
		return false
	return not demo_busy and not is_instruction_speech_busy()


func _ensure_authored_hierarchy() -> void:
	if get_node_or_null("Card") == null:
		var packed: PackedScene = load("res://scenes/ui/tutorial.tscn")
		if packed != null:
			var authored: Control = packed.instantiate()
			var authored_card: PanelContainer = authored.get_node_or_null("Card") as PanelContainer
			if authored_card != null:
				authored.remove_child(authored_card)
				add_child(authored_card)
			authored.free()
	card = get_node_or_null("Card") as PanelContainer
	state_label = get_node_or_null("Card/Column/StateLabel") as Label
	heading = get_node_or_null("Card/Column/HeadingLabel") as Label
	body_label = get_node_or_null("Card/Column/BodyLabel") as Label
	practice_button = get_node_or_null("Card/Column/PracticeButton") as Button
	if is_instance_valid(body_label):
		body_label.modulate = UI.MUTED
	if is_instance_valid(practice_button):
		practice_button.focus_mode = Control.FOCUS_NONE
		practice_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		practice_button.shortcut = null
		practice_button.text = SKIP_TEXT
		if practice_button.pressed.is_connected(request_practice):
			practice_button.pressed.disconnect(request_practice)
		if not practice_button.pressed.is_connected(_on_practice_button_pressed):
			practice_button.pressed.connect(_on_practice_button_pressed)


func _on_practice_button_pressed() -> void:
	skip_active_lesson(true)


func skip_active_lesson(from_mouse: bool = true) -> bool:
	if not visible or active_id.is_empty() or not blocking or practicing or _skip_latched:
		return false
	if SceneManager != null and SceneManager.has_popup():
		return false
	if GameState != null and GameState.is_paused():
		return false
	_skip_latched = true
	var id := active_id
	last_skipped_id = id
	_suppress_release_after_dismiss = true
	var am := _get_audio_manager()
	if is_instance_valid(am) and am.has_method("stop_dialogue"):
		am.call("stop_dialogue")
	skip_requested.emit(id)
	if blocking and active_id == id:
		request_practice()
	_apply_post_dismiss_carryover_guard(from_mouse)
	return true


func _auto_handoff_to_practice() -> bool:
	if not can_dismiss_normally() or practicing:
		return false
	var lmb_down := _held_lmb_while_blocked or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_suppress_release_after_dismiss = lmb_down
	request_practice()
	_apply_post_dismiss_carryover_guard(lmb_down)
	return true


func _try_user_dismiss(from_mouse: bool = false) -> bool:
	if not from_mouse:
		return false
	return skip_active_lesson(true)


func _apply_post_dismiss_carryover_guard(from_mouse: bool) -> void:
	if not is_instance_valid(camera):
		return
	var player_node := camera.get_parent() as Node3D
	if not is_instance_valid(player_node):
		return
	if player_node.has_method("reset_input"):
		player_node.call("reset_input")
	var arena_node := player_node.get_parent() as Node
	if not is_instance_valid(arena_node):
		return
	arena_node.set("_space_action_held", false)
	var lmb_down := from_mouse or _held_lmb_while_blocked or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if lmb_down:
		arena_node.set("_suppress_next_lmb_release", true)
	var weapons_node := arena_node.get("weapons") as Node
	if is_instance_valid(weapons_node):
		if weapons_node.has_method("cancel_input"):
			weapons_node.call("cancel_input")
		weapons_node.set("mouse_held", false)
		if lmb_down:
			weapons_node.set("require_fresh_press", true)
	var tc := arena_node.get("time_controller") as Node
	if is_instance_valid(tc):
		tc.set("slow_requested", false)


func is_point_on_skip_button(screen_pos: Vector2) -> bool:
	if not visible or not blocking or practicing:
		return false
	if not is_instance_valid(practice_button) or not practice_button.visible or practice_button.disabled:
		return false
	return practice_button.get_global_rect().has_point(screen_pos)


func _update_practice_button_state() -> void:
	if not is_instance_valid(practice_button):
		return
	if not blocking or practicing:
		practice_button.release_focus()
		practice_button.focus_mode = Control.FOCUS_NONE
		practice_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		practice_button.disabled = true
		practice_button.hide()
		return
	practice_button.show()
	practice_button.release_focus()
	practice_button.disabled = false
	practice_button.focus_mode = Control.FOCUS_NONE
	practice_button.mouse_filter = Control.MOUSE_FILTER_STOP
	practice_button.text = SKIP_TEXT


func _capture_initial_held_inputs() -> void:
	_held_keys_while_blocked.clear()
	_held_lmb_while_blocked = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		if Input.is_physical_key_pressed(code):
			_held_keys_while_blocked[code] = true
	if InputMap.has_action(&"move_up") and Input.is_action_pressed(&"move_up"):
		_held_keys_while_blocked[KEY_W] = true
	if InputMap.has_action(&"slow_time") and Input.is_action_pressed(&"slow_time"):
		_held_keys_while_blocked[KEY_SPACE] = true


func _on_resized() -> void:
	_layout(true)


func setup(value: Camera3D) -> void:
	camera = value


static func is_drawing_lesson(id: StringName) -> bool:
	return id in [&"cut", &"loop", &"zigzag"]


static func accent_for_lesson(id: StringName) -> Color:
	if id == &"heat":
		return ORANGE
	if id in [&"shot", &"charge", &"pair", &"final"]:
		return YELLOW
	if id in [&"slow", &"rewind", &"time_meter"]:
		return VIOLET
	if id == &"repair":
		return GUIDE
	return BLUE


static func subtitle_for_lesson(id: StringName) -> String:
	if LESSONS.has(String(id)):
		var entry: Array = LESSONS[String(id)]
		if entry.size() >= 4:
			return String(entry[3])
	return "ACTION GUIDE"


func set_phase_accent(color: Color, subtitle: String = "") -> void:
	accent = color
	if color == BLUE and active_id in [&"cut", &"opening", &"loop", &"zigzag"]:
		var g_id: StringName = &"cut" if active_id == &"opening" else active_id
		ghost.assign(gesture_for(g_id))
	elif color != BLUE and active_id in [&"cut", &"opening", &"loop", &"zigzag"]:
		ghost.clear()
	if is_instance_valid(state_label):
		state_label.modulate = accent
		if not subtitle.is_empty():
			_subtitle_text = subtitle
			state_label.text = subtitle
	queue_redraw()


func set_phase_prompt(title_text: String, body_text: String, color: Color, subtitle: String = "") -> void:
	if is_instance_valid(heading) and not title_text.is_empty():
		heading.text = title_text
	if is_instance_valid(body_label) and not body_text.is_empty():
		body_label.text = body_text
	set_phase_accent(color, subtitle)
	_layout(true)


func show_known_lesson(id: StringName, targets: Array[Vector3]) -> bool:
	if not LESSONS.has(String(id)):
		return false
	var text: Array = LESSONS[String(id)]
	_subtitle_text = subtitle_for_lesson(id)
	show_lesson(id, String(text[0]), String(text[1]), targets, gesture_for(id))
	if active_id == id:
		align_pattern = is_drawing_lesson(id)
	return visible and active_id == id


func show_lesson(id: StringName, title: String, text: String, targets: Array[Vector3], gesture: Array[Vector2] = []) -> void:
	_ensure_authored_hierarchy()
	_bind_audio_signals()
	if is_learned(id) or id == active_id or not active_id.is_empty():
		return
	active_id = id
	align_pattern = false
	draw_style = &"time" if id == &"time_meter" else &""
	world_points = targets.duplicate()
	ghost.clear()
	if is_drawing_lesson(id) or not LESSONS.has(String(id)):
		ghost.assign(gesture)
	heading.text = title
	body_label.text = text
	accent = accent_for_lesson(id)
	_subtitle_text = subtitle_for_lesson(id)
	state_label.modulate = accent
	state_label.text = _subtitle_text
	practicing = false
	waiting_for_speech = false
	age = 0.0
	_teaching_age = 0.0
	_teaching_speech_seen = is_instruction_speech_busy()
	_skip_latched = false
	_suppress_release_after_dismiss = false
	_capture_initial_held_inputs()
	_set_blocking(true)
	_update_practice_button_state()
	show()
	_layout(true)


func request_practice() -> void:
	if active_id.is_empty() or not blocking or SceneManager.has_popup():
		return
	demo_busy = false
	waiting_for_speech = false
	practicing = true
	draw_style = &""
	_update_practice_button_state()
	state_label.modulate = accent
	state_label.text = _subtitle_text + " · YOUR TURN"
	_set_blocking(false)
	resume_requested.emit(active_id)
	_layout(true)


func complete_lesson(id: StringName) -> void:
	# Only the campaign/harness calls this after observing actual success.
	if id != active_id or not practicing:
		return
	learned[id] = true
	active_id = &""
	practicing = false
	demo_busy = false
	waiting_for_speech = false
	draw_style = &""
	_skip_latched = false
	_held_keys_while_blocked.clear()
	_held_lmb_while_blocked = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	ghost.clear()
	hide()
	lesson_completed.emit(id)


func is_learned(id: StringName) -> bool:
	return bool(learned.get(id, false)) or not bool(GameState.preferences().tutorial)


func dismiss() -> void:
	active_id = &""
	practicing = false
	demo_busy = false
	waiting_for_speech = false
	draw_style = &""
	_skip_latched = false
	_held_keys_while_blocked.clear()
	_held_lmb_while_blocked = false
	_suppress_release_after_dismiss = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	ghost.clear()
	hide()


func reset_run() -> void:
	learned.clear()
	active_id = &""
	practicing = false
	demo_busy = false
	waiting_for_speech = false
	draw_style = &""
	_skip_latched = false
	last_skipped_id = &""
	_teaching_speech_seen = false
	_teaching_age = 0.0
	_held_keys_while_blocked.clear()
	_held_lmb_while_blocked = false
	_suppress_release_after_dismiss = false
	_set_blocking(false)
	world_points.clear()
	projected.clear()
	ghost.clear()
	hide()


func _set_blocking(value: bool) -> void:
	var filter := Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	if is_instance_valid(card):
		card.mouse_filter = filter
	if blocking != value:
		blocking = value
		blocking_changed.emit(value)


func _on_settings_changed(values: Dictionary) -> void:
	if not values.tutorial and not active_id.is_empty():
		var id := active_id
		var prior := learned.duplicate()
		reset_run()
		learned = prior
		resume_requested.emit(id)
	else:
		_update_practice_button_state()


func _layout(force: bool = true) -> void:
	if not is_instance_valid(card):
		return
	if is_inside_tree() and (size.x <= 1.0 or size.y <= 1.0):
		size = get_viewport_rect().size
	if force or _layout_dirty or _layout_size != size:
		_layout_size = size
		_layout_dirty = false
		var factor := UI.scale_for(self)
		theme.default_font_size = roundi(18 * factor)
		var width := minf(420 * factor, maxf(210, size.x - 32))
		var inner_w := maxf(160.0, width - 32.0)
		var col := card.get_node_or_null("Column") as Control
		if is_instance_valid(col):
			col.custom_minimum_size.x = inner_w
			col.size.x = inner_w
		for ctrl: Control in [state_label, heading, body_label]:
			if is_instance_valid(ctrl):
				ctrl.custom_minimum_size.x = inner_w
				ctrl.size.x = inner_w
		if is_instance_valid(practice_button):
			practice_button.size_flags_horizontal = Control.SIZE_SHRINK_END
			practice_button.custom_minimum_size = Vector2(roundi(84 * factor), roundi(28 * factor))
			practice_button.add_theme_font_size_override("font_size", roundi(13 * factor))
		card.custom_minimum_size.x = width
		card.size = Vector2(width, 0.0)
		heading.add_theme_font_size_override("font_size", roundi((22 if size.y < 480 else 26) * factor))
		body_label.add_theme_font_size_override("font_size", roundi((13 if size.y < 480 else 14) * factor))
		state_label.add_theme_font_size_override("font_size", roundi(12 * factor))
		card.reset_size()
	var min_size := card.get_combined_minimum_size()
	if absf(card.size.y - min_size.y) > 1.0:
		card.size.y = min_size.y
	card.position.x = (size.x - card.size.x) * 0.5
	var target_y := size.y * 0.4
	if not projected.is_empty():
		target_y = projected[0].y
	card.position.y = maxf(14, size.y - card.size.y - 16) if target_y < size.y * 0.55 else 16


func _process(delta: float) -> void:
	if not visible:
		return
	_bind_audio_signals()
	if is_inside_tree() and (size.x <= 1.0 or size.y <= 1.0):
		size = get_viewport_rect().size
	# Pause/settings cover this card and stop its practice controls; emergency mode stays uncovered.
	var in_emergency: bool = GameState.has_method("is_in_emergency") and bool(GameState.call("is_in_emergency")) and not GameState.is_paused()
	var covered: bool = SceneManager.has_popup() or (not GameState.is_playing() and not in_emergency)
	card.visible = not covered
	if covered:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()
		return
	if blocking and not practicing:
		if is_instruction_speech_busy():
			_teaching_speech_seen = true
		_teaching_age += maxf(0.0, delta)
		if not demo_busy and not is_instruction_speech_busy():
			if _teaching_speech_seen or _teaching_age >= NO_SPEECH_READ_SECONDS:
				_auto_handoff_to_practice()
	_update_practice_button_state()
	var filter := Control.MOUSE_FILTER_STOP if blocking else Control.MOUSE_FILTER_IGNORE
	mouse_filter = filter
	card.mouse_filter = filter
	age += delta
	projected.clear()
	offscreen.clear()
	if is_instance_valid(camera):
		var rect := get_viewport_rect().grow(-36)
		for point in world_points:
			var behind := camera.is_position_behind(point)
			var screen := camera.unproject_position(point)
			if behind:
				var local := camera.to_local(point)
				var direction := Vector2(local.x, -local.y)
				if direction.is_zero_approx():
					direction = Vector2.DOWN
				screen = size * 0.5 + direction.normalized() * size.length()
			var outside := behind or not rect.has_point(screen)
			projected.append(screen.clamp(rect.position, rect.end))
			offscreen.append(outside)
	_layout(false)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _suppress_release_after_dismiss:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_suppress_release_after_dismiss = false
			# Only swallow the release belonging to the dismiss click.
			# A fresh press starts a playable gesture and must keep its release.
			if not event.pressed:
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
				return

	if not visible or not blocking:
		return
	if SceneManager != null and SceneManager.has_popup():
		return
	if GameState != null and GameState.is_paused():
		return

	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code in [KEY_ESCAPE, KEY_F10, KEY_M, KEY_F7]:
			return
		if code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			if event.pressed:
				_held_keys_while_blocked[code] = true
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
			else:
				_held_keys_while_blocked.erase(code)
			return
		if code in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
			if not event.pressed:
				_held_keys_while_blocked.erase(code)
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			if event.echo:
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
			if code == KEY_E and active_id == &"repair" and not demo_busy and not bool(_held_keys_while_blocked.get(code, false)):
				return
			_held_keys_while_blocked[code] = true
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_held_lmb_while_blocked = false
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		if _held_lmb_while_blocked:
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
		_held_lmb_while_blocked = true
		if is_point_on_skip_button(event.position):
			skip_active_lesson(true)
		if is_inside_tree() and get_viewport() != null:
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not blocking:
		return
	if event is InputEventMouseButton or event is InputEventMouse:
		accept_event()


func _draw() -> void:
	if not visible or not card.visible:
		return
	var font := ThemeDB.fallback_font
	var factor := UI.scale_for(self)
	for i in range(projected.size()):
		var p := projected[i]
		var r := 21.0 + 2.5 * sin(age * 4.0)
		draw_arc(p, r, 0, TAU, 36, accent, 2.5, true)
		draw_circle(p, 3.5, accent)

		# Attack-accurate target gesture accents (never a cutter line for yellow shots).
		if not offscreen[i]:
			if (active_id in [&"shot", &"pair"] and draw_style != &"time") or (active_id == &"opening" and accent == YELLOW):
				for tick_idx in range(4):
					var ang := float(tick_idx) * PI * 0.5
					var dir := Vector2(cos(ang), sin(ang))
					draw_line(p + dir * (r + 3.0), p + dir * (r + 10.0), YELLOW, 2.2, true)
			elif active_id == &"charge" or (active_id in [&"loop", &"zigzag"] and accent == YELLOW):
				var charge_prog := clampf(fmod(age * 0.95, 1.15), 0.0, 1.0)
				draw_arc(p, r + 7.0, -PI * 0.5, -PI * 0.5 + TAU * charge_prog, 32, YELLOW, 3.2, true)
				if charge_prog >= 0.92:
					draw_arc(p, r + 11.0, 0, TAU, 32, Color(1.0, 0.98, 0.78, 0.85), 2.0, true)
			elif active_id == &"heat":
				var wave_t := fmod(age * 1.4, 1.0)
				draw_arc(p, r + 6.0 + wave_t * 12.0, -PI * 0.82, -PI * 0.18, 24, Color(ORANGE, 0.75 * (1.0 - wave_t)), 3.0, true)
			elif active_id == &"slow" or active_id == &"time_meter" or draw_style == &"time":
				draw_arc(p, r + 7.0, 0, TAU, 32, Color(VIOLET, 0.7), 2.0, true)
				draw_circle(p, 4.0, VIOLET if (active_id == &"time_meter" or draw_style == &"time") else YELLOW)

		if projected.size() > 1 or offscreen[i] or active_id == &"pair":
			var caption := str(i + 1) + (" · offscreen" if offscreen[i] else "")
			if active_id == &"pair" and not offscreen[i]:
				caption = ("A" if i == 0 else "B")
			var label_position := p + Vector2(26, 6)
			label_position.x = clampf(label_position.x, 16, maxf(16, size.x - 160 * factor))
			draw_string(font, label_position, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * factor), GUIDE)
		if offscreen[i]:
			var direction := (p - size * 0.5).normalized()
			var side := direction.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + direction * 17, p - direction * 8 + side * 8, p - direction * 8 - side * 8]), accent)

	# A blue line only teaches drawing; never draw a moving line for clicks, holds, Space, or rewind.
	if ghost.size() >= 2 and accent == BLUE and (is_drawing_lesson(active_id) or not LESSONS.has(String(active_id))) and not projected.is_empty() and not offscreen.has(true):
		var area := Rect2(projected[0], Vector2.ZERO)
		for p in projected:
			area = area.expand(p)
		area = area.grow(48)
		var path := PackedVector2Array()
		for p in ghost:
			path.append(area.position + p * area.size)
		if align_pattern and active_id in [&"loop", &"zigzag"] and projected.size() >= 2:
			path = PackedVector2Array(projected)
			if active_id == &"loop":
				path.append(projected[0])
		draw_polyline(path, Color(BLUE, 0.55), 3.2, true)
		var step := fmod(age * 0.65, 1.0) * (path.size() - 1)
		var index := mini(int(step), path.size() - 2)
		var cursor := path[index].lerp(path[index + 1], step - index)
		draw_circle(cursor, 6.5, GUIDE)
		draw_arc(cursor, 10.5, 0, TAU, 24, BLUE, 2.0, true)
	elif active_id == &"opening" and accent == BLUE and not projected.is_empty() and not offscreen[0]:
		var center := projected[0]
		var cut_a := center + Vector2(-42.0, 22.0)
		var cut_b := center + Vector2(42.0, -22.0)
		draw_line(cut_a, cut_b, Color(BLUE, 0.55), 3.2, true)
		var t_open := fmod(age * 0.85, 1.0)
		var cur_open := cut_a.lerp(cut_b, t_open)
		draw_circle(cur_open, 6.5, GUIDE)
		draw_arc(cur_open, 10.5, 0, TAU, 24, BLUE, 2.0, true)


# Ghost coordinates are normalized to the padded projected target bounds.
# Only drawing lessons return a blue trace path; clicks/holds/Space/rewind use real action demos.
static func gesture_for(id: StringName) -> Array[Vector2]:
	var empty: Array[Vector2] = []
	if id == &"loop":
		var path: Array[Vector2] = []
		for i in range(25):
			path.append(Vector2(0.5, 0.5) + Vector2(cos(i * TAU / 24), sin(i * TAU / 24)) * 0.43)
		return path
	if id == &"zigzag":
		return [Vector2(0, 0.75), Vector2(0.25, 0.2), Vector2(0.5, 0.8), Vector2(0.75, 0.2), Vector2(1, 0.7)]
	if id == &"cut":
		return [Vector2(0, 0.75), Vector2(1, 0.25)]
	return empty
