class_name LessonDemo
extends Node

## Cancellable ordinary-action demonstration driver.
## Drives the real protagonist sprite and WeaponController against real targets
## while isolating demonstration costs, history, and outcomes from the player's run.
## Waits for both the visual demonstration and tutorial speech (AudioManager.instruction_busy)
## before emitting ready_for_practice.

signal ready_for_practice(lesson_id: StringName)
signal demo_completed(lesson_id: StringName, summary: Dictionary)
signal demo_cancelled(lesson_id: StringName)

const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
const TIME_METER_LINE := "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge."

const SUPPORTED_LESSONS: Array[StringName] = [
	&"shot",
	&"charge",
	&"cut",
	&"heat",
	&"slow",
	&"opening",
	&"pair",
	&"loop",
	&"zigzag",
]

const SPECS := {
	"time_meter": {
		"heading": "Watch your time reserve",
		"subtitle": "TIME RESERVE",
		"body": TIME_METER_LINE,
		"primary_tool": 2,
		"secondary_tool": 2,
		"enemy_kind": &"yellow",
		"drawing": false,
	},
	"shot": {
		"heading": "Click to shoot",
		"subtitle": "2 · FOCUSED FLASH",
		"body": "2 · Focused Flash — aim at the yellow core.",
		"primary_tool": 2,
		"secondary_tool": 2,
		"enemy_kind": &"yellow",
		"drawing": false,
	},
	"charge": {
		"heading": "Hold, then release",
		"subtitle": "2 · FOCUSED FLASH · PIERCE",
		"body": "2 · Focused Flash — charge until bright to pierce aligned targets.",
		"primary_tool": 2,
		"secondary_tool": 2,
		"enemy_kind": &"yellow",
		"drawing": false,
	},
	"cut": {
		"heading": "Hold, draw, release",
		"subtitle": "1 · Ring Cutter — draw across the blue link.",
		"body": "1 · Ring Cutter — draw across the blue link.",
		"primary_tool": 1,
		"secondary_tool": 1,
		"enemy_kind": &"blue",
		"drawing": true,
	},
	"heat": {
		"heading": "Aim and hold",
		"subtitle": "3 · HEAT BELLOWS",
		"body": "3 · Heat Bellows — strip orange armor and push threats back.",
		"primary_tool": 3,
		"secondary_tool": 3,
		"enemy_kind": &"orange",
		"drawing": false,
	},
	"slow": {
		"heading": "Hold Space",
		"subtitle": "TIME SLOW",
		"body": "Hold Space to slow the world, shoot the target, then release.",
		"primary_tool": 2,
		"secondary_tool": 2,
		"enemy_kind": &"yellow",
		"drawing": false,
	},
	"opening": {
		"heading": "Cut or heat, then shoot",
		"subtitle": "OPEN · THEN 2 · FOCUSED FLASH",
		"body": "Open the blue link or orange armor, then switch to 2 for yellow.",
		"primary_tool": 1,
		"secondary_tool": 2,
		"enemy_kind": &"side_guard",
		"drawing": false,
	},
	"pair": {
		"heading": "Click A, then B",
		"subtitle": "2 · FOCUSED FLASH · PAIR",
		"body": "2 · Focused Flash — shoot A to open B before its shutter closes.",
		"primary_tool": 2,
		"secondary_tool": 2,
		"enemy_kind": &"pair",
		"drawing": false,
	},
	"loop": {
		"heading": "Hold, draw, release",
		"subtitle": "1 · RING CUTTER · LOOP",
		"body": "1 · Ring Cutter — cut every blue support, then charge 2 on yellow.",
		"primary_tool": 1,
		"secondary_tool": 2,
		"enemy_kind": &"loop",
		"drawing": true,
	},
	"zigzag": {
		"heading": "Hold, draw, release",
		"subtitle": "1 · RING CUTTER · ZIGZAG",
		"body": "1 · Ring Cutter — bend across each blue span, then charge 2 on yellow.",
		"primary_tool": 1,
		"secondary_tool": 2,
		"enemy_kind": &"zigzag",
		"drawing": true,
	},
}

const DEMO_STAGE_ORIGIN := Vector3(0.0, 0.0, 3.2)
const DEMO_CAMERA_OFFSET := Vector3(0.0, 13.5, 6.9)
const HEAT_START_OFFSET_Z := -2.1
const HEAT_MAX_PUSH_Z := -4.45

var active := false
var lesson_id: StringName = &""
var phase := 0
var elapsed := 0.0
var phase_elapsed := 0.0
var arena: Node3D = null
var tutorial_ui: Control = null
var audio_manager_override: Node = null
var demo_enemies: Array[Node3D] = []
var learned_demos: Dictionary = {}
var last_summary: Dictionary = {}
## When true, starting `&"shot"` while `&"time_meter"` is unlearned runs the
## staged multi-enemy `time_meter` damage demo before the yellow shot demo even
## if `tutorial.time_meter` audio is not currently active.
var prestage_time_meter_on_shot := false
var substage: StringName:
	get: return _substage

var _substage: StringName = &""
var _substage_pass_completed := false
var _terminal_state: StringName = &""
var _demo_origin := DEMO_STAGE_ORIGIN
var _demo_player_y := 0.55
var _current_aim := Vector3.ZERO
var _stroke_waypoints: Array[Vector3] = []
var _waypoint_index := 0
var _handoff_emitted := false
var _restoring := false
var _pass_completed := false
var _repeat_cooldown := 0.0
var _lmb_held_during_demo := false
var _bound_audio: Node = null
var _last_process_frame := -1
var _unawaited_sync_steps := 0

var _saved_player: Dictionary = {}
var _saved_visual_tool := 1
var _saved_camera_pos := Vector3(0.0, 20.0, 14.0)
var _saved_camera_rot := Vector3(-0.959931, 0.0, 0.0)
var _saved_camera_fov := 52.0
var _has_saved_camera := false
var _saved_equipment: Dictionary = {}
var _saved_training_protection: Array = []
var _saved_weapons: Dictionary = {}
var _saved_available_tools: Array[int] = []
var _saved_selected_tool := 1
var _saved_director: Dictionary = {}
var _saved_spawn_counter := 0
var _saved_cover_rects: Array = []
var _saved_time: Dictionary = {}
var _saved_practice: Dictionary = {}
var _disconnected_campaign_hit := false
var _disconnected_campaign_event := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	_unbind_audio_signals()
	if active:
		cancel(false)


static func handles(id: StringName) -> bool:
	return id == &"time_meter" or id in SUPPORTED_LESSONS


static func spec_for(id: StringName) -> Dictionary:
	return SPECS.get(String(id), {}).duplicate(true)


static func _game_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameState") if tree != null and tree.root != null else null


static func _scene_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SceneManager") if tree != null and tree.root != null else null


func _can_touch_world_transforms() -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(arena) or not arena.is_inside_tree() or arena.is_queued_for_deletion():
		return false
	var player: Node3D = arena.get("player") as Node3D
	if is_instance_valid(player) and not player.is_inside_tree():
		return false
	return true


func _get_audio_manager() -> Node:
	if is_instance_valid(audio_manager_override):
		return audio_manager_override
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("AudioManager") if tree != null and tree.root != null else null


func _current_speech_event_name() -> String:
	var am := _get_audio_manager()
	if am == null or not is_instance_valid(am):
		return ""
	if am.has_method("current_speech_event"):
		return String(am.call("current_speech_event"))
	return String(am.get("current_event"))


func _bind_audio_signals() -> void:
	var am := _get_audio_manager()
	if am == _bound_audio and is_instance_valid(_bound_audio):
		return
	_unbind_audio_signals()
	_bound_audio = am
	if is_instance_valid(_bound_audio):
		if _bound_audio.has_signal("speech_finished") and not _bound_audio.is_connected("speech_finished", _on_audio_speech_finished):
			_bound_audio.connect("speech_finished", _on_audio_speech_finished)


func _unbind_audio_signals() -> void:
	if is_instance_valid(_bound_audio):
		if _bound_audio.has_signal("speech_finished") and _bound_audio.is_connected("speech_finished", _on_audio_speech_finished):
			_bound_audio.disconnect("speech_finished", _on_audio_speech_finished)
	_bound_audio = null


func _on_audio_speech_finished(event: StringName, interrupted: bool = false) -> void:
	if not active or not _terminal_state.is_empty():
		return
	if interrupted or not _can_touch_world_transforms():
		if not _can_touch_world_transforms():
			cancel(false)
		return
	if lesson_id == &"shot" and _substage == &"time_meter" and _substage_pass_completed:
		if String(event) == "tutorial.time_meter" or _current_speech_event_name() != "tutorial.time_meter":
			_transition_prestage_to_shot()
			return
	if _pass_completed and not is_instruction_speech_busy():
		_complete_and_handoff()


func is_instruction_speech_busy() -> bool:
	var am := _get_audio_manager()
	if am == null or not is_instance_valid(am):
		return false
	if am.has_method("instruction_busy"):
		return bool(am.call("instruction_busy"))
	var gs := _game_state()
	if gs != null and gs.has_method("preferences"):
		var prefs: Dictionary = gs.call("preferences")
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


