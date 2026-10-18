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
var specimens: Array[Node3D] = []
var _specimen_ids: Array[int] = []
var _campaign_ready := false
var _origin := Vector3.ZERO
var _kills: Dictionary = {}
var _opened := false
var _cut := false
var _heated := false
var _slow_used := false
var _charged := false
var _pierced := false
var _repaired := false
var _rewound := false
var _injury_given := false
var _practice_age := 0.0
var _dead_age := 0.0
var _damage_flash := 0.0
var _review_start_health := 100.0
var _charged_kills: Dictionary = {}
var title: Label
var run_hint: Label
var health_label: Label

func _ready() -> void:
	history = History.new(12.0,240)
	super._ready()
	remove_child(museum)
	museum.queue_free()
	museum = RoomEnvironment.new()
	add_child(museum)
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	tutorial = Tutorial.new()
	layer.add_child(tutorial)
	tutorial.setup(player.camera)
	tutorial.blocking_changed.connect(_on_teaching_block)
	for field in ["title","run_hint","health_label"]:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x",1)
		label.add_theme_constant_override("shadow_offset_y",1)
		layer.add_child(label)
		set(field,label)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -360; title.offset_right = 360; title.offset_top = 32
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.offset_bottom = 180
	title.add_theme_font_size_override("font_size",26)
	run_hint.position = Vector2(18,285)
	run_hint.add_theme_font_size_override("font_size",16)
	health_label.position = Vector2(18,260)
	health_label.add_theme_font_size_override("font_size",18)
	player.wounded.connect(_on_wounded)
	weapons.combat_event.connect(_on_run_event)
	weapons.resolved_hit.connect(_on_resolved_hit)
	equipment.repaired.connect(func(_tool,_amount): _repaired = true)
	SceneManager.restart_room_requested.connect(retry_room)
	_campaign_ready = true
	enter_room(0)
	GameState.apply_preferences(feedback,status_hud)

func enter_room(index: int) -> void:
	if index >= Rooms.definitions().size():
		mode = &"won"
		SceneManager.show_run_result(true)
		return
	room_index = index
	super.reset_arena()
	recovery.reset()
	director.clear()
	room = Rooms.definitions()[index].duplicate(true)
	waves = room.waves.duplicate(true)
	# Every required interaction appears before the boss; calm utility lessons
	# are explicit beats rather than mixed-wave ambushes.
	if index == 0:
		waves.insert(2,{"lesson":&"slow","formation":&"curve","enemies":[&"blue"],"count":2,"recovery":2.5})
		waves.append({"lesson":&"rewind","formation":&"mixed","enemies":[],"count":0,"recovery":2.0})
	museum.apply_room(room,cover,self)
	museum.sync_cover_colliders(self)
	museum.set_exit_open(false)
	if bool(room.get("is_boss_room",false)): museum.set_boss_ceremony_phase(&"inactive")
	player.position = room.player_spawn
	player.reset_physics_interpolation()
	wave_index = -1
	specimens.clear()
	_specimen_ids.clear()
	mode = &"title"
	timer = 2.0
	title.text = room.title
	run_hint.text = "Move through the galleries. Follow the marked targets."
	_dead_age = 0
	_update_run_hud()

func retry_room() -> void:
	SceneManager.clear_popups()
	GameState.start_game()
	# Learned controls persist, but the current room restarts from its checkpoint.
	tutorial.active_id = &""
	tutorial.practicing = false
	tutorial.blocking = false
	tutorial.hide()
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
	if _campaign_ready and (tutorial.blocking or mode in [&"title",&"ceremony",&"won"]):
		return # GUI still receives clicks; the tutorial owns its practice button.
	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if _campaign_ready:
		if tutorial.blocking or mode in [&"title",&"ceremony",&"won"]: return
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_R:
				retry_room(); return
			# Keep sandbox spawn/reset keys out of a scored, taught run.
			if event.physical_keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F6,KEY_F8,KEY_F9,KEY_BACKSPACE]: return
	super._unhandled_input(event)

