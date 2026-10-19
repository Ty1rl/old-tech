class_name LessonDemo
extends Node

## Cancellable ordinary-action demonstration driver.
## Drives the real protagonist sprite and WeaponController against real targets
## while isolating demonstration costs, history, and outcomes from the player's run.

signal ready_for_practice(lesson_id: StringName)
signal demo_completed(lesson_id: StringName, summary: Dictionary)
signal demo_cancelled(lesson_id: StringName)

const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")

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
		"subtitle": "1 · RING CUTTER",
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

var active := false
var lesson_id: StringName = &""
var phase := 0
var elapsed := 0.0
var phase_elapsed := 0.0
var arena: Node3D = null
var tutorial_ui: Control = null
var demo_enemies: Array[Node3D] = []
var learned_demos: Dictionary = {}
var last_summary: Dictionary = {}

var _demo_origin := Vector3.ZERO
var _current_aim := Vector3.ZERO
var _stroke_waypoints: Array[Vector3] = []
var _waypoint_index := 0
var _handoff_emitted := false
var _restoring := false

var _saved_player: Dictionary = {}
var _saved_visual_tool := 1
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


static func handles(id: StringName) -> bool:
	return id in SUPPORTED_LESSONS


static func spec_for(id: StringName) -> Dictionary:
	return SPECS.get(String(id), {}).duplicate(true)


static func _game_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameState") if tree != null and tree.root != null else null


static func _scene_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SceneManager") if tree != null and tree.root != null else null


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


func mark_learned(id: StringName) -> void:
	if not id.is_empty():
		learned_demos[id] = true


func reset_run() -> void:
	if active:
		cancel()
	learned_demos.clear()
	last_summary.clear()


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
	phase = 0
	elapsed = 0.0
	phase_elapsed = 0.0
	_handoff_emitted = false
	_stroke_waypoints.clear()
	_waypoint_index = 0

	var spec := spec_for(id)
	var p_tool := int(spec.get("primary_tool", 2))
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
		"slow_engaged": false,
		"min_world_scale": 1.0,
		"shot_during_slow": false,
		"slow_resumed": false,
		"max_world_scale_after_slow": 0.0,
		"opened_before_finish": false,
		"yellow_finished_after_open": false,
		"target_killed": false,
		"completed": false,
		"cancelled": false,
		"skipped": false,
		"isolated_restore_verified": false,
	}

	_capture_baseline()
	_setup_demo_stage(id, spec)
	active = true

	if is_instance_valid(tutorial_ui):
		if tutorial_ui.get("active_id") != id:
			tutorial_ui.call("show_known_lesson", id, current_targets())
		else:
			tutorial_ui.world_points.assign(current_targets())
		if tutorial_ui.has_signal("resume_requested") and not tutorial_ui.resume_requested.is_connected(_on_tutorial_resume_requested):
			tutorial_ui.resume_requested.connect(_on_tutorial_resume_requested)
		if tutorial_ui.has_signal("lesson_completed") and not tutorial_ui.lesson_completed.is_connected(_on_tutorial_lesson_completed):
			tutorial_ui.lesson_completed.connect(_on_tutorial_lesson_completed)

	if not arena.tree_exiting.is_connected(_on_arena_tree_exiting):
		arena.tree_exiting.connect(_on_arena_tree_exiting)

	return true