func _clean_demo_combat_speech() -> void:
	var am := _get_audio_manager()
	if am == null or not is_instance_valid(am):
		return
	var q: Variant = am.get("_queue")
	if q is Array:
		for i in range(q.size() - 1, -1, -1):
			var item: Variant = q[i]
			var ev_name := String(item.get("event", "")) if item is Dictionary else (String(item) if item is String else "")
			if ev_name.begins_with("combat.") or ev_name.begins_with("protagonist."):
				q.remove_at(i)
	var cur_ev := String(am.get("current_event"))
	if cur_ev.begins_with("combat.") or cur_ev.begins_with("protagonist."):
		if am.has_method("stop_dialogue"):
			am.call("stop_dialogue")
		var vp := am.get_node_or_null("Voice") as AudioStreamPlayer
		if vp != null:
			vp.stop()
			vp.stream = null


func is_demo_learned(id: StringName, overlay: Control = null) -> bool:
	if bool(learned_demos.get(id, false)):
		return true
	var ui := overlay if overlay != null else tutorial_ui
	if is_instance_valid(ui) and ui.has_method("is_learned") and bool(ui.call("is_learned", id)):
		return true
	var gs := _game_state()
	if gs != null and gs.has_method("preferences") and not bool(gs.call("preferences").get("tutorial", true)):
		return true
	return false


func _mark_time_meter_learned(complete_card: bool = false) -> void:
	learned_demos[&"time_meter"] = true
	if is_instance_valid(tutorial_ui):
		if "learned" in tutorial_ui and tutorial_ui.get("learned") is Dictionary:
			tutorial_ui.learned[&"time_meter"] = true
		if complete_card and tutorial_ui.get("active_id") == &"time_meter" and tutorial_ui.has_method("complete_lesson"):
			tutorial_ui.call("complete_lesson", &"time_meter")


func mark_learned(id: StringName) -> void:
	if not id.is_empty():
		learned_demos[id] = true


func reset_run() -> void:
	if active:
		cancel()
	learned_demos.clear()
	last_summary.clear()


func _is_time_meter_speech_active_or_queued() -> bool:
	if _current_speech_event_name() == "tutorial.time_meter":
		return true
	var am := _get_audio_manager()
	if am == null or not is_instance_valid(am):
		return false
	var q_real: Variant = am.get("_queue")
	if q_real is Array:
		for item in q_real:
			if item is Dictionary and String(item.get("event", "")) == "tutorial.time_meter":
				return true
	var q_mock: Variant = am.get("queue")
	if q_mock is Array:
		for ev in q_mock:
			if String(ev) == "tutorial.time_meter":
				return true
	return false


func _should_prestage_time_meter(id: StringName, overlay: Control = null) -> bool:
	if id != &"shot":
		return false
	if is_demo_learned(&"time_meter", overlay) or bool(learned_demos.get(&"time_meter", false)):
		return false
	if prestage_time_meter_on_shot:
		return true
	return _is_time_meter_speech_active_or_queued()


func begin(target_arena: Node3D, id: StringName, overlay: Control = null) -> bool:
	if target_arena == null or not is_instance_valid(target_arena) or not handles(id):
		return false
	if is_demo_learned(id, overlay):
		return false
	if active:
		cancel()

	arena = target_arena
	tutorial_ui = overlay
	lesson_id = id
	_substage = &"time_meter" if _should_prestage_time_meter(id, overlay) else id
	_substage_pass_completed = false
	_terminal_state = &""
	phase = 0
	elapsed = 0.0
	phase_elapsed = 0.0
	_handoff_emitted = false
	_pass_completed = false
	_repeat_cooldown = 0.0
	_lmb_held_during_demo = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_last_process_frame = Engine.get_process_frames()
	_unawaited_sync_steps = 0
	_stroke_waypoints.clear()
	_waypoint_index = 0

	var spec := spec_for(_substage)
	var main_spec := spec_for(id)
	var p_tool := int(main_spec.get("primary_tool", 2))
	var tc_ref: TimeController = arena.get("time_controller") as TimeController
	var start_meter := tc_ref.capacity if is_instance_valid(tc_ref) else 60.0
	last_summary = {
		"lesson_id": id,
		"tools_used": [p_tool],
		"shot_fired": false,
		"charged_shot_fired": false,
		"max_charge": 0.0,
		"pierced": false,
		"pierce_kills": 0,
		"ring_drawn": false,
		"ring_launched": false,
		"cable_cut": false,
		"cone_held": false,
		"plate_broken": false,
		"knocked_back": false,
		"heat_knockback_seen": false,
		"heat_knockback_distance": 0.0,
		"slow_engaged": false,
		"min_world_scale": 1.0,
		"shot_during_slow": false,
		"slow_resumed": false,
		"max_world_scale_after_slow": 0.0,
		"opened_before_finish": false,
		"yellow_finished_after_open": false,
		"time_meter_drained": false,
		"time_meter_restored": false,
		"time_meter_prestage_completed": false,
		"time_meter_restored_before_shot": false,
		"enemies_attacked": 0,
		"time_meter_hits": 0,
		"initial_time_meter": start_meter,
		"min_time_meter": start_meter,
		"time_meter_min": start_meter,
		"target_killed": false,
		"completed": false,
		"cancelled": false,
		"skipped": false,
		"isolated_restore_verified": false,
		"waited_for_speech": false,
		"visual_passes": 0,
	}

	_capture_baseline()
	_setup_demo_stage(_substage, spec)
	active = true
	_bind_audio_signals()

	if is_instance_valid(tutorial_ui):
		if tutorial_ui.has_method("set_demo_busy"):
			tutorial_ui.call("set_demo_busy", true)
		if tutorial_ui.get("active_id") != id:
			tutorial_ui.call("show_known_lesson", id, current_targets())
		else:
			tutorial_ui.world_points.assign(current_targets())
		if tutorial_ui.has_method("set_demo_busy"):
			tutorial_ui.call("set_demo_busy", true)
		if _substage == &"time_meter" and tutorial_ui.has_method("set_phase_prompt"):
			tutorial_ui.set("draw_style", &"time")
			tutorial_ui.call("set_phase_prompt", String(spec.get("heading", "")), String(spec.get("body", "")), ToolStyle.CLOCK, String(spec.get("subtitle", "TIME RESERVE")))
		elif id == &"opening" and tutorial_ui.has_method("set_phase_accent"):
			tutorial_ui.call("set_phase_accent", ToolStyle.RING, "1 · RING CUTTER · OPEN BLUE LINK")
		if tutorial_ui.has_signal("skip_requested") and not tutorial_ui.skip_requested.is_connected(_on_tutorial_skip_requested):
			tutorial_ui.skip_requested.connect(_on_tutorial_skip_requested)
		if tutorial_ui.has_signal("resume_requested") and not tutorial_ui.resume_requested.is_connected(_on_tutorial_resume_requested):
			tutorial_ui.resume_requested.connect(_on_tutorial_resume_requested)
		if tutorial_ui.has_signal("lesson_completed") and not tutorial_ui.lesson_completed.is_connected(_on_tutorial_lesson_completed):
			tutorial_ui.lesson_completed.connect(_on_tutorial_lesson_completed)

	if not arena.tree_exiting.is_connected(_on_arena_tree_exiting):
		arena.tree_exiting.connect(_on_arena_tree_exiting)

	return true


func _input(event: InputEvent) -> void:
	if not active:
		return
	if _is_paused_or_covered():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_lmb_held_during_demo = event.pressed
			if event.pressed and is_instance_valid(tutorial_ui) and tutorial_ui.has_method("is_point_on_skip_button") and bool(tutorial_ui.call("is_point_on_skip_button", event.position)):
				if tutorial_ui.has_method("skip_active_lesson"):
					tutorial_ui.call("skip_active_lesson", true)
				else:
					skip_to_practice()
		if is_inside_tree() and get_viewport() != null:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if code in [KEY_ESCAPE, KEY_F10, KEY_M, KEY_F7]:
			return
		if code in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E, KEY_1, KEY_2, KEY_3, KEY_TAB, KEY_W, KEY_A, KEY_S, KEY_D]:
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()


func is_visual_pass_completed() -> bool:
	return _pass_completed