func _physics_process(delta: float) -> void:
	if not _campaign_ready: return
	_damage_flash = maxf(0,_damage_flash-delta)
	_update_run_hud()
	if tutorial.blocking: return
	if mode == &"won": return
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
		weapons.select_tool(4)
		run_hint.text = "Hold Space + scroll down to undo the injury · R retry room"
		if _dead_age >= 6.0 or not equipment.can_use(&"clock"):
			SceneManager.show_run_result(false)
		return
	var inspecting_before: bool = history.inspecting
	super._physics_process(delta)
	if inspecting_before or history.inspecting: return
	if not (mode == &"practice" and lesson == &"rewind" and not _rewound):
		player.health = recovery.step(delta,player.health,float(Tuning.PLAYER.health))
	if mode == &"practice":
		if tutorial.is_learned(lesson):
			_start_pressure()
			return
		_practice_age += delta
		_slow_used = _slow_used or player.world_scale < .99
		_observe_specimens()
		if lesson == &"rewind" and not _injury_given and _practice_age >= 1.5:
			player.take_damage(20)
			_injury_given = true
		if not tutorial.active_id.is_empty(): tutorial.world_points.assign(_targets())
		if _lesson_succeeded():
			tutorial.complete_lesson(lesson)
			history.clear()
			_start_pressure()
		elif _needs_combat_target() and _alive_specimens() == 0:
			_spawn_practice() # A body-only kill does not deadlock the teaching.
	elif mode == &"pressure" and director.enemies.is_empty():
		mode = &"recovery"
		timer = float(waves[wave_index].get("recovery",3.0))
		history.clear()
		run_hint.text = "Clear. Repair before the next group."
	elif mode == &"recovery":
		timer -= delta * player.world_scale
		if timer <= 0 and equipment.repairing == &"": _begin_wave()
	elif mode == &"exit":
		var exit: Vector3 = room.exit_door.position
		if Vector2(player.position.x-exit.x,player.position.z-exit.z).length() < 1.8:
			enter_room(room_index+1)

func _begin_wave() -> void:
	history.clear()
	wave_index += 1
	if wave_index >= waves.size():
		if room_index == 3:
			mode = &"won"
			SceneManager.show_run_result(true)
		else:
			mode = &"exit"
			museum.set_exit_open(true)
			run_hint.text = "Gallery clear · walk to the lit exit."
		return
	var wave: Dictionary = waves[wave_index]
	lesson = StringName(wave.lesson)
	if &"final_boss" in wave.enemies:
		mode = &"ceremony"
		title.text = "The Burial Device"
		museum.start_boss_entrance()
	else: _spawn_wave()

func _spawn_wave() -> void:
	title.text = ""
	var wave: Dictionary = waves[wave_index]
	if tutorial.is_learned(lesson) or (room_index == 3 and not &"final_boss" in wave.enemies):
		mode = &"pressure"
		_spawn_members(int(wave.count))
		return
	_charged_kills.clear()
	_kills.clear(); _opened=false; _cut=false; _heated=false
	_slow_used=false; _charged=false; _pierced=false; _repaired=false; _rewound=false
	_injury_given=false; _practice_age=0
	_origin = player.position
	mode = &"practice"
	_spawn_practice()
	if lesson == &"move":
		tutorial.show_lesson(lesson,"Find your footing","WASD moves. Aim with the mouse. Walk around the displays.",_targets())
	else: tutorial.show_known_lesson(lesson,_targets())

func _spawn_practice() -> void:
	specimens.clear()
	_specimen_ids.clear()
	_kills.clear(); _charged_kills.clear(); _cut=false; _heated=false; _opened=false; _pierced=false
	if not _needs_combat_target():
		if lesson == &"repair" and equipment.is_full(&"ring"):
			equipment.spend(&"ring",equipment.capacity(&"ring")*.3)
			weapons.select_tool(1)
		return
	var kind: StringName = StringName(waves[wave_index].enemies[0])
	if lesson == &"charge": kind = &"yellow"
	var count := 3 if lesson == &"charge" else 1
	specimens.assign(director.spawn_formation(&"line" if lesson == &"charge" else &"curve",_repeat(kind,count),player,room_index*37+wave_index))
	for enemy in specimens:
		_specimen_ids.append(enemy.rewind_id)
		if kind != &"final_boss":
			enemy.contact_damage = 0
			enemy.move_speed = minf(enemy.move_speed,.65)

func _repeat(kind: StringName,count: int) -> Array:
	var result: Array = []
	for i in range(count): result.append(kind)
	return result

func _spawn_members(count: int) -> void:
	var wave: Dictionary = waves[wave_index]
	var kinds: Array = []
	for i in range(count): kinds.append(wave.enemies[i % wave.enemies.size()])
	if not kinds.is_empty(): director.spawn_formation(wave.formation,kinds,player,room_index*53+wave_index)

