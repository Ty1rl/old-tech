extends "res://scenes/prototype/arena.gd"

const Rooms = preload("res://scenes/prototype/rooms.gd")
const RoomEnvironment = preload("res://scenes/prototype/room_environment.gd")
const Tutorial = preload("res://scenes/ui/tutorial.gd")
const Recovery = preload("res://scenes/prototype/health_recovery.gd")
var recovery := Recovery.new()
var tutorial: Control
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
var _dead_age := 0.0
var _damage_flash := 0.0
var _review_start_health := 100.0
var _charged_kills: Dictionary = {}
var _pending := 0
var _spawned := 0
var _spawn_timer := 0.0
var _debug_boss_phase := -1
var _result_shown := false
var title: Label
var run_hint: Label
var health_label: Label

func create_museum() -> Node3D:
	return RoomEnvironment.new()

func _ready() -> void:
	history = History.new(12.0, 240)
	super._ready()
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	tutorial = Tutorial.new()
	layer.add_child(tutorial)
	tutorial.setup(player.camera)
	tutorial.blocking_changed.connect(_on_teaching_block)
	for field in ["title", "run_hint", "health_label"]:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		layer.add_child(label)
		set(field, label)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -360; title.offset_right = 360; title.offset_top = 32
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.offset_bottom = 180
	title.add_theme_font_size_override("font_size", 26)
	run_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	run_hint.offset_left = 18; run_hint.offset_right = -18
	run_hint.offset_top = -88; run_hint.offset_bottom = -60
	run_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	run_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	run_hint.add_theme_font_size_override("font_size", 16)
	health_label.position = Vector2(18, 260)
	health_label.add_theme_font_size_override("font_size", 18)
	player.wounded.connect(_on_wounded)
	weapons.combat_event.connect(_on_run_event)
	weapons.resolved_hit.connect(_on_resolved_hit)
	equipment.repaired.connect(_on_equipment_repaired)
	SceneManager.restart_room_requested.connect(retry_room)
	_campaign_ready = true
	enter_room(0)
	if SceneManager.params.has("debug_room"):
		debug_start(int(SceneManager.params.debug_room), int(SceneManager.params.get("debug_wave", 0)), int(SceneManager.params.get("debug_phase", -1)))
	GameState.apply_preferences(feedback, status_hud)

func enter_room(index: int) -> void:
	if index >= Rooms.definitions().size():
		_finish_run(true)
		return
	room_index = clampi(index, 0, 3)
	super.reset_arena()
	recovery.reset()
	director.clear()
	room = Rooms.definitions()[room_index].duplicate(true)
	waves = room.waves.duplicate(true)
	# A later-room checkpoint always includes the preceding rooms' tools.
	for previous in range(room_index):
		for wave: Dictionary in Rooms.definitions()[previous].waves:
			var tool := int(wave.get("acquire", 0))
			if tool > 0 and not tool in acquired: acquired.append(tool)
	weapons.set_loadout(acquired, 2)
	museum.apply_room(room, cover, self)
	museum.sync_cover_colliders(self)
	museum.set_boss_ceremony_phase(&"inactive")
	museum.set_exit_open(false)
	player.position = room.player_spawn
	player.reset_physics_interpolation()
	wave_index = -1
	specimens.clear()
	_specimen_ids.clear()
	_pending = 0; _spawned = 0; _spawn_timer = 0
	_debug_boss_phase = -1
	mode = &"title"
	timer = 2.0
	title.text = "%d / 4 · %s" % [room_index + 1, room.title]
	run_hint.text = "WASD move · mouse aim · collect the lit equipment exhibit."
	_dead_age = 0; _result_shown = false
	_update_run_hud()

# Starts a checkpoint with all prerequisites and the selected lesson already learned.
# A boss phase uses the real enemy's restore_state, preserving its native geometry.
func debug_start(index: int, requested_wave: int = 0, boss_phase: int = -1) -> void:
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	acquired.clear()
	var definitions := Rooms.definitions()
	var target_room := clampi(index, 0, definitions.size() - 1)
	var target_wave := clampi(requested_wave, 0, definitions[target_room].waves.size() - 1)
	for ri in range(target_room + 1):
		var end: int = target_wave + 1 if ri == target_room else definitions[ri].waves.size()
		for wi in range(end):
			var wave: Dictionary = definitions[ri].waves[wi]
			var tool := int(wave.get("acquire", 0))
			if tool > 0 and not tool in acquired: acquired.append(tool)
			var taught := StringName(wave.get("lesson", &""))
			if not taught.is_empty(): tutorial.learned[taught] = true
	enter_room(target_room)
	wave_index = target_wave - 1
	_debug_boss_phase = boss_phase
	_begin_wave()

func retry_room() -> void:
	SceneManager.clear_popups()
	GameState.start_game()
	tutorial.dismiss()
	enter_room(room_index)

