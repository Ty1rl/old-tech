extends "res://scenes/prototype/enemy.gd"
# Drop-in enemy implementation; the campaign director selects this via handles().
const PatternVisual = preload("res://scenes/prototype/pattern_visual.gd")
const PHASES := [&"pair", &"zigzag", &"loop", &"core"]
var pattern_visual: Node3D
var phase := 0
var link_mask := 0
var pair_progress := 0
var window_timer := 0.0
var pattern_open := false
var motion_clock := 0.0

static func handles(value: StringName) -> bool:
	return value in [&"pair", &"loop", &"zigzag", &"final_boss"]

func configure(p_kind: StringName, spawn_pos: Vector3, orbit_seed: int = 0) -> void:
	phase = 0
	link_mask = 0
	pair_progress = 0
	window_timer = 0
	pattern_open = false
	motion_clock = 0
	super.configure(p_kind, spawn_pos, orbit_seed)

func active_pattern() -> StringName:
	return PHASES[clampi(phase, 0, 3)] if kind == &"final_boss" else kind

func mechanism() -> StringName:
	return &"pattern" if handles(kind) else super.mechanism()

func lesson_state() -> Dictionary:
	var mode := active_pattern()
	var total := 2 if mode == &"pair" else PatternVisual.spans(mode).size()
	return {"pattern": mode, "progress": pair_progress if mode == &"pair" else _cut_count(),
		"total": total, "open": pattern_open or (kind == &"final_boss" and phase == 3), "complete": pattern_open or health <= 0,
		"phase": phase}

func _cut_count() -> int:
	var count := 0
	for i in range(4):
		if link_mask & (1 << i): count += 1
	return count

func is_core_exposed() -> bool:
	return active_pattern() == &"pair" or pattern_open or (kind == &"final_boss" and phase == 3)

func has_cuttable_part() -> bool:
	return health > 0 and active_pattern() in [&"loop", &"zigzag"] and not pattern_open

func attack_radius(_tool: StringName) -> float:
	return 2.85 if active_pattern() == &"loop" else (2.85 if active_pattern() == &"zigzag" else radius)

# Flat pairs of anchors, NOT an implied continuous polyline. Receive_attack tests
# each physical span separately, so empty gaps never become cuttable connections.
func cable_world_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for span: Array in PatternVisual.spans(active_pattern()):
		points.append(_local_part_world(span[0]))
		points.append(_local_part_world(span[1]))
	return points

func core_world_position() -> Vector3:
	if active_pattern() == &"pair" and not pattern_open:
		return valve_world_position(pair_progress)
	return _local_part_world(PatternVisual.core_anchor(kind == &"final_boss"))

func valve_world_position(index: int) -> Vector3:
	return _local_part_world(PatternVisual.valve_anchor(clampi(index, 0, 1), kind == &"final_boss"))

func _build_visuals() -> void:
	if not handles(kind):
		super._build_visuals()
		return
	if is_instance_valid(visual_root): visual_root.queue_free()
	if is_instance_valid(status_root): status_root.queue_free()
	part_visual = null
	warden_visual = null
	body_material = _make_mat(Color("92918b"))
	base_body_color = Color("92918b")
	pattern_visual = PatternVisual.new()
	visual_root = pattern_visual
	add_child(visual_root)
	pattern_visual.build(active_pattern(), kind == &"final_boss")
	status_root = Node3D.new()
	add_child(status_root)
	hp_bar_fill = pattern_visual.box(status_root, Vector3(0, 4.3, 0), Vector3(radius * 2, 0.1, 0.1), Color("67d97e"))
	hp_bar_material = hp_bar_fill.material_override
	feedback_label = Label3D.new()
	feedback_label.position = Vector3(0, 4.8, 0)
	feedback_label.font_size = 28
	feedback_label.pixel_size = 0.012
	feedback_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
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
	return max_health * float(3 - phase) / 4.0 if kind == &"final_boss" else 0.0