func step(real_delta: float) -> void:
	if not active:
		return
	if not _can_touch_world_transforms():
		cancel(false)
		return
	var gs := _game_state()
	if gs != null and gs.has_method("preferences") and not bool(gs.call("preferences").get("tutorial", true)):
		skip_to_practice()
		return
	if _is_paused_or_covered():
		_suspend_active_inputs()
		return

	var dt := clampf(real_delta, 0.0, 0.05)
	if dt <= 0.0:
		return

	_bind_audio_signals()
	var cur_frame := Engine.get_process_frames()
	if cur_frame == _last_process_frame:
		_unawaited_sync_steps += 1
	else:
		_last_process_frame = cur_frame
		_unawaited_sync_steps = 0

	# If a legacy synchronous test loops >=140 ticks in a single un-awaited frame without
	# advancing SceneTree process frames, release real AudioStreamPlayer playback.
	if _unawaited_sync_steps >= 140 and _pass_completed:
		var am := _get_audio_manager()
		var root_am := get_tree().root.get_node_or_null("AudioManager") if is_inside_tree() else null
		if am != null and am == root_am and am.has_method("stop_dialogue"):
			am.call("stop_dialogue")

	if lesson_id == &"shot" and _substage == &"time_meter" and _substage_pass_completed:
		if _current_speech_event_name() != "tutorial.time_meter" or not is_instruction_speech_busy() or _unawaited_sync_steps >= 55:
			_transition_prestage_to_shot()

	if _pass_completed and not is_instruction_speech_busy():
		_complete_and_handoff()
		return

	elapsed += dt
	phase_elapsed += dt

	var tc: TimeController = arena.get("time_controller") as TimeController
	if _substage == &"slow" and is_instance_valid(tc):
		tc.advance(dt)
		var ws := tc.world_scale
		last_summary["min_world_scale"] = minf(float(last_summary["min_world_scale"]), ws)
		if phase >= 4:
			last_summary["max_world_scale_after_slow"] = maxf(float(last_summary["max_world_scale_after_slow"]), ws)
	elif _substage == &"time_meter" and is_instance_valid(tc) and phase >= 3:
		tc.advance(dt)
	var world_scale := tc.world_scale if (_substage == &"slow" and is_instance_valid(tc)) else 1.0
	var world_dt := dt * world_scale

	_step_lesson_choreography(dt, world_dt)
	if not active:
		return

	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	var director: Node3D = arena.get("director") as Node3D

	if is_instance_valid(player):
		player.position = Vector3(_demo_origin.x, _demo_player_y, _demo_origin.z)
		if player.has_method("reset_input"):
			player.call("reset_input")
		if player.has_method("_face"):
			player.call("_face", _current_aim)
		var visual: Node3D = player.get("visual") as Node3D
		if is_instance_valid(visual) and visual.has_method("step_visual"):
			visual.call("step_visual", world_dt, 0.0, float(Tuning.PLAYER.speed), Vector3.ZERO)

	if is_instance_valid(director):
		director.call("step", world_dt, player)

	if is_instance_valid(weapons):
		weapons.call("step", dt, player, _current_aim, director.enemies if is_instance_valid(director) else [], world_dt)
		if is_instance_valid(weapons.flash):
			last_summary["max_charge"] = maxf(float(last_summary["max_charge"]), float(weapons.flash.charge))
		_sustain_demo_weapon_visuals(player, weapons)
	_clean_demo_combat_speech()

	_observe_demo_targets()

	if is_instance_valid(tutorial_ui) and tutorial_ui.get("active_id") == lesson_id:
		if lesson_id == &"shot" and (_substage == &"time_meter" or _current_speech_event_name() == "tutorial.time_meter") and tutorial_ui.has_method("set_phase_prompt"):
			var tm_spec := spec_for(&"time_meter")
			tutorial_ui.set("draw_style", &"time")
			tutorial_ui.call("set_phase_prompt", String(tm_spec.get("heading", "")), String(tm_spec.get("body", "")), ToolStyle.CLOCK, String(tm_spec.get("subtitle", "TIME RESERVE")))
		var pts := current_targets()
		if not pts.is_empty():
			tutorial_ui.world_points.assign(pts)

	var status_hud: Node = arena.get("status_hud") as Node
	if is_instance_valid(status_hud) and is_instance_valid(player) and is_instance_valid(weapons):
		status_hud.call("update_status", player, weapons, arena.get("equipment"))
	var time_cue: Node = arena.get("time_cue") as Node
	if is_instance_valid(time_cue) and time_cue.has_method("update_state"):
		time_cue.call("update_state", world_scale, false)

	_check_phase_completion(dt)


func skip_to_practice() -> void:
	if not active or not _terminal_state.is_empty():
		return
	_terminal_state = &"skipped"
	var id := lesson_id
	if _substage == &"time_meter" or id == &"time_meter":
		_mark_time_meter_learned(id == &"time_meter")
	last_summary["skipped"] = true
	var am := _get_audio_manager()
	if is_instance_valid(am) and am.has_method("stop_dialogue"):
		am.call("stop_dialogue")
	_teardown_demo(true)
	_emit_practice_handoff(id)


func cancel(restore_world: bool = true) -> void:
	if not active or not _terminal_state.is_empty():
		return
	_terminal_state = &"cancelled"
	var id := lesson_id
	last_summary["cancelled"] = true
	_teardown_demo(restore_world and _can_touch_world_transforms())
	demo_cancelled.emit(id)


func current_targets() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var active_stage := _substage if not _substage.is_empty() else lesson_id
	for enemy in demo_enemies:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree() or float(enemy.get("health")) <= 0.0:
			continue
		if active_stage == &"pair" and enemy.has_method("valve_world_position"):
			var prog := int(enemy.get("pair_progress"))
			if prog <= 0 and not bool(enemy.get("pattern_open")):
				pts.append(enemy.call("valve_world_position", 0))
				pts.append(enemy.call("valve_world_position", 1))
			else:
				pts.append(enemy.call("valve_world_position", clampi(prog, 0, 1)))
		elif active_stage == &"heat" and is_instance_valid(enemy.get("part_visual")) and is_instance_valid(enemy.part_visual.get("plate")) and enemy.part_visual.plate.is_inside_tree():
			pts.append(enemy.part_visual.plate.global_position + Vector3.UP * 0.5)
		elif active_stage in [&"cut", &"opening", &"loop", &"zigzag"] and enemy.has_method("has_cuttable_part") and bool(enemy.call("has_cuttable_part")):
			var cable: Array = enemy.call("cable_world_points")
			if enemy.has_method("lesson_state"):
				for i in range(0, cable.size() - 1, 2):
					pts.append((cable[i] + cable[i + 1]) * 0.5)
			elif cable.size() >= 2:
				pts.append((cable[0] + cable[-1]) * 0.5)
		elif enemy.has_method("core_world_position"):
			pts.append(enemy.call("core_world_position"))
		else:
			pts.append(enemy.position + Vector3.UP)
	if pts.is_empty() and is_instance_valid(arena) and is_instance_valid(arena.get("player")):
		pts.append(_demo_origin + Vector3(0.0, 1.0, -4.8))
	return pts


func _is_paused_or_covered() -> bool:
	var gs := _game_state()
	if gs != null and gs.has_method("is_paused") and bool(gs.call("is_paused")):
		return true
	var sm := _scene_manager()
	if sm != null and sm.has_method("has_popup"):
		for popup_key in [&"PauseMenu", &"Settings", &"Developer", &"RunResult"]:
			if bool(sm.call("has_popup", popup_key)):
				return true
	return false


func _suspend_active_inputs() -> void:
	if not is_instance_valid(arena):
		return
	var player: Node3D = arena.get("player") as Node3D
	if is_instance_valid(player) and player.has_method("reset_input"):
		player.call("reset_input")


func _capture_baseline() -> void:
	var player: Node3D = arena.get("player") as Node3D
	var equipment: WeaponEquipment = arena.get("equipment") as WeaponEquipment
	var weapons: Node3D = arena.get("weapons") as Node3D
	var director: Node3D = arena.get("director") as Node3D
	var tc: TimeController = arena.get("time_controller") as TimeController
	var cover: RefCounted = arena.get("cover") as RefCounted

	_saved_player = player.call("capture_state").duplicate(true) if is_instance_valid(player) else {}
	_saved_visual_tool = int(player.get("visual_tool")) if is_instance_valid(player) else 1
	_has_saved_camera = false
	if is_instance_valid(player) and is_instance_valid(player.get("camera")):
		var cam: Camera3D = player.get("camera") as Camera3D
		_saved_camera_pos = cam.position
		_saved_camera_rot = cam.rotation
		_saved_camera_fov = cam.fov
		_has_saved_camera = true
	_saved_equipment = equipment.capture_state().duplicate(true) if equipment != null else {}
	_saved_training_protection = equipment.training_protection.duplicate() if equipment != null else []
	_saved_weapons = weapons.call("capture_state").duplicate(true) if is_instance_valid(weapons) else {}
	_saved_available_tools.clear()
	if is_instance_valid(weapons):
		for slot in weapons.get("available_tools"):
			_saved_available_tools.append(int(slot))
		_saved_selected_tool = int(weapons.get("selected_tool"))
	_saved_director = director.call("capture_state").duplicate(true) if is_instance_valid(director) else {}
	_saved_spawn_counter = int(director.get("_spawn_counter")) if is_instance_valid(director) else 0
	_saved_cover_rects = cover.rectangles.duplicate() if cover != null else []
	if is_instance_valid(tc):
		_saved_time = {
			"meter": tc.meter,
			"slow_requested": tc.slow_requested,
			"slow_unlocked": tc.slow_unlocked,
			"rewind_unlocked": tc.rewind_unlocked,
			"charges": tc.charges_remaining,
		}
	else:
		_saved_time = {}
	_saved_practice = arena.call("_capture_practice").duplicate(true) if arena.has_method("_capture_practice") else {}

	_disconnected_campaign_hit = false
	_disconnected_campaign_event = false
	if is_instance_valid(weapons):
		if arena.has_method("_on_resolved_hit") and weapons.resolved_hit.is_connected(Callable(arena, "_on_resolved_hit")):
			weapons.resolved_hit.disconnect(Callable(arena, "_on_resolved_hit"))
			_disconnected_campaign_hit = true
		if arena.has_method("_on_run_event") and weapons.combat_event.is_connected(Callable(arena, "_on_run_event")):
			weapons.combat_event.disconnect(Callable(arena, "_on_run_event"))
			_disconnected_campaign_event = true
		if arena.has_method("_on_combat_dialogue") and weapons.combat_event.is_connected(Callable(arena, "_on_combat_dialogue")):
			weapons.combat_event.disconnect(Callable(arena, "_on_combat_dialogue"))
		if not weapons.resolved_hit.is_connected(_on_demo_resolved_hit):
			weapons.resolved_hit.connect(_on_demo_resolved_hit)
		if not weapons.combat_event.is_connected(_on_demo_combat_event):
			weapons.combat_event.connect(_on_demo_combat_event)
	if is_instance_valid(director):
		if arena.has_method("_on_enemy_dialogue") and director.enemy_event.is_connected(Callable(arena, "_on_enemy_dialogue")):
			director.enemy_event.disconnect(Callable(arena, "_on_enemy_dialogue"))