func _start_pressure() -> void:
	mode = &"pressure"
	for enemy in specimens:
		if is_instance_valid(enemy) and enemy.health > 0:
			var cfg: Dictionary = Tuning.ENEMIES[String(enemy.kind)]
			enemy.move_speed = float(cfg.speed)
			enemy.contact_damage = float(cfg.damage)
	run_hint.text = "Use the opening. Keep an escape route."
	# Utility practice stays calm. A boss is never duplicated after its lesson.
	var count := int(waves[wave_index].count)
	if lesson in [&"move",&"repair",&"rewind",&"final"]: count = 0
	else: count = maxi(0,count - specimens.size())
	_spawn_members(count)

func _needs_combat_target() -> bool:
	return lesson not in [&"move",&"repair",&"rewind"]

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
	if lesson == &"move": return player.position.distance_to(_origin) > 2
	if lesson == &"repair": return _repaired
	if lesson == &"rewind": return _rewound and _injury_given
	if lesson == &"slow": return _slow_used and _cut and not _kills.is_empty()
	if lesson == &"charge": return _pierced and _charged_kills.size() >= 2
	if lesson == &"cut": return _cut and not _kills.is_empty()
	if lesson == &"heat": return _heated and not _kills.is_empty()
	if lesson in [&"opening",&"loop",&"zigzag"]: return _opened and not _kills.is_empty()
	return not _kills.is_empty()

func _targets() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for enemy in specimens:
		if not is_instance_valid(enemy) or enemy.health <= 0: continue
		if enemy.has_method("active_pattern") and enemy.active_pattern() == &"pair":
			points.append(enemy.valve_world_position(0))
			points.append(enemy.valve_world_position(1))
		elif lesson == &"heat" and is_instance_valid(enemy.part_visual.plate):
			points.append(enemy.part_visual.plate.global_position+Vector3.UP*.5)
		elif lesson == &"opening" and not enemy.is_core_exposed():
			var ends: Array = enemy.cable_world_points()
			points.append((ends[0]+ends[-1])*.5)
		elif lesson in [&"cut",&"slow",&"loop",&"zigzag"] or (lesson == &"final" and enemy.has_cuttable_part()):
			var cable: Array = enemy.cable_world_points()
			if enemy.has_method("lesson_state"):
				for i in range(0,cable.size()-1,2): points.append((cable[i]+cable[i+1])*.5)
			else: points.append((cable[0]+cable[-1])*.5)
		else: points.append(enemy.core_world_position() if enemy.is_core_exposed() else enemy.position+Vector3.UP)
	if points.is_empty(): points.append(player.position)
	return points

func _on_run_event(kind: StringName,_point: Vector3,_strength: float) -> void:
	if kind == &"flash_pierce": _charged = true

func _on_resolved_hit(tool: StringName,result: Dictionary,context: Dictionary,enemy_id: int) -> void:
	if tool == &"beam" and bool(result.get("killed",false)) and bool(context.get("piercing",false)):
		_charged_kills[enemy_id] = true
		_pierced = _pierced or int(context.get("prior_hits",0)) > 0

func _on_wounded(amount: float) -> void:
	recovery.damaged(amount)
	_damage_flash = .5
	feedback.cue(&"hit",player.position,minf(1,amount/20))

func _update_run_hud() -> void:
	if health_label == null: return
	health_label.modulate = Color.WHITE.lerp(Color("ff7766"),clampf(_damage_flash*2,0,1))
	health_label.text = "Health %.0f" % player.health
	if recovery.recoverable > 0: health_label.text += " · %.0f recoverable" % recovery.recoverable
	if history.inspecting: health_label.text = "Health %.0f → %.0f · return %.1fs" % [_review_start_health,player.health,history.selected_seconds_ago]

func capture_state() -> Dictionary:
	var data := super.capture_state()
	data["recovery"] = recovery.capture_state()
	return data

func _restore_world(data: Dictionary,live_clock: float) -> void:
	super._restore_world(data,live_clock)
	recovery.restore_state(data.get("recovery",{}))
	if mode == &"practice":
		specimens.clear()
		for enemy in director.enemies:
			if enemy.rewind_id in _specimen_ids:
				specimens.append(enemy)
				if enemy.kind != &"final_boss":
					enemy.contact_damage = 0
					enemy.move_speed = minf(enemy.move_speed,.65)
	if player.health > 0: _dead_age = 0

func _begin_inspection() -> void:
	_review_start_health = player.health
	super._begin_inspection()

func _finish_inspection(commit: bool) -> void:
	var age: float = history.selected_seconds_ago
	var before := _review_start_health
	super._finish_inspection(commit)
	if commit and age > 0 and player.health > before: _rewound = true