func reset_arena() -> void:
	if _campaign_ready: retry_room()
	else: super.reset_arena()

func _on_teaching_block(blocked: bool) -> void:
	if not blocked: return
	weapons.cancel_input()
	player.reset_input()
	_space_held = false
	_space_release_required = true
	_close_repair()

func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and key_event.physical_keycode == KEY_F10:
		super._input(event)
		return
	if _campaign_ready and (tutorial.blocking or mode in [&"title", &"ceremony", &"won"]):
		# Block new actions, but never swallow release cleanup during a transition.
		if key_event != null and not key_event.pressed and key_event.physical_keycode in [KEY_SPACE, KEY_E]: super._input(event)
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			weapons.cancel_input()
			weapons.mouse_held = false
		return
	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if _campaign_ready:
		if mode == &"pickup" and event is InputEventMouse: return
		if tutorial.blocking or mode in [&"title", &"ceremony", &"won"]: return
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_R:
				retry_room(); return
			if event.physical_keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F6,KEY_F8,KEY_F9,KEY_BACKSPACE]: return
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	if not _campaign_ready: return
	_damage_flash = maxf(0, _damage_flash - delta)
	_update_run_hud()
	if not GameState.is_playing() or SceneManager.has_popup(&"Developer") or SceneManager.has_popup(&"Settings"): return
	if tutorial.blocking or mode == &"won": return
	if mode == &"title":
		timer -= delta
		if timer <= 0:
			title.text = ""
			_begin_wave()
		return
	if mode == &"ceremony":
		museum.step_ceremony(delta)
		if museum.is_boss_active(): _spawn_wave()
		return
	if player.health <= 0 and not history.inspecting:
		_dead_age += delta
		if 4 in acquired:
			weapons.select_tool(4)
			run_hint.text = "Hold Space + scroll down to undo the injury · R retry room"
		else: run_hint.text = "The exhibit overwhelmed you · R retry room"
		if _dead_age >= 6.0 or not 4 in acquired or not equipment.can_use(&"clock"):
			_finish_run(false)
		return
	var inspecting_before: bool = history.inspecting
	super._physics_process(delta)
	if inspecting_before or history.inspecting: return
	if player.health <= 0: return # Never clear a wave or win on the frame of lethal damage.
	if not (mode == &"practice" and lesson == &"rewind" and not _rewound):
		player.health = recovery.step(delta, player.health, float(Tuning.PLAYER.health))
	if mode == &"pickup":
		var point: Vector3 = museum.pickup_position
		if Vector2(player.position.x - point.x, player.position.z - point.z).length() <= 1.7:
			var tool: int = museum.pickup_tool
			if not tool in acquired: acquired.append(tool)
			weapons.set_loadout(acquired, tool)
			museum.clear_tool_pickup()
			_spawn_wave()
	elif mode == &"practice":
		if tutorial.is_learned(lesson):
			_start_pressure()
			return
		_practice_age += delta
		_slow_used = _slow_used or player.world_scale < .99
		_observe_specimens()
		if lesson == &"rewind" and not _injury_given and _practice_age >= 2.0:
			player.take_damage(minf(20.0, maxf(0, player.health - 1.0)))
			_injury_given = true
		if not tutorial.active_id.is_empty(): tutorial.world_points.assign(_targets())
		if _lesson_succeeded():
			tutorial.complete_lesson(lesson)
			history.clear()
			_start_pressure()
		elif _needs_combat_target() and _alive_specimens() == 0: _spawn_practice()
	elif mode == &"pressure":
		_step_pressure(delta * player.world_scale)
		if _pending == 0 and director.enemies.is_empty() and director.projectiles.is_empty():
			mode = &"recovery"
			timer = float(waves[wave_index].get("recovery", 5.0))
			history.clear()
			run_hint.text = "Exhibits quiet · hold E to service your tools before the next group."
	elif mode == &"recovery":
		timer -= delta * player.world_scale
		if timer <= 0 and equipment.repairing == &"": _begin_wave()
	elif mode == &"exit":
		if equipment.repairing == &"" and museum.player_in_exit(player.position): enter_room(room_index + 1)

func _finish_run(won: bool) -> void:
	if _result_shown: return
	_result_shown = true
	mode = &"won"
	weapons.cancel_input()
	player.reset_input()
	SceneManager.show_run_result(won)