func step(real_delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(arena) or not arena.is_inside_tree():
		cancel()
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

	elapsed += dt
	phase_elapsed += dt

	var tc: TimeController = arena.get("time_controller") as TimeController
	if lesson_id == &"slow" and is_instance_valid(tc):
		tc.advance(dt)
		var ws := tc.world_scale
		last_summary["min_world_scale"] = minf(float(last_summary["min_world_scale"]), ws)
		if phase >= 4:
			last_summary["max_world_scale_after_slow"] = maxf(float(last_summary["max_world_scale_after_slow"]), ws)
	var world_scale := tc.world_scale if (lesson_id == &"slow" and is_instance_valid(tc)) else 1.0
	var world_dt := dt * world_scale

	_step_lesson_choreography(dt, world_dt)
	if not active:
		return

	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	var director: Node3D = arena.get("director") as Node3D

	if is_instance_valid(player):
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

	_observe_demo_targets()

	if is_instance_valid(tutorial_ui) and tutorial_ui.get("active_id") == lesson_id:
		var pts := current_targets()
		if not pts.is_empty():
			tutorial_ui.world_points.assign(pts)

	var status_hud: Node = arena.get("status_hud") as Node
	if is_instance_valid(status_hud) and is_instance_valid(player) and is_instance_valid(weapons):
		status_hud.call("update_status", player, weapons, arena.get("equipment"))
	var time_cue: Node = arena.get("time_cue") as Node
	if is_instance_valid(time_cue) and time_cue.has_method("update_state"):
		time_cue.call("update_state", world_scale, false)

	_check_phase_completion()


func skip_to_practice() -> void:
	if not active:
		return
	var id := lesson_id
	last_summary["skipped"] = true
	_teardown_demo(true)
	_emit_practice_handoff(id)


func cancel() -> void:
	if not active:
		return
	var id := lesson_id
	last_summary["cancelled"] = true
	_teardown_demo(true)
	demo_cancelled.emit(id)


func current_targets() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for enemy in demo_enemies:
		if not is_instance_valid(enemy) or not enemy.is_inside_tree() or float(enemy.get("health")) <= 0.0:
			continue
		if lesson_id == &"pair" and enemy.has_method("valve_world_position"):
			var prog := int(enemy.get("pair_progress"))
			pts.append(enemy.call("valve_world_position", clampi(prog, 0, 1)))
		elif lesson_id == &"heat" and is_instance_valid(enemy.get("part_visual")) and is_instance_valid(enemy.part_visual.get("plate")) and enemy.part_visual.plate.is_inside_tree():
			pts.append(enemy.part_visual.plate.global_position + Vector3.UP * 0.5)
		elif lesson_id in [&"cut", &"opening", &"loop", &"zigzag"] and enemy.has_method("has_cuttable_part") and bool(enemy.call("has_cuttable_part")):
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
		pts.append((arena.get("player") as Node3D).position + Vector3(0.0, 1.0, -5.0))
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
		if not weapons.resolved_hit.is_connected(_on_demo_resolved_hit):
			weapons.resolved_hit.connect(_on_demo_resolved_hit)
		if not weapons.combat_event.is_connected(_on_demo_combat_event):
			weapons.combat_event.connect(_on_demo_combat_event)


func _setup_demo_stage(id: StringName, spec: Dictionary) -> void:
	var player: Node3D = arena.get("player") as Node3D
	var equipment: WeaponEquipment = arena.get("equipment") as WeaponEquipment
	var weapons: Node3D = arena.get("weapons") as Node3D
	var director: Node3D = arena.get("director") as Node3D
	var cover: RefCounted = arena.get("cover") as RefCounted

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
	_demo_origin = Vector3(clampf(raw_pos.x, -8.0, 8.0), 0.0, clampf(raw_pos.z, -3.5, 10.0))
	if is_instance_valid(player):
		player.position = Vector3(_demo_origin.x, raw_pos.y, _demo_origin.z)
		player.reset_physics_interpolation()

	var p_tool := int(spec.get("primary_tool", 2))
	if is_instance_valid(weapons):
		var all_tools: Array[int] = [1, 2, 3]
		weapons.call("set_loadout", all_tools, p_tool)
		weapons.call("select_tool", p_tool)
	if is_instance_valid(player) and player.has_method("set_visual_tool"):
		player.call("set_visual_tool", p_tool)

	demo_enemies.clear()
	if is_instance_valid(director):
		if id == &"charge":
			var front: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(0.0, 0.0, -4.6))
			var back: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(0.0, 0.0, -7.8))
			for enemy in [front, back]:
				if is_instance_valid(enemy):
					_prepare_demo_enemy(enemy)
					demo_enemies.append(enemy)
		elif id == &"heat":
			var orange: Node3D = director.call("spawn", &"orange", _demo_origin + Vector3(0.0, 0.0, -3.6))
			if is_instance_valid(orange):
				_prepare_demo_enemy(orange)
				demo_enemies.append(orange)
		elif id == &"slow":
			var mover: Node3D = director.call("spawn", &"yellow", _demo_origin + Vector3(-1.4, 0.0, -5.4))
			if is_instance_valid(mover):
				_prepare_demo_enemy(mover)
				demo_enemies.append(mover)
		elif id in [&"pair", &"loop", &"zigzag"]:
			var pat: Node3D = director.call("spawn", spec.get("enemy_kind", id), _demo_origin + Vector3(0.0, 0.0, -6.4))
			if is_instance_valid(pat):
				_prepare_demo_enemy(pat)
				demo_enemies.append(pat)
		else:
			var single: Node3D = director.call("spawn", spec.get("enemy_kind", &"yellow"), _demo_origin + Vector3(0.0, 0.0, -5.4))
			if is_instance_valid(single):
				_prepare_demo_enemy(single)
				demo_enemies.append(single)

	_build_stroke_waypoints(id)
	var init_targets := current_targets()
	_current_aim = init_targets[0] if not init_targets.is_empty() else (_demo_origin + Vector3(0.0, 0.0, -5.4))
	if is_instance_valid(player) and player.has_method("_face"):
		player.call("_face", _current_aim)
	if is_instance_valid(weapons):
		weapons.call("rebuild_visuals", player)


