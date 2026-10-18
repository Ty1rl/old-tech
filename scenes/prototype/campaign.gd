class_name MuseumCampaign
extends CombatArena

const Rooms = preload("res://scenes/prototype/rooms.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")
const Tutorial = preload("res://scenes/ui/tutorial.gd")

@onready var overlay: CanvasLayer = get_node_or_null("Overlay") as CanvasLayer
@onready var tutorial: Control = get_node_or_null("Overlay/Tutorial") as Control
@onready var title: Label = get_node_or_null("Overlay/TitleLabel") as Label
@onready var run_hint: Label = get_node_or_null("Overlay/RunHintLabel") as Label

var room_index := 0
var wave_index := -1
var mode: StringName = &"title"
var timer := 0.0
var room: Dictionary
var waves: Array = []
var lesson: StringName = &""
# Acquisition and lessons are run progress, deliberately outside rewind snapshots.
var acquired: Array[int] = []
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


func _seed_room_checkpoint() -> void:
	if history == null:
		return
	history.clear()
	if history is ReplayHistory:
		(history as ReplayHistory).seed_checkpoint(capture_state())


func enter_room(index: int) -> void:
	if index >= Rooms.definitions().size():
		_finish_run(true)
		return
	room_index = clampi(index, 0, 3)
	super.reset_arena()
	director.clear()
	room = Rooms.definitions()[room_index].duplicate(true)
	waves = room.waves.duplicate(true)
	# A later-room checkpoint always includes the preceding rooms' tools (yellow -> orange -> blue).
	for previous in range(room_index):
		for wave: Dictionary in Rooms.definitions()[previous].waves:
			var tool := int(wave.get("acquire", 0))
			if tool > 0 and tool <= 3 and not tool in acquired:
				acquired.append(tool)
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
	if time_controller != null:
		time_controller.slow_requested = false
		time_controller.begin_attempt()
	_seed_room_checkpoint()
	_update_run_hud()


# Starts a checkpoint with all prerequisites and the selected lesson already learned.
# A boss phase uses the real enemy's restore_state, preserving its native geometry.
func debug_start(index: int, requested_wave: int = 0, boss_phase: int = -1) -> void:
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	acquired.clear()
	tutorial.learned.clear()
	var definitions := Rooms.definitions()
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
	if wave_index >= 0 and wave_index < waves.size() and StringName(waves[wave_index].get("lesson", &"")) == &"repair":
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
		# The explanation's click has been consumed; the next attack needs no re-arm.
		weapons.require_fresh_press = false
		time_controller.slow_requested = _is_slow_held()
		aim = floor_aim(get_viewport().get_mouse_position())


func _input(event: InputEvent) -> void:
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
	if mode == &"practice" and lesson == &"rewind" and not tutorial.is_learned(lesson) and not _injury_given and not is_emergency_active():
		if _practice_age + delta >= 2.0 and history.snapshot_count >= 2:
			_practice_age += delta
			_injury_given = true
			_trigger_teaching_depletion()
			_update_run_hud()
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
			_start_pressure()
			return
		_practice_age += delta
		_slow_used = _slow_used or (time_controller != null and time_controller.slow_active) or world_scale < 0.99 or player.world_scale < 0.99
		_observe_specimens()
		if lesson == &"rewind" and not _injury_given and _practice_age >= 2.0 and history.snapshot_count >= 2:
			_injury_given = true
			_trigger_teaching_depletion()
			_update_run_hud()
			return
		if not tutorial.active_id.is_empty():
			tutorial.world_points.assign(_targets())
		if _lesson_succeeded():
			var finished_lesson := lesson
			tutorial.complete_lesson(lesson)
			lesson = &""
			_sync_training_protection()
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
		_step_pressure(delta * world_scale)
		if _pending == 0 and director.enemies.is_empty() and director.projectiles.is_empty():
			mode = &"recovery"
			timer = float(waves[wave_index].get("recovery", 2.5))
			_seed_room_checkpoint()
			if int(waves[wave_index].get("count", 0)) == 0:
				run_hint.text = "Tools restored · next exhibit group approaching."
			else:
				run_hint.text = "Exhibits quiet · press E to toggle tool repair before the next group."
	elif mode == &"recovery":
		timer -= delta * world_scale
		if timer <= 0.0 and equipment.repairing == &"":
			_begin_wave()
	elif mode == &"exit":
		if equipment.repairing == &"" and museum.player_in_exit(player.position):
			enter_room(room_index + 1)


