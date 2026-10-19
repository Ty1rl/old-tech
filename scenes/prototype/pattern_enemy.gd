class_name CombatPatternEnemy
extends "res://scenes/prototype/enemy.gd"
# Drop-in enemy implementation; the campaign director selects this via handles().
const PatternVisual = preload("res://scenes/prototype/pattern_visual.gd")
const PHASES := [&"pair", &"zigzag", &"loop", &"core"]
var pattern_visual: CombatPatternVisual
var phase := 0
var link_mask := 0
var pair_progress := 0
var window_timer := 0.0
var pattern_open := false
var motion_clock := 0.0

static func handles(value: StringName) -> bool:
	return value in [&"pair", &"loop", &"zigzag", &"loop_boss", &"sequence_boss", &"final_boss"]

static func recommended_boss_escorts(boss_kind: StringName, hard: bool = false) -> Array[StringName]:
	var result: Array[StringName] = []
	var raw: Array = []
	match boss_kind:
		&"sequence_boss":
			raw = [&"yellow", &"ranged", &"blue", &"orange"] if hard else [&"yellow", &"ranged", &"blue"]
		&"loop_boss":
			raw = [&"blue", &"ranged", &"orange", &"yellow"] if hard else [&"blue", &"ranged", &"orange"]
		&"final_boss":
			raw = [&"blue", &"yellow", &"ranged", &"orange", &"side_guard"] if hard else [&"blue", &"yellow", &"ranged"]
		_:
			raw = [&"yellow", &"ranged", &"blue"]
	for item in raw:
		result.append(StringName(item))
	return result

func is_boss() -> bool:
	return String(kind).ends_with("_boss")

static func phases_for(value: StringName) -> int:
	return 4 if value == &"final_boss" else (3 if String(value).ends_with("_boss") else 1)

func phase_count() -> int:
	return phases_for(kind)

func _spans() -> Array:
	return PatternVisual.spans(active_pattern(), phase if kind == &"loop_boss" else 0)

func configure(p_kind: StringName, spawn_pos: Vector3, orbit_seed: int = 0) -> void:
	phase = 0
	link_mask = 0
	pair_progress = 0
	window_timer = 0
	pattern_open = false
	motion_clock = 0
	super.configure(p_kind, spawn_pos, orbit_seed)

func set_instruction_visible(value: bool) -> void:
	super.set_instruction_visible(value)
	if is_instance_valid(pattern_visual):
		pattern_visual.set_instruction_visible(value)

func active_pattern() -> StringName:
	if kind == &"loop_boss": return &"loop"
	if kind == &"sequence_boss": return &"pair"
	return PHASES[clampi(phase, 0, 3)] if kind == &"final_boss" else kind

func mechanism() -> StringName:
	return &"pattern" if handles(kind) else super.mechanism()

func lesson_state() -> Dictionary:
	var mode := active_pattern()
	var total := 2 if mode == &"pair" else _spans().size()
	return {"pattern": mode, "progress": pair_progress if mode == &"pair" else _cut_count(),
		"total": total, "open": pattern_open or (kind == &"final_boss" and phase == 3), "complete": pattern_open or health <= 0,
		"phase": phase, "phases": phase_count(), "boss": is_boss()}

func _cut_count() -> int:
	var count := 0
	for i in range(4):
		if link_mask & (1 << i): count += 1
	return count

func is_core_exposed() -> bool:
	return active_pattern() == &"pair" or pattern_open or (kind == &"final_boss" and phase == 3)

func has_cuttable_part() -> bool:
	return health > 0 and active_pattern() in [&"loop", &"zigzag"] and not pattern_open

func movement_radius() -> float:
	# Wide links/supports keep their physical room while turning or being shoved;
	# body contact damage still uses the smaller configured body radius.
	return PatternVisual.silhouette_radius(kind) if handles(kind) else radius

func attack_radius(_tool: StringName) -> float:
	return PatternVisual.silhouette_radius(kind)

# Flat pairs of anchors, NOT an implied continuous polyline. Receive_attack tests
# each physical span separately, so empty gaps never become cuttable connections.
func cable_world_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for span: Array in _spans():
		points.append(_local_part_world(span[0]))
		points.append(_local_part_world(span[1]))
	return points

func core_world_position() -> Vector3:
	if active_pattern() == &"pair" and not pattern_open:
		return valve_world_position(pair_progress)
	return _local_part_world(PatternVisual.core_anchor(is_boss()))

func valve_world_position(index: int) -> Vector3:
	return _local_part_world(PatternVisual.valve_anchor(clampi(index, 0, 1), is_boss()))

