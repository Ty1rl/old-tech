class_name MuseumCampaign
extends CombatArena

const Rooms = preload("res://scenes/prototype/rooms.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")
const Tutorial = preload("res://scenes/ui/tutorial.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")

@onready var overlay: CanvasLayer = get_node_or_null("Overlay") as CanvasLayer
@onready var tutorial: Control = get_node_or_null("Overlay/Tutorial") as Control
@onready var title: Label = get_node_or_null("Overlay/TitleLabel") as Label
@onready var run_hint: Label = get_node_or_null("Overlay/RunHintLabel") as Label
@onready var lesson_demo: LessonDemo = $LessonDemo
@onready var rewind_lesson: RewindLesson = $RewindLesson

var difficulty_id: StringName = &"easy"
var difficulty_spec: CampaignDifficulty = null
var skip_tutorials := false
var room_index := 0
var wave_index := -1
var mode: StringName = &"title"
var timer := 0.0
var room: Dictionary
var waves: Array = []
var lesson: StringName = &""
# Acquisition, learned tutorials, and unlocked time capabilities are permanent run progress,
# deliberately outside rewind snapshots.
var acquired: Array[int] = []
var _slow_unlocked := false
var _rewind_unlocked := false
var specimens: Array[Node3D] = []
var _specimen_ids: Array[int] = []
var _campaign_ready := false
var _practice_stage: StringName = &""
var _stationary_quota := 0
var _stationary_done := 0
var _moving_quota := 0
var _moving_done := 0
var _kills: Dictionary = {}
var _opened := false
var _cut := false
var _heated := false
var _slow_used := false
var _pierced := false
var _repaired := false
var _rewound := false
var _injury_given := false
var _practice_age := 0.0
var _damage_flash := 0.0
var _charged_kills: Dictionary = {}
var _pending := 0
var _spawned := 0
var _spawn_timer := 0.0
var _debug_boss_phase := -1
var _debug_direct_wave := false
var _result_shown := false
var _emergency_selected_index := 0
var _exit_requires_reentry := false
var _exit_blocked_by_held_forward := false
var _forward_held_at_wave_clear := false
var _w_key_held := false
var _last_music_context: StringName = &""
var _time_meter_elapsed := 0.0
var _time_meter_hit_applied := false
var _time_meter_recharged := false
var _time_meter_min_meter := 100.0
var _time_meter_max_after_hit := 0.0
var _time_meter_sync_steps := 0
var _time_meter_last_frame := -1
var _pickup_stage: StringName = &""
var _movement_cue_done := false
var _tool_switch_cue_done := false
var _cue_elapsed := 0.0
var _cue_speech_accepted := false
var _pickup_ticks_in_stage := 0
var _awaiting_rewind_charges_speech := false
var _rewind_charges_elapsed := 0.0
var _rewind_charges_speech_accepted := false
var _suppress_enter_release := false

const MOVEMENT_CUE_LINE := "Mouse aims. WASD moves."
const PICKUP_WALK_LINE := "Walk towards the new item."
const TOOL_SWITCH_CUE_LINE := "Press Tab, one, two, or three; to select tools."
const TIME_METER_LINE := "Taking damage, slowing time, and repairing drain your reserve. Find moments to let it recharge."
const REWIND_CHARGES_LINE := "Each room gives you three emergency rewinds."


static func practice_quotas_for(id: StringName) -> Vector2i:
	if id in [&"shot", &"charge", &"heat", &"slow", &"cut", &"opening", &"pair", &"loop", &"zigzag"]:
		return Vector2i(2, 2)
	return Vector2i.ZERO


func set_skip_tutorials(value: bool) -> void:
	skip_tutorials = value


func _prefs_skip_tutorials() -> bool:
	return bool(GameState.preferences().get("skip_tutorials", false))


func _params_skip_tutorials() -> Variant:
	if SceneManager.params.has("skip_tutorials"):
		return bool(SceneManager.params.get("skip_tutorials", false))
	return null


func _is_skip_tutorials_active() -> bool:
	return skip_tutorials


func _should_play_teaching_cues() -> bool:
	return not _is_skip_tutorials_active() and bool(GameState.preferences().get("tutorial", true)) and not _debug_direct_wave


func _set_music_context(context: StringName) -> void:
	_last_music_context = context
	if AudioManager == null or not AudioManager.has_method("set_music_context"):
		return
	AudioManager.call("set_music_context", context)
	if context == &"regular_combat":
		var active_ctx: Variant = AudioManager.get("music_context")
		if active_ctx == null:
			active_ctx = AudioManager.get("current_music_context")
		if active_ctx != null and StringName(active_ctx) != &"regular_combat":
			AudioManager.call("set_music_context", &"encounter")


func _is_instruction_speech_busy() -> bool:
	if AudioManager == null:
		return false
	if AudioManager.has_method("instruction_busy"):
		return bool(AudioManager.call("instruction_busy"))
	return false


func _is_event_speaking(event: StringName) -> bool:
	if AudioManager == null or event.is_empty():
		return false
	if AudioManager.has_method("is_speaking"):
		return bool(AudioManager.call("is_speaking", event))
	return StringName(AudioManager.get("current_event")) == event


func _play_lesson_speech(id: StringName) -> void:
	if AudioManager == null or id.is_empty():
		return
	var cur := String(AudioManager.get("current_event"))
	if cur in ["tutorial.movement", "tutorial.pickup", "tutorial.tool_switch", "tutorial.rewind_charges"]:
		AudioManager.say(StringName("tutorial." + String(id)), 3)
	else:
		AudioManager.lesson(id)


func _on_audio_speech_finished(event: StringName, interrupted: bool) -> void:
	if interrupted or not is_inside_tree() or is_queued_for_deletion():
		return
	if _awaiting_rewind_charges_speech and (event == &"tutorial.rewind_charges" or not _is_event_speaking(&"tutorial.rewind_charges")):
		_finish_rewind_charges_speech(false)
		return
	if mode == &"pickup":
		if _pickup_stage == &"movement_cue" and (event == &"tutorial.movement" or not _is_event_speaking(&"tutorial.movement")):
			_start_pickup_walk_cue(true)
			return
		if _pickup_stage == &"await_pickup_speech" and not _is_instruction_speech_busy():
			_advance_after_pickup_collected()
			return
		if _pickup_stage == &"tool_switch_cue" and (event == &"tutorial.tool_switch" or not _is_event_speaking(&"tutorial.tool_switch")):
			_pickup_stage = &""
			_spawn_wave()
			return
	if mode == &"practice" and _practice_stage == &"await_speech" and not _is_instruction_speech_busy():
		if lesson == &"time_meter":
			_finish_time_meter_lesson(false)
		else:
			_start_stationary_practice()
	elif mode == &"practice" and _practice_stage == &"time_meter_demo" and _time_meter_recharged and not _is_instruction_speech_busy():
		_finish_time_meter_lesson(false)


func _is_forward_move_held() -> bool:
	return _w_key_held or Input.is_action_pressed(&"move_up") or Input.get_action_strength(&"move_up") > 0.05


func _is_in_exit_approach_zone(point: Vector3) -> bool:
	return museum != null and bool(museum.player_in_exit(point))


func _arm_room_exit() -> void:
	var pos := player.position if is_instance_valid(player) else Vector3.ZERO
	_exit_requires_reentry = museum != null and bool(museum.player_in_exit(pos))
	_exit_blocked_by_held_forward = false
	_forward_held_at_wave_clear = false


func _update_exit_gate_state() -> void:
	if mode != &"exit" or not is_instance_valid(player):
		return
	var in_exit: bool = museum != null and bool(museum.player_in_exit(player.position))
	if _exit_requires_reentry and not in_exit:
		_exit_requires_reentry = false


func _can_traverse_open_exit() -> bool:
	if mode != &"exit" or not is_instance_valid(player) or museum == null or not museum.exit_open:
		return false
	if _exit_requires_reentry:
		return false
	return bool(museum.player_in_exit(player.position))


func create_museum() -> Node3D:
	return RoomEnvironment.new()


func set_difficulty(value: Variant) -> void:
	difficulty_spec = Rooms.DifficultySpec.load_for(value)
	difficulty_id = difficulty_spec.id
	if is_instance_valid(director):
		director.combat_difficulty = difficulty_spec


func _room_definitions() -> Array[Dictionary]:
	return Rooms.definitions(difficulty_spec if difficulty_spec != null else difficulty_id)


func _apply_time_capabilities() -> void:
	if tutorial != null:
		if bool(tutorial.learned.get(&"slow", false)):
			_slow_unlocked = true
		if bool(tutorial.learned.get(&"rewind", false)):
			_rewind_unlocked = true
	if time_controller != null:
		time_controller.set_capabilities(_slow_unlocked, _rewind_unlocked)
	if status_hud != null and is_instance_valid(player) and is_instance_valid(weapons) and is_instance_valid(equipment):
		status_hud.update_status(player, weapons, equipment)


func _cancel_active_teaching_controllers() -> void:
	if lesson_demo != null and lesson_demo.active:
		lesson_demo.cancel()
	if rewind_lesson != null and rewind_lesson.active:
		rewind_lesson.cancel()
	if _awaiting_rewind_charges_speech:
		_awaiting_rewind_charges_speech = false
		_rewind_charges_elapsed = 0.0
		_rewind_charges_speech_accepted = false
		if rewind_lesson != null:
			rewind_lesson._sync_banner()


func start_new_run(new_difficulty: Variant = null, new_skip_tutorials: Variant = null) -> void:
	AudioManager.begin_run()
	_cancel_active_teaching_controllers()
	if new_difficulty != null:
		set_difficulty(new_difficulty)
	elif SceneManager.params.has("difficulty"):
		set_difficulty(SceneManager.params.get("difficulty", &"easy"))
	if new_skip_tutorials != null:
		set_skip_tutorials(bool(new_skip_tutorials))
	else:
		var param_skip: Variant = _params_skip_tutorials()
		if param_skip != null:
			set_skip_tutorials(bool(param_skip))
		else:
			set_skip_tutorials(_prefs_skip_tutorials())
	SceneManager.clear_popups()
	GameState.start_game()
	acquired.clear()
	if tutorial != null:
		tutorial.reset_run()
	if lesson_demo != null:
		lesson_demo.reset_run()
	if rewind_lesson != null:
		rewind_lesson.reset_for_new_run()
	_slow_unlocked = false
	_rewind_unlocked = false
	_movement_cue_done = false
	_tool_switch_cue_done = false
	_pickup_stage = &""
	_cue_elapsed = 0.0
	_cue_speech_accepted = false
	_pickup_ticks_in_stage = 0
	_awaiting_rewind_charges_speech = false
	_rewind_charges_elapsed = 0.0
	_rewind_charges_speech_accepted = false
	_suppress_enter_release = false
	_apply_time_capabilities()
	lesson = &""
	_practice_stage = &""
	# The new-run checkbox is authoritative; an older contextual-teaching
	# preference must not silently bypass an explicitly requested taught run.
	if not skip_tutorials: GameState.set_setting("tutorial", true)
	enter_room(0)