func _trigger_teaching_depletion() -> void:
	if not time_controller.emergency_active and not time_controller.exhausted:
		time_controller.force_depletion()


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
		run_hint.text = "Emergency rewind · scroll mouse wheel down to an earlier safe moment, then click or press Enter."
		if is_instance_valid(tutorial) and tutorial.practicing:
			tutorial.state_label.text = "EMERGENCY FROZEN · SCROLL WHEEL DOWN, THEN CLICK OR ENTER"
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
			run_hint.text = "GALLERY CLEAR · press E to toggle repair at leisure, then walk through the green doorway."
		return
	var wave: Dictionary = waves[wave_index]
	lesson = StringName(wave.get("lesson", &""))
	_sync_training_protection()
	var tool := int(wave.get("acquire", 0))
	if tool > 0 and tool <= 3 and not tool in acquired:
		mode = &"pickup"
		museum.show_tool_pickup(tool, Vector3(room.player_spawn) + Vector3(0, 0, -3.0))
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
	mode = &"practice"
	# Select the tool the safe task actually needs (only weapons 1..3 exist).
	var desired_tool: int = {
		&"shot": 2,
		&"charge": 2,
		&"heat": 3,
		&"repair": 2,
		&"cut": 1,
		&"opening": 1,
		&"slow": 1,
		&"rewind": 1,
		&"loop": 1,
		&"pair": 2,
		&"zigzag": 1,
	}.get(lesson, 2)
	weapons.select_tool(_preferred_tool(desired_tool))
	_spawn_practice()
	tutorial.show_known_lesson(lesson, _targets())
	if lesson == &"repair":
		run_hint.text = "Practice exhibit · press E to toggle repair, trace matching contacts, then press E to close."
	elif lesson == &"rewind":
		run_hint.text = "Practice exhibit · wait for the safe time depletion, scroll down, then click or press Enter."
	else:
		run_hint.text = "Practice exhibit · complete the marked action safely."
	_seed_room_checkpoint()
	if lesson == &"rewind" and history is ReplayHistory:
		(history as ReplayHistory).push(capture_state())


func _spawn_practice() -> void:
	specimens.clear()
	_specimen_ids.clear()
	_kills.clear()
	_charged_kills.clear()
	_cut = false
	_heated = false
	_opened = false
	_pierced = false
	if not _needs_combat_target():
		if lesson == &"repair":
			_sync_training_protection()
			equipment.spend(&"beam", equipment.capacity(&"beam"))
			weapons.select_tool(2)
		return
	var kind: StringName = StringName(waves[wave_index].enemies[0])
	if lesson in [&"cut", &"slow"]:
		kind = &"blue"
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
	if _pending > 0 and director.enemies.size() <= (0 if int(wave.burst) <= 1 else 1):
		_spawn_timer = minf(_spawn_timer, float(wave.get("refill_delay", 0.75)))
	_spawn_timer = maxf(0.0, _spawn_timer - maxf(0.0, world_delta))
	if _pending > 0 and _spawn_timer <= 0.0:
		var space := maxi(0, int(wave.max_live) - director.enemies.size())
		var count := mini(_pending, mini(int(wave.burst), space))
		if count > 0:
			var kinds: Array = []
			for i in range(count):
				kinds.append(wave.enemies[(_spawned + i) % wave.enemies.size()])
			var arrived: Array = director.spawn_formation(wave.formation, kinds, player, room_index * 53 + wave_index * 7 + _spawned)
			_pending -= arrived.size()
			_spawned += arrived.size()
			_spawn_timer = float(wave.interval) if not arrived.is_empty() else 1.0
			if _debug_boss_phase >= 0 and bool(wave.get("boss", false)) and not arrived.is_empty():
				var boss: Node3D = arrived[0]
				boss.debug_set_phase(_debug_boss_phase)
				_debug_boss_phase = -1
	if bool(wave.get("boss", false)):
		run_hint.text = "Guardian · finish its marked mechanism, then charge the exposed yellow core."
	else:
		run_hint.text = "Exhibit %d / %d · %d active · %d reinforcements · keep an escape lane." % [wave_index + 1, waves.size(), director.enemies.size(), _pending]


func _needs_combat_target() -> bool:
	return lesson not in [&"repair", &"rewind"]


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
		return _repaired and equipment.remaining(&"beam") > 0.0
	if lesson == &"rewind":
		return _rewound and _injury_given and not is_emergency_active()
	if lesson == &"slow":
		return _slow_used and _cut and not _kills.is_empty()
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
		_repaired = true


func _on_wounded(amount: float) -> void:
	_damage_flash = 0.5


func _update_run_hud() -> void:
	if run_hint == null:
		return
	run_hint.visible = not tutorial.visible and not is_emergency_active() and equipment.repairing == &""


func capture_state() -> Dictionary:
	var data := super.capture_state()
	# Reinforcement debt rewinds with the roster. Learned controls, tools, and time/charges do not.
	data["campaign_wave"] = {
		"room": room_index,
		"wave": wave_index,
		"pending": _pending,
		"spawned": _spawned,
		"timer": _spawn_timer,
	}
	return data


func _restore_base_arena_state(data: Dictionary) -> void:
	_restore_world(data)


func _apply_campaign_snapshot(data: Dictionary, preview_only: bool = false) -> void:
	var preferred := int(data.get("weapons", {}).get("selected_tool", weapons.selected_tool))
	weapons.available_tools.assign(acquired)
	weapons.selected_tool = _preferred_tool(preferred)
	if not preview_only:
		var schedule: Dictionary = data.get("campaign_wave", {})
		if int(schedule.get("room", -1)) == room_index and int(schedule.get("wave", -2)) == wave_index:
			_pending = int(schedule.get("pending", _pending))
			_spawned = int(schedule.get("spawned", _spawned))
			_spawn_timer = float(schedule.get("timer", _spawn_timer))
	_sync_training_protection()
	if mode == &"practice":
		specimens.clear()
		for enemy in director.enemies:
			if enemy.rewind_id in _specimen_ids:
				specimens.append(enemy)
				_make_specimen_safe(enemy)
	weapons.rebuild_visuals(player)


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
	if _emergency_selected_index > 0 or age_seconds != 0.0:
		_rewound = true
	_emergency_selected_index = 0
	weapons.require_fresh_press = false