func _begin_wave() -> void:
	history.clear()
	wave_index += 1
	if wave_index >= waves.size():
		if room_index == 3: _finish_run(true)
		else:
			mode = &"exit"
			museum.set_boss_ceremony_phase(&"inactive")
			museum.set_exit_open(true)
			run_hint.text = "GALLERY CLEAR · repair at leisure, then walk through the green doorway."
		return
	var wave: Dictionary = waves[wave_index]
	lesson = StringName(wave.get("lesson", &""))
	var tool := int(wave.get("acquire", 0))
	if tool > 0 and not tool in acquired:
		mode = &"pickup"
		museum.show_tool_pickup(tool, Vector3(room.player_spawn) + Vector3(0, 0, -3.0))
		run_hint.text = "New equipment exhibit · walk into its colored light to collect it."
	elif bool(wave.get("boss", false)) and _debug_boss_phase < 0:
		weapons.cancel_input()
		weapons.mouse_held = false
		player.reset_input()
		_space_held = false
		_space_release_required = true
		mode = &"ceremony"
		title.text = {&"loop_boss": "The Loop Curator", &"sequence_boss": "The Sequence Warden", &"final_boss": "The Burial Device"}.get(wave.enemies[0], "Exhibition Guardian")
		museum.start_boss_entrance()
	else: _spawn_wave()

func _spawn_wave() -> void:
	title.text = ""
	_pending = 0; _spawned = 0; _spawn_timer = 0
	if lesson.is_empty() or tutorial.is_learned(lesson):
		specimens.clear(); _specimen_ids.clear()
		_start_pressure()
		return
	_kills.clear(); _charged_kills.clear()
	_opened = false; _cut = false; _heated = false
	_slow_used = false; _pierced = false; _repaired = false; _rewound = false
	_injury_given = false; _practice_age = 0
	mode = &"practice"
	# Select the tool the safe task actually needs; slow keeps the cutter equipped.
	weapons.select_tool({&"shot": 2, &"charge": 2, &"heat": 3, &"repair": 2,
		&"cut": 1, &"opening": 1, &"slow": 1, &"rewind": 4, &"loop": 1, &"pair": 2, &"zigzag": 1}.get(lesson, 2))
	_spawn_practice()
	tutorial.show_known_lesson(lesson, _targets())
	run_hint.text = "Practice exhibit · complete the marked action safely."
	history.clear()

func _spawn_practice() -> void:
	specimens.clear(); _specimen_ids.clear()
	_kills.clear(); _charged_kills.clear(); _cut = false; _heated = false; _opened = false; _pierced = false
	if not _needs_combat_target():
		if lesson == &"repair":
			equipment.spend(&"beam", equipment.capacity(&"beam"))
			weapons.select_tool(2)
		return
	var kind: StringName = StringName(waves[wave_index].enemies[0])
	if lesson in [&"cut", &"slow"]: kind = &"blue"
	elif lesson == &"charge": kind = &"yellow"
	elif lesson == &"opening": kind = &"side_guard"
	var count := 3 if lesson == &"charge" else 1
	specimens.assign(director.spawn_formation(&"line" if lesson == &"charge" else &"curve", _repeat(kind, count), player, room_index * 37 + wave_index))
	for enemy in specimens:
		_specimen_ids.append(enemy.rewind_id)
		_make_specimen_safe(enemy)

func _make_specimen_safe(enemy: Node3D) -> void:
	enemy.contact_damage = 0
	enemy.move_speed = 0
	# Safe practice must also suppress ranged/boss offense, not just touch damage.
	if "projectile_damage" in enemy: enemy.projectile_damage = 0

func _repeat(kind: StringName, count: int) -> Array:
	var result: Array = []
	for i in range(count): result.append(kind)
	return result

func _start_pressure() -> void:
	# Training bodies are retired; each pressure roster is explicit and finite.
	director.clear()
	specimens.clear(); _specimen_ids.clear()
	mode = &"pressure"
	_pending = int(waves[wave_index].count)
	_spawned = 0; _spawn_timer = 0
	history.clear()
	_step_pressure(0)

func _step_pressure(world_delta: float) -> void:
	var wave: Dictionary = waves[wave_index]
	_spawn_timer = maxf(0, _spawn_timer - maxf(0, world_delta))
	if _pending > 0 and _spawn_timer <= 0:
		var space := maxi(0, int(wave.max_live) - director.enemies.size())
		var count := mini(_pending, mini(int(wave.burst), space))
		if count > 0:
			var kinds: Array = []
			for i in range(count): kinds.append(wave.enemies[(_spawned + i) % wave.enemies.size()])
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
		if is_instance_valid(enemy) and enemy.health > 0: count += 1
	return count

func _observe_specimens() -> void:
	for enemy in specimens:
		if not is_instance_valid(enemy): continue
		if enemy.health <= 0: _kills[enemy.rewind_id] = true
		_cut = _cut or enemy.cable_cut
		_heated = _heated or enemy.plate_broken
		_opened = _opened or enemy.is_core_exposed()