func _build_visuals() -> void:
	if not handles(kind):
		super._build_visuals()
		return
	if is_instance_valid(visual_root): visual_root.queue_free()
	if is_instance_valid(status_root): status_root.queue_free()
	part_visual = null
	warden_visual = null
	var pal := PatternVisual.palette_for(kind, is_boss())
	base_body_color = pal["body"]
	body_material = _make_mat(base_body_color)
	pattern_visual = PatternVisual.new()
	visual_root = pattern_visual
	add_child(visual_root)
	pattern_visual.build(active_pattern(), is_boss(), kind, phase)
	status_root = Node3D.new()
	add_child(status_root)
	var bar_y := 4.85 if is_boss() else 4.3
	hp_bar_fill = pattern_visual.box(status_root, Vector3(0, bar_y, 0), Vector3(radius * 2, 0.12 if is_boss() else 0.1, 0.12 if is_boss() else 0.1), Color("67d97e"))
	hp_bar_material = hp_bar_fill.material_override
	feedback_label = Label3D.new()
	feedback_label.position = Vector3(0, bar_y + 0.35, 0)
	feedback_label.font_size = 28
	feedback_label.pixel_size = 0.012
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	feedback_label.text = ""
	feedback_label.visible = false
	status_root.add_child(feedback_label)
	_update_warden_visuals()

func _update_warden_visuals() -> void:
	if not handles(kind):
		super._update_warden_visuals()
	elif is_instance_valid(pattern_visual):
		pattern_visual.sync(link_mask, pattern_open or (kind == &"final_boss" and phase == 3), plate_broken, pair_progress if active_pattern() == &"pair" else _cut_count(), window_timer, phase, attack_phase, health > 0)

func _reset_partial() -> void:
	link_mask = 0
	pair_progress = 0
	window_timer = 0
	# Health, destroyed orange plates and completed openings are never reset here.

func _open_pattern() -> void:
	pattern_open = true
	plate_broken = true
	cable_cut = true
	window_timer = 0

func _phase_floor() -> float:
	return max_health * float(phase_count() - 1 - phase) / float(phase_count()) if is_boss() else 0.0

func _advance_phase() -> void:
	phase = mini(phase_count() - 1, phase + 1)
	_reset_partial()
	pattern_open = kind == &"final_boss" and phase == 3
	cable_cut = pattern_open
	plate_broken = false
	shield_heat = 0
	core_broken = false
	attack_phase = &"recover"
	attack_timer = float(Tuning.PATTERNS.recovery)
	_build_visuals()
	_update_visual_facing()
	_update_health_visuals()

func debug_set_phase(value: int) -> void:
	if not is_boss(): return
	phase = clampi(value, 0, phase_count() - 1)
	health = max_health * float(phase_count() - phase) / float(phase_count())
	_reset_partial()
	pattern_open = kind == &"final_boss" and phase == 3
	cable_cut = pattern_open
	plate_broken = false
	core_broken = false
	shield_heat = 0
	attack_phase = &"recover"
	attack_timer = float(Tuning.PATTERNS.recovery)
	_build_visuals()
	_sync_derived_visuals("", Color.WHITE)
	_sync_pattern_attack_warning()