func _setup_demo_stage(id: StringName, spec: Dictionary) -> void:
	if not _can_touch_world_transforms():
		return
	var player: Node3D = arena.get("player") as Node3D
	var equipment: WeaponEquipment = arena.get("equipment") as WeaponEquipment
	var weapons: Node3D = arena.get("weapons") as Node3D
	var director: Node3D = arena.get("director") as Node3D
	var cover: RefCounted = arena.get("cover") as RefCounted
	var tc: TimeController = arena.get("time_controller") as TimeController

	_clear_all_controls()
	if cover != null:
		cover.rectangles.clear()
	if is_instance_valid(director):
		director.call("clear")
	if equipment != null:
		equipment.set_training_protection([&"ring", &"beam", &"cone"])
		for tool_name in [&"ring", &"beam", &"cone"]:
			equipment.restore_tool(tool_name, 1.0)

	var raw_pos: Vector3 = _saved_player.get("position", Vector3(0.0, 0.55, 0.0))
	_demo_player_y = raw_pos.y
	_demo_origin = DEMO_STAGE_ORIGIN
	if is_instance_valid(player) and player.is_inside_tree():
		player.position = Vector3(_demo_origin.x, _demo_player_y, _demo_origin.z)
		player.reset_physics_interpolation()
		var cam: Camera3D = player.get("camera") as Camera3D
		if is_instance_valid(cam) and cam.is_inside_tree():
			cam.position = DEMO_CAMERA_OFFSET
			cam.reset_physics_interpolation()
			cam.force_update_transform()

	var p_tool := int(spec.get("primary_tool", 2))
	if is_instance_valid(weapons) and weapons.is_inside_tree():
		var all_tools: Array[int] = [1, 2, 3]
		weapons.call("set_loadout", all_tools, p_tool)
		weapons.call("select_tool", p_tool)
		weapons.call("reset_state")
		weapons.call("select_tool", p_tool)
	if is_instance_valid(player) and player.is_inside_tree() and player.has_method("set_visual_tool"):
		player.call("set_visual_tool", p_tool)

	if id == &"time_meter" and is_instance_valid(tc):
		tc.slow_requested = false
		tc.set("_slow_active", false)
		tc.set("_world_scale", 1.0)
		tc.set("_meter", tc.capacity)
		last_summary["initial_time_meter"] = tc.meter
		last_summary["min_time_meter"] = tc.meter

	demo_enemies.clear()
	if is_instance_valid(director):
		if id == &"time_meter":
			var left_attacker: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(-1.35, 0.0, -2.0))
			var right_attacker: Node3D = director.call("spawn", &"orange", _demo_origin + Vector3(1.35, 0.0, -2.2))
			for enemy in [left_attacker, right_attacker]:
				if is_instance_valid(enemy):
					_prepare_demo_enemy(enemy)
					demo_enemies.append(enemy)
		elif id == &"charge":
			var front: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(0.0, 0.0, -4.2))
			var back: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(0.0, 0.0, -7.2))
			for enemy in [front, back]:
				if is_instance_valid(enemy):
					_prepare_demo_enemy(enemy)
					demo_enemies.append(enemy)
		elif id == &"heat":
			var orange: Node3D = director.call("spawn", &"orange", _demo_origin + Vector3(0.0, 0.0, HEAT_START_OFFSET_Z))
			if is_instance_valid(orange):
				_prepare_demo_enemy(orange)
				demo_enemies.append(orange)
		elif id == &"slow":
			var mover: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(-1.8, 0.0, -4.8))
			if is_instance_valid(mover):
				_prepare_demo_enemy(mover)
				demo_enemies.append(mover)
		elif id in [&"pair", &"loop", &"zigzag"]:
			var pat: Node3D = director.call("spawn", spec.get("enemy_kind", id), _demo_origin + Vector3(0.0, 0.0, -5.2))
			if is_instance_valid(pat):
				_prepare_demo_enemy(pat)
				demo_enemies.append(pat)
		else:
			var single: Node3D = director.call("spawn", spec.get("enemy_kind", &"yellow"), _demo_origin + Vector3(0.0, 0.0, -4.8))
			if is_instance_valid(single):
				_prepare_demo_enemy(single)
				demo_enemies.append(single)

	if arena.get("specimens") is Array and arena.get("_specimen_ids") is Array:
		arena.specimens.assign(demo_enemies)
		arena._specimen_ids.clear()
		for de in demo_enemies:
			if is_instance_valid(de):
				arena._specimen_ids.append(int(de.get("rewind_id")))

	_build_stroke_waypoints(id)
	var init_targets := current_targets()
	_current_aim = init_targets[0] if not init_targets.is_empty() else (_demo_origin + Vector3(0.0, 0.0, -4.8))
	if is_instance_valid(player) and player.is_inside_tree() and player.has_method("_face"):
		player.call("_face", _current_aim)
	if is_instance_valid(weapons) and weapons.is_inside_tree() and is_instance_valid(player) and player.is_inside_tree():
		weapons.call("rebuild_visuals", player)


func _transition_prestage_to_shot() -> void:
	if not active or not _can_touch_world_transforms():
		return
	_mark_time_meter_learned(false)
	last_summary["time_meter_prestage_completed"] = true
	var tc: TimeController = arena.get("time_controller") as TimeController
	if is_instance_valid(tc):
		var restored_meter: float = float(_saved_time.get("meter", tc.capacity))
		tc.slow_requested = false
		tc.set("_slow_active", false)
		tc.set("_world_scale", 1.0)
		tc.set("_meter", restored_meter)
		last_summary["time_meter_restored"] = true
		last_summary["time_meter_restored_before_shot"] = is_equal_approx(tc.meter, restored_meter)
	var player: Node3D = arena.get("player") as Node3D
	if is_instance_valid(player) and not _saved_player.is_empty():
		player.call("restore_state", _saved_player)
	_substage = &"shot"
	_substage_pass_completed = false
	_pass_completed = false
	phase = 0
	phase_elapsed = 0.0
	_repeat_cooldown = 0.0
	_waypoint_index = 0
	last_summary["target_killed"] = false
	last_summary["shot_fired"] = false
	var shot_spec := spec_for(&"shot")
	_setup_demo_stage(&"shot", shot_spec)
	if is_instance_valid(tutorial_ui):
		tutorial_ui.set("draw_style", &"")
		if tutorial_ui.has_method("set_waiting_for_speech"):
			tutorial_ui.call("set_waiting_for_speech", false)
		if tutorial_ui.has_method("set_phase_prompt"):
			tutorial_ui.call("set_phase_prompt", String(shot_spec.get("heading", "")), String(shot_spec.get("body", "")), ToolStyle.BEAM, String(shot_spec.get("subtitle", "")))
		tutorial_ui.world_points.assign(current_targets())
	var status_hud: Node = arena.get("status_hud") as Node
	var weapons: Node3D = arena.get("weapons") as Node3D
	if is_instance_valid(status_hud) and is_instance_valid(player) and is_instance_valid(weapons):
		status_hud.call("update_status", player, weapons, arena.get("equipment"))


func _restart_demo_pass() -> void:
	if not active or not _can_touch_world_transforms():
		return
	var stage_id := _substage if not _substage.is_empty() else lesson_id
	var spec := spec_for(stage_id)
	phase = 0
	phase_elapsed = 0.0
	_repeat_cooldown = 0.0
	_waypoint_index = 0
	if is_instance_valid(tutorial_ui) and tutorial_ui.has_method("set_phase_prompt"):
		var base_col: Color = ToolStyle.CLOCK if stage_id == &"time_meter" else (tutorial_ui.call("accent_for_lesson", stage_id) if tutorial_ui.has_method("accent_for_lesson") else ToolStyle.BEAM)
		var base_sub: String = tutorial_ui.call("subtitle_for_lesson", stage_id) if tutorial_ui.has_method("subtitle_for_lesson") else String(spec.get("subtitle", ""))
		tutorial_ui.set("draw_style", &"time" if stage_id == &"time_meter" else &"")
		tutorial_ui.call("set_phase_prompt", String(spec.get("heading", "")), String(spec.get("body", "")), base_col, base_sub)
	_setup_demo_stage(stage_id, spec)


func _prepare_demo_enemy(enemy: Node3D) -> void:
	enemy.set("contact_damage", 0.0)
	enemy.set("move_speed", 0.0)
	enemy.set("facing", Vector3.BACK)
	if "projectile_damage" in enemy:
		enemy.set("projectile_damage", 0.0)
	if "attack_timer" in enemy:
		enemy.set("attack_timer", 99.0)
	if enemy.has_method("set_instruction_visible"):
		enemy.call("set_instruction_visible", false)
	if "part_visual" in enemy and is_instance_valid(enemy.get("part_visual")) and enemy.part_visual.has_method("set_instruction_visible"):
		enemy.part_visual.call("set_instruction_visible", true)
	if "pattern_visual" in enemy and is_instance_valid(enemy.get("pattern_visual")) and enemy.pattern_visual.has_method("set_instruction_visible"):
		enemy.pattern_visual.call("set_instruction_visible", true)
	_suppress_enemy_overhead_labels(enemy)