func _lesson_succeeded() -> bool:
	if lesson == &"repair": return _repaired and equipment.remaining(&"beam") > 0
	if lesson == &"rewind": return _rewound and _injury_given
	if lesson == &"slow": return _slow_used and _cut and not _kills.is_empty()
	if lesson == &"charge": return _pierced and _charged_kills.size() >= 2
	if lesson == &"cut": return _cut and not _kills.is_empty()
	if lesson == &"heat": return _heated and not _kills.is_empty()
	if lesson in [&"opening", &"loop", &"zigzag"]: return _opened and not _kills.is_empty()
	return not _kills.is_empty()

func _targets() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for enemy in specimens:
		if not is_instance_valid(enemy) or enemy.health <= 0: continue
		if enemy.has_method("active_pattern") and enemy.active_pattern() == &"pair":
			points.append(enemy.valve_world_position(0)); points.append(enemy.valve_world_position(1))
		elif lesson == &"heat" and is_instance_valid(enemy.part_visual) and is_instance_valid(enemy.part_visual.plate):
			points.append(enemy.part_visual.plate.global_position + Vector3.UP * .5)
		elif lesson == &"opening" and not enemy.is_core_exposed():
			var ends: Array = enemy.cable_world_points()
			if ends.size() >= 2: points.append((ends[0] + ends[-1]) * .5)
		elif lesson in [&"cut", &"slow", &"loop", &"zigzag"] and enemy.has_cuttable_part():
			var cable: Array = enemy.cable_world_points()
			if enemy.has_method("lesson_state"):
				for i in range(0, cable.size() - 1, 2): points.append((cable[i] + cable[i + 1]) * .5)
			elif cable.size() >= 2: points.append((cable[0] + cable[-1]) * .5)
		else: points.append(enemy.core_world_position() if enemy.is_core_exposed() else enemy.position + Vector3.UP)
	if points.is_empty(): points.append(player.position)
	return points

func _on_run_event(_kind: StringName, _point: Vector3, _strength: float) -> void:
	pass

func _on_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, enemy_id: int) -> void:
	if mode != &"practice": return
	# The director may prune a killed target before the next campaign tick.
	_observe_specimens()
	if bool(result.get("killed", false)): _kills[enemy_id] = true
	if tool == &"beam" and bool(result.get("killed", false)) and bool(context.get("piercing", false)):
		_charged_kills[enemy_id] = true
		_pierced = _pierced or int(context.get("prior_hits", 0)) > 0

func _on_equipment_repaired(tool: StringName, amount: float) -> void:
	if tool == &"beam" and amount > 0: _repaired = true

func _on_wounded(amount: float) -> void:
	recovery.damaged(amount)
	_damage_flash = .5
	feedback.cue(&"hit", player.position, minf(1, amount / 20))

func _update_run_hud() -> void:
	if health_label == null: return
	health_label.visible = status_hud.readout_mode != 2
	run_hint.visible = not tutorial.visible and equipment.repairing == &""
	health_label.self_modulate.a = 0.45 if status_hud.readout_mode == 1 else 1.0
	health_label.modulate = Color.WHITE.lerp(Color("ff7766"), clampf(_damage_flash * 2, 0, 1))
	health_label.text = "Health %.0f" % player.health
	if recovery.recoverable > 0: health_label.text += " · %.0f recoverable" % recovery.recoverable
	if history.inspecting: health_label.text = "Health %.0f → %.0f · return %.1fs" % [_review_start_health, player.health, history.selected_seconds_ago]

func capture_state() -> Dictionary:
	var data := super.capture_state()
	data["recovery"] = recovery.capture_state()
	# Reinforcement debt rewinds with the roster. Learned controls and tools do not.
	data["campaign_wave"] = {"room": room_index, "wave": wave_index, "pending": _pending, "spawned": _spawned, "timer": _spawn_timer}
	return data

func _restore_world(data: Dictionary, live_clock: float) -> void:
	super._restore_world(data, live_clock)
	weapons.set_loadout(acquired, 4 if 4 in acquired else 2)
	recovery.restore_state(data.get("recovery", {}))
	var schedule: Dictionary = data.get("campaign_wave", {})
	if int(schedule.get("room", -1)) == room_index and int(schedule.get("wave", -2)) == wave_index:
		_pending = int(schedule.get("pending", _pending))
		_spawned = int(schedule.get("spawned", _spawned))
		_spawn_timer = float(schedule.get("timer", _spawn_timer))
	if mode == &"practice":
		specimens.clear()
		for enemy in director.enemies:
			if enemy.rewind_id in _specimen_ids:
				specimens.append(enemy)
				_make_specimen_safe(enemy)
	if player.health > 0: _dead_age = 0

func _begin_inspection() -> void:
	_review_start_health = player.health
	super._begin_inspection()

func _finish_inspection(commit: bool) -> void:
	var age: float = history.selected_seconds_ago
	var before := _review_start_health
	super._finish_inspection(commit)
	if commit and age > 0 and player.health > before: _rewound = true
