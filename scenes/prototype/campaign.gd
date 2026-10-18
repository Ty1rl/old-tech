class_name MuseumCampaign
extends CombatArena

const Rooms = preload("res://scenes/prototype/rooms.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")
const Tutorial = preload("res://scenes/ui/tutorial.gd")

@onready var overlay: CanvasLayer = get_node_or_null("Overlay") as CanvasLayer
@onready var tutorial: Control = get_node_or_null("Overlay/Tutorial") as Control
@onready var title: Label = get_node_or_null("Overlay/TitleLabel") as Label
@onready var run_hint: Label = get_node_or_null("Overlay/RunHintLabel") as Label

var difficulty_id: StringName = &"easy"
var difficulty_spec: CampaignDifficulty = null
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
var _rewind_world_age := 0.0
var _rewind_start_pos := Vector3.ZERO
var _rewind_moved := false
var _rewind_attack_seen := false
var _rewind_projectile_spawned := false
var _damage_flash := 0.0
var _charged_kills: Dictionary = {}
var _pending := 0
var _spawned := 0
var _spawn_timer := 0.0
var _debug_boss_phase := -1
var _result_shown := false
var _emergency_selected_index := 0


func create_museum() -> Node3D:
	return RoomEnvironment.new()


func set_difficulty(value: Variant) -> void:
	difficulty_spec = Rooms.DifficultySpec.load_for(value)
	difficulty_id = difficulty_spec.id


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


func start_new_run(new_difficulty: Variant = null) -> void:
	if new_difficulty != null:
		set_difficulty(new_difficulty)
	elif SceneManager.params.has("difficulty"):
		set_difficulty(SceneManager.params.get("difficulty", &"easy"))
	SceneManager.clear_popups()
	GameState.start_game()
	acquired.clear()
	if tutorial != null:
		tutorial.reset_run()
	_slow_unlocked = false
	_rewind_unlocked = false
	_apply_time_capabilities()
	lesson = &""
	enter_room(0)


func _ready() -> void:
	super._ready()
	museum.combat_event.connect(feedback.cue)
	tutorial.setup(player.camera)
	if not tutorial.blocking_changed.is_connected(_on_teaching_block):
		tutorial.blocking_changed.connect(_on_teaching_block)
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
	_slow_unlocked = false
	_rewind_unlocked = false
	_apply_time_capabilities()
	_campaign_ready = true
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
	weapons.set_loadout(acquired, _preferred_tool(2))
	museum.apply_room(room, cover, self)
	museum.sync_cover_colliders(self)
	museum.set_boss_ceremony_phase(&"inactive")
	museum.set_exit_open(false)
	player.position = room.player_spawn
	player.reset_physics_interpolation()
	wave_index = -1
	specimens.clear()
	_specimen_ids.clear()
	_pending = 0
	_spawned = 0
	_spawn_timer = 0.0
	_debug_boss_phase = -1
	mode = &"title"
	timer = 2.0
	title.text = "%d / 4 · %s" % [room_index + 1, room.title]
	run_hint.text = "WASD move · mouse aim · collect the lit equipment exhibit."
	_result_shown = false
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
	if SceneManager.params.has("difficulty"):
		set_difficulty(SceneManager.params.get("difficulty", difficulty_id))
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	acquired.clear()
	tutorial.learned.clear()
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
				if taught == &"slow":
					_slow_unlocked = true
				elif taught == &"rewind":
					_rewind_unlocked = true
	_apply_time_capabilities()
	enter_room(target_room)
	wave_index = target_wave - 1
	_debug_boss_phase = boss_phase
	_begin_wave()


func retry_room() -> void:
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	lesson = &""
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
	return super._is_slow_held() and not tutorial.blocking and mode in [&"pickup", &"practice", &"pressure", &"recovery", &"exit"]