func _prepare_demo_enemy(enemy: Node3D) -> void:
	enemy.set("contact_damage", 0.0)
	enemy.set("move_speed", 0.0)
	enemy.set("facing", Vector3.BACK)
	if "projectile_damage" in enemy:
		enemy.set("projectile_damage", 0.0)
	if "attack_timer" in enemy:
		enemy.set("attack_timer", 99.0)


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
		var start := a - dir * 0.95
		var finish := b + dir * 0.95
		for i in range(9):
			_stroke_waypoints.append(start.lerp(finish, float(i) / 8.0))
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
		_append_densified_waypoints(anchors, 5)
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
		_append_densified_waypoints(anchors, 4)


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


func _switch_demo_tool(tool_slot: int, phase_color: Color = Color.WHITE, subtitle: String = "") -> void:
	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	if is_instance_valid(weapons):
		weapons.call("select_tool", tool_slot)
		weapons.set("require_fresh_press", false)
	if is_instance_valid(player) and player.has_method("set_visual_tool"):
		player.call("set_visual_tool", tool_slot)
	_record_tool_used(tool_slot)
	if is_instance_valid(tutorial_ui) and tutorial_ui.has_method("set_phase_accent") and phase_color != Color.WHITE:
		tutorial_ui.call("set_phase_accent", phase_color, subtitle)


func _advance_phase(next_phase: int) -> void:
	phase = next_phase
	phase_elapsed = 0.0