func _suppress_enemy_overhead_labels(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	var vroot := enemy.get("visual_root") as Node
	if is_instance_valid(vroot):
		var vinst := vroot.get("instruction") as Node3D
		if is_instance_valid(vinst):
			vinst.visible = false
	var pv := enemy.get("part_visual") as Node
	if is_instance_valid(pv):
		var pinst := pv.get("instruction") as Node3D
		if is_instance_valid(pinst):
			pinst.visible = false
	var patv := enemy.get("pattern_visual") as Node
	if is_instance_valid(patv):
		var cdown := patv.get("countdown") as Node3D
		if is_instance_valid(cdown):
			cdown.visible = false


func _build_stroke_waypoints(id: StringName) -> void:
	_stroke_waypoints.clear()
	_waypoint_index = 0
	if demo_enemies.is_empty() or not is_instance_valid(demo_enemies[0]):
		return
	var enemy := demo_enemies[0]
	if not enemy.has_method("cable_world_points"):
		return
	var pts: Array = enemy.call("cable_world_points")
	if id in [&"cut", &"opening"] and pts.size() >= 2:
		var a := Vector3(pts[0].x, 0.0, pts[0].z)
		var b := Vector3(pts[1].x, 0.0, pts[1].z)
		var dir := (b - a).normalized() if b.distance_to(a) > 0.01 else Vector3.RIGHT
		var start := a - dir * 1.05
		var finish := b + dir * 1.05
		for i in range(13):
			_stroke_waypoints.append(start.lerp(finish, float(i) / 12.0))
	elif id == &"loop" and pts.size() >= 8:
		var mids: Array[Vector3] = []
		for i in range(4):
			var m: Vector3 = (pts[i * 2] + pts[i * 2 + 1]) * 0.5
			mids.append(Vector3(m.x, 0.0, m.z))
		var anchors: Array[Vector3] = [
			mids[0] + Vector3(-0.35, 0.0, 0.35),
			mids[0],
			mids[1],
			mids[2],
			mids[3],
			mids[0] + Vector3(0.35, 0.0, -0.35),
		]
		_append_densified_waypoints(anchors, 6)
	elif id == &"zigzag" and pts.size() >= 6:
		var m0: Vector3 = (pts[0] + pts[1]) * 0.5
		var m1: Vector3 = (pts[2] + pts[3]) * 0.5
		var m2: Vector3 = (pts[4] + pts[5]) * 0.5
		var d0 := (Vector3(pts[1].x, 0.0, pts[1].z) - Vector3(pts[0].x, 0.0, pts[0].z)).normalized()
		var d2 := (Vector3(pts[5].x, 0.0, pts[5].z) - Vector3(pts[4].x, 0.0, pts[4].z)).normalized()
		var anchors: Array[Vector3] = [
			Vector3(pts[0].x, 0.0, pts[0].z) - d0 * 0.45,
			Vector3(m0.x, 0.0, m0.z),
			Vector3(pts[1].x, 0.0, pts[1].z) + d0 * 0.25,
			Vector3(m1.x, 0.0, m1.z),
			Vector3(pts[4].x, 0.0, pts[4].z) - d2 * 0.25,
			Vector3(m2.x, 0.0, m2.z),
			Vector3(pts[5].x, 0.0, pts[5].z) + d2 * 0.45,
		]
		_append_densified_waypoints(anchors, 5)


func _append_densified_waypoints(anchors: Array[Vector3], subdivisions: int) -> void:
	for i in range(anchors.size() - 1):
		for s in range(subdivisions):
			_stroke_waypoints.append(anchors[i].lerp(anchors[i + 1], float(s) / float(subdivisions)))
	if not anchors.is_empty():
		_stroke_waypoints.append(anchors[-1])


func _record_tool_used(tool_slot: int) -> void:
	var used: Array = last_summary.get("tools_used", [])
	if tool_slot not in used:
		used.append(tool_slot)
		last_summary["tools_used"] = used


func _switch_demo_tool(tool_slot: int, phase_color: Color = Color.WHITE, subtitle: String = "", heading_override: String = "", body_override: String = "") -> void:
	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	if is_instance_valid(weapons):
		weapons.call("select_tool", tool_slot)
		weapons.set("require_fresh_press", false)
	if is_instance_valid(player) and player.is_inside_tree() and player.has_method("set_visual_tool"):
		player.call("set_visual_tool", tool_slot)
	_record_tool_used(tool_slot)
	if is_instance_valid(tutorial_ui):
		if (not heading_override.is_empty() or not body_override.is_empty()) and tutorial_ui.has_method("set_phase_prompt"):
			tutorial_ui.call("set_phase_prompt", heading_override, body_override, phase_color, subtitle)
		elif tutorial_ui.has_method("set_phase_accent") and phase_color != Color.WHITE:
			tutorial_ui.call("set_phase_accent", phase_color, subtitle)


func _advance_phase(next_phase: int) -> void:
	phase = next_phase
	phase_elapsed = 0.0


func _apply_staged_time_meter_hit(attacker: Node3D, meter_drain: float) -> void:
	var tc: TimeController = arena.get("time_controller") as TimeController
	var player: Node3D = arena.get("player") as Node3D
	var feedback: Node = arena.get("feedback") as Node
	if is_instance_valid(tc):
		var drop := maxf(meter_drain, tc.capacity * 0.28)
		var next_meter := maxf(18.0, tc.meter - drop)
		if tc.has_method("_set_meter"):
			tc.call("_set_meter", next_meter)
		else:
			tc.set("_meter", next_meter)
		var min_m := minf(float(last_summary.get("min_time_meter", tc.capacity)), next_meter)
		last_summary["min_time_meter"] = min_m
		last_summary["time_meter_min"] = min_m
		last_summary["time_meter_drained"] = next_meter < float(last_summary.get("initial_time_meter", tc.capacity)) - 1.0
	var hits := int(last_summary.get("enemies_attacked", 0)) + 1
	last_summary["enemies_attacked"] = hits
	last_summary["time_meter_hits"] = hits
	if is_instance_valid(player):
		if "_hit_flash" in player:
			player.set("_hit_flash", 0.35)
		if is_instance_valid(feedback) and feedback.has_method("cue") and player.is_inside_tree():
			feedback.call("cue", &"player_hurt", player.global_position, 0.85)
	if is_instance_valid(attacker) and "attack_flash" in attacker:
		attacker.set("attack_flash", 0.3)
	if "_damage_flash" in arena:
		arena.set("_damage_flash", 0.35)
	_clean_demo_combat_speech()


func _sustain_demo_weapon_visuals(player: Node3D, weapons: Node3D) -> void:
	if not is_instance_valid(weapons) or not weapons.is_inside_tree() or not is_instance_valid(weapons.flash):
		return
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var active_stage := _substage if not _substage.is_empty() else lesson_id
	var flash: FocusedFlash = weapons.flash
	var keep_beam := false
	if active_stage == &"shot" and phase == 2 and phase_elapsed < 0.28:
		flash.flash_timer = maxf(flash.flash_timer, 0.12)
		flash.flash_charge = maxf(flash.flash_charge, 0.45)
		keep_beam = true
	elif active_stage == &"charge" and phase == 2 and bool(last_summary.get("pierced", false)) and phase_elapsed < 0.30:
		flash.pulses.clear()
		flash.end_point = _demo_origin + Vector3(0.0, 0.0, -8.6)
		flash.flash_charge = 1.0
		flash.flash_timer = maxf(flash.flash_timer, 0.14)
		keep_beam = true
	elif active_stage == &"slow" and phase == 3 and phase_elapsed < 0.24:
		flash.flash_timer = maxf(flash.flash_timer, 0.12)
		flash.flash_charge = maxf(flash.flash_charge, 0.45)
		keep_beam = true
	elif active_stage == &"opening" and phase == 4 and phase_elapsed < 0.26:
		flash.flash_timer = maxf(flash.flash_timer, 0.12)
		flash.flash_charge = maxf(flash.flash_charge, 0.5)
		keep_beam = true
	elif active_stage == &"pair" and ((phase == 1 and phase_elapsed < 0.22) or (phase == 3 and phase_elapsed < 0.26)):
		flash.flash_timer = maxf(flash.flash_timer, 0.12)
		flash.flash_charge = maxf(flash.flash_charge, 0.45)
		keep_beam = true
	elif active_stage in [&"loop", &"zigzag"] and phase == 5 and bool(last_summary.get("target_killed", false)) and phase_elapsed < 0.28:
		flash.pulses.clear()
		flash.end_point = _demo_origin + Vector3(0.0, 0.0, -6.2)
		flash.flash_charge = 1.0
		flash.flash_timer = maxf(flash.flash_timer, 0.14)
		keep_beam = true
	if keep_beam:
		weapons.call("rebuild_visuals", player)


func _step_lesson_choreography(_dt: float, world_dt: float) -> void:
	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	var tc: TimeController = arena.get("time_controller") as TimeController
	if not is_instance_valid(player) or not is_instance_valid(weapons):
		return
	var enemy: Node3D = demo_enemies[0] if (not demo_enemies.is_empty() and is_instance_valid(demo_enemies[0]) and demo_enemies[0].is_inside_tree()) else null
	var active_stage := _substage if not _substage.is_empty() else lesson_id

	match active_stage:
		&"time_meter":
			var second_enemy: Node3D = demo_enemies[1] if (demo_enemies.size() > 1 and is_instance_valid(demo_enemies[1]) and demo_enemies[1].is_inside_tree()) else null
			if phase == 0:
				if enemy != null:
					var lunge_a := clampf(phase_elapsed / 0.24, 0.0, 1.0)
					enemy.position = (_demo_origin + Vector3(-1.35, 0.0, -2.0)).lerp(_demo_origin + Vector3(-0.55, 0.0, -0.75), lunge_a)
					enemy.set("facing", (_demo_origin - enemy.position).normalized())
					_current_aim = enemy.position
				if second_enemy != null:
					var approach_b := clampf(phase_elapsed / 0.24, 0.0, 1.0)
					second_enemy.position = (_demo_origin + Vector3(1.35, 0.0, -2.2)).lerp(_demo_origin + Vector3(1.05, 0.0, -1.55), approach_b)
					second_enemy.set("facing", (_demo_origin - second_enemy.position).normalized())
				if phase_elapsed >= 0.24:
					_apply_staged_time_meter_hit(enemy, 18.0)
					_advance_phase(1)
			elif phase == 1:
				if enemy != null:
					var recoil_a := clampf(phase_elapsed / 0.26, 0.0, 1.0)
					enemy.position = (_demo_origin + Vector3(-0.55, 0.0, -0.75)).lerp(_demo_origin + Vector3(-1.45, 0.0, -2.3), recoil_a)
				if second_enemy != null:
					var lunge_b := clampf(phase_elapsed / 0.26, 0.0, 1.0)
					second_enemy.position = (_demo_origin + Vector3(1.05, 0.0, -1.55)).lerp(_demo_origin + Vector3(0.55, 0.0, -0.75), lunge_b)
					second_enemy.set("facing", (_demo_origin - second_enemy.position).normalized())
					_current_aim = second_enemy.position
				if phase_elapsed >= 0.26:
					_apply_staged_time_meter_hit(second_enemy, 18.0)
					_advance_phase(2)
			elif phase == 2:
				if second_enemy != null:
					var recoil_b := clampf(phase_elapsed / 0.28, 0.0, 1.0)
					second_enemy.position = (_demo_origin + Vector3(0.55, 0.0, -0.75)).lerp(_demo_origin + Vector3(1.55, 0.0, -2.4), recoil_b)
				if phase_elapsed >= 0.28:
					_advance_phase(3)
			elif phase == 3:
				if phase_elapsed >= 0.30:
					for de in demo_enemies:
						if is_instance_valid(de):
							de.set("health", 0.0)
					last_summary["target_killed"] = true
					last_summary["time_meter_restored"] = true
					_advance_phase(4)

		&"shot":
			if enemy != null:
				_current_aim = enemy.call("core_world_position")
			if phase == 0 and phase_elapsed >= 0.26:
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(1)
			elif phase == 1 and phase_elapsed >= 0.18:
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["shot_fired"] = true
				_advance_phase(2)

		&"charge":
			var back_enemy: Node3D = demo_enemies[1] if (demo_enemies.size() > 1 and is_instance_valid(demo_enemies[1]) and demo_enemies[1].is_inside_tree()) else enemy
			if back_enemy != null:
				_current_aim = back_enemy.call("core_world_position")
			if phase == 0 and phase_elapsed >= 0.20:
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(1)
			elif phase == 1 and float(weapons.flash.charge) >= 1.0 and phase_elapsed >= 0.96:
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["charged_shot_fired"] = true
				_advance_phase(2)

		&"cut":
			if phase == 0 and not _stroke_waypoints.is_empty() and phase_elapsed >= 0.18:
				_current_aim = _stroke_waypoints[0]
				weapons.ring.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["ring_drawn"] = true
				_advance_phase(1)
			elif phase == 1:
				_sample_ring_along_waypoints(0.42, player, weapons)
				if phase_elapsed >= 0.42:
					_current_aim = _stroke_waypoints[-1]
					_advance_phase(2)
			elif phase == 2 and phase_elapsed >= 0.20:
				_current_aim = _stroke_waypoints[-1]
				weapons.ring.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 1))
				weapons.mouse_held = false
				last_summary["ring_launched"] = true
				_advance_phase(3)

		&"heat":
			if enemy != null and float(enemy.get("health")) > 0.0:
				enemy.position.x = _demo_origin.x
				if enemy.position.z <= _demo_origin.z + HEAT_MAX_PUSH_Z:
					enemy.position.z = _demo_origin.z + HEAT_MAX_PUSH_Z
					enemy.set("knockback_vel", Vector3.ZERO)
				var start_z := _demo_origin.z + HEAT_START_OFFSET_Z
				var pushed_dist := maxf(0.0, start_z - enemy.position.z)
				if pushed_dist > float(last_summary.get("heat_knockback_distance", 0.0)):
					last_summary["heat_knockback_distance"] = pushed_dist
				if pushed_dist >= 0.65:
					last_summary["knocked_back"] = true
					last_summary["heat_knockback_seen"] = true
				_current_aim = enemy.position
			if phase == 0 and phase_elapsed >= 0.20:
				weapons.bellows.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["cone_held"] = true
				_advance_phase(1)
			elif phase == 1:
				weapons.bellows.aim_at(_demo_origin, _current_aim)
				if bool(last_summary["plate_broken"]) and (enemy == null or float(enemy.get("health")) <= 0.0):
					_advance_phase(2)
			elif phase == 2:
				weapons.bellows.aim_at(_demo_origin, _current_aim)
				if phase_elapsed >= 0.16:
					weapons.bellows.release()
					weapons.mouse_held = false
					_advance_phase(3)

		&"slow":
			if enemy != null and float(enemy.get("health")) > 0.0:
				enemy.position.x = clampf(enemy.position.x + 3.0 * world_dt, _demo_origin.x - 2.4, _demo_origin.x + 2.4)
				_current_aim = enemy.call("core_world_position")
			if phase == 0 and phase_elapsed >= 0.26:
				if is_instance_valid(tc):
					tc.set_capabilities(true, tc.rewind_unlocked)
					tc.slow_requested = true
				if is_instance_valid(tutorial_ui) and tutorial_ui.has_method("set_phase_accent"):
					tutorial_ui.call("set_phase_accent", ToolStyle.CLOCK, "TIME SLOW · WORLD SLOWED")
				last_summary["slow_engaged"] = true
				_advance_phase(1)
			elif phase == 1 and is_instance_valid(tc) and tc.world_scale <= 0.45 and phase_elapsed >= 0.30:
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(2)
			elif phase == 2 and phase_elapsed >= 0.14:
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["shot_fired"] = true
				last_summary["shot_during_slow"] = is_instance_valid(tc) and tc.world_scale < 0.55
				_advance_phase(3)
			elif phase == 3 and bool(last_summary["target_killed"]) and phase_elapsed >= 0.24:
				if is_instance_valid(tc):
					tc.slow_requested = false
				_advance_phase(4)
			elif phase == 4 and is_instance_valid(tc) and tc.world_scale >= 0.85 and phase_elapsed >= 0.14:
				last_summary["slow_resumed"] = true
				_advance_phase(5)

		&"opening":
			if phase == 0 and not _stroke_waypoints.is_empty() and phase_elapsed >= 0.16:
				_current_aim = _stroke_waypoints[0]
				weapons.ring.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["ring_drawn"] = true
				_advance_phase(1)
			elif phase == 1:
				_sample_ring_along_waypoints(0.34, player, weapons)
				if phase_elapsed >= 0.34:
					_current_aim = _stroke_waypoints[-1]
					_advance_phase(2)
			elif phase == 2 and phase_elapsed >= 0.16:
				_current_aim = _stroke_waypoints[-1]
				weapons.ring.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 1))
				weapons.mouse_held = false
				last_summary["ring_launched"] = true
				_advance_phase(3)
			elif phase == 3 and bool(last_summary["opened_before_finish"]):
				_switch_demo_tool(
					2,
					ToolStyle.BEAM,
					"2 · FOCUSED FLASH · FINISH YELLOW",
					"Click to shoot",
					"2 · Focused Flash — shoot the exposed yellow core."
				)
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				if phase_elapsed >= 0.24:
					weapons.flash.press()
					weapons.mouse_held = true
					_advance_phase(4)
			elif phase == 4 and phase_elapsed >= 0.14:
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["shot_fired"] = true
				_advance_phase(5)

		&"pair":
			if phase == 0 and enemy != null:
				_current_aim = enemy.call("valve_world_position", 0)
				if phase_elapsed >= 0.20 and not weapons.flash.charging:
					weapons.flash.press()
					weapons.mouse_held = true
				if phase_elapsed >= 0.34 and weapons.flash.charging:
					weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
					weapons.mouse_held = false
					last_summary["shot_fired"] = true
					_advance_phase(1)
			elif phase == 1 and bool(last_summary["opened_before_finish"]) and phase_elapsed >= 0.22:
				if is_instance_valid(tutorial_ui) and tutorial_ui.has_method("set_phase_accent"):
					tutorial_ui.call("set_phase_accent", ToolStyle.BEAM, "2 · FOCUSED FLASH · SHOOT VALVE B")
				_advance_phase(2)
			elif phase == 2 and enemy != null:
				_current_aim = enemy.call("valve_world_position", 1)
				if float(weapons.flash.cooldown) <= 0.0 and not weapons.flash.charging and phase_elapsed >= 0.12:
					weapons.flash.press()
					weapons.mouse_held = true
				elif weapons.flash.charging and phase_elapsed >= 0.26:
					weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
					weapons.mouse_held = false
					_advance_phase(3)

		&"loop", &"zigzag":
			if phase == 0 and not _stroke_waypoints.is_empty() and phase_elapsed >= 0.16:
				_current_aim = _stroke_waypoints[0]
				weapons.ring.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["ring_drawn"] = true
				_advance_phase(1)
			elif phase == 1:
				_sample_ring_along_waypoints(0.42, player, weapons)
				if phase_elapsed >= 0.42:
					_current_aim = _stroke_waypoints[-1]
					_advance_phase(2)
			elif phase == 2 and phase_elapsed >= 0.16:
				_current_aim = _stroke_waypoints[-1]
				weapons.ring.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 1))
				weapons.mouse_held = false
				last_summary["ring_launched"] = true
				_advance_phase(3)
			elif phase == 3 and bool(last_summary["opened_before_finish"]):
				_switch_demo_tool(
					2,
					ToolStyle.BEAM,
					"2 · FOCUSED FLASH · CHARGE YELLOW",
					"Hold, then release",
					"2 · Focused Flash — charge and fire into the exposed yellow core."
				)
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(4)
			elif phase == 4:
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				if float(weapons.flash.charge) >= 1.0 and phase_elapsed >= 0.94:
					weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
					weapons.mouse_held = false
					last_summary["charged_shot_fired"] = true
					last_summary["shot_fired"] = true
					_advance_phase(5)