func _ready() -> void:
	super._ready()
	AudioManager.begin_run()
	if AudioManager != null and AudioManager.has_signal("speech_finished"):
		if not AudioManager.is_connected("speech_finished", _on_audio_speech_finished):
			AudioManager.connect("speech_finished", _on_audio_speech_finished)
	if not lesson_demo.ready_for_practice.is_connected(_on_lesson_demo_ready_for_practice):
		lesson_demo.ready_for_practice.connect(_on_lesson_demo_ready_for_practice)
	if not rewind_lesson.completed.is_connected(_on_rewind_lesson_completed):
		rewind_lesson.completed.connect(_on_rewind_lesson_completed)
	museum.combat_event.connect(feedback.cue)
	tutorial.setup(player.camera)
	if not tutorial.blocking_changed.is_connected(_on_teaching_block):
		tutorial.blocking_changed.connect(_on_teaching_block)
	if tutorial.has_signal("skip_requested") and not tutorial.is_connected("skip_requested", _on_tutorial_skip_requested):
		tutorial.connect("skip_requested", _on_tutorial_skip_requested)
	if not player.wounded.is_connected(_on_wounded):
		player.wounded.connect(_on_wounded)
	if not weapons.combat_event.is_connected(_on_run_event):
		weapons.combat_event.connect(_on_run_event)
	if not weapons.resolved_hit.is_connected(_on_resolved_hit):
		weapons.resolved_hit.connect(_on_resolved_hit)
	if not equipment.repaired.is_connected(_on_equipment_repaired):
		equipment.repaired.connect(_on_equipment_repaired)
	if not SceneManager.restart_room_requested.is_connected(retry_room):
		SceneManager.restart_room_requested.connect(retry_room)
	set_difficulty(SceneManager.params.get("difficulty", &"easy"))
	var param_skip: Variant = _params_skip_tutorials()
	if param_skip != null:
		set_skip_tutorials(bool(param_skip))
	else:
		set_skip_tutorials(_prefs_skip_tutorials())
	_slow_unlocked = false
	_rewind_unlocked = false
	_apply_time_capabilities()
	_campaign_ready = true
	if not skip_tutorials: GameState.set_setting("tutorial", true)
	enter_room(0)
	if SceneManager.params.has("debug_room"):
		debug_start(
			int(SceneManager.params.debug_room),
			int(SceneManager.params.get("debug_wave", 0)),
			int(SceneManager.params.get("debug_phase", -1))
		)
	GameState.apply_preferences(feedback, status_hud)


func is_emergency_active() -> bool:
	return time_controller.emergency_active


func _world_scale() -> float:
	return time_controller.world_scale


func _preferred_tool(preferred: int = 2) -> int:
	if preferred in acquired:
		return preferred
	if 2 in acquired:
		return 2
	if not acquired.is_empty():
		return acquired[0]
	return 2


func _pickup_spawn_position() -> Vector3:
	var base_pos := Vector3(room.get("player_spawn", Vector3.ZERO)) + Vector3(0.0, 0.0, -3.0)
	if not is_instance_valid(player):
		return base_pos
	var p2 := Vector2(player.position.x, player.position.z)
	var b2 := Vector2(base_pos.x, base_pos.z)
	if p2.distance_to(b2) >= 2.6:
		return base_pos
	var step_z := -3.2 if player.position.z > -9.5 else 3.2
	return Vector3(
		clampf(player.position.x, -8.0, 8.0),
		base_pos.y,
		clampf(player.position.z + step_z, -12.5, 11.5)
	)


func _start_pickup_walk_cue(speak_cue: bool = true) -> void:
	_pickup_stage = &"pickup_cue"
	_cue_elapsed = 0.0
	_pickup_ticks_in_stage = 0
	run_hint.text = PICKUP_WALK_LINE
	_cue_speech_accepted = false
	if speak_cue and AudioManager != null and _should_play_teaching_cues():
		_cue_speech_accepted = AudioManager.say(&"tutorial.pickup", 3, false)
	_update_run_hud()


func _enter_pickup_mode(tool: int, speak_cue: bool = true) -> void:
	mode = &"pickup"
	if tutorial != null:
		tutorial.dismiss()
	museum.show_tool_pickup(tool, _pickup_spawn_position())
	if speak_cue and not _movement_cue_done and acquired.is_empty() and _should_play_teaching_cues():
		_movement_cue_done = true
		_pickup_stage = &"movement_cue"
		_cue_elapsed = 0.0
		_pickup_ticks_in_stage = 0
		run_hint.text = MOVEMENT_CUE_LINE
		_cue_speech_accepted = AudioManager != null and AudioManager.say(&"tutorial.movement", 3, true)
		_update_run_hud()
		return
	_start_pickup_walk_cue(speak_cue)


func _advance_after_pickup_collected() -> void:
	if acquired.size() == 2 and not _tool_switch_cue_done and _should_play_teaching_cues():
		_tool_switch_cue_done = true
		_pickup_stage = &"tool_switch_cue"
		_cue_elapsed = 0.0
		_pickup_ticks_in_stage = 0
		run_hint.text = TOOL_SWITCH_CUE_LINE
		_cue_speech_accepted = AudioManager != null and AudioManager.say(&"tutorial.tool_switch", 3, true)
		_update_run_hud()
		return
	_pickup_stage = &""
	_cue_elapsed = 0.0
	_pickup_ticks_in_stage = 0
	_spawn_wave()


func _step_pickup_mode(delta: float) -> void:
	_cue_elapsed += maxf(0.0, delta)
	_pickup_ticks_in_stage += 1
	var fast_headless := not is_physics_processing() and delta <= 0.002
	if _pickup_stage == &"movement_cue":
		var move_speaking := _is_event_speaking(&"tutorial.movement")
		if fast_headless:
			if move_speaking and AudioManager != null:
				AudioManager.stop_dialogue()
			_start_pickup_walk_cue(true)
			return
		if not is_physics_processing() and _cue_elapsed >= 2.2:
			if move_speaking and AudioManager != null:
				AudioManager.stop_dialogue()
			_start_pickup_walk_cue(true)
			return
		if not move_speaking and (not _cue_speech_accepted and _cue_elapsed >= 0.85 or _cue_speech_accepted):
			_start_pickup_walk_cue(true)
			return
		return
	if _pickup_stage == &"await_pickup_speech":
		var pickup_speaking := _is_event_speaking(&"tutorial.pickup") or _is_event_speaking(&"tutorial.movement")
		if fast_headless:
			if pickup_speaking and AudioManager != null:
				AudioManager.stop_dialogue()
			_advance_after_pickup_collected()
			return
		if not is_physics_processing() and _cue_elapsed >= 2.2:
			if pickup_speaking and AudioManager != null:
				AudioManager.stop_dialogue()
			_advance_after_pickup_collected()
			return
		if not pickup_speaking:
			_advance_after_pickup_collected()
		return
	if _pickup_stage == &"tool_switch_cue":
		var switch_speaking := _is_event_speaking(&"tutorial.tool_switch")
		if fast_headless:
			if switch_speaking and AudioManager != null:
				AudioManager.stop_dialogue()
			_pickup_stage = &""
			_spawn_wave()
			return
		if not is_physics_processing() and _cue_elapsed >= 2.2:
			if switch_speaking and AudioManager != null:
				AudioManager.stop_dialogue()
			_pickup_stage = &""
			_spawn_wave()
			return
		if not switch_speaking and (not _cue_speech_accepted and _cue_elapsed >= 0.85 or _cue_speech_accepted):
			_pickup_stage = &""
			_spawn_wave()
		return
	if museum.pickup_tool > 0:
		var point: Vector3 = museum.pickup_position
		if Vector2(player.position.x - point.x, player.position.z - point.z).length() <= 1.7:
			var tool: int = museum.pickup_tool
			if tool > 0 and tool <= 3 and not tool in acquired:
				acquired.append(tool)
			weapons.set_loadout(acquired, _preferred_tool(tool))
			museum.clear_tool_pickup()
			var pickup_speaking := _is_event_speaking(&"tutorial.pickup") or _is_event_speaking(&"tutorial.movement")
			if pickup_speaking and not fast_headless:
				_pickup_stage = &"await_pickup_speech"
				_cue_elapsed = 0.0
				_pickup_ticks_in_stage = 0
				_update_run_hud()
				return
			if pickup_speaking and fast_headless and AudioManager != null:
				AudioManager.stop_dialogue()
			_advance_after_pickup_collected()


func _reset_room_history() -> void:
	if history == null:
		return
	history.clear()
	if history is ReplayHistory:
		(history as ReplayHistory).seed_checkpoint(capture_state())


func _seed_room_checkpoint() -> void:
	if history == null:
		return
	if history is ReplayHistory:
		var rh := history as ReplayHistory
		var snap := capture_state()
		rh.seed_checkpoint(snap)
		if rh.snapshot_count > 0:
			rh.push(snap)