func _step_lesson_choreography(_dt: float, world_dt: float) -> void:
	var player: Node3D = arena.get("player") as Node3D
	var weapons: Node3D = arena.get("weapons") as Node3D
	var tc: TimeController = arena.get("time_controller") as TimeController
	if not is_instance_valid(player) or not is_instance_valid(weapons):
		return
	var enemy: Node3D = demo_enemies[0] if (not demo_enemies.is_empty() and is_instance_valid(demo_enemies[0]) and demo_enemies[0].is_inside_tree()) else null

	match lesson_id:
		&"shot":
			if enemy != null:
				_current_aim = enemy.call("core_world_position")
			if phase == 0 and phase_elapsed >= 0.12:
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(1)
			elif phase == 1 and phase_elapsed >= 0.06:
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["shot_fired"] = true
				_advance_phase(2)

		&"charge":
			var back_enemy: Node3D = demo_enemies[1] if (demo_enemies.size() > 1 and is_instance_valid(demo_enemies[1]) and demo_enemies[1].is_inside_tree()) else enemy
			if back_enemy != null:
				_current_aim = back_enemy.call("core_world_position")
			if phase == 0 and phase_elapsed >= 0.10:
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(1)
			elif phase == 1 and float(weapons.flash.charge) >= 1.0 and phase_elapsed >= 0.72:
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["charged_shot_fired"] = true
				_advance_phase(2)

		&"cut":
			if phase == 0 and not _stroke_waypoints.is_empty() and phase_elapsed >= 0.08:
				_current_aim = _stroke_waypoints[0]
				weapons.ring.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["ring_drawn"] = true
				_advance_phase(1)
			elif phase == 1:
				_sample_ring_along_waypoints(0.32, player, weapons)
				if phase_elapsed >= 0.32:
					_current_aim = _stroke_waypoints[-1]
					weapons.ring.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 1))
					weapons.mouse_held = false
					last_summary["ring_launched"] = true
					_advance_phase(2)

		&"heat":
			if enemy != null and float(enemy.get("health")) > 0.0:
				enemy.set("knockback_vel", Vector3.ZERO)
				enemy.position.x = _demo_origin.x
				enemy.position.z = clampf(enemy.position.z, _demo_origin.z - 4.2, _demo_origin.z - 3.4)
				_current_aim = enemy.position
			if phase == 0 and phase_elapsed >= 0.08:
				weapons.bellows.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["cone_held"] = true
				_advance_phase(1)
			elif phase == 1:
				weapons.bellows.aim_at(_demo_origin, _current_aim)
				if bool(last_summary["plate_broken"]) or (enemy == null or float(enemy.get("health")) <= 0.0):
					weapons.bellows.release()
					weapons.mouse_held = false
					_advance_phase(2)

		&"slow":
			if enemy != null and float(enemy.get("health")) > 0.0:
				enemy.position.x = clampf(enemy.position.x + 2.2 * world_dt, _demo_origin.x - 2.2, _demo_origin.x + 2.2)
				_current_aim = enemy.call("core_world_position")
			if phase == 0 and phase_elapsed >= 0.14:
				if is_instance_valid(tc):
					tc.set_capabilities(true, tc.rewind_unlocked)
					tc.slow_requested = true
				last_summary["slow_engaged"] = true
				_advance_phase(1)
			elif phase == 1 and is_instance_valid(tc) and tc.world_scale <= 0.45 and phase_elapsed >= 0.22:
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(2)
			elif phase == 2 and phase_elapsed >= 0.05:
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["shot_fired"] = true
				last_summary["shot_during_slow"] = is_instance_valid(tc) and tc.world_scale < 0.55
				_advance_phase(3)
			elif phase == 3 and bool(last_summary["target_killed"]):
				if is_instance_valid(tc):
					tc.slow_requested = false
				_advance_phase(4)
			elif phase == 4 and is_instance_valid(tc) and tc.world_scale >= 0.85:
				last_summary["slow_resumed"] = true
				_advance_phase(5)

		&"opening":
			if phase == 0 and not _stroke_waypoints.is_empty() and phase_elapsed >= 0.08:
				_current_aim = _stroke_waypoints[0]
				weapons.ring.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["ring_drawn"] = true
				_advance_phase(1)
			elif phase == 1:
				_sample_ring_along_waypoints(0.28, player, weapons)
				if phase_elapsed >= 0.28:
					_current_aim = _stroke_waypoints[-1]
					weapons.ring.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 1))
					weapons.mouse_held = false
					last_summary["ring_launched"] = true
					_advance_phase(2)
			elif phase == 2 and bool(last_summary["opened_before_finish"]):
				_switch_demo_tool(2, ToolStyle.BEAM, "2 · FOCUSED FLASH · FINISH YELLOW")
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(3)
			elif phase == 3 and phase_elapsed >= 0.06:
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
				weapons.mouse_held = false
				last_summary["shot_fired"] = true
				_advance_phase(4)

		&"pair":
			if phase == 0 and enemy != null:
				_current_aim = enemy.call("valve_world_position", 0)
				if phase_elapsed >= 0.08 and not weapons.flash.charging:
					weapons.flash.press()
					weapons.mouse_held = true
				if phase_elapsed >= 0.14 and weapons.flash.charging:
					weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
					weapons.mouse_held = false
					last_summary["shot_fired"] = true
					_advance_phase(1)
			elif phase == 1 and bool(last_summary["opened_before_finish"]):
				_advance_phase(2)
			elif phase == 2 and enemy != null:
				_current_aim = enemy.call("valve_world_position", 1)
				if float(weapons.flash.cooldown) <= 0.0 and not weapons.flash.charging:
					weapons.flash.press()
					weapons.mouse_held = true
				elif weapons.flash.charging and phase_elapsed >= 0.06:
					weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
					weapons.mouse_held = false
					_advance_phase(3)

		&"loop", &"zigzag":
			if phase == 0 and not _stroke_waypoints.is_empty() and phase_elapsed >= 0.08:
				_current_aim = _stroke_waypoints[0]
				weapons.ring.press(_demo_origin, _current_aim)
				weapons.mouse_held = true
				last_summary["ring_drawn"] = true
				_advance_phase(1)
			elif phase == 1:
				_sample_ring_along_waypoints(0.38, player, weapons)
				if phase_elapsed >= 0.38:
					_current_aim = _stroke_waypoints[-1]
					weapons.ring.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 1))
					weapons.mouse_held = false
					last_summary["ring_launched"] = true
					_advance_phase(2)
			elif phase == 2 and bool(last_summary["opened_before_finish"]):
				_switch_demo_tool(2, ToolStyle.BEAM, "2 · FOCUSED FLASH · CHARGE YELLOW")
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				weapons.flash.press()
				weapons.mouse_held = true
				_advance_phase(3)
			elif phase == 3:
				if enemy != null:
					_current_aim = enemy.call("core_world_position")
				if float(weapons.flash.charge) >= 1.0:
					weapons.flash.release(_demo_origin, _current_aim, weapons.call("_muzzle", player, 2))
					weapons.mouse_held = false
					last_summary["charged_shot_fired"] = true
					last_summary["shot_fired"] = true
					_advance_phase(4)


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
	for enemy in demo_enemies:
		if not is_instance_valid(enemy):
			continue
		if bool(enemy.get("cable_cut")):
			last_summary["cable_cut"] = true
		if bool(enemy.get("plate_broken")):
			last_summary["plate_broken"] = true
		if lesson_id == &"opening" and bool(enemy.call("is_core_exposed")) and float(enemy.get("health")) > 0.0:
			last_summary["opened_before_finish"] = true
		elif lesson_id == &"pair" and int(enemy.get("pair_progress")) >= 1 and float(enemy.get("health")) > 0.0:
			last_summary["opened_before_finish"] = true
		elif lesson_id in [&"loop", &"zigzag"] and bool(enemy.get("pattern_open")) and float(enemy.get("health")) > 0.0:
			last_summary["opened_before_finish"] = true
			last_summary["cable_cut"] = true
		if float(enemy.get("health")) <= 0.0:
			if lesson_id in [&"opening", &"pair", &"loop", &"zigzag"] and bool(last_summary["opened_before_finish"]):
				last_summary["yellow_finished_after_open"] = true
		else:
			alive += 1
	if not demo_enemies.is_empty() and alive == 0:
		last_summary["target_killed"] = true