func _sample_ring_along_waypoints(duration: float, _player: Node3D, weapons: Node3D) -> void:
	if _stroke_waypoints.is_empty():
		return
	var progress := clampf(phase_elapsed / maxf(0.05, duration), 0.0, 1.0)
	var target_idx := clampi(int(floor(progress * float(_stroke_waypoints.size() - 1))), 0, _stroke_waypoints.size() - 1)
	while _waypoint_index <= target_idx:
		_current_aim = _stroke_waypoints[_waypoint_index]
		weapons.ring.sample(_current_aim, _demo_origin)
		_waypoint_index += 1


func _observe_demo_targets() -> void:
	var alive := 0
	var active_stage := _substage if not _substage.is_empty() else lesson_id
	for enemy in demo_enemies:
		if not is_instance_valid(enemy):
			continue
		_suppress_enemy_overhead_labels(enemy)
		if active_stage == &"heat":
			var start_z := _demo_origin.z + HEAT_START_OFFSET_Z
			var pushed_dist := maxf(0.0, start_z - enemy.position.z)
			if pushed_dist > float(last_summary.get("heat_knockback_distance", 0.0)):
				last_summary["heat_knockback_distance"] = pushed_dist
			if pushed_dist >= 0.65:
				last_summary["knocked_back"] = true
				last_summary["heat_knockback_seen"] = true
		if bool(enemy.get("cable_cut")):
			last_summary["cable_cut"] = true
		if bool(enemy.get("plate_broken")):
			last_summary["plate_broken"] = true
		if active_stage == &"opening" and bool(enemy.call("is_core_exposed")) and float(enemy.get("health")) > 0.0:
			last_summary["opened_before_finish"] = true
		elif active_stage == &"pair" and int(enemy.get("pair_progress")) >= 1 and float(enemy.get("health")) > 0.0:
			last_summary["opened_before_finish"] = true
		elif active_stage in [&"loop", &"zigzag"] and bool(enemy.get("pattern_open")) and float(enemy.get("health")) > 0.0:
			last_summary["opened_before_finish"] = true
			last_summary["cable_cut"] = true
		if float(enemy.get("health")) <= 0.0:
			if active_stage in [&"opening", &"pair", &"loop", &"zigzag"] and bool(last_summary["opened_before_finish"]):
				last_summary["yellow_finished_after_open"] = true
		else:
			alive += 1
	if not demo_enemies.is_empty() and alive == 0:
		last_summary["target_killed"] = true