func enter_room(index: int) -> void:
	_cancel_active_teaching_controllers()
	AudioManager.stop_dialogue()
	var definitions := _room_definitions()
	if index >= definitions.size():
		_finish_run(true)
		return
	room_index = clampi(index, 0, definitions.size() - 1)
	super.reset_arena()
	director.clear()
	room = definitions[room_index].duplicate(true)
	waves = room.waves.duplicate(true)
	# A later-room checkpoint always includes the preceding rooms' tools and capabilities.
	for previous in range(room_index):
		for wave: Dictionary in definitions[previous].waves:
			var tool := int(wave.get("acquire", 0))
			if tool > 0 and tool <= 3 and not tool in acquired:
				acquired.append(tool)
			var taught := StringName(wave.get("lesson", &""))
			if taught == &"slow":
				_slow_unlocked = true
			elif taught == &"rewind":
				_rewind_unlocked = true
	if room_index == 0 and acquired.is_empty():
		_movement_cue_done = false
		_tool_switch_cue_done = false
	else:
		if acquired.size() >= 1:
			_movement_cue_done = true
		if acquired.size() >= 2:
			_tool_switch_cue_done = true
	_pickup_stage = &""
	_cue_elapsed = 0.0
	_cue_speech_accepted = false
	_pickup_ticks_in_stage = 0
	_awaiting_rewind_charges_speech = false
	_rewind_charges_elapsed = 0.0
	_rewind_charges_speech_accepted = false
	_suppress_enter_release = false
	weapons.set_loadout(acquired, _preferred_tool(2))
	museum.apply_room(room, cover, self)
	museum.sync_cover_colliders(self)
	museum.set_boss_ceremony_phase(&"inactive")
	museum.set_exit_open(false)
	player.position = room.player_spawn
	player.reset_physics_interpolation()
	player.reset_input()
	wave_index = -1
	specimens.clear()
	_specimen_ids.clear()
	_practice_stage = &""
	_stationary_quota = 0
	_stationary_done = 0
	_moving_quota = 0
	_moving_done = 0
	_pending = 0
	_spawned = 0
	_spawn_timer = 0.0
	_debug_boss_phase = -1
	_exit_requires_reentry = false
	_exit_blocked_by_held_forward = false
	_forward_held_at_wave_clear = false
	mode = &"title"
	timer = 2.0
	title.text = "%d / %d · %s" % [room_index + 1, definitions.size(), room.title]
	run_hint.text = PICKUP_WALK_LINE
	_result_shown = false
	_set_music_context(&"regular_combat")
	_sync_training_protection()
	_apply_time_capabilities()
	if time_controller != null:
		time_controller.slow_requested = false
		time_controller.begin_attempt()
	_reset_room_history()
	_update_run_hud()


# Starts a checkpoint with all prerequisites and the selected lesson already learned.
# A boss phase uses the real enemy's restore_state, preserving its native geometry.
func debug_start(index: int, requested_wave: int = 0, boss_phase: int = -1) -> void:
	_cancel_active_teaching_controllers()
	AudioManager.stop_dialogue()
	if SceneManager.params.has("difficulty"):
		set_difficulty(SceneManager.params.get("difficulty", difficulty_id))
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	acquired.clear()
	tutorial.learned.clear()
	if lesson_demo != null:
		lesson_demo.reset_run()
	if rewind_lesson != null:
		rewind_lesson.reset_for_new_run()
	_slow_unlocked = false
	_rewind_unlocked = false
	var definitions := _room_definitions()
	var target_room := clampi(index, 0, definitions.size() - 1)
	var target_wave := clampi(requested_wave, 0, definitions[target_room].waves.size() - 1)
	for ri in range(target_room + 1):
		var end: int = target_wave + 1 if ri == target_room else definitions[ri].waves.size()
		for wi in range(end):
			var wave: Dictionary = definitions[ri].waves[wi]
			var tool := int(wave.get("acquire", 0))
			if tool > 0 and tool <= 3 and not tool in acquired:
				acquired.append(tool)
			var taught := StringName(wave.get("lesson", &""))
			if not taught.is_empty():
				tutorial.learned[taught] = true
				if lesson_demo != null:
					lesson_demo.mark_learned(taught)
				if taught == &"slow":
					_slow_unlocked = true
				elif taught == &"rewind":
					_rewind_unlocked = true
	_apply_time_capabilities()
	enter_room(target_room)
	wave_index = target_wave - 1
	_debug_boss_phase = boss_phase
	_debug_direct_wave = true
	_begin_wave()
	_debug_direct_wave = false


func retry_room() -> void:
	_cancel_active_teaching_controllers()
	AudioManager.stop_dialogue()
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	lesson = &""
	_practice_stage = &""
	enter_room(room_index)


func reset_arena() -> void:
	if _campaign_ready:
		retry_room()
	else:
		super.reset_arena()


func _is_yellow_protected() -> bool:
	if bool(tutorial.learned.get(&"repair", false)):
		return false
	if lesson == &"repair":
		return false
	if room_index > 0:
		return false
	if wave_index >= 0 and wave_index < waves.size():
		for wi in range(wave_index + 1):
			if StringName(waves[wi].get("lesson", &"")) == &"repair":
				return false
	return true


func _sync_training_protection() -> void:
	if equipment == null or tutorial == null:
		return
	var protect := _is_yellow_protected()
	equipment.set_training_protection([&"beam"] if protect else [])
	if protect:
		equipment.restore_tool(&"beam", 1.0)


func _is_slow_held() -> bool:
	if lesson_demo != null and lesson_demo.active:
		return false
	if rewind_lesson != null and rewind_lesson.active:
		return false
	return super._is_slow_held() and not tutorial.blocking and mode in [&"pickup", &"practice", &"pressure", &"recovery", &"exit"]


func _on_tutorial_skip_requested(id: StringName) -> void:
	if _awaiting_rewind_charges_speech and (id.is_empty() or id in [&"rewind", &"rewind_charges"]):
		_finish_rewind_charges_speech(true)
		return
	if mode != &"practice":
		return
	var target_id := id if not id.is_empty() else lesson
	if target_id == &"time_meter" or lesson == &"time_meter":
		if lesson_demo != null and lesson_demo.active:
			lesson_demo.cancel()
		_finish_time_meter_lesson(true)
		return
	if target_id == &"repair" or lesson == &"repair":
		_skip_repair_explanation()
		return


func _skip_repair_explanation() -> void:
	if _is_instruction_speech_busy() or (AudioManager != null and String(AudioManager.get("current_event")).begins_with("tutorial.repair")):
		AudioManager.stop_dialogue()
	# Skip narration, not the player's first repair. E still opens the damaged
	# tool, and only completing its stages can finish this lesson.
	if tutorial.blocking:
		tutorial.request_practice()
	_sync_repair_lesson_guidance()