func receive_attack(tool: StringName, amount: float, contact_world: Vector3, context: Dictionary = {}) -> Dictionary:
	if not handles(kind): return super.receive_attack(tool, amount, contact_world, context)
	var miss := {"dealt": 0.0, "armored": false, "killed": false, "connected": false, "cue": &""}
	if health <= 0 or amount <= 0: return miss
	var start: Vector3 = context.get("segment_start", contact_world)
	var finish: Vector3 = context.get("segment_end", contact_world)
	var width := maxf(0, float(context.get("radius", 0)))
	var segmented := context.has("segment_start") and context.has("segment_end")
	var body := _point_segment_distance(position, start, finish) <= radius + width
	var already := tool == &"ring" and bool(context.get("already_hit", false))
	var cuts := 0
	if tool == &"ring" and segmented and has_cuttable_part():
		var points := cable_world_points()
		for i in range(points.size() / 2):
			if _segment_distance(start, finish, points[i * 2], points[i * 2 + 1]) <= width + float(Tuning.PATTERNS.link_radius):
				cuts |= 1 << i
	var target_finish: Vector3 = context.get("mechanism_end", finish)
	var valve_hit := -1
	if tool == &"beam" and segmented and active_pattern() == &"pair" and not pattern_open:
		# Aim assistance selects the currently open valve. A ray crossing both
		# sensors must not overwrite that valid hit with the closed sensor.
		for i in [pair_progress, 1-pair_progress]:
			if _point_segment_distance(valve_world_position(i), start, target_finish) <= width + float(Tuning.PATTERNS.target_radius):
				valve_hit = i
				break
	var core_hit := tool == &"beam" and segmented and _point_segment_distance(core_world_position(), start, target_finish) <= width + float(Tuning.PATTERNS.target_radius)
	# Preserve exact swept endpoints: a blocked/short segment cannot hit beyond it.
	if not body and cuts == 0 and not core_hit and valve_hit == -1: return miss
	var cue: StringName = &""
	var decisive := false
	var mode := active_pattern()
	# Launch dedup controls body damage only. Link progress belongs to the enemy
	# until the first cut's fixed deadline expires; fresh launches never reset it.
	if cuts != 0:
		var previous := link_mask
		link_mask |= cuts
		if link_mask != previous:
			if window_timer <= 0: window_timer = float(Tuning.PATTERNS.window)
			cue = &"link_cut"
		if _cut_count() == _spans().size():
			_open_pattern()
			cue = &"pattern_open"
	if tool == &"beam" and segmented and mode == &"pair" and not pattern_open:
		if valve_hit == pair_progress:
			pair_progress += 1
			if pair_progress == 2:
				_open_pattern()
				cue = &"pattern_open"
				decisive = not is_boss() # Bosses require a charged exposed-core finisher.
			else:
				window_timer = float(Tuning.PATTERNS.pair_window)
				cue = &"valve_b"
		elif body or valve_hit != -1:
			_reset_partial()
			cue = &"shutters_reset"
	elif core_hit and is_core_exposed() and float(context.get("charge", 0)) >= float(Tuning.PATTERNS.core_charge):
		decisive = true
		core_broken = true
		cue = &"core_break"
	if tool == &"cone" and body and not plate_broken:
		shield_heat += maxf(0, float(context.get("dt", 0)))
		if shield_heat >= float(Tuning.MATCHUPS.heat_seconds):
			plate_broken = true
			shield_heat = 0
			cue = &"armor_removed"
	var damage := 0.0 if already or (not body and valve_hit == -1) else amount * float(Tuning.PATTERNS.body_bare if plate_broken else Tuning.PATTERNS.body_armored)
	if decisive: damage = maxf(0, health - _phase_floor())
	var result := hit(damage, contact_world)
	result["connected"] = true
	result["armored"] = not plate_broken and not decisive
	if is_boss() and health > 0:
		while phase < phase_count() - 1 and health <= _phase_floor() + 0.001:
			_advance_phase()
			cue = &"phase_removed"
	result["cue"] = cue
	last_hit_result = result.duplicate()
	if is_instance_valid(feedback_label):
		feedback_label.text = ""
		feedback_label.visible = false
	feedback_timer = 0.0
	_update_warden_visuals()
	return result

func step_enemy(world_delta: float, player: Node3D, neighbors: Array = [], cohesion: Vector3 = Vector3.ZERO) -> void:
	if not handles(kind):
		super.step_enemy(world_delta, player, neighbors, cohesion)
		return
	if world_delta <= 0 or (is_instance_valid(player) and not player.can_act): navigation.suspend_avoidance()
	if health <= 0 or world_delta <= 0 or (is_instance_valid(player) and not player.can_act): return
	if not pattern_open and window_timer > 0:
		window_timer = maxf(0, window_timer - world_delta)
		if window_timer <= 0: _reset_partial()
	# Base movement/cover/stagger integration is reused. Pattern attacks provide
	# a longer warning, a committed beat, then a generous stationary recovery.
	# Face the player between boss attacks; the visible warning and shot stay locked.
	if is_boss() and attack_phase == &"recover" and stagger_timer <= 0.0 and is_instance_valid(player):
		var toward := Vector3(player.position.x - position.x, 0.0, player.position.z - position.z)
		if toward.length_squared() > 0.0001:
			facing = _rotate_xz_toward(facing, toward.normalized(), aim_turn_rate(float(Tuning.PATTERNS.boss_recovery_turn_rate)) * world_delta)
	var before := position
	var locked_facing := facing
	var locked := attack_phase != &"approach"
	super.step_enemy(world_delta, player, neighbors, cohesion)
	if is_instance_valid(player) and not player.can_act: return
	if locked: facing = locked_facing
	var speed := position.distance_to(before) / world_delta
	motion_clock += speed * world_delta * 5.5
	# Only feet/stone body move visually; interactive anchors stay authoritative.
	if is_instance_valid(pattern_visual):
		_update_warden_visuals()
		pattern_visual.pose(motion_clock, speed if attack_phase == &"approach" else 0, attack_phase, attack_timer)
		_sync_pattern_attack_warning()