func _advance_phase() -> void:
	phase = mini(3, phase + 1)
	_reset_partial()
	pattern_open = phase == 3
	cable_cut = pattern_open
	core_broken = false
	attack_phase = &"recover"
	attack_timer = float(Tuning.PATTERNS.recovery)
	_build_visuals()
	_update_visual_facing()
	_update_health_visuals()

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
	var valve_hit := -1
	if tool == &"beam" and segmented and active_pattern() == &"pair" and not pattern_open:
		for i in range(2):
			if _point_segment_distance(valve_world_position(i), start, finish) <= width + float(Tuning.PATTERNS.target_radius): valve_hit = i
	var core_hit := tool == &"beam" and segmented and _point_segment_distance(core_world_position(), start, finish) <= width + float(Tuning.PATTERNS.target_radius)
	# Preserve exact swept endpoints: a blocked/short segment cannot hit beyond it.
	if not body and cuts == 0 and not core_hit and valve_hit == -1: return miss
	var cue: StringName = &""
	var decisive := false
	var mode := active_pattern()
	if tool == &"ring" and not already and not pattern_open:
		# The baseline weapon's first connected segment carries already_hit=false;
		# all later segments of that launch carry true, including cuts after a body hit.
		# A fresh launch starts a fresh pattern; separate launches cannot accumulate.
		_reset_partial()
	if cuts != 0:
		var previous := link_mask
		link_mask |= cuts
		if link_mask != previous:
			if window_timer <= 0: window_timer = float(Tuning.PATTERNS.window)
			cue = &"link_cut"
		if _cut_count() == PatternVisual.spans(mode).size():
			_open_pattern()
			cue = &"pattern_open"
	if tool == &"beam" and segmented and mode == &"pair" and not pattern_open:
		if valve_hit == pair_progress:
			pair_progress += 1
			if pair_progress == 2:
				_open_pattern()
				cue = &"pattern_open"
				decisive = kind != &"final_boss" # Ordinary Twin Valve: two quick accurate hits.
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
	if kind == &"final_boss" and health > 0:
		while phase < 3 and health <= _phase_floor() + 0.001:
			_advance_phase()
			cue = &"phase_removed"
	result["cue"] = cue
	last_hit_result = result.duplicate()
	if cue != &"" and is_instance_valid(feedback_label):
		feedback_label.text = String(cue).replace("_", " ").to_upper()
		feedback_timer = 0.9
	_update_warden_visuals()
	return result

func step_enemy(world_delta: float, player: Node3D, neighbors: Array = []) -> void:
	if not handles(kind):
		super.step_enemy(world_delta, player, neighbors)
		return
	if health <= 0 or world_delta <= 0: return
	if not pattern_open and window_timer > 0:
		window_timer = maxf(0, window_timer - world_delta)
		if window_timer <= 0: _reset_partial()
	# Base movement/cover/stagger integration is reused. Pattern attacks provide
	# a longer warning, a committed beat, then a generous stationary recovery.
	var before := position
	var locked_facing := facing
	var locked := attack_phase != &"approach"
	super.step_enemy(world_delta, player, neighbors)
	if locked: facing = locked_facing
	var speed := position.distance_to(before) / world_delta
	motion_clock += speed * world_delta * 5.5
	# Only feet/stone body move visually; interactive anchors stay authoritative.
	if is_instance_valid(pattern_visual):
		_update_warden_visuals()
		pattern_visual.pose(motion_clock, speed if attack_phase == &"approach" else 0, attack_phase, attack_timer)

func _step_part_attack(world_delta: float, player: Node3D, distance: float) -> void:
	if not handles(kind):
		super._step_part_attack(world_delta, player, distance)
		return
	var reach := radius + PLAYER_CONTACT_RADIUS + 0.2
	if attack_phase == &"approach":
		if distance <= reach:
			attack_phase = &"windup"
			attack_timer = float(Tuning.PATTERNS.windup)
		return
	attack_timer = maxf(0, attack_timer - world_delta)
	if attack_timer > 0: return
	if attack_phase == &"windup":
		attack_phase = &"commit"
		attack_timer = float(Tuning.PATTERNS.commit)
	elif attack_phase == &"commit":
		if distance <= reach and player.health > 0: player.take_damage(contact_damage)
		attack_phase = &"recover"
		attack_timer = float(Tuning.PATTERNS.recovery)
	else:
		attack_phase = &"approach"

func capture_state() -> Dictionary:
	var state := super.capture_state()
	state.merge({"phase": phase, "link_mask": link_mask, "pair_progress": pair_progress,
		"window_timer": window_timer, "pattern_open": pattern_open, "motion_clock": motion_clock})
	return state

func restore_state(data: Dictionary) -> void:
	phase = clampi(int(data.get("phase", 0)), 0, 3)
	link_mask = int(data.get("link_mask", 0)) & 15
	pair_progress = clampi(int(data.get("pair_progress", 0)), 0, 2)
	window_timer = maxf(0, float(data.get("window_timer", 0)))
	pattern_open = bool(data.get("pattern_open", false))
	motion_clock = float(data.get("motion_clock", 0))
	super.restore_state(data)
	# Same-kind rewind may cross a boss phase; geometry must follow the snapshot.
	if handles(kind):
		_build_visuals()
		_sync_derived_visuals(String(data.get("feedback_text", "")), data.get("feedback_color", Color.WHITE))