func _on_teaching_block(blocked: bool) -> void:
	if lesson_demo != null and lesson_demo.active:
		return
	weapons.cancel_input()
	weapons.mouse_held = false
	player.reset_input()
	if blocked:
		time_controller.slow_requested = false
		_close_repair()
	else:
		if lesson == &"slow":
			_slow_unlocked = true
			_apply_time_capabilities()
		elif lesson == &"rewind":
			_rewind_unlocked = true
			_apply_time_capabilities()
		elif lesson == &"time_meter":
			AudioManager.stop_dialogue()
			_finish_time_meter_lesson(true)
			return
		if _practice_stage == &"await_speech":
			AudioManager.stop_dialogue()
			_start_stationary_practice()
			return
		# The explanation's click has been consumed; the next attack needs no re-arm unless mouse is still held.
		weapons.require_fresh_press = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		time_controller.slow_requested = _is_slow_held()
		aim = floor_aim(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var kcode: int = event.physical_keycode if event.physical_keycode else event.keycode
		if kcode in [KEY_W, KEY_UP]:
			_w_key_held = event.pressed
		if kcode in [KEY_ENTER, KEY_KP_ENTER] and (_suppress_enter_release or _awaiting_rewind_charges_speech):
			if not event.pressed:
				_suppress_enter_release = false
			if is_inside_tree() and get_viewport() != null:
				get_viewport().set_input_as_handled()
			return
	if _awaiting_rewind_charges_speech and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if rewind_lesson != null and is_instance_valid(rewind_lesson.skip_button) and rewind_lesson.skip_button.visible and not rewind_lesson.skip_button.disabled:
			if rewind_lesson.skip_button.get_global_rect().has_point(event.position):
				_finish_rewind_charges_speech(true)
				if is_inside_tree() and get_viewport() != null:
					get_viewport().set_input_as_handled()
				return
	if _campaign_ready and rewind_lesson != null and rewind_lesson.active and rewind_lesson.phase == RewindLesson.Phase.STAGING:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_F10:
			super._input(event)
		return
	if _campaign_ready and (tutorial.blocking or mode in [&"title", &"ceremony", &"won"]):
		if tutorial.blocking and mode == &"practice" and lesson == &"repair" and event is InputEventKey and event.pressed and not event.echo:
			var r_code: int = event.physical_keycode if event.physical_keycode else event.keycode
			if r_code == KEY_E:
				tutorial.request_practice()
				if _player_can_act() and not _owned_tool_slots().is_empty():
					_open_smart_repair()
				get_viewport().set_input_as_handled()
				return
		# Keep explanation GUI usable and clean up held releases without starting actions.
		if event is InputEventKey and (not event.pressed or event.physical_keycode == KEY_F10):
			super._input(event)
		elif event is InputEventMouseButton and not event.pressed:
			if lesson_demo == null or not lesson_demo.active:
				weapons.cancel_input()
				weapons.mouse_held = false
		return
	super._input(event)


func _unhandled_input(event: InputEvent) -> void:
	if _campaign_ready:
		if (lesson_demo != null and lesson_demo.active) or (rewind_lesson != null and rewind_lesson.active):
			return
		if mode == &"pickup" and event is InputEventMouse:
			return
		if tutorial.blocking or mode in [&"title", &"ceremony", &"won"]:
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var code: int = event.physical_keycode if event.physical_keycode else event.keycode
			if code in [KEY_ENTER, KEY_KP_ENTER] and (_suppress_enter_release or _awaiting_rewind_charges_speech):
				return
			if code == KEY_R:
				retry_room()
				return
			if code == KEY_4:
				return
			if code in [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F8, KEY_F9, KEY_BACKSPACE]:
				return
	super._unhandled_input(event)


func _physics_process(delta: float) -> void:
	if not _campaign_ready:
		return
	_damage_flash = maxf(0.0, _damage_flash - delta)
	_update_run_hud()
	var in_emergency: bool = GameState.is_in_emergency() and not GameState.is_paused()
	if (not GameState.is_playing() and not in_emergency) or SceneManager.has_popup(&"Developer") or SceneManager.has_popup(&"Settings"):
		return
	if mode == &"won":
		return
	if rewind_lesson != null and rewind_lesson.active:
		rewind_lesson.step(delta)
		feedback.step(delta, 0.0, _world_scale(), is_emergency_active(), _scrub_speed, weapons, equipment)
		_update_run_hud()
		return
	if lesson_demo != null and lesson_demo.active:
		lesson_demo.step(delta)
		feedback.step(delta, delta * _world_scale(), _world_scale(), false, 0.0, weapons, equipment)
		_update_run_hud()
		return
	if mode == &"practice" and _practice_stage == &"time_meter_demo":
		if tutorial.is_learned(&"time_meter"):
			_finish_time_meter_lesson(true)
			return
		_step_time_meter_demo(delta)
		feedback.step(delta, delta * _world_scale(), _world_scale(), false, 0.0, weapons, equipment)
		_update_run_hud()
		return
	if mode == &"practice" and _practice_stage == &"await_speech":
		if not _is_instruction_speech_busy():
			if lesson == &"time_meter":
				_finish_time_meter_lesson(false)
			else:
				_start_stationary_practice()
		else:
			feedback.step(delta, delta * _world_scale(), _world_scale(), false, 0.0, weapons, equipment)
			_update_run_hud()
			return
	if bool(tutorial.blocking):
		return
	if mode == &"title":
		timer -= delta
		if timer <= 0.0:
			title.text = ""
			_begin_wave()
		return
	if mode == &"ceremony":
		museum.step_ceremony(delta)
		if museum.is_boss_active():
			_spawn_wave()
		return
	if time_controller != null and time_controller.exhausted:
		retry_room()
		return
	if mode == &"exit":
		_update_exit_gate_state()
	var emergency_before := is_emergency_active()
	super._physics_process(delta)
	if time_controller != null and time_controller.exhausted:
		retry_room()
		return
	if emergency_before or is_emergency_active():
		_update_run_hud()
		return
	var world_scale := _world_scale()
	var world_delta := delta * world_scale
	if mode == &"pickup":
		_step_pickup_mode(delta)
	elif mode == &"practice":
		if tutorial.is_learned(lesson):
			if lesson == &"time_meter":
				_finish_time_meter_lesson(true)
				return
			tutorial.learned[lesson] = true
			if lesson_demo != null:
				lesson_demo.mark_learned(lesson)
			_cancel_active_teaching_controllers()
			tutorial.dismiss()
			if lesson == &"repair":
				_sync_training_protection()
				equipment.restore_tool(&"beam", 1.0)
			elif lesson == &"slow":
				_slow_unlocked = true
				_apply_time_capabilities()
			elif lesson == &"rewind":
				_rewind_unlocked = true
				_apply_time_capabilities()
			_practice_stage = &""
			_start_pressure()
			return
		_practice_age += delta
		_slow_used = _slow_used or (time_controller != null and time_controller.slow_active) or world_scale < 0.99 or player.world_scale < 0.99
		_maintain_practice_specimens(world_delta)
		_observe_specimens()
		if not tutorial.active_id.is_empty():
			_sync_practice_tutorial_prompt()
		if _lesson_succeeded():
			_advance_practice_rep()
		elif _needs_combat_target() and _alive_specimens() == 0:
			_spawn_practice()
			_sync_practice_tutorial_prompt()
	elif mode == &"pressure":
		_step_pressure(world_delta)
		if _pending == 0 and director.enemies.is_empty() and director.projectiles.is_empty():
			_forward_held_at_wave_clear = _is_forward_move_held()
			mode = &"recovery"
			timer = float(waves[wave_index].get("recovery", 1.8))
			_seed_room_checkpoint()
			if int(waves[wave_index].get("count", 0)) == 0:
				run_hint.text = "Tools restored · next exhibit group approaching."
			else:
				run_hint.text = "Exhibits quiet · press E to toggle tool repair before the next group."
	elif mode == &"recovery":
		if not _is_forward_move_held():
			_forward_held_at_wave_clear = false
		timer -= world_delta
		_step_rewind_charges_wait(delta)
		if mode == &"recovery" and timer <= 0.0 and not _awaiting_rewind_charges_speech and equipment.repairing == &"":
			_begin_wave()
	elif mode == &"exit":
		_update_exit_gate_state()
		if equipment.repairing == &"" and _can_traverse_open_exit():
			enter_room(room_index + 1)


func _on_popup_opened(key: StringName, popup: Node) -> void:
	super._on_popup_opened(key, popup)
	var repair := popup as WeaponRepair
	if key == &"Repair" and repair != null:
		if not repair.stage_changed.is_connected(_on_repair_stage_changed):
			repair.stage_changed.connect(_on_repair_stage_changed)
		if not repair.tool_switched.is_connected(_on_repair_tool_switched):
			repair.tool_switched.connect(_on_repair_tool_switched)
		_sync_repair_lesson_guidance(repair)


func _on_repair_stage_changed(_tool_id: StringName, _stage: int) -> void:
	_sync_repair_lesson_guidance()


func _on_repair_tool_switched(_tool_id: StringName) -> void:
	_sync_repair_lesson_guidance()


func _sync_repair_lesson_guidance(repair: WeaponRepair = null) -> void:
	if mode != &"practice" or lesson != &"repair":
		return
	if repair == null:
		repair = SceneManager.get_popup(&"Repair") as WeaponRepair
	var total_stages := equipment.repair_steps
	var current_stage := equipment.stage(&"beam")
	if equipment.is_full(&"beam"):
		_repaired = true
		if is_instance_valid(repair): repair.clear_stage_hint()
		run_hint.text = "Focused Flash restored."
		return
	if not is_instance_valid(repair):
		run_hint.text = "Press E to repair the yellow flash camera (%d / %d sections restored)." % [current_stage, total_stages]
		return
	if repair.tool != &"beam":
		repair.show_stage_hint("Press 2 or Tab to select Focused Flash.")
		return
	var part_label := String(repair.active_op.get("part_label", "Marked Part"))
	AudioManager.say(StringName("tutorial.repair." + String(repair.current_operation_kind())), 4, true)
	var prompt := String(repair.active_op.get("prompt", "Follow the highlighted guide."))
	var stage_num := clampi(current_stage + 1, 1, total_stages)
	repair.show_stage_hint("Stage %d / %d (%s): %s" % [stage_num, total_stages, part_label, prompt])
	run_hint.text = "Repair %d / %d · %s" % [stage_num, total_stages, part_label]


func _on_emergency_started(choice_count: int) -> void:
	super._on_emergency_started(choice_count)
	_emergency_selected_index = 0
	if SceneManager.has_popup(&"Repair"):
		_close_repair()
	weapons.cancel_input()
	weapons.mouse_held = false
	player.reset_input()
	if time_controller != null:
		time_controller.slow_requested = false
	if (rewind_lesson != null and rewind_lesson.active) or (mode == &"practice" and lesson == &"rewind"):
		tutorial.hide()
		run_hint.text = ""
	else:
		run_hint.text = "Emergency rewind (%d left) · scroll wheel to choose a moment, then click or press Enter." % time_controller.charges_remaining
	_update_run_hud()


func _on_attempt_exhausted() -> void:
	if not _campaign_ready or mode == &"won":
		return
	retry_room()


func _finish_run(won: bool) -> void:
	if won:
		_set_music_context(&"victory")
		AudioManager.say(&"protagonist.boss_defeated", 2)
	_cancel_active_teaching_controllers()
	if _result_shown:
		return
	_result_shown = true
	mode = &"won"
	weapons.cancel_input()
	player.reset_input()
	SceneManager.show_run_result(won)


func _wave_has_post_lesson_pressure() -> bool:
	if wave_index < 0 or wave_index >= waves.size():
		return false
	var w: Dictionary = waves[wave_index]
	var w_lesson := StringName(w.get("lesson", &""))
	return bool(w.get("pressure", w_lesson.is_empty()))


func _complete_teaching_wave(custom_hint: String = "") -> void:
	director.clear()
	specimens.clear()
	_specimen_ids.clear()
	_practice_stage = &""
	_pending = 0
	_spawned = 0
	_spawn_timer = 0.0
	mode = &"recovery"
	timer = float(waves[wave_index].get("recovery", 0.35)) if wave_index >= 0 and wave_index < waves.size() else 0.35
	_sync_training_protection()
	_apply_time_capabilities()
	_seed_room_checkpoint()
	if not custom_hint.is_empty():
		run_hint.text = custom_hint
	else:
		run_hint.text = "Training complete · next exhibit ready."
	_update_run_hud()


func _begin_wave() -> void:
	_cancel_active_teaching_controllers()
	if _is_instruction_speech_busy():
		var cur_ev := String(AudioManager.get("current_event")) if AudioManager != null else ""
		if not (cur_ev in ["tutorial.movement", "tutorial.pickup", "tutorial.tool_switch", "tutorial.rewind_charges"]):
			AudioManager.stop_dialogue()
	_seed_room_checkpoint()
	wave_index += 1
	if not _debug_direct_wave:
		var skip_all_tutorials := _is_skip_tutorials_active()
		while wave_index < waves.size():
			var cand: Dictionary = waves[wave_index]
			var cand_lesson := StringName(cand.get("lesson", &""))
			var cand_pressure := bool(cand.get("pressure", cand_lesson.is_empty()))
			if not cand_lesson.is_empty() and not cand_pressure and (bool(tutorial.learned.get(cand_lesson, false)) or skip_all_tutorials):
				tutorial.learned[cand_lesson] = true
				if lesson_demo != null:
					lesson_demo.mark_learned(cand_lesson)
				var cand_tool := int(cand.get("acquire", 0))
				if cand_tool > 0 and cand_tool <= 3 and not (cand_tool in acquired):
					acquired.append(cand_tool)
				weapons.set_loadout(acquired, _preferred_tool(cand_tool if cand_tool > 0 else weapons.selected_tool))
				if cand_lesson == &"repair":
					_sync_training_protection()
					equipment.restore_tool(&"beam", 1.0)
					equipment.restore_tool(&"cone", 1.0)
				elif cand_lesson == &"slow":
					_slow_unlocked = true
					_apply_time_capabilities()
				elif cand_lesson == &"rewind":
					_rewind_unlocked = true
					_apply_time_capabilities()
				wave_index += 1
			else:
				break
	if wave_index >= waves.size():
		if room_index >= _room_definitions().size() - 1:
			_finish_run(true)
		else:
			mode = &"exit"
			museum.set_boss_ceremony_phase(&"inactive")
			museum.set_exit_open(true)
			_arm_room_exit()
			AudioManager.say(&"protagonist.room_cleared")
			_seed_room_checkpoint()
			run_hint.text = "GALLERY CLEAR · press E to toggle repair at leisure, then walk through the green doorway."
		return
	var wave: Dictionary = waves[wave_index]
	lesson = StringName(wave.get("lesson", &""))
	_sync_training_protection()
	if bool(wave.get("boss", false)):
		_set_music_context(&"boss")
	else:
		_set_music_context(&"regular_combat")
	var tool := int(wave.get("acquire", 0))
	if tool > 0 and tool <= 3 and not tool in acquired:
		_enter_pickup_mode(tool, true)
		_seed_room_checkpoint()
	elif bool(wave.get("boss", false)) and _debug_boss_phase < 0:
		weapons.cancel_input()
		weapons.mouse_held = false
		player.reset_input()
		time_controller.slow_requested = false
		mode = &"ceremony"
		title.text = {
			&"loop_boss": "The Loop Curator",
			&"sequence_boss": "The Sequence Warden",
			&"final_boss": "The Burial Device",
		}.get(wave.enemies[0], "Exhibition Guardian")
		museum.start_boss_entrance()
		AudioManager.say(StringName("boss." + String(wave.enemies[0]) + ".entrance"), 3)
	else:
		_spawn_wave()


func _desired_tool_for_lesson(id: StringName) -> int:
	return int({
		&"time_meter": 2,
		&"shot": 2,
		&"charge": 2,
		&"heat": 3,
		&"repair": 2,
		&"cut": 1,
		&"opening": 1,
		&"slow": 2,
		&"rewind": 2 if 2 in acquired else 1,
		&"loop": 1,
		&"pair": 2,
		&"zigzag": 1,
	}.get(id, 2))


func _reset_rep_flags() -> void:
	_kills.clear()
	_charged_kills.clear()
	_opened = false
	_cut = false
	_heated = false
	_slow_used = false
	_pierced = false
	_practice_age = 0.0


func _spawn_wave() -> void:
	_cancel_active_teaching_controllers()
	title.text = ""
	_pending = 0
	_spawned = 0
	_spawn_timer = 0.0
	_sync_training_protection()
	if wave_index >= 0 and wave_index < waves.size() and bool(waves[wave_index].get("boss", false)):
		_set_music_context(&"boss")
	else:
		_set_music_context(&"regular_combat")
	if lesson.is_empty() or tutorial.is_learned(lesson):
		if lesson == &"repair":
			tutorial.learned[&"repair"] = true
			_sync_training_protection()
			equipment.restore_tool(&"beam", 1.0)
		elif lesson == &"slow":
			_slow_unlocked = true
			_apply_time_capabilities()
		elif lesson == &"rewind":
			_rewind_unlocked = true
			_apply_time_capabilities()
		_practice_stage = &""
		specimens.clear()
		_specimen_ids.clear()
		if not lesson.is_empty() and not _wave_has_post_lesson_pressure() and not _debug_direct_wave and bool(GameState.preferences().get("tutorial", true)):
			lesson = &""
			_complete_teaching_wave()
			return
		_start_pressure()
		return
	_reset_rep_flags()
	_repaired = false
	_rewound = false
	_injury_given = false
	var quotas := practice_quotas_for(lesson)
	_stationary_quota = quotas.x
	_stationary_done = 0
	_moving_quota = quotas.y
	_moving_done = 0
	mode = &"practice"
	weapons.select_tool(_preferred_tool(_desired_tool_for_lesson(lesson)))
	if lesson == &"time_meter":
		_practice_stage = &"demo"
		_play_lesson_speech(&"time_meter")
		run_hint.text = ""
		if lesson_demo != null and lesson_demo.begin(self, &"time_meter", tutorial):
			_update_run_hud()
			return
		_begin_builtin_time_meter_demo()
		return
	if lesson == &"repair":
		_practice_stage = &"repair"
		_play_lesson_speech(&"repair")
		_spawn_practice()
		tutorial.show_known_lesson(lesson, _targets())
		var total_stages := maxi(1, equipment.repair_steps)
		run_hint.text = "Practice exhibit · press E to open repair and complete all %d stages on the yellow flash camera." % total_stages
		_seed_room_checkpoint()
		_update_run_hud()
		return
	if lesson == &"rewind":
		_practice_stage = &"rewind"
		_play_lesson_speech(&"rewind")
		_rewind_unlocked = true
		_apply_time_capabilities()
		tutorial.dismiss()
		run_hint.text = ""
		if rewind_lesson != null:
			rewind_lesson.begin(self)
		_update_run_hud()
		return
	_practice_stage = &"demo"
	_play_lesson_speech(lesson)
	run_hint.text = ""
	if lesson_demo != null and lesson_demo.begin(self, lesson, tutorial):
		_update_run_hud()
		return
	_start_stationary_practice()


func _begin_builtin_time_meter_demo() -> void:
	_practice_stage = &"time_meter_demo"
	_time_meter_elapsed = 0.0
	_time_meter_hit_applied = false
	_time_meter_recharged = false
	_time_meter_sync_steps = 0
	_time_meter_last_frame = Engine.get_process_frames()
	director.clear()
	specimens.clear()
	_specimen_ids.clear()
	if time_controller != null:
		time_controller.slow_requested = false
		time_controller.begin_attempt()
		_time_meter_min_meter = time_controller.meter
		_time_meter_max_after_hit = 0.0
	var demo_pos := player.position + Vector3(0.0, 0.0, -2.5)
	var demo_enemy: Node3D = director.spawn(&"yellow", demo_pos)
	if is_instance_valid(demo_enemy):
		specimens.append(demo_enemy)
		_specimen_ids.append(demo_enemy.rewind_id)
		_make_specimen_safe(demo_enemy)
		_set_enemy_instruction_visible(demo_enemy, false)
	if is_instance_valid(tutorial):
		var target_pts: Array[Vector3] = _targets()
		if not tutorial.show_known_lesson(&"time_meter", target_pts):
			tutorial.show_lesson(
				&"time_meter",
				"Watch your time reserve",
				TIME_METER_LINE,
				target_pts
			)
			tutorial.set_phase_accent(ToolStyle.CLOCK, "TIME RESERVE · DRAIN & RECHARGE")
		if tutorial.has_method("set_demo_busy"):
			tutorial.call("set_demo_busy", true)
	_update_run_hud()


func _step_time_meter_demo(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return
	var cur_frame := Engine.get_process_frames()
	if cur_frame == _time_meter_last_frame:
		_time_meter_sync_steps += 1
	else:
		_time_meter_last_frame = cur_frame
		_time_meter_sync_steps = 0
	_time_meter_elapsed += dt
	if not specimens.is_empty() and is_instance_valid(specimens[0]):
		var enemy: Node3D = specimens[0]
		enemy.contact_damage = 0.0
		enemy.move_speed = 0.0
		if _time_meter_elapsed < 0.35:
			var t := clampf(_time_meter_elapsed / 0.35, 0.0, 1.0)
			enemy.position = player.position + Vector3(0.0, 0.0, lerpf(-2.5, -1.05, t))
		else:
			var t_back := clampf((_time_meter_elapsed - 0.35) / 0.45, 0.0, 1.0)
			enemy.position = player.position + Vector3(0.0, 0.0, lerpf(-1.05, -2.8, t_back))
	if not _time_meter_hit_applied and _time_meter_elapsed >= 0.35:
		_time_meter_hit_applied = true
		if time_controller != null:
			time_controller.apply_hit(34.0)
			_time_meter_min_meter = minf(_time_meter_min_meter, time_controller.meter)
			_time_meter_max_after_hit = time_controller.meter
		_damage_flash = 0.35
	elif _time_meter_hit_applied and time_controller != null:
		time_controller.slow_requested = false
		time_controller.advance(dt * 2.4)
		_time_meter_max_after_hit = maxf(_time_meter_max_after_hit, time_controller.meter)
		if _time_meter_max_after_hit >= _time_meter_min_meter + 12.0 and _time_meter_elapsed >= 1.4:
			_time_meter_recharged = true
			if is_instance_valid(tutorial) and tutorial.has_method("set_demo_busy"):
				tutorial.call("set_demo_busy", false)
	if status_hud != null and is_instance_valid(player) and is_instance_valid(weapons) and is_instance_valid(equipment):
		status_hud.update_status(player, weapons, equipment)
	if _time_meter_recharged:
		if _time_meter_sync_steps >= 90 and AudioManager != null and AudioManager.has_method("stop_dialogue"):
			AudioManager.stop_dialogue()
		if not _is_instruction_speech_busy():
			_finish_time_meter_lesson(false)


func _finish_time_meter_lesson(skipped: bool = false) -> void:
	if skipped and AudioManager != null:
		AudioManager.stop_dialogue()
	if lesson_demo != null and lesson_demo.active:
		lesson_demo.cancel()
	director.clear()
	specimens.clear()
	_specimen_ids.clear()
	if is_instance_valid(player) and "max_health" in player:
		player.health = player.max_health
	if time_controller != null:
		time_controller.slow_requested = false
		time_controller.begin_attempt()
	if is_instance_valid(tutorial):
		tutorial.learned[&"time_meter"] = true
		if tutorial.active_id == &"time_meter":
			if tutorial.blocking:
				tutorial.request_practice()
			tutorial.complete_lesson(&"time_meter")
		else:
			tutorial.dismiss()
	if lesson_demo != null:
		lesson_demo.mark_learned(&"time_meter")
	weapons.cancel_input()
	weapons.mouse_held = false
	if skipped or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		weapons.require_fresh_press = true
	lesson = &""
	_practice_stage = &""
	_complete_teaching_wave("Time reserve restored · next exhibit ready.")


func _on_lesson_demo_ready_for_practice(id: StringName) -> void:
	if mode != &"practice" or lesson != id:
		return
	if id == &"time_meter":
		var skipped_tm := lesson_demo != null and bool(lesson_demo.last_summary.get("skipped", false))
		if skipped_tm or not _is_instruction_speech_busy():
			_finish_time_meter_lesson(skipped_tm)
		else:
			_practice_stage = &"await_speech"
			_update_run_hud()
		return
	if tutorial.is_learned(id):
		if id == &"slow":
			_slow_unlocked = true
			_apply_time_capabilities()
		_practice_stage = &""
		if not _wave_has_post_lesson_pressure() and bool(GameState.preferences().get("tutorial", true)):
			lesson = &""
			_complete_teaching_wave()
		else:
			_start_pressure()
		return
	var was_skipped := lesson_demo != null and bool(lesson_demo.last_summary.get("skipped", false))
	if was_skipped or tutorial.practicing:
		if _is_instruction_speech_busy():
			AudioManager.stop_dialogue()
		_start_stationary_practice()
		return
	if _is_instruction_speech_busy():
		_practice_stage = &"await_speech"
		_update_run_hud()
		return
	_start_stationary_practice()


func _start_stationary_practice() -> void:
	if _is_instruction_speech_busy():
		AudioManager.stop_dialogue()
	AudioManager.say(&"tutorial.practice_ready", 2)
	if lesson == &"slow":
		_slow_unlocked = true
		_apply_time_capabilities()
	_practice_stage = &"stationary"
	_stationary_done = 0
	_moving_done = 0
	_spawn_practice()
	if not tutorial.visible or tutorial.active_id != lesson:
		tutorial.show_known_lesson(lesson, _targets())
	if tutorial.blocking:
		tutorial.request_practice()
	_sync_practice_tutorial_prompt()
	run_hint.text = "Practice exhibit · stationary target %d / %d." % [clampi(_stationary_done + 1, 1, maxi(1, _stationary_quota)), maxi(1, _stationary_quota)]
	_seed_room_checkpoint()
	_update_run_hud()


func _finish_rewind_charges_speech(skipped: bool = false) -> void:
	_awaiting_rewind_charges_speech = false
	_rewind_charges_elapsed = 0.0
	_rewind_charges_speech_accepted = false
	if rewind_lesson != null:
		rewind_lesson._sync_banner()
	if skipped:
		if AudioManager != null:
			AudioManager.stop_dialogue()
		var lmb_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if lmb_down:
			_suppress_next_lmb_release = true
		weapons.cancel_input()
		weapons.mouse_held = false
		weapons.require_fresh_press = true
	if mode == &"recovery":
		run_hint.text = "Emergency rewind ready · next exhibit group approaching."
		_update_run_hud()
		if timer <= 0.0 and equipment.repairing == &"":
			_begin_wave()


func _step_rewind_charges_wait(delta: float) -> void:
	if not _awaiting_rewind_charges_speech:
		return
	_rewind_charges_elapsed += maxf(0.0, delta)
	var charges_speaking := _is_event_speaking(&"tutorial.rewind_charges")
	if not is_physics_processing() and _rewind_charges_elapsed >= 3.2:
		if charges_speaking and AudioManager != null:
			AudioManager.stop_dialogue()
		_finish_rewind_charges_speech(false)
		return
	if not charges_speaking and (not _rewind_charges_speech_accepted and _rewind_charges_elapsed >= 0.85 or _rewind_charges_speech_accepted):
		_finish_rewind_charges_speech(false)


func _on_rewind_lesson_completed() -> void:
	tutorial.learned[&"rewind"] = true
	if lesson_demo != null:
		lesson_demo.mark_learned(&"rewind")
	_rewind_unlocked = true
	_rewound = true
	_injury_given = true
	_practice_stage = &""
	lesson = &""
	tutorial.dismiss()
	_apply_time_capabilities()
	if time_controller != null:
		time_controller.set_capabilities(_slow_unlocked, true)
		time_controller.begin_attempt()
	_suppress_enter_release = true
	var was_skipped := rewind_lesson != null and rewind_lesson.was_skipped
	if was_skipped:
		_awaiting_rewind_charges_speech = false
		_rewind_charges_elapsed = 0.0
		_rewind_charges_speech_accepted = false
		if AudioManager != null:
			AudioManager.stop_dialogue()
		if _wave_has_post_lesson_pressure():
			_start_pressure()
		else:
			_complete_teaching_wave("Emergency rewind ready · next exhibit group approaching.")
		_update_run_hud()
		return
	if AudioManager != null:
		AudioManager.stop_dialogue()
		_rewind_charges_speech_accepted = AudioManager.say(&"tutorial.rewind_charges", 3, true)
	else:
		_rewind_charges_speech_accepted = false
	_awaiting_rewind_charges_speech = true
	_rewind_charges_elapsed = 0.0
	if rewind_lesson != null and rewind_lesson.overlay != null:
		rewind_lesson.overlay.visible = true
		if is_instance_valid(rewind_lesson.title_label):
			rewind_lesson.title_label.text = "EMERGENCY REWIND"
		if is_instance_valid(rewind_lesson.action_label):
			rewind_lesson.action_label.text = REWIND_CHARGES_LINE
		if is_instance_valid(rewind_lesson.skip_button):
			rewind_lesson.skip_button.text = "Skip"
			rewind_lesson.skip_button.visible = true
			rewind_lesson.skip_button.disabled = false
			rewind_lesson.skip_button.focus_mode = Control.FOCUS_NONE
	if _wave_has_post_lesson_pressure():
		_start_pressure()
	else:
		_complete_teaching_wave(REWIND_CHARGES_LINE)
	_update_run_hud()


func _spawn_practice() -> void:
	director.clear()
	specimens.clear()
	_specimen_ids.clear()
	_reset_rep_flags()
	if lesson == &"repair":
		_sync_training_protection()
		equipment.restore_tool(&"cone", 1.0)
		equipment.restore_tool(&"beam", 1.0)
		equipment.spend(&"beam", equipment.capacity(&"beam"))
		weapons.select_tool(2)
		return
	if lesson in [&"rewind", &"time_meter"]:
		return
	for slot in acquired:
		var tool_name: StringName = TOOL_IDS[clampi(int(slot) - 1, 0, TOOL_IDS.size() - 1)]
		if equipment.remaining(tool_name) < equipment.capacity(tool_name) * 0.35:
			equipment.restore_tool(tool_name, 0.5)
	weapons.select_tool(_preferred_tool(_desired_tool_for_lesson(lesson)))
	var rep_seed := room_index * 37 + wave_index * 13 + _stationary_done * 5 + _moving_done * 11
	if lesson == &"opening":
		var rep_idx := _stationary_done if _practice_stage == &"stationary" else _moving_done
		var guard_kind: StringName = &"side_guard" if (rep_idx % 2) == 0 else &"front_guard"
		weapons.select_tool(_preferred_tool(1 if guard_kind == &"side_guard" else 3))
		specimens.assign(director.spawn_formation(&"curve", [guard_kind], player, rep_seed))
	else:
		var kind: StringName = StringName(waves[wave_index].enemies[0])
		if lesson == &"cut":
			kind = &"blue"
		elif lesson == &"slow":
			kind = &"yellow"
		elif lesson in [&"shot", &"charge"]:
			kind = &"yellow"
		elif lesson == &"heat":
			kind = &"orange"
		elif lesson in [&"pair", &"loop", &"zigzag"]:
			kind = lesson
		var count := 3 if lesson == &"charge" else 1
		specimens.assign(director.spawn_formation(&"line" if lesson == &"charge" else &"curve", _repeat(kind, count), player, rep_seed))
		if lesson == &"heat" and not specimens.is_empty() and is_instance_valid(specimens[0]):
			var heat_enemy: Node3D = specimens[0]
			var to_enemy := heat_enemy.position - player.position
			to_enemy.y = 0.0
			var dir := to_enemy.normalized() if to_enemy.length() > 0.05 else Vector3.FORWARD
			var target_dist := 2.8 if _practice_stage == &"stationary" else 4.0
			heat_enemy.position = Vector3(
				clampf(player.position.x + dir.x * target_dist, -14.0, 14.0),
				heat_enemy.position.y,
				clampf(player.position.z + dir.z * target_dist, -14.0, 14.0)
			)
	for enemy in specimens:
		_specimen_ids.append(enemy.rewind_id)
		_make_specimen_safe(enemy)
	if "flow" in director and director.flow != null and director.flow.has_method("reset"):
		director.flow.reset()


func _make_specimen_safe(enemy: Node3D) -> void:
	if not is_instance_valid(enemy):
		return
	enemy.contact_damage = 0.0
	if _practice_stage == &"moving":
		var base_speed := float(Tuning.ENEMIES.get(String(enemy.kind), {}).get("speed", 2.2))
		enemy.move_speed = maxf(1.5, base_speed * 0.72)
	else:
		enemy.move_speed = 0.0
	# Safe practice must also suppress ranged/boss offense, not just touch damage.
	if "projectile_damage" in enemy:
		enemy.projectile_damage = 0.0
	if "attack_timer" in enemy:
		enemy.attack_timer = 99.0
	_set_enemy_instruction_visible(enemy, true)


func _set_enemy_instruction_visible(enemy: Node3D, visible_flag: bool) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy.has_method("set_instruction_visible"):
		enemy.set_instruction_visible(visible_flag)
	if "part_visual" in enemy and is_instance_valid(enemy.part_visual) and enemy.part_visual.has_method("set_instruction_visible"):
		enemy.part_visual.set_instruction_visible(visible_flag)
	if "pattern_visual" in enemy and is_instance_valid(enemy.pattern_visual) and enemy.pattern_visual.has_method("set_instruction_visible"):
		enemy.pattern_visual.set_instruction_visible(visible_flag)


func _maintain_practice_specimens(_world_delta: float) -> void:
	if _practice_stage == &"stationary":
		for enemy in specimens:
			if not is_instance_valid(enemy) or enemy.health <= 0:
				continue
			enemy.contact_damage = 0.0
			enemy.move_speed = 0.0
			if lesson == &"heat":
				var offset := enemy.position - player.position
				offset.y = 0.0
				if offset.length() > 4.65:
					var dir := offset.normalized()
					enemy.position = Vector3(
						player.position.x + dir.x * 4.65,
						enemy.position.y,
						player.position.z + dir.z * 4.65
					)
			elif "knockback_vel" in enemy:
				enemy.knockback_vel = Vector3.ZERO
	elif _practice_stage == &"moving":
		var line_dir := Vector3.FORWARD
		if lesson == &"charge" and not specimens.is_empty() and is_instance_valid(specimens.back()):
			var to_back: Vector3 = (specimens.back() as Node3D).position - player.position
			to_back.y = 0.0
			if to_back.length() > 0.05:
				line_dir = to_back.normalized()
		for idx in range(specimens.size()):
			var enemy := specimens[idx]
			if not is_instance_valid(enemy) or enemy.health <= 0:
				continue
			enemy.contact_damage = 0.0
			var base_speed := float(Tuning.ENEMIES.get(String(enemy.kind), {}).get("speed", 2.2))
			if enemy.move_speed < 1.2:
				enemy.move_speed = maxf(1.5, base_speed * 0.72)
			if lesson == &"charge":
				var offset := enemy.position - player.position
				offset.y = 0.0
				var dist := clampf(offset.length(), 3.2 + float(idx) * 2.1, 10.5 + float(idx) * 2.1)
				enemy.position = Vector3(
					clampf(player.position.x + line_dir.x * dist, -17.5, 17.5),
					enemy.position.y,
					clampf(player.position.z + line_dir.z * dist, -17.5, 17.5)
				)


func _sync_practice_tutorial_prompt() -> void:
	if not is_instance_valid(tutorial) or tutorial.active_id != lesson:
		return
	tutorial.world_points.assign(_targets())
	if not tutorial.practicing:
		return
	var base_sub := Tutorial.subtitle_for_lesson(lesson)
	var col := Tutorial.accent_for_lesson(lesson)
	if lesson == &"opening" and not _opened and not specimens.is_empty() and is_instance_valid(specimens[0]) and specimens[0].kind == &"front_guard":
		col = ToolStyle.CONE
		base_sub = "3 · HEAT BELLOWS · THEN 2"
	elif lesson in [&"opening", &"loop", &"zigzag"] and _opened:
		col = ToolStyle.BEAM
		base_sub = "2 · FOCUSED FLASH · CHARGE YELLOW" if lesson in [&"loop", &"zigzag"] else "2 · FOCUSED FLASH · SHOOT YELLOW"
	if _practice_stage == &"stationary" and _stationary_quota > 0:
		var rep_num := clampi(_stationary_done + 1, 1, _stationary_quota)
		tutorial.set_phase_accent(col, "%s · STATIONARY %d/%d" % [base_sub, rep_num, _stationary_quota])
	elif _practice_stage == &"moving" and _moving_quota > 0:
		var rep_num := clampi(_moving_done + 1, 1, _moving_quota)
		tutorial.set_phase_accent(col, "%s · MOVING %d/%d" % [base_sub, rep_num, _moving_quota])


func _advance_practice_rep() -> void:
	if lesson == &"repair":
		if _is_instruction_speech_busy():
			AudioManager.stop_dialogue()
		if tutorial.blocking:
			tutorial.request_practice()
		tutorial.complete_lesson(lesson)
		if lesson_demo != null:
			lesson_demo.mark_learned(&"repair")
		lesson = &""
		_practice_stage = &""
		_sync_training_protection()
		_apply_time_capabilities()
		equipment.restore_tool(&"beam", 1.0)
		equipment.restore_tool(&"cone", 1.0)
		if SceneManager.has_popup(&"Repair"):
			_close_repair()
		if _wave_has_post_lesson_pressure():
			_seed_room_checkpoint()
			_start_pressure()
		else:
			_complete_teaching_wave("Tools restored · next exhibit group approaching.")
		return
	if _practice_stage == &"stationary":
		_stationary_done += 1
		if _stationary_done < _stationary_quota:
			_spawn_practice()
			_sync_practice_tutorial_prompt()
			run_hint.text = "Practice exhibit · stationary target %d / %d." % [clampi(_stationary_done + 1, 1, maxi(1, _stationary_quota)), maxi(1, _stationary_quota)]
			_seed_room_checkpoint()
			_update_run_hud()
			return
		if _moving_quota > 0:
			_practice_stage = &"moving"
			_moving_done = 0
			_spawn_practice()
			_sync_practice_tutorial_prompt()
			run_hint.text = "Practice exhibit · moving target %d / %d." % [clampi(_moving_done + 1, 1, maxi(1, _moving_quota)), maxi(1, _moving_quota)]
			_seed_room_checkpoint()
			_update_run_hud()
			return
	_moving_done += 1
	if _practice_stage == &"moving" and _moving_done < _moving_quota:
		_spawn_practice()
		_sync_practice_tutorial_prompt()
		run_hint.text = "Practice exhibit · moving target %d / %d." % [clampi(_moving_done + 1, 1, maxi(1, _moving_quota)), maxi(1, _moving_quota)]
		_seed_room_checkpoint()
		_update_run_hud()
		return
	var finished_lesson := lesson
	if _is_instruction_speech_busy():
		AudioManager.stop_dialogue()
	if tutorial.blocking:
		tutorial.request_practice()
	tutorial.complete_lesson(finished_lesson)
	if lesson_demo != null:
		lesson_demo.mark_learned(finished_lesson)
	lesson = &""
	_practice_stage = &""
	_sync_training_protection()
	_apply_time_capabilities()
	if _wave_has_post_lesson_pressure():
		_seed_room_checkpoint()
		_start_pressure()
	else:
		_complete_teaching_wave()


func _repeat(kind: StringName, count: int) -> Array:
	var result: Array = []
	for i in range(count):
		result.append(kind)
	return result


func _start_pressure() -> void:
	# Training bodies are retired; each pressure roster is explicit and finite.
	director.clear()
	specimens.clear()
	_specimen_ids.clear()
	_practice_stage = &""
	mode = &"pressure"
	_sync_training_protection()
	_pending = int(waves[wave_index].count)
	_spawned = 0
	_spawn_timer = 0.0
	_seed_room_checkpoint()
	_step_pressure(0.0)


func _boss_phase_guidance(boss: Node3D) -> Dictionary:
	var bkind: StringName = boss.get("kind") if is_instance_valid(boss) else &"final_boss"
	var bphase := int(boss.get("phase")) if is_instance_valid(boss) else 0
	var pat: StringName = boss.call("active_pattern") if (is_instance_valid(boss) and boss.has_method("active_pattern")) else &"core"
	var core_open := bool(boss.get("pattern_open")) or pat == &"core"
	var total_phases := 4 if bkind == &"final_boss" else 3
	var phase_num := clampi(bphase + 1, 1, total_phases)
	var btitle := String({
		&"loop_boss": "Loop Curator",
		&"sequence_boss": "Sequence Warden",
		&"final_boss": "Burial Device",
	}.get(bkind, "Exhibition Guardian"))
	if core_open:
		var is_final_core := (bkind == &"final_boss" and phase_num == 4)
		return {
			"heading": "Hold, then release",
			"body": "2 · Focused Flash - charge and fire into the exposed yellow core%s." % (" to finish the Guardian" if is_final_core else ""),
			"subtitle": "%s · PHASE %d/%d EXPOSED CORE" % [btitle.to_upper(), phase_num, total_phases],
			"color": ToolStyle.BEAM,
			"hint": "%s (%d/%d) · yellow core exposed - charge 2 (Focused Flash) on the yellow core." % [btitle, phase_num, total_phases],
		}
	if pat == &"pair":
		return {
			"heading": "Click A, then B",
			"body": "2 · Focused Flash - shoot valve A, then shoot valve B before its shutter closes.",
			"subtitle": "%s · PHASE %d/%d PAIR VALVES" % [btitle.to_upper(), phase_num, total_phases],
			"color": ToolStyle.BEAM,
			"hint": "%s (%d/%d) · press 2 (Focused Flash) to shoot valve A, then valve B." % [btitle, phase_num, total_phases],
		}
	if pat == &"zigzag":
		return {
			"heading": "Hold, draw, release",
			"body": "1 · Ring Cutter - bend across all 3 blue zigzag spans in one stroke.",
			"subtitle": "%s · PHASE %d/%d ZIGZAG LOCK" % [btitle.to_upper(), phase_num, total_phases],
			"color": ToolStyle.RING,
			"hint": "%s (%d/%d) · hold 1 (Ring Cutter) and bend across all 3 blue zigzag spans." % [btitle, phase_num, total_phases],
		}
	return {
		"heading": "Hold, draw, release",
		"body": "1 · Ring Cutter - draw a loop across all 4 blue supports in one stroke.",
		"subtitle": "%s · PHASE %d/%d LOOP LOCK" % [btitle.to_upper(), phase_num, total_phases],
		"color": ToolStyle.RING,
		"hint": "%s (%d/%d) · hold 1 (Ring Cutter) and draw a loop through all 4 blue supports." % [btitle, phase_num, total_phases],
	}


func _step_pressure(world_delta: float) -> void:
	var wave: Dictionary = waves[wave_index]
	var is_boss_wave := bool(wave.get("boss", false))
	var live_boss: Node3D = null
	if is_boss_wave:
		for enemy in director.enemies:
			if is_instance_valid(enemy) and enemy.has_method("is_boss") and enemy.is_boss() and enemy.health > 0:
				live_boss = enemy
				break
		if _spawned >= 1 and live_boss == null:
			_pending = 0
			director.clear()
			return
	if _pending > 0 and director.enemies.size() <= (0 if int(wave.burst) <= 1 else 1):
		if not is_boss_wave or _spawned == 0:
			_spawn_timer = minf(_spawn_timer, float(wave.get("refill_delay", 0.75)))
	_spawn_timer = maxf(0.0, _spawn_timer - maxf(0.0, world_delta))
	if _pending > 0 and _spawn_timer <= 0.0:
		var space := maxi(0, int(wave.max_live) - director.enemies.size())
		var count := mini(_pending, mini(int(wave.burst), space))
		if is_boss_wave and _spawned == 0: count = mini(count, 1)
		if count > 0:
			var wave_enemies: Array = wave.get("enemies", [])
			var kinds: Array = []
			for i in range(count):
				var kind_idx: int = (_spawned + i) % maxi(1, wave_enemies.size())
				if is_boss_wave and (_spawned + i) > 0 and wave_enemies.size() > 1:
					kind_idx = 1 + ((_spawned + i - 1) % (wave_enemies.size() - 1))
				kinds.append(wave_enemies[kind_idx])
			var arrived: Array = director.spawn_formation(wave.formation, kinds, player, room_index * 53 + wave_index * 7 + _spawned)
			for spawned_enemy in arrived:
				_set_enemy_instruction_visible(spawned_enemy, false)
			_pending -= arrived.size()
			_spawned += arrived.size()
			_spawn_timer = float(wave.interval) if not arrived.is_empty() else 1.0
			if _debug_boss_phase >= 0 and is_boss_wave and not arrived.is_empty():
				var boss: Node3D = arrived[0]
				boss.debug_set_phase(_debug_boss_phase)
				_debug_boss_phase = -1
			if is_boss_wave and live_boss == null and not arrived.is_empty():
				live_boss = arrived[0]
	if is_boss_wave:
		if is_instance_valid(live_boss):
			var guide := _boss_phase_guidance(live_boss)
			run_hint.text = String(guide.get("hint", ""))
			if is_instance_valid(tutorial) and tutorial.visible and tutorial.active_id == &"final":
				tutorial.set_phase_prompt(
					String(guide.get("heading", "")),
					String(guide.get("body", "")),
					guide.get("color", ToolStyle.BEAM),
					String(guide.get("subtitle", ""))
				)
				tutorial.world_points.assign([live_boss.core_world_position() if live_boss.has_method("core_world_position") else live_boss.position + Vector3.UP])
		else:
			run_hint.text = "Exhibition Guardian approaching · prepare tools 1 and 2."
	else:
		run_hint.text = "Exhibit %d / %d · %d active · %d reinforcements · keep an escape lane." % [wave_index + 1, waves.size(), director.enemies.size(), _pending]


func _needs_combat_target() -> bool:
	return not (lesson in [&"repair", &"rewind", &"time_meter"])


func _alive_specimens() -> int:
	var count := 0
	for enemy in specimens:
		if is_instance_valid(enemy) and enemy.health > 0:
			count += 1
	return count


func _observe_specimens() -> void:
	for enemy in specimens:
		if not is_instance_valid(enemy):
			continue
		if enemy.health <= 0:
			_kills[enemy.rewind_id] = true
		_cut = _cut or enemy.cable_cut
		_heated = _heated or enemy.plate_broken
		_opened = _opened or enemy.is_core_exposed()


func _lesson_succeeded() -> bool:
	if lesson == &"time_meter":
		return _time_meter_recharged
	if lesson == &"repair":
		return _repaired and equipment.is_full(&"beam")
	if lesson == &"rewind":
		return _rewound and _injury_given and not is_emergency_active()
	if lesson == &"slow":
		if 1 in acquired:
			return _slow_used and (_cut or not _kills.is_empty()) and not _kills.is_empty()
		return _slow_used and not _kills.is_empty()
	if lesson == &"charge":
		return _pierced and _charged_kills.size() >= 2
	if lesson == &"cut":
		return _cut and not _kills.is_empty()
	if lesson == &"heat":
		return _heated and not _kills.is_empty()
	if lesson in [&"opening", &"loop", &"zigzag"]:
		return _opened and not _kills.is_empty()
	return not _kills.is_empty()


func _targets() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for enemy in specimens:
		if not is_instance_valid(enemy) or enemy.health <= 0:
			continue
		if enemy.has_method("active_pattern") and enemy.active_pattern() == &"pair":
			points.append(enemy.valve_world_position(0))
			points.append(enemy.valve_world_position(1))
		elif (lesson == &"heat" or (lesson == &"opening" and enemy.kind == &"front_guard" and not enemy.is_core_exposed())) and is_instance_valid(enemy.part_visual) and is_instance_valid(enemy.part_visual.plate):
			points.append(enemy.part_visual.plate.global_position + Vector3.UP * 0.5)
		elif lesson == &"opening" and not enemy.is_core_exposed():
			var ends: Array = enemy.cable_world_points()
			if ends.size() >= 2:
				points.append((ends[0] + ends[-1]) * 0.5)
		elif lesson in [&"cut", &"slow", &"loop", &"zigzag"] and enemy.has_cuttable_part():
			var cable: Array = enemy.cable_world_points()
			if enemy.has_method("lesson_state"):
				for i in range(0, cable.size() - 1, 2):
					points.append((cable[i] + cable[i + 1]) * 0.5)
			elif cable.size() >= 2:
				points.append((cable[0] + cable[-1]) * 0.5)
		else:
			points.append(enemy.core_world_position() if enemy.is_core_exposed() else enemy.position + Vector3.UP)
	if points.is_empty():
		points.append(player.position)
	return points


func _on_run_event(_kind: StringName, _point: Vector3, _strength: float) -> void:
	pass


func _on_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int) -> void:
	if mode != &"practice":
		return
	# The director may prune a killed target before the next campaign tick.
	_observe_specimens()
	if bool(result.get("killed", false)):
		_kills[enemy_id] = true
	if tool == &"beam" and bool(result.get("killed", false)) and bool(context.get("piercing", false)):
		_charged_kills[enemy_id] = true
		_pierced = _pierced or int(context.get("prior_hits", 0)) > 0


func _on_equipment_repaired(tool: StringName, amount: float) -> void:
	if tool == &"beam" and amount > 0.0:
		if equipment.is_full(&"beam"):
			_repaired = true
		_sync_repair_lesson_guidance()


func _on_wounded(_amount: float) -> void:
	_damage_flash = 0.5


func _update_run_hud() -> void:
	if run_hint == null:
		return
	var demo_or_scrub := (
		(lesson_demo != null and lesson_demo.active)
		or (rewind_lesson != null and rewind_lesson.active)
		or is_emergency_active()
	)
	var contextual := mode in [&"pickup", &"practice", &"exit"] or (mode == &"recovery" and _awaiting_rewind_charges_speech) or SceneManager.developer_tools
	run_hint.visible = contextual and not tutorial.visible and not demo_or_scrub and equipment.repairing == &"" and not run_hint.text.is_empty()


func capture_state() -> Dictionary:
	var data := super.capture_state()
	# Reinforcement debt and wave scheduler rewind atomically with enemies.
	# Learned controls, acquired tools, capability unlocks, and time/charges do not.
	data["campaign_wave"] = {
		"room": room_index,
		"wave": wave_index,
		"mode": mode,
		"mode_timer": timer,
		"pending": _pending,
		"spawned": _spawned,
		"timer": _spawn_timer,
		"lesson": lesson,
		"specimen_ids": _specimen_ids.duplicate(),
		"practice": _capture_practice(),
	}
	return data


func _capture_practice() -> Dictionary:
	return {
		"stage": _practice_stage,
		"stat_quota": _stationary_quota,
		"stat_done": _stationary_done,
		"mov_quota": _moving_quota,
		"mov_done": _moving_done,
		"kills": _kills.duplicate(), "charged_kills": _charged_kills.duplicate(),
		"opened": _opened, "cut": _cut, "heated": _heated,
		"slow_used": _slow_used, "pierced": _pierced, "repaired": _repaired,
		"rewound": _rewound, "injury_given": _injury_given,
		"age": _practice_age,
	}


func _restore_practice(state: Dictionary) -> void:
	_practice_stage = StringName(state.get("stage", _practice_stage))
	_stationary_quota = int(state.get("stat_quota", _stationary_quota))
	_stationary_done = int(state.get("stat_done", _stationary_done))
	_moving_quota = int(state.get("mov_quota", _moving_quota))
	_moving_done = int(state.get("mov_done", _moving_done))
	_kills = state.get("kills", {}).duplicate()
	_charged_kills = state.get("charged_kills", {}).duplicate()
	_opened = bool(state.get("opened", false))
	_cut = bool(state.get("cut", false))
	_heated = bool(state.get("heated", false))
	_slow_used = bool(state.get("slow_used", false))
	_pierced = bool(state.get("pierced", false))
	_repaired = bool(state.get("repaired", false))
	_rewound = bool(state.get("rewound", false))
	_injury_given = bool(state.get("injury_given", false))
	_practice_age = float(state.get("age", 0.0))


func _restore_base_arena_state(data: Dictionary) -> void:
	_restore_world(data)


func _apply_campaign_snapshot(data: Dictionary, preview_only: bool = false) -> void:
	var preferred := int(data.get("weapons", {}).get("selected_tool", weapons.selected_tool))
	weapons.available_tools.assign(acquired)
	weapons.selected_tool = _preferred_tool(preferred)
	if not preview_only:
		var schedule: Dictionary = data.get("campaign_wave", {})
		if int(schedule.get("room", -1)) == room_index:
			var snap_wave := int(schedule.get("wave", wave_index))
			if snap_wave >= -1 and snap_wave <= waves.size():
				wave_index = snap_wave
			_pending = int(schedule.get("pending", _pending))
			_spawned = int(schedule.get("spawned", _spawned))
			_spawn_timer = float(schedule.get("timer", _spawn_timer))
			var snap_mode := StringName(schedule.get("mode", mode))
			var snap_lesson := StringName(schedule.get("lesson", lesson))
			var restored_ids: Array[int] = []
			for sid in schedule.get("specimen_ids", _specimen_ids):
				restored_ids.append(int(sid))
			_specimen_ids = restored_ids
			if snap_mode in [&"pressure", &"recovery", &"exit"]:
				mode = snap_mode
				timer = float(schedule.get("mode_timer", timer))
				lesson = snap_lesson if not tutorial.is_learned(snap_lesson) else &""
				_practice_stage = &""
				museum.clear_tool_pickup()
				museum.set_exit_open(mode == &"exit")
				if mode == &"exit":
					_forward_held_at_wave_clear = false
					_arm_room_exit()
			elif snap_mode == &"title":
				mode = &"title"
				timer = float(schedule.get("mode_timer", 0.0))
				lesson = &""
				_practice_stage = &""
				museum.clear_tool_pickup()
				museum.set_exit_open(false)
			elif snap_mode == &"practice":
				museum.clear_tool_pickup()
				museum.set_exit_open(false)
				_restore_practice(schedule.get("practice", {}))
				if snap_lesson == &"rewind" and ((rewind_lesson != null and rewind_lesson.active) or (mode == &"practice" and lesson == &"rewind")):
					mode = &"practice"
					lesson = &"rewind"
					_practice_stage = &"rewind"
				elif not snap_lesson.is_empty() and not tutorial.is_learned(snap_lesson):
					mode = &"practice"
					lesson = snap_lesson
					if _practice_stage.is_empty() or _practice_stage in [&"demo", &"await_speech"]:
						_practice_stage = &"stationary"
				else:
					lesson = &""
					_practice_stage = &""
					if _wave_has_post_lesson_pressure():
						_start_pressure()
					else:
						_complete_teaching_wave()
			elif snap_mode == &"pickup":
				museum.set_exit_open(false)
				var wave_tool := int(waves[wave_index].get("acquire", 0)) if wave_index >= 0 and wave_index < waves.size() else 0
				if wave_tool > 0 and not (wave_tool in acquired):
					_enter_pickup_mode(wave_tool, false)
				else:
					museum.clear_tool_pickup()
					_spawn_wave()
		if wave_index >= 0 and wave_index < waves.size() and bool(waves[wave_index].get("boss", false)):
			_set_music_context(&"boss")
		elif mode != &"won":
			_set_music_context(&"regular_combat")
	_sync_training_protection()
	_apply_time_capabilities()
	if mode == &"practice":
		if lesson == &"rewind":
			if not preview_only:
				tutorial.dismiss()
		else:
			if not preview_only and lesson_demo != null and lesson_demo.active:
				lesson_demo.cancel(false)
			specimens.clear()
			for enemy in director.enemies:
				if enemy.rewind_id in _specimen_ids:
					specimens.append(enemy)
					_make_specimen_safe(enemy)
			if not preview_only:
				if tutorial.active_id != lesson:
					tutorial.show_known_lesson(lesson, _targets())
				if _practice_stage in [&"stationary", &"moving"] and tutorial.blocking:
					tutorial.request_practice()
				_sync_practice_tutorial_prompt()
	elif not preview_only:
		tutorial.dismiss()
	weapons.rebuild_visuals(player)
	_update_run_hud()


func restore_campaign_state(data: Dictionary) -> void:
	_restore_base_arena_state(data)
	_apply_campaign_snapshot(data, false)


func _on_emergency_selection_changed(index: int, age_seconds: float, state: Dictionary) -> void:
	super._on_emergency_selection_changed(index, age_seconds, state)
	_emergency_selected_index = index
	if state.is_empty():
		return
	_apply_campaign_snapshot(state, true)


func _on_emergency_confirmed(age_seconds: float, state: Dictionary) -> void:
	super._on_emergency_confirmed(age_seconds, state)
	if not state.is_empty():
		_apply_campaign_snapshot(state, false)
	if _emergency_selected_index > 0 or age_seconds > 0.0 or age_seconds == EmergencyRewind.CHECKPOINT_AGE:
		_rewound = true
		if mode == &"practice" and lesson == &"rewind":
			_injury_given = true
	_emergency_selected_index = 0
	weapons.require_fresh_press = false
	_update_run_hud()


func _incidental_dialogue_allowed() -> bool:
	return super._incidental_dialogue_allowed() and mode == &"pressure"