func hostile_shot_directions() -> Array[Vector3]:
	var directions: Array[Vector3] = []
	if not is_boss() or active_pattern() == &"loop": return directions
	# Three broad, fixed rays. At a 3m dodge radius each gap is >1.7m clear
	# of the .24m bolt heads: space for a 1m player plus lateral margin.
	for angle: float in [-.78, 0.0, .78]:
		directions.append(ranged_aim.rotated(Vector3.UP, angle))
	return directions


func _sync_pattern_attack_warning() -> void:
	var ranged_boss := is_boss() and active_pattern() != &"loop"
	if ranged_boss or is_instance_valid(ranged_warning):
		_sync_attack_warning(hostile_shot_directions(), 11, ranged_boss and attack_phase in [&"windup", &"commit"])
	# Keep the existing visual-family warning node/API, but show the exact
	# authoritative shot lanes instead of its old, mismatched 5-ray overlay.
	if ranged_boss and is_instance_valid(pattern_visual):
		for child in pattern_visual.warning.get_children(): child.visible = false


func _step_part_attack(world_delta: float, player: Node3D, distance: float) -> void:
	if not handles(kind):
		super._step_part_attack(world_delta, player, distance)
		return
	if health <= 0 or world_delta <= 0 or not is_instance_valid(player) or not player.can_act: return
	var mode := active_pattern()
	var reach := 4.1 if is_boss() and mode == &"loop" else radius + PLAYER_CONTACT_RADIUS + 0.2
	var trigger := 9.5 if is_boss() and mode in [&"pair", &"zigzag", &"core"] else reach
	if attack_phase == &"approach":
		if distance <= trigger:
			_lock_warning_aim()
			attack_phase = &"windup"
			attack_timer = attack_windup(1.1 if is_boss() else float(Tuning.PATTERNS.windup))
			_emit_enemy_event(&"warning", position)
		_sync_pattern_attack_warning()
		return
	attack_timer = maxf(0, attack_timer - world_delta)
	if attack_timer > 0:
		_sync_pattern_attack_warning()
		return
	if attack_phase == &"windup":
		attack_phase = &"commit"
		attack_timer = float(Tuning.PATTERNS.commit)
	elif attack_phase == &"commit":
		# Commit recovery before a strike can capture emergency NOW synchronously.
		attack_phase = &"recover"
		attack_timer = 2.3 if is_boss() else float(Tuning.PATTERNS.recovery)
		if is_boss() and mode != &"loop":
			var director := get_parent()
			if director != null and director.has_method("launch_projectile"):
				var emitted := false
				for direction in hostile_shot_directions():
					emitted = director.launch_projectile(projectile_origin(direction), direction, contact_damage, 5.6, combat_id()) or emitted
				if emitted:
					_emit_enemy_event(&"attack", projectile_origin(ranged_aim))
		else:
			_emit_enemy_event(&"attack", position)
		if (not is_boss() or mode == &"loop") and distance <= reach and player.can_act:
			var toward: Vector3 = player.position - position
			if is_boss() or toward.normalized().dot(facing) > .2:
				var controller: TimeController = player.time_controller
				var before := controller.meter
				player.take_damage(contact_damage)
				var director := get_parent()
				if controller.meter < before and director != null and director.has_method("hostile_cue"):
					director.hostile_cue(&"player_hurt", player.position, 1)
	else:
		attack_phase = &"approach"
	_sync_pattern_attack_warning()

func capture_state() -> Dictionary:
	var state := super.capture_state()
	state.merge({"phase": phase, "link_mask": link_mask, "pair_progress": pair_progress,
		"window_timer": window_timer, "pattern_open": pattern_open, "motion_clock": motion_clock, "hostile_aim": ranged_aim})
	return state

func restore_state(data: Dictionary) -> void:
	var previous_phase := phase
	var previous_kind := kind
	phase = clampi(int(data.get("phase", 0)), 0, 3)
	link_mask = int(data.get("link_mask", 0)) & 15
	pair_progress = clampi(int(data.get("pair_progress", 0)), 0, 2)
	window_timer = maxf(0, float(data.get("window_timer", 0)))
	pattern_open = bool(data.get("pattern_open", false))
	motion_clock = float(data.get("motion_clock", 0))
	super.restore_state(data)
	ranged_aim = Vector3(data.get("hostile_aim", facing)).normalized()
	# Same-kind rewind may cross a boss phase; geometry must follow the snapshot.
	if handles(kind):
		if phase != previous_phase and kind == previous_kind: _build_visuals()
		_sync_derived_visuals(String(data.get("feedback_text", "")), data.get("feedback_color", Color.WHITE))
		_sync_pattern_attack_warning()