func _on_teaching_block(blocked: bool) -> void:
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
			_rewind_world_age = 0.0
			_rewind_start_pos = player.position
			_rewind_moved = false
			_rewind_attack_seen = false
			_rewind_projectile_spawned = false
			if history is ReplayHistory:
				var snap := capture_state()
				(history as ReplayHistory).seed_checkpoint(snap)
				(history as ReplayHistory).push(snap)
		# The explanation's click has been consumed; the next attack needs no re-arm.
		weapons.require_fresh_press = false
		time_controller.slow_requested = _is_slow_held()
		aim = floor_aim(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
	if _campaign_ready and is_emergency_active() and mode == &"practice" and lesson == &"rewind" and not GameState.is_paused() and not _has_non_repair_popup():
		if emergency_rewind != null and emergency_rewind.selected_index <= 0:
			var confirm_attempt := false
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				confirm_attempt = true
			elif event is InputEventKey and event.pressed and not event.echo:
				var key_code: int = event.physical_keycode if event.physical_keycode else event.keycode
				if key_code == KEY_ENTER or key_code == KEY_KP_ENTER:
					confirm_attempt = true
			if confirm_attempt:
				run_hint.text = "Scroll mouse wheel down to an earlier safe moment first, then click or press Enter."
				if is_instance_valid(tutorial) and tutorial.practicing:
					tutorial.state_label.text = "SCROLL DOWN TO AN EARLIER MOMENT FIRST · THEN CLICK OR PRESS ENTER"
				get_viewport().set_input_as_handled()
				return
	if _campaign_ready and (tutorial.blocking or mode in [&"title", &"ceremony", &"won"]):
		# Keep explanation GUI usable and clean up held releases without starting actions.
		if event is InputEventKey and (not event.pressed or event.physical_keycode == KEY_F10):
			super._input(event)
		elif event is InputEventMouseButton and not event.pressed:
			weapons.cancel_input()
			weapons.mouse_held = false
		return
	super._input(event)


func _unhandled_input(event: InputEvent) -> void:
	if _campaign_ready:
		if mode == &"pickup" and event is InputEventMouse:
			return
		if tutorial.blocking or mode in [&"title", &"ceremony", &"won"]:
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var code: int = event.physical_keycode if event.physical_keycode else event.keycode
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
	if bool(tutorial.blocking) or mode == &"won":
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
		var point: Vector3 = museum.pickup_position
		if Vector2(player.position.x - point.x, player.position.z - point.z).length() <= 1.7:
			var tool: int = museum.pickup_tool
			if tool > 0 and tool <= 3 and not tool in acquired:
				acquired.append(tool)
			weapons.set_loadout(acquired, _preferred_tool(tool))
			museum.clear_tool_pickup()
			_spawn_wave()
	elif mode == &"practice":
		if tutorial.is_learned(lesson):
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
			_start_pressure()
			return
		_practice_age += delta
		_slow_used = _slow_used or (time_controller != null and time_controller.slow_active) or world_scale < 0.99 or player.world_scale < 0.99
		_observe_specimens()
		if lesson == &"rewind" and not _injury_given:
			_step_rewind_practice(world_delta)
			if _injury_given:
				_update_run_hud()
				return
		if not tutorial.active_id.is_empty():
			tutorial.world_points.assign(_targets())
		if _lesson_succeeded():
			var finished_lesson := lesson
			tutorial.complete_lesson(lesson)
			lesson = &""
			_sync_training_protection()
			_apply_time_capabilities()
			if finished_lesson == &"repair":
				equipment.restore_tool(&"beam", 1.0)
				equipment.restore_tool(&"cone", 1.0)
				if SceneManager.has_popup(&"Repair"):
					_close_repair()
			_seed_room_checkpoint()
			_start_pressure()
		elif _needs_combat_target() and _alive_specimens() == 0:
			_spawn_practice()
	elif mode == &"pressure":
		_step_pressure(world_delta)
		if _pending == 0 and director.enemies.is_empty() and director.projectiles.is_empty():
			mode = &"recovery"
			timer = float(waves[wave_index].get("recovery", 2.5))
			_seed_room_checkpoint()
			if int(waves[wave_index].get("count", 0)) == 0:
				run_hint.text = "Tools restored · next exhibit group approaching."
			else:
				run_hint.text = "Exhibits quiet · press E to toggle tool repair before the next group."
	elif mode == &"recovery":
		timer -= world_delta
		if timer <= 0.0 and equipment.repairing == &"":
			_begin_wave()
	elif mode == &"exit":
		if equipment.repairing == &"" and museum.player_in_exit(player.position):
			enter_room(room_index + 1)


func _step_rewind_practice(world_delta: float) -> void:
	_rewind_world_age += maxf(0.0, world_delta)
	if (player.position - _rewind_start_pos).length() >= 0.75:
		_rewind_moved = true
	elif _rewind_world_age >= 0.6 and _rewind_world_age <= 3.6 and player.velocity.length() < 0.1:
		var step_dir := Vector3(1.0, 0.0, -0.35).normalized()
		player.position += step_dir * (1.35 * maxf(0.0, world_delta))
		player.position.x = clampf(player.position.x, -14.0, 14.0)
		player.position.z = clampf(player.position.z, -14.0, 14.0)
		if (player.position - _rewind_start_pos).length() >= 0.75:
			_rewind_moved = true
	if not _rewind_attack_seen and weapons.mouse_held:
		_rewind_attack_seen = true
	if not _rewind_attack_seen and _rewind_world_age >= 2.0:
		var target_pos: Vector3 = _targets()[0] if not _targets().is_empty() else (player.position + Vector3.FORWARD * 5.0)
		if weapons != null and weapons.flash != null:
			weapons.flash.press()
			weapons.flash.release(player.position, target_pos, player.position + Vector3(0.0, 0.9, 0.0))
		_rewind_attack_seen = true
	if not _rewind_projectile_spawned and _rewind_world_age >= 4.8:
		_rewind_projectile_spawned = true
		var origin := player.position + Vector3(0.0, 0.0, -8.5)
		if not specimens.is_empty() and is_instance_valid(specimens[0]):
			origin = specimens[0].position
		var to_player := player.position - origin
		to_player.y = 0.0
		var dir := to_player.normalized() if to_player.length() > 0.01 else Vector3.BACK
		# Spawn a visible incoming hostile shot; keep its direct damage 0 so we trigger the exact depletion hit once >= 6.0 world seconds are in ReplayHistory.
		director.launch_projectile(origin + dir * 1.1, dir, 7.5, 0.0)
		run_hint.text = "Incoming shot · watch the projectile strike, then rewind to your earlier safe position."
	var oldest_world_age := 0.0
	if history is ReplayHistory and history.snapshot_count > 0:
		oldest_world_age = (history as ReplayHistory).age_of(0)
	if _rewind_world_age >= 6.05 and oldest_world_age >= 6.0 and history.snapshot_count >= 2:
		director.projectiles.clear()
		player.wounded.emit(24.0)
		_damage_flash = 0.5
		if history is ReplayHistory:
			(history as ReplayHistory).push(capture_state())
		_injury_given = true
		_trigger_teaching_depletion()


func _trigger_teaching_depletion() -> void:
	if not time_controller.emergency_active and not time_controller.exhausted:
		time_controller.force_depletion()


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
	if mode == &"practice" and lesson == &"rewind":
		# The recovery timeline now carries the instruction; avoid two overlapping cards.
		tutorial.hide()
		run_hint.text = "Emergency rewind · scroll mouse wheel down to an earlier safe moment, then click or press Enter."
		if is_instance_valid(tutorial) and tutorial.practicing:
			tutorial.state_label.text = "EMERGENCY FROZEN · SCROLL WHEEL DOWN, THEN CLICK OR PRESS ENTER"
	else:
		run_hint.text = "Emergency rewind (%d left) · scroll wheel to choose a moment, then click or press Enter." % time_controller.charges_remaining


func _on_attempt_exhausted() -> void:
	if not _campaign_ready or mode == &"won":
		return
	retry_room()


func _finish_run(won: bool) -> void:
	if _result_shown:
		return
	_result_shown = true
	mode = &"won"
	weapons.cancel_input()
	player.reset_input()
	SceneManager.show_run_result(won)


func _begin_wave() -> void:
	_seed_room_checkpoint()
	wave_index += 1
	if wave_index >= waves.size():
		if room_index == 3:
			_finish_run(true)
		else:
			mode = &"exit"
			museum.set_boss_ceremony_phase(&"inactive")
			museum.set_exit_open(true)
			_seed_room_checkpoint()
			run_hint.text = "GALLERY CLEAR · press E to toggle repair at leisure, then walk through the green doorway."
		return
	var wave: Dictionary = waves[wave_index]
	lesson = StringName(wave.get("lesson", &""))
	_sync_training_protection()
	var tool := int(wave.get("acquire", 0))
	if tool > 0 and tool <= 3 and not tool in acquired:
		mode = &"pickup"
		museum.show_tool_pickup(tool, Vector3(room.player_spawn) + Vector3(0, 0, -3.0))
		_seed_room_checkpoint()
		run_hint.text = "New equipment exhibit · walk into its colored light to collect it."
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
	else:
		_spawn_wave()


func _spawn_wave() -> void:
	title.text = ""
	_pending = 0
	_spawned = 0
	_spawn_timer = 0.0
	_sync_training_protection()
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
		specimens.clear()
		_specimen_ids.clear()
		_start_pressure()
		return
	_kills.clear()
	_charged_kills.clear()
	_opened = false
	_cut = false
	_heated = false
	_slow_used = false
	_pierced = false
	_repaired = false
	_rewound = false
	_injury_given = false
	_practice_age = 0.0
	_rewind_world_age = 0.0
	_rewind_start_pos = player.position
	_rewind_moved = false
	_rewind_attack_seen = false
	_rewind_projectile_spawned = false
	mode = &"practice"
	# Select the tool the safe task actually needs (only weapons 1..3 exist).
	var desired_tool: int = {
		&"shot": 2,
		&"charge": 2,
		&"heat": 3,
		&"repair": 2,
		&"cut": 1,
		&"opening": 1,
		&"slow": 1 if 1 in acquired else 2,
		&"rewind": 2 if 2 in acquired else 1,
		&"loop": 1,
		&"pair": 2,
		&"zigzag": 1,
	}.get(lesson, 2)
	weapons.select_tool(_preferred_tool(desired_tool))
	_spawn_practice()
	tutorial.show_known_lesson(lesson, _targets())
	if lesson == &"repair":
		var total_stages := maxi(1, equipment.repair_steps)
		run_hint.text = "Practice exhibit · press E to open repair and complete all %d stages on the yellow flash camera." % total_stages
	elif lesson == &"rewind":
		run_hint.text = "Practice exhibit · move and fire until the incoming shot empties time, scroll down, then click or press Enter."
	else:
		run_hint.text = "Practice exhibit · complete the marked action safely."
	_seed_room_checkpoint()


func _spawn_practice() -> void:
	specimens.clear()
	_specimen_ids.clear()
	_kills.clear()
	_charged_kills.clear()
	_cut = false
	_heated = false
	_opened = false
	_pierced = false
	if lesson == &"repair":
		_sync_training_protection()
		equipment.restore_tool(&"cone", 1.0)
		equipment.restore_tool(&"beam", 1.0)
		equipment.spend(&"beam", equipment.capacity(&"beam"))
		weapons.select_tool(2)
		return
	if lesson == &"rewind":
		specimens.assign(director.spawn_formation(&"line", [&"ranged"], player, room_index * 37 + wave_index))
		for enemy in specimens:
			_specimen_ids.append(enemy.rewind_id)
			_make_specimen_safe(enemy)
			enemy.health = 999.0
		return
	var kind: StringName = StringName(waves[wave_index].enemies[0])
	if lesson == &"cut":
		kind = &"blue"
	elif lesson == &"slow":
		kind = &"blue" if 1 in acquired else &"yellow"
	elif lesson == &"charge":
		kind = &"yellow"
	elif lesson == &"opening":
		kind = &"side_guard"
	var count := 3 if lesson == &"charge" else 1
	specimens.assign(director.spawn_formation(&"line" if lesson == &"charge" else &"curve", _repeat(kind, count), player, room_index * 37 + wave_index))
	for enemy in specimens:
		_specimen_ids.append(enemy.rewind_id)
		_make_specimen_safe(enemy)


func _make_specimen_safe(enemy: Node3D) -> void:
	enemy.contact_damage = 0
	enemy.move_speed = 0
	# Safe practice must also suppress ranged/boss offense, not just touch damage.
	if "projectile_damage" in enemy:
		enemy.projectile_damage = 0
	if "attack_timer" in enemy:
		enemy.attack_timer = 99.0


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
	mode = &"pressure"
	_sync_training_protection()
	_pending = int(waves[wave_index].count)
	_spawned = 0
	_spawn_timer = 0.0
	_seed_room_checkpoint()
	_step_pressure(0.0)


func _step_pressure(world_delta: float) -> void:
	var wave: Dictionary = waves[wave_index]
	var is_boss_wave := bool(wave.get("boss", false))
	if is_boss_wave and _spawned >= 1:
		var boss_alive := false
		for enemy in director.enemies:
			if is_instance_valid(enemy) and enemy.has_method("is_boss") and enemy.is_boss() and enemy.health > 0:
				boss_alive = true
				break
		if not boss_alive:
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
		if count > 0:
			var wave_enemies: Array = wave.get("enemies", [])
			var kinds: Array = []
			for i in range(count):
				var kind_idx: int = (_spawned + i) % maxi(1, wave_enemies.size())
				if is_boss_wave and (_spawned + i) > 0 and wave_enemies.size() > 1:
					kind_idx = 1 + ((_spawned + i - 1) % (wave_enemies.size() - 1))
				kinds.append(wave_enemies[kind_idx])
			var arrived: Array = director.spawn_formation(wave.formation, kinds, player, room_index * 53 + wave_index * 7 + _spawned)
			_pending -= arrived.size()
			_spawned += arrived.size()
			_spawn_timer = float(wave.interval) if not arrived.is_empty() else 1.0
			if _debug_boss_phase >= 0 and is_boss_wave and not arrived.is_empty():
				var boss: Node3D = arrived[0]
				boss.debug_set_phase(_debug_boss_phase)
				_debug_boss_phase = -1
	if is_boss_wave:
		run_hint.text = "Guardian · finish its marked mechanism, then charge the exposed yellow core."
	else:
		run_hint.text = "Exhibit %d / %d · %d active · %d reinforcements · keep an escape lane." % [wave_index + 1, waves.size(), director.enemies.size(), _pending]


func _needs_combat_target() -> bool:
	return lesson != &"repair"


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
		elif lesson == &"heat" and is_instance_valid(enemy.part_visual) and is_instance_valid(enemy.part_visual.plate):
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
	if mode == &"practice" and lesson == &"rewind":
		_rewind_attack_seen = true


func _on_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int) -> void:
	if mode != &"practice":
		return
	if lesson == &"rewind":
		_rewind_attack_seen = true
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
	run_hint.visible = not tutorial.visible and not is_emergency_active() and equipment.repairing == &""


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
		"kills": _kills.duplicate(), "charged_kills": _charged_kills.duplicate(),
		"opened": _opened, "cut": _cut, "heated": _heated,
		"slow_used": _slow_used, "pierced": _pierced, "repaired": _repaired,
		"rewound": _rewound, "injury_given": _injury_given,
		"age": _practice_age, "rewind_age": _rewind_world_age,
		"rewind_start": _rewind_start_pos, "moved": _rewind_moved,
		"attack_seen": _rewind_attack_seen, "projectile_spawned": _rewind_projectile_spawned,
	}