func _on_demo_resolved_hit(tool: StringName, result: Dictionary, context: Dictionary, _enemy_id: int) -> void:
	if not active:
		return
	_observe_demo_targets()
	var killed := bool(result.get("killed", false))
	if killed:
		if lesson_id != &"charge":
			last_summary["target_killed"] = true
		if tool == &"beam" and bool(context.get("piercing", false)):
			var pk := int(last_summary.get("pierce_kills", 0)) + 1
			last_summary["pierce_kills"] = pk
			if int(context.get("prior_hits", 0)) > 0 or pk >= 2:
				last_summary["pierced"] = true
			if pk >= 2:
				last_summary["target_killed"] = true
		if tool == &"beam" and lesson_id in [&"opening", &"pair", &"loop", &"zigzag"] and bool(last_summary["opened_before_finish"]):
			last_summary["yellow_finished_after_open"] = true


func _on_demo_combat_event(_kind: StringName, _point: Vector3, _strength: float) -> void:
	pass


func _check_phase_completion() -> void:
	if not active:
		return
	var done := false
	match lesson_id:
		&"shot":
			done = phase >= 2 and bool(last_summary["shot_fired"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.12
		&"charge":
			done = phase >= 2 and bool(last_summary["charged_shot_fired"]) and bool(last_summary["pierced"]) and int(last_summary["pierce_kills"]) >= 2 and phase_elapsed >= 0.12
		&"cut":
			done = phase >= 2 and bool(last_summary["ring_drawn"]) and bool(last_summary["ring_launched"]) and bool(last_summary["cable_cut"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.12
		&"heat":
			done = phase >= 2 and bool(last_summary["cone_held"]) and bool(last_summary["plate_broken"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.10
		&"slow":
			done = phase >= 5 and bool(last_summary["slow_engaged"]) and bool(last_summary["shot_during_slow"]) and bool(last_summary["target_killed"]) and bool(last_summary["slow_resumed"])
		&"opening", &"pair", &"loop", &"zigzag":
			done = phase >= 3 and bool(last_summary["opened_before_finish"]) and bool(last_summary["yellow_finished_after_open"]) and bool(last_summary["target_killed"]) and phase_elapsed >= 0.12

	if done:
		var id := lesson_id
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
	var finished_id := lesson_id
	lesson_id = &""
	demo_enemies.clear()
	_stroke_waypoints.clear()

	if is_instance_valid(tutorial_ui):
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

		_clear_all_controls()

		if restore_world and arena.is_inside_tree():
			var player: Node3D = arena.get("player") as Node3D
			var equipment: WeaponEquipment = arena.get("equipment") as WeaponEquipment
			var director: Node3D = arena.get("director") as Node3D
			var tc: TimeController = arena.get("time_controller") as TimeController
			var cover: RefCounted = arena.get("cover") as RefCounted

			if cover != null:
				cover.rectangles.assign(_saved_cover_rects)
			if is_instance_valid(director):
				director.call("restore_state", _saved_director)
				director.set("_spawn_counter", _saved_spawn_counter)
			if equipment != null:
				equipment.restore_state(_saved_equipment.duplicate(true))
				equipment.set_training_protection(_saved_training_protection)
			if is_instance_valid(player):
				player.call("restore_state", _saved_player)
				if player.has_method("set_visual_tool"):
					player.call("set_visual_tool", _saved_visual_tool)
			if is_instance_valid(weapons):
				weapons.available_tools.assign(_saved_available_tools)
				weapons.call("restore_state", _saved_weapons)
				weapons.set("selected_tool", _saved_selected_tool)
				weapons.call("cancel_input")
				weapons.set("mouse_held", false)
				weapons.set("require_fresh_press", false)
				weapons.call("rebuild_visuals", player)
			if is_instance_valid(tc) and not _saved_time.is_empty():
				tc.set_capabilities(bool(_saved_time.get("slow_unlocked", false)), bool(_saved_time.get("rewind_unlocked", false)))
				tc.slow_requested = false
				tc.set("_slow_active", false)
				tc.set("_meter", float(_saved_time.get("meter", tc.capacity)))
				tc.set("_world_scale", 1.0)
				tc.set("_charges", int(_saved_time.get("charges", tc.charges_per_attempt)))
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
			var status_hud: Node = arena.get("status_hud") as Node
			if is_instance_valid(status_hud) and is_instance_valid(player) and is_instance_valid(weapons):
				status_hud.call("update_status", player, weapons, equipment)
			var time_cue: Node = arena.get("time_cue") as Node
			if is_instance_valid(time_cue) and time_cue.has_method("update_state"):
				time_cue.call("update_state", 1.0, false)
			if is_instance_valid(tutorial_ui) and not finished_id.is_empty():
				if tutorial_ui.has_method("set_phase_accent") and tutorial_ui.has_method("accent_for_lesson") and tutorial_ui.has_method("subtitle_for_lesson"):
					var base_col: Color = tutorial_ui.call("accent_for_lesson", finished_id)
					var base_sub: String = tutorial_ui.call("subtitle_for_lesson", finished_id)
					tutorial_ui.call("set_phase_accent", base_col, base_sub)
				if arena.has_method("_targets"):
					tutorial_ui.world_points.assign(arena.call("_targets"))

			last_summary["isolated_restore_verified"] = true

	_disconnected_campaign_hit = false
	_disconnected_campaign_event = false
	_restoring = false


func _emit_practice_handoff(id: StringName) -> void:
	if _handoff_emitted or id.is_empty():
		return
	_handoff_emitted = true
	if is_instance_valid(tutorial_ui) and bool(tutorial_ui.get("blocking")) and tutorial_ui.get("active_id") == id:
		tutorial_ui.call("request_practice")
	ready_for_practice.emit(id)


func _on_tutorial_resume_requested(id: StringName) -> void:
	if active and id == lesson_id:
		skip_to_practice()


func _on_tutorial_lesson_completed(id: StringName) -> void:
	mark_learned(id)


func _on_arena_tree_exiting() -> void:
	if active:
		_teardown_demo(false)
		demo_cancelled.emit(lesson_id)