func _on_demo_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, _enemy_id: int) -> void:
	if not active:
		return
	_observe_demo_targets()
	var active_stage := _substage if not _substage.is_empty() else lesson_id
	var killed := bool(result.get("killed", false))
	if killed:
		if active_stage != &"charge":
			last_summary["target_killed"] = true
		if tool == &"beam" and bool(context.get("piercing", false)):
			var pk := int(last_summary.get("pierce_kills", 0)) + 1
			last_summary["pierce_kills"] = pk
			if int(context.get("prior_hits", 0)) > 0 or pk >= 2:
				last_summary["pierced"] = true
			if pk >= 2:
				last_summary["target_killed"] = true
		if tool == &"beam" and active_stage in [&"opening", &"pair", &"loop", &"zigzag"] and bool(last_summary["opened_before_finish"]):
			last_summary["yellow_finished_after_open"] = true


func _on_demo_combat_event(_kind: StringName, _point: Vector3, _strength: float) -> void:
	pass


func _check_phase_completion(dt: float) -> void:
	if not active:
		return
	var active_stage := _substage if not _substage.is_empty() else lesson_id
	var done := false
	match active_stage:
		&"time_meter":
			done = phase >= 4 and bool(last_summary["time_meter_drained"]) and int(last_summary["enemies_attacked"]) >= 2
		&"shot":
			done = phase >= 2 and bool(last_summary["shot_fired"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.30
		&"charge":
			done = phase >= 2 and bool(last_summary["charged_shot_fired"]) and bool(last_summary["pierced"]) and int(last_summary["pierce_kills"]) >= 2 and phase_elapsed >= 0.32
		&"cut":
			done = phase >= 3 and bool(last_summary["ring_drawn"]) and bool(last_summary["ring_launched"]) and bool(last_summary["cable_cut"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.32
		&"heat":
			done = phase >= 3 and bool(last_summary["cone_held"]) and bool(last_summary["plate_broken"]) and bool(last_summary["knocked_back"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.18
		&"slow":
			done = phase >= 5 and bool(last_summary["slow_engaged"]) and bool(last_summary["shot_during_slow"]) and bool(last_summary["target_killed"]) and bool(last_summary["slow_resumed"])
		&"opening":
			done = phase >= 5 and bool(last_summary["opened_before_finish"]) and bool(last_summary["yellow_finished_after_open"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.28
		&"pair":
			done = phase >= 3 and bool(last_summary["opened_before_finish"]) and bool(last_summary["yellow_finished_after_open"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.28
		&"loop", &"zigzag":
			done = phase >= 5 and bool(last_summary["opened_before_finish"]) and bool(last_summary["yellow_finished_after_open"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.28

	if not done:
		return

	if lesson_id == &"shot" and _substage == &"time_meter":
		_substage_pass_completed = true
		if _current_speech_event_name() != "tutorial.time_meter" or not is_instruction_speech_busy() or _unawaited_sync_steps >= 55:
			_transition_prestage_to_shot()
			return
		last_summary["waited_for_speech"] = true
		if is_instance_valid(tutorial_ui) and tutorial_ui.has_method("set_waiting_for_speech"):
			tutorial_ui.call("set_waiting_for_speech", true)
		_repeat_cooldown += dt
		if _repeat_cooldown >= 0.42:
			_restart_demo_pass()
		return

	if not _pass_completed:
		_pass_completed = true
		last_summary["completed"] = true
		last_summary["visual_passes"] = int(last_summary.get("visual_passes", 0)) + 1
	if not is_instruction_speech_busy():
		_complete_and_handoff()
		return
	last_summary["waited_for_speech"] = true
	if is_instance_valid(tutorial_ui) and tutorial_ui.has_method("set_waiting_for_speech"):
		tutorial_ui.call("set_waiting_for_speech", true)
	_repeat_cooldown += dt
	if _repeat_cooldown >= 0.38:
		last_summary["visual_passes"] = int(last_summary.get("visual_passes", 1)) + 1
		_restart_demo_pass()


func _complete_and_handoff() -> void:
	if not active or not _terminal_state.is_empty():
		return
	if not _can_touch_world_transforms():
		cancel(false)
		return
	_terminal_state = &"completed"
	var id := lesson_id
	if id == &"time_meter" or _substage == &"time_meter":
		_mark_time_meter_learned(id == &"time_meter")
	last_summary["completed"] = true
	_teardown_demo(true)
	demo_completed.emit(id, last_summary.duplicate(true))
	_emit_practice_handoff(id)


func _clear_all_controls() -> void:
	if not is_instance_valid(arena):
		return
	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	var tc: TimeController = arena.get("time_controller") as TimeController
	if is_instance_valid(weapons):
		weapons.call("cancel_input")
		weapons.set("mouse_held", false)
		weapons.set("require_fresh_press", false)
	if is_instance_valid(player) and player.has_method("reset_input"):
		player.call("reset_input")
	arena.set("_space_action_held", false)
	if InputMap.has_action(&"slow_time"):
		Input.action_release(&"slow_time")
	if is_instance_valid(tc):
		tc.slow_requested = false


func _teardown_demo(restore_world: bool) -> void:
	if _restoring:
		return
	_restoring = true
	active = false
	_clean_demo_combat_speech()
	_unbind_audio_signals()
	var finished_id := lesson_id
	lesson_id = &""
	_substage = &""
	_substage_pass_completed = false
	demo_enemies.clear()
	_stroke_waypoints.clear()

	if is_instance_valid(tutorial_ui):
		tutorial_ui.set("draw_style", &"")
		if tutorial_ui.has_method("set_demo_busy"):
			tutorial_ui.call("set_demo_busy", false)
		if tutorial_ui.has_signal("skip_requested") and tutorial_ui.skip_requested.is_connected(_on_tutorial_skip_requested):
			tutorial_ui.skip_requested.disconnect(_on_tutorial_skip_requested)
		if tutorial_ui.has_signal("resume_requested") and tutorial_ui.resume_requested.is_connected(_on_tutorial_resume_requested):
			tutorial_ui.resume_requested.disconnect(_on_tutorial_resume_requested)

	if is_instance_valid(arena):
		if arena.tree_exiting.is_connected(_on_arena_tree_exiting):
			arena.tree_exiting.disconnect(_on_arena_tree_exiting)
		var weapons: Node3D = arena.get("weapons") as Node3D
		if is_instance_valid(weapons):
			if weapons.resolved_hit.is_connected(_on_demo_resolved_hit):
				weapons.resolved_hit.disconnect(_on_demo_resolved_hit)
			if weapons.combat_event.is_connected(_on_demo_combat_event):
				weapons.combat_event.disconnect(_on_demo_combat_event)
		var feedback_node: Node = arena.get("feedback") as Node
		if is_instance_valid(feedback_node) and feedback_node.has_method("reset_state"):
			feedback_node.call("reset_state")

		_clear_all_controls()

		var can_restore := restore_world and _can_touch_world_transforms()
		if can_restore:
			var player: Node3D = arena.get("player") as Node3D
			var equipment: WeaponEquipment = arena.get("equipment") as WeaponEquipment
			var director: Node3D = arena.get("director") as Node3D
			var tc: TimeController = arena.get("time_controller") as TimeController
			var cover: RefCounted = arena.get("cover") as RefCounted

			if cover != null:
				cover.rectangles.assign(_saved_cover_rects)
			if is_instance_valid(director) and director.is_inside_tree():
				director.call("restore_state", _saved_director)
				director.set("_spawn_counter", _saved_spawn_counter)
			if equipment != null:
				equipment.restore_state(_saved_equipment.duplicate(true))
				equipment.set_training_protection(_saved_training_protection)
			if is_instance_valid(player) and player.is_inside_tree():
				player.call("restore_state", _saved_player)
				if player.has_method("set_visual_tool"):
					player.call("set_visual_tool", _saved_visual_tool)
				if _has_saved_camera and is_instance_valid(player.get("camera")):
					var cam: Camera3D = player.get("camera") as Camera3D
					if cam.is_inside_tree():
						cam.position = _saved_camera_pos
						cam.rotation = _saved_camera_rot
						cam.fov = _saved_camera_fov
						cam.reset_physics_interpolation()
						cam.force_update_transform()
			if is_instance_valid(weapons) and weapons.is_inside_tree():
				weapons.available_tools.assign(_saved_available_tools)
				weapons.call("restore_state", _saved_weapons)
				weapons.set("selected_tool", _saved_selected_tool)
				weapons.call("cancel_input")
				weapons.set("mouse_held", false)
				weapons.set("require_fresh_press", false)
				if is_instance_valid(player) and player.is_inside_tree():
					weapons.call("rebuild_visuals", player)
			if is_instance_valid(tc) and not _saved_time.is_empty():
				tc.set_capabilities(bool(_saved_time.get("slow_unlocked", false)), bool(_saved_time.get("rewind_unlocked", false)))
				tc.slow_requested = false
				tc.set("_slow_active", false)
				tc.set("_meter", float(_saved_time.get("meter", tc.capacity)))
				tc.set("_world_scale", 1.0)
				tc.set("_charges", int(_saved_time.get("charges", tc.charges_per_attempt)))
				if finished_id == &"time_meter":
					last_summary["time_meter_restored"] = is_equal_approx(tc.meter, float(_saved_time.get("meter", tc.capacity)))
			if arena.has_method("_restore_practice") and not _saved_practice.is_empty():
				arena.call("_restore_practice", _saved_practice)
			if arena.get("specimens") is Array and arena.get("_specimen_ids") is Array and is_instance_valid(director):
				var restored_specimens: Array[Node3D] = []
				var spec_ids: Array = arena.get("_specimen_ids")
				for enemy in director.enemies:
					if is_instance_valid(enemy) and int(enemy.get("rewind_id")) in spec_ids:
						restored_specimens.append(enemy)
						if arena.has_method("_make_specimen_safe"):
							arena.call("_make_specimen_safe", enemy)
				arena.specimens.assign(restored_specimens)
			if is_instance_valid(weapons):
				if _disconnected_campaign_hit and arena.has_method("_on_resolved_hit") and not weapons.resolved_hit.is_connected(Callable(arena, "_on_resolved_hit")):
					weapons.resolved_hit.connect(Callable(arena, "_on_resolved_hit"))
				if _disconnected_campaign_event and arena.has_method("_on_run_event") and not weapons.combat_event.is_connected(Callable(arena, "_on_run_event")):
					weapons.combat_event.connect(Callable(arena, "_on_run_event"))
				if arena.has_method("_on_combat_dialogue") and not weapons.combat_event.is_connected(Callable(arena, "_on_combat_dialogue")):
					weapons.combat_event.connect(Callable(arena, "_on_combat_dialogue"))
			if is_instance_valid(director):
				if arena.has_method("_on_enemy_dialogue") and not director.enemy_event.is_connected(Callable(arena, "_on_enemy_dialogue")):
					director.enemy_event.connect(Callable(arena, "_on_enemy_dialogue"))
			var status_hud: Node = arena.get("status_hud") as Node
			if is_instance_valid(status_hud) and is_instance_valid(player) and is_instance_valid(weapons):
				status_hud.call("update_status", player, weapons, equipment)
			var time_cue: Node = arena.get("time_cue") as Node
			if is_instance_valid(time_cue) and time_cue.has_method("update_state"):
				time_cue.call("update_state", 1.0, false)
			if is_instance_valid(tutorial_ui) and not finished_id.is_empty():
				var spec := spec_for(finished_id)
				if tutorial_ui.has_method("set_phase_prompt") and tutorial_ui.has_method("accent_for_lesson") and tutorial_ui.has_method("subtitle_for_lesson"):
					var base_col: Color = tutorial_ui.call("accent_for_lesson", finished_id)
					var base_sub: String = tutorial_ui.call("subtitle_for_lesson", finished_id)
					tutorial_ui.call("set_phase_prompt", String(spec.get("heading", "")), String(spec.get("body", "")), base_col, base_sub)
				if arena.has_method("_targets"):
					tutorial_ui.world_points.assign(arena.call("_targets"))

			last_summary["isolated_restore_verified"] = true
		elif _can_touch_world_transforms():
			var player_ref: Node3D = arena.get("player") as Node3D
			if _has_saved_camera and is_instance_valid(player_ref) and is_instance_valid(player_ref.get("camera")):
				var cam_ref: Camera3D = player_ref.get("camera") as Camera3D
				if cam_ref.is_inside_tree():
					cam_ref.position = _saved_camera_pos
					cam_ref.rotation = _saved_camera_rot
					cam_ref.fov = _saved_camera_fov
			var cover_ref: RefCounted = arena.get("cover") as RefCounted
			if cover_ref != null and cover_ref.rectangles.is_empty() and not _saved_cover_rects.is_empty():
				cover_ref.rectangles.assign(_saved_cover_rects)
			if is_instance_valid(weapons):
				if _disconnected_campaign_hit and arena.has_method("_on_resolved_hit") and not weapons.resolved_hit.is_connected(Callable(arena, "_on_resolved_hit")):
					weapons.resolved_hit.connect(Callable(arena, "_on_resolved_hit"))
				if _disconnected_campaign_event and arena.has_method("_on_run_event") and not weapons.combat_event.is_connected(Callable(arena, "_on_run_event")):
					weapons.combat_event.connect(Callable(arena, "_on_run_event"))
				if arena.has_method("_on_combat_dialogue") and not weapons.combat_event.is_connected(Callable(arena, "_on_combat_dialogue")):
					weapons.combat_event.connect(Callable(arena, "_on_combat_dialogue"))

	_disconnected_campaign_hit = false
	_disconnected_campaign_event = false
	_restoring = false


func _emit_practice_handoff(id: StringName) -> void:
	if _handoff_emitted or id.is_empty():
		return
	_handoff_emitted = true
	var was_skipped := bool(last_summary.get("skipped", false))
	if is_instance_valid(tutorial_ui):
		if tutorial_ui.has_method("set_demo_busy"):
			tutorial_ui.call("set_demo_busy", false)
		if bool(tutorial_ui.get("blocking")) and tutorial_ui.get("active_id") == id:
			tutorial_ui.call("request_practice")
	ready_for_practice.emit(id)
	if is_instance_valid(arena):
		var player: Node3D = arena.get("player") as Node3D
		if is_instance_valid(player) and player.has_method("reset_input"):
			player.call("reset_input")
		arena.set("_space_action_held", false)
		var weapons: Node3D = arena.get("weapons") as Node3D
		if is_instance_valid(weapons):
			weapons.call("cancel_input")
			var lmb_down := was_skipped or _lmb_held_during_demo or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			weapons.set("mouse_held", false)
			weapons.set("require_fresh_press", lmb_down)
			if lmb_down:
				arena.set("_suppress_next_lmb_release", true)


func _on_tutorial_skip_requested(id: StringName) -> void:
	if active and id == lesson_id:
		skip_to_practice()


func _on_tutorial_resume_requested(id: StringName) -> void:
	if active and id == lesson_id:
		skip_to_practice()


func _on_tutorial_lesson_completed(id: StringName) -> void:
	mark_learned(id)


func _on_arena_tree_exiting() -> void:
	if active:
		cancel(false)