func _restore_practice(state: Dictionary) -> void:
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
	_rewind_world_age = float(state.get("rewind_age", 0.0))
	_rewind_start_pos = state.get("rewind_start", player.position)
	_rewind_moved = bool(state.get("moved", false))
	_rewind_attack_seen = bool(state.get("attack_seen", false))
	_rewind_projectile_spawned = bool(state.get("projectile_spawned", false))


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
				museum.clear_tool_pickup()
				museum.set_exit_open(mode == &"exit")
			elif snap_mode == &"title":
				mode = &"title"
				timer = float(schedule.get("mode_timer", 0.0))
				lesson = &""
				museum.clear_tool_pickup()
				museum.set_exit_open(false)
			elif snap_mode == &"practice":
				museum.clear_tool_pickup()
				museum.set_exit_open(false)
				_restore_practice(schedule.get("practice", {}))
				if snap_lesson == &"rewind" and mode == &"practice" and lesson == &"rewind":
					mode = &"practice"
					lesson = &"rewind"
				elif not snap_lesson.is_empty() and not tutorial.is_learned(snap_lesson):
					mode = &"practice"
					lesson = snap_lesson
				else:
					lesson = &""
					_start_pressure()
			elif snap_mode == &"pickup":
				museum.set_exit_open(false)
				var wave_tool := int(waves[wave_index].get("acquire", 0)) if wave_index >= 0 and wave_index < waves.size() else 0
				if wave_tool > 0 and not (wave_tool in acquired):
					mode = &"pickup"
					museum.show_tool_pickup(wave_tool, Vector3(room.player_spawn) + Vector3(0, 0, -3.0))
				else:
					museum.clear_tool_pickup()
					_spawn_wave()
	_sync_training_protection()
	_apply_time_capabilities()
	if mode == &"practice":
		specimens.clear()
		for enemy in director.enemies:
			if enemy.rewind_id in _specimen_ids:
				specimens.append(enemy)
				_make_specimen_safe(enemy)
		if not preview_only and tutorial.active_id != lesson:
			tutorial.show_known_lesson(lesson, _targets())
	elif not preview_only:
		tutorial.dismiss()
	weapons.rebuild_visuals(player)


func restore_campaign_state(data: Dictionary) -> void:
	_restore_base_arena_state(data)
	_apply_campaign_snapshot(data, false)


func _on_emergency_selection_changed(index: int, age_seconds: float, state: Dictionary) -> void:
	super._on_emergency_selection_changed(index, age_seconds, state)
	_emergency_selected_index = index
	if mode == &"practice" and lesson == &"rewind":
		if index > 0:
			run_hint.text = "Earlier safe moment (-%.1fs) selected · click or press Enter to recover here." % maxf(0.0, age_seconds)
			if is_instance_valid(tutorial) and tutorial.practicing:
				tutorial.state_label.text = "EARLIER MOMENT (-%.1fS) · CLICK OR PRESS ENTER TO RECOVER" % maxf(0.0, age_seconds)
		else:
			run_hint.text = "Scroll mouse wheel down to an earlier safe moment, then click or press Enter."
			if is_instance_valid(tutorial) and tutorial.practicing:
				tutorial.state_label.text = "EMERGENCY FROZEN · SCROLL WHEEL DOWN, THEN CLICK OR PRESS ENTER"
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
			# Completing the recovery is the lesson; do not stage a second depletion.
			_injury_given = true
	_emergency_selected_index = 0
	weapons.require_fresh_press = false
