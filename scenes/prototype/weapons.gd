extends Node3D

signal combat_event(kind: StringName, point: Vector3, strength: float)

const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
const Tuning = preload("res://scenes/prototype/tuning.gd")
const EquipmentScript = preload("res://scenes/prototype/equipment.gd")
const CoverScript = preload("res://scenes/prototype/cover.gd")
const Presentation = preload("res://scenes/prototype/weapon_presentation.gd")
var presentation: RefCounted = Presentation.new()
var preview_overlay: Dictionary = {} # Display only; never restores held input.
@export_range(0.0, 1.0) var beam_pierce_threshold := 0.9
var cutter_display_smoothing := true # Visual only; raw samples always drive sweeps.
var beam_flash_charge := 0.0


func presentation_state() -> Dictionary:
	if not preview_overlay.is_empty(): return preview_overlay
	return {"tool": selected_tool,"charging": beam_charging,"charge": beam_charge,
		"ready": beam_charging and beam_charge >= beam_pierce_threshold,
		"air": cone_active,"phase": presentation.phase}

const TOOL_IDS: Array[StringName] = [&"ring", &"beam", &"cone", &"clock"]

var equipment: RefCounted
var cover: RefCounted

var selected_tool: int = 1

# Tool 1 (Ring) state
var ring_drawing: bool = false
var preview_points: Array[Vector3] = []
var preview_length: float = 0.0
var preview_blocked: bool = false
var preview_cutoff_point: Vector3 = Vector3.ZERO
var preview_unblocked_points: Array[Vector3] = []
var preview_blocked_points: Array[Vector3] = []

var ring_phase: String = "idle" # "idle" | "outbound" | "stroke" | "return"
var ring_pos: Vector3 = Vector3.ZERO
var ring_launch_origin: Vector3 = Vector3.ZERO
var ring_points: Array[Vector3] = []
var ring_stroke_index: int = 0
var ring_hit_ids: Dictionary = {}

# Tool 2 (Charged Traveling Flash / Beam) state
var beam_charging: bool = false
var beam_charge_time: float = 0.0
var beam_charge: float = 0.0
var beam_cooldown: float = 0.0
var beam_flash_timer: float = 0.0
var beam_start: Vector3 = Vector3.ZERO
var beam_end: Vector3 = Vector3.ZERO
var beam_visual_origin := Vector3.ZERO
var beam_pulses: Array[Dictionary] = []

# Tool 3 (Cone) state
var cone_active: bool = false
var cone_origin: Vector3 = Vector3.ZERO
var cone_forward: Vector2 = Vector2(0.0, -1.0)
var cone_burst_cooldown: float = 0.0
var _cone_fresh_press: bool = false

# Input & feedback state
var mouse_held: bool = false
var require_fresh_press: bool = false
var last_aim: Vector3 = Vector3(0.0, 0.0, -6.0)
var last_feedback: String = "Ready"

# Visual nodes
var _draw_mesh: ImmediateMesh
var _draw_instance: MeshInstance3D


func _ready() -> void:
	if equipment == null:
		equipment = EquipmentScript.new()
	if cover == null:
		cover = CoverScript.new()
	_setup_visuals()


func _setup_visuals() -> void:
	if _draw_instance != null:
		return
	_draw_mesh = ImmediateMesh.new()
	_draw_instance = MeshInstance3D.new()
	_draw_instance.mesh = _draw_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_draw_instance.material_override = mat
	add_child(_draw_instance)
	presentation.attach(self)


func select_tool(tool_index: int) -> void:
	var target_tool := clampi(tool_index, 1, 4)
	if target_tool == selected_tool:
		return
	var held_before := mouse_held
	cancel_input()
	mouse_held = held_before
	if mouse_held:
		require_fresh_press = true
	selected_tool = target_tool
	last_feedback = "Switched to tool %d" % selected_tool


func handle_event(event: InputEvent, player: Node3D, aim: Vector3) -> void:
	last_aim = aim
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if code == KEY_1:
			select_tool(1)
			return
		elif code == KEY_2:
			select_tool(2)
			return
		elif code == KEY_3:
			select_tool(3)
			return
		elif code == KEY_4:
			select_tool(4)
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_held = true
			require_fresh_press = false
			_on_left_press(player, aim)
		else:
			var was_blocked := require_fresh_press
			mouse_held = false
			require_fresh_press = false
			if not was_blocked:
				_on_left_release(player, aim)
	elif event is InputEventMouseMotion:
		if mouse_held and not require_fresh_press and selected_tool == 1 and ring_drawing:
			_add_ring_sample(aim, player)
		if selected_tool == 3 and cone_active and player != null:
			_update_cone_aim(player.global_position, aim)


func _on_left_press(player: Node3D, aim: Vector3) -> void:
	if player == null:
		return
	match selected_tool:
		1:
			if ring_phase != "idle":
				last_feedback = "Ring in flight"
				return
			if not _can_use_tool(&"ring", 1.0):
				last_feedback = "Ring empty — hold E for Repair"
				return
			ring_drawing = true
			preview_points.clear()
			preview_length = 0.0
			preview_points.append(_clamp_ring_point(aim, player))
			_recompute_ring_preview_split()
			last_feedback = "Drawing ring path"
		2:
			if not _can_use_tool(&"beam", 1.0):
				beam_charging = false
				beam_charge_time = 0.0
				beam_charge = 0.0
				last_feedback = "Flash empty — hold E for Repair"
				return
			if beam_cooldown > 0.0:
				last_feedback = "Flash cooling (%.2fs)" % beam_cooldown
				return
			if beam_pulses.size() >= _beam_max_pulses():
				last_feedback = "Flash max pulses active (%d)" % _beam_max_pulses()
				return
			beam_charging = true
			beam_charge_time = 0.0
			beam_charge = 0.0
			last_feedback = "Charging Flash"
		3:
			if not _can_use_tool(&"cone"):
				cone_active = false
				_cone_fresh_press = false
				last_feedback = "Cone empty — hold E for Repair"
				return
			cone_active = true
			_cone_fresh_press = true
			_update_cone_aim(player.global_position, aim)
			last_feedback = "Cone active"
		4:
			# Clock has no left-click action.
			pass


func _on_left_release(player: Node3D, aim: Vector3) -> void:
	match selected_tool:
		1:
			if not ring_drawing:
				return
			if player != null:
				_add_ring_sample(aim, player)
			ring_drawing = false
			if preview_length < float(Tuning.RING.minimum_length) or preview_points.size() < 2:
				_clear_ring_preview()
				last_feedback = "Stroke too short (<%.1fm)" % float(Tuning.RING.minimum_length)
				return
			if not _can_use_tool(&"ring", 1.0):
				_clear_ring_preview()
				last_feedback = "Ring empty — hold E for Repair"
				return
			_spend_tool(&"ring", 1.0)
			ring_points = preview_points.duplicate()
			_clear_ring_preview()
			ring_phase = "outbound"
			ring_stroke_index = 0
			ring_hit_ids.clear()
			if player != null:
				ring_launch_origin = Vector3(player.global_position.x, 0.0, player.global_position.z)
			else:
				ring_launch_origin = ring_points[0]
			ring_pos = ring_launch_origin
			last_feedback = "Ring launched"
			combat_event.emit(&"ring_launch", Presentation.muzzle(player, 1), 1.0)
		2:
			if not beam_charging:
				return
			var charge_frac := clampf(beam_charge_time / _beam_charge_duration(), 0.0, 1.0)
			beam_charging = false
			beam_charge_time = 0.0
			beam_charge = 0.0
			if player == null:
				return
			if not _can_use_tool(&"beam", 1.0):
				last_feedback = "Flash empty — hold E for Repair"
				return
			if beam_pulses.size() >= _beam_max_pulses():
				last_feedback = "Flash max pulses active (%d)" % _beam_max_pulses()
				return
			_spend_tool(&"beam", 1.0)
			beam_cooldown = _beam_cooldown_duration()
			var dmg := lerpf(_beam_min_damage(), _beam_max_damage(), charge_frac)
			var origin_xz := Vector3(player.global_position.x, 0.0, player.global_position.z)
			var dir := _aim_dir_xz(player.global_position, aim)
			var pulse: Dictionary = {
				"muzzle": Presentation.muzzle(player, 2),
				"pos": origin_xz,
				"dir": dir,
				"speed": _beam_speed(),
				"remaining_range": _beam_max_range(),
				"radius": _beam_radius(),
				"damage": dmg,
				"charge": charge_frac,
				"piercing": charge_frac >= beam_pierce_threshold,
				"hit_ids": [],
			}
			beam_pulses.append(pulse)
			beam_start = origin_xz
			beam_visual_origin = pulse.muzzle
			beam_end = origin_xz + Vector3(dir.x, 0.0, dir.y) * minf(1.5, _beam_max_range())
			beam_flash_timer = 0.14
			beam_flash_charge = charge_frac
			last_feedback = "Piercing flash launched" if pulse.piercing else "Flash launched (%.0f dmg)" % dmg
			combat_event.emit(&"flash_fire", pulse.muzzle, 0.4 + charge_frac * 0.6)
			if pulse.piercing: combat_event.emit(&"flash_pierce", pulse.muzzle, 1.0)
		3:
			if cone_active:
				cone_active = false
				_cone_fresh_press = false
				last_feedback = "Cone released"
		4:
			pass


func step(delta: float, player: Node3D, aim: Vector3, enemies: Array, world_delta: float = -1.0) -> void:
	last_aim = aim
	var w_delta: float = delta if world_delta < 0.0 else world_delta
	presentation.phase = fposmod(presentation.phase + maxf(0,w_delta),1024)

	# Real delta drives cooldowns, Flash charge accumulation, and Ring drawing samples.
	beam_cooldown = maxf(0.0, beam_cooldown - maxf(0.0, delta))
	beam_flash_timer = maxf(0.0, beam_flash_timer - maxf(0.0, delta))

	if selected_tool == 2 and beam_charging and not require_fresh_press:
		if not _can_use_tool(&"beam", 1.0):
			beam_charging = false
			beam_charge_time = 0.0
			beam_charge = 0.0
			last_feedback = "Flash empty — hold E for Repair"
		elif delta > 0.0:
			var was_ready := beam_charge >= beam_pierce_threshold
			beam_charge_time += delta
			beam_charge = clampf(beam_charge_time / _beam_charge_duration(), 0.0, 1.0)
			if beam_charge >= beam_pierce_threshold:
				last_feedback = "PIERCE READY — release to fire"
				if not was_ready: combat_event.emit(&"flash_ready", Presentation.muzzle(player, 2), 1.0)
			else:
				last_feedback = "Charging Flash %.0f%%" % (beam_charge * 100.0)

	if selected_tool == 1 and ring_drawing and player != null and not require_fresh_press:
		_add_ring_sample(aim, player)

	# World delta drives Ring flight, Flash projectile flight, and Cone damage / control pulses.
	if ring_phase != "idle" and player != null and w_delta > 0.0:
		_step_ring(w_delta, player, enemies)

	if not beam_pulses.is_empty() and w_delta > 0.0:
		_step_beam_pulses(w_delta, enemies)

	if selected_tool == 3 and cone_active and player != null and not require_fresh_press:
		_update_cone_aim(player.global_position, aim)
		_step_cone(delta, w_delta, player, enemies)
	elif w_delta > 0.0:
		cone_burst_cooldown = maxf(0.0, cone_burst_cooldown - w_delta)

	if player != null:
		var visual: Variant = player.get("visual")
		if is_instance_valid(visual) and visual.has_method("set_combat_pose"):
			visual.set_combat_pose(beam_flash_timer,cone_active)
	_rebuild_visuals(player, aim)


func cancel_input() -> void:
	ring_drawing = false
	_clear_ring_preview()
	beam_charging = false
	beam_charge_time = 0.0
	beam_charge = 0.0
	cone_active = false
	_cone_fresh_press = false
	if mouse_held:
		require_fresh_press = true
	_rebuild_visuals(null, last_aim)


func reset_state() -> void:
	preview_overlay.clear()
	presentation.reset()
	beam_visual_origin = Vector3.ZERO
	beam_flash_charge = 0.0
	selected_tool = 1
	mouse_held = false
	require_fresh_press = false
	cancel_input()
	ring_phase = "idle"
	ring_pos = Vector3.ZERO
	ring_launch_origin = Vector3.ZERO
	ring_points.clear()
	ring_stroke_index = 0
	ring_hit_ids.clear()
	beam_cooldown = 0.0
	beam_flash_timer = 0.0
	beam_start = Vector3.ZERO
	beam_end = Vector3.ZERO
	beam_pulses.clear()
	cone_burst_cooldown = 0.0
	_cone_fresh_press = false
	last_feedback = "Ready"
	_rebuild_visuals(null, last_aim)


func capture_state() -> Dictionary:
	var pts_copy: Array[Vector3] = []
	for pt in ring_points:
		pts_copy.append(Vector3(pt))
	var hit_ids_copy: Array[int] = []
	for k in ring_hit_ids.keys():
		hit_ids_copy.append(int(k))
	hit_ids_copy.sort()
	var pulses_copy: Array[Dictionary] = []
	for p in beam_pulses:
		var p_dict: Dictionary = p
		pulses_copy.append({
			"muzzle": Vector3(p_dict.get("muzzle",p_dict["pos"])),
			"pos": Vector3(p_dict["pos"]),
			"dir": Vector2(p_dict["dir"]),
			"speed": float(p_dict["speed"]),
			"remaining_range": float(p_dict["remaining_range"]),
			"radius": float(p_dict["radius"]),
			"damage": float(p_dict["damage"]),
			"charge": float(p_dict.get("charge", 0.0)),
			"piercing": bool(p_dict.get("piercing", float(p_dict.get("charge", 0.0)) >= beam_pierce_threshold)),
			"hit_ids": _pulse_hit_ids(p_dict.get("hit_ids", [])),
		})
	return {
		"overlay": {"tool": selected_tool,"charging": beam_charging,"charge": beam_charge,
			"ready": beam_charging and beam_charge >= beam_pierce_threshold,
			"air": cone_active,"phase": presentation.phase},
		"selected_tool": int(selected_tool),
		"ring_phase": String(ring_phase),
		"ring_pos": Vector3(ring_pos),
		"ring_launch_origin": Vector3(ring_launch_origin),
		"ring_points": pts_copy,
		"ring_stroke_index": int(ring_stroke_index),
		"ring_hit_ids": hit_ids_copy,
		"beam_cooldown": float(beam_cooldown),
		"beam_flash_timer": float(beam_flash_timer),
		"beam_start": Vector3(beam_start),
		"beam_end": Vector3(beam_end),
		"beam_visual_origin": beam_visual_origin,
		"beam_flash_charge": beam_flash_charge,
		"beam_pulses": pulses_copy,
		"cone_burst_cooldown": float(cone_burst_cooldown),
		"cone_origin": Vector3(cone_origin),
		"cone_forward": Vector2(cone_forward),
		"last_aim": Vector3(last_aim),
		"last_feedback": String(last_feedback),
	}


func restore_state(data: Dictionary) -> void:
	preview_overlay.clear()
	# Do not restore a held gesture: cancel drawing/charging/cone and require a fresh press.
	ring_drawing = false
	_clear_ring_preview()
	beam_charging = false
	beam_charge_time = 0.0
	beam_charge = 0.0
	cone_active = false
	_cone_fresh_press = false
	require_fresh_press = true

	selected_tool = clampi(int(data.get("selected_tool", 1)), 1, 4)
	ring_phase = String(data.get("ring_phase", "idle"))
	ring_pos = Vector3(data.get("ring_pos", Vector3.ZERO))
	ring_launch_origin = Vector3(data.get("ring_launch_origin", ring_pos))

	ring_points.clear()
	var raw_pts: Variant = data.get("ring_points", [])
	if raw_pts is Array:
		for pt in raw_pts:
			ring_points.append(Vector3(pt))
	ring_stroke_index = int(data.get("ring_stroke_index", 0))

	ring_hit_ids.clear()
	var raw_ids: Variant = data.get("ring_hit_ids", [])
	if raw_ids is Array:
		for id_val in raw_ids:
			ring_hit_ids[int(id_val)] = true

	beam_cooldown = maxf(0.0, float(data.get("beam_cooldown", 0.0)))
	beam_flash_timer = maxf(0.0, float(data.get("beam_flash_timer", 0.0)))
	beam_start = Vector3(data.get("beam_start", Vector3.ZERO))
	beam_end = Vector3(data.get("beam_end", Vector3.ZERO))
	beam_visual_origin = Vector3(data.get("beam_visual_origin", beam_start))
	beam_flash_charge = clampf(float(data.get("beam_flash_charge", 0.0)), 0.0, 1.0)

	beam_pulses.clear()
	var raw_pulses: Variant = data.get("beam_pulses", [])
	if raw_pulses is Array:
		for p in raw_pulses:
			if p is Dictionary:
				var p_dict: Dictionary = p
				beam_pulses.append({
					"muzzle": Vector3(p_dict.get("muzzle",p_dict.get("pos",Vector3.ZERO))),
					"pos": Vector3(p_dict.get("pos", Vector3.ZERO)),
					"dir": Vector2(p_dict.get("dir", Vector2(0.0, -1.0))),
					"speed": float(p_dict.get("speed", _beam_speed())),
					"remaining_range": float(p_dict.get("remaining_range", 0.0)),
					"radius": float(p_dict.get("radius", _beam_radius())),
					"damage": float(p_dict.get("damage", _beam_min_damage())),
					"charge": float(p_dict.get("charge", 0.0)),
					"piercing": bool(p_dict.get("piercing", float(p_dict.get("charge", 0.0)) >= beam_pierce_threshold)),
					"hit_ids": _pulse_hit_ids(p_dict.get("hit_ids", [])),
				})

	cone_burst_cooldown = maxf(0.0, float(data.get("cone_burst_cooldown", 0.0)))
	cone_origin = Vector3(data.get("cone_origin", Vector3.ZERO))
	cone_forward = Vector2(data.get("cone_forward", Vector2(0.0, -1.0)))
	last_aim = Vector3(data.get("last_aim", Vector3(0.0, 0.0, -6.0)))
	last_feedback = String(data.get("last_feedback", "Ready"))

	_rebuild_visuals(null, last_aim)


func status_text() -> String:
	var names := {1: "1:Ring", 2: "2:Flash", 3: "3:Cone", 4: "4:Clock"}
	var rem_len := maxf(0.0, float(Tuning.RING.length) - preview_length)
	var ring_info := "idle"
	if ring_drawing:
		ring_info = "draw %.1f/%.1fm (rem %.1fm)%s" % [
			preview_length, float(Tuning.RING.length), rem_len,
			" BLOCKED" if preview_blocked else ""
		]
	elif ring_phase != "idle":
		ring_info = ring_phase
	elif not _can_use_tool(&"ring", 1.0):
		ring_info = "REPAIR(E)"
	var flash_info := "ready"
	if not _can_use_tool(&"beam", 1.0):
		flash_info = "REPAIR(E)"
	elif beam_charging:
		flash_info = "charge %.0f%%" % (beam_charge * 100.0)
	elif beam_cooldown > 0.0:
		flash_info = "%.2fs" % beam_cooldown
	elif not beam_pulses.is_empty():
		flash_info = "%d active" % beam_pulses.size()
	var cone_info := "idle"
	if not _can_use_tool(&"cone"):
		cone_info = "REPAIR(E)"
	elif cone_active:
		cone_info = "HOLD"
	elif cone_burst_cooldown > 0.0:
		cone_info = "pulse %.1fs" % cone_burst_cooldown
	return "Tool [%s] | Ring: %s | Flash: %s | Cone: %s\n%s" % [
		names.get(selected_tool, "1:Ring"), ring_info, flash_info, cone_info, last_feedback
	]


# --- Tuning Helpers with Round D Defaults ---

func _ring_arc_height() -> float:
	return float(Tuning.RING.get("arc_height", 3.2))


func _beam_min_damage() -> float:
	return float(Tuning.BEAM.get("min_damage", 30.0))


func _beam_max_damage() -> float:
	return float(Tuning.BEAM.get("max_damage", 100.0))


func _beam_charge_duration() -> float:
	return maxf(0.05, float(Tuning.BEAM.get("charge_time", 0.9)))


func _beam_speed() -> float:
	return float(Tuning.BEAM.get("speed", 42.0))


func _beam_max_range() -> float:
	if Tuning.BEAM.has("charge_time") or float(Tuning.BEAM.get("range", 35.0)) > 20.0:
		return float(Tuning.BEAM.get("range", 35.0))
	return float(Tuning.BEAM.get("pulse_range", 35.0))


func _beam_radius() -> float:
	return float(Tuning.BEAM.get("radius", 0.35))


func _beam_cooldown_duration() -> float:
	if Tuning.BEAM.has("pulse_cooldown"):
		return float(Tuning.BEAM.get("pulse_cooldown", 0.25))
	if Tuning.BEAM.has("charge_time"):
		return float(Tuning.BEAM.get("cooldown", 0.25))
	return minf(0.25, float(Tuning.BEAM.get("cooldown", 0.25)))


func _beam_max_pulses() -> int:
	return int(Tuning.BEAM.get("max_pulses", 8))


func _cone_pulse_interval() -> float:
	if Tuning.CONTROL.has("pulse_interval"):
		return float(Tuning.CONTROL.get("pulse_interval", 1.2))
	var bi := float(Tuning.CONTROL.get("burst_interval", 1.2))
	return bi if not is_equal_approx(bi, 1.5) else 1.2


func _cone_pulse_cost() -> float:
	return float(Tuning.CONTROL.get("pulse_cost", Tuning.CONTROL.get("burst_cost", 1.5)))


func _cone_pulse_impulse() -> float:
	if Tuning.CONTROL.has("pulse_impulse"):
		return float(Tuning.CONTROL.get("pulse_impulse", 22.0))
	var imp := float(Tuning.CONTROL.get("impulse", 22.0))
	return imp if not is_equal_approx(imp, 13.0) else 22.0


func _cone_pulse_stagger() -> float:
	if Tuning.CONTROL.has("pulse_stagger"):
		return float(Tuning.CONTROL.get("pulse_stagger", 0.85))
	var stg := float(Tuning.CONTROL.get("stagger", 0.85))
	return stg if not is_equal_approx(stg, 0.65) else 0.85


func _can_use_tool(tool: StringName, amount: float = 0.000001) -> bool:
	if equipment == null:
		return true
	return bool(equipment.can_use(tool, amount))


func _spend_tool(tool: StringName, amount: float) -> float:
	if equipment == null:
		return amount
	return float(equipment.spend(tool, amount))


func _enemy_combat_id(enemy_node: Node3D) -> int:
	if enemy_node.has_method("combat_id"):
		var cid: int = int(enemy_node.call("combat_id"))
		if cid > 0:
			return cid
	var prop_id: Variant = enemy_node.get("rewind_id")
	if prop_id != null and int(prop_id) > 0:
		return int(prop_id)
	return enemy_node.get_instance_id()


# --- Tool 1: Ring Helpers ---

func _clear_ring_preview() -> void:
	preview_points.clear()
	preview_length = 0.0
	preview_blocked = false
	preview_cutoff_point = Vector3.ZERO
	preview_unblocked_points.clear()
	preview_blocked_points.clear()


func _clamp_ring_point(raw_aim: Vector3, player: Node3D) -> Vector3:
	var half := float(Tuning.ARENA_HALF_SIZE)
	var p := Vector2(clampf(raw_aim.x, -half, half), clampf(raw_aim.z, -half, half))
	if player != null:
		var origin := Vector2(player.global_position.x, player.global_position.z)
		var offset := p - origin
		var max_r := float(Tuning.RING.range)
		if offset.length() > max_r:
			p = origin + offset.normalized() * max_r
			p.x = clampf(p.x, -half, half)
			p.y = clampf(p.y, -half, half)
	return Vector3(p.x, 0.0, p.y)


func _add_ring_sample(raw_aim: Vector3, player: Node3D) -> void:
	if not ring_drawing or preview_points.is_empty():
		return
	var max_len := float(Tuning.RING.length)
	if preview_length >= max_len - 1e-5:
		return
	var clamped := _clamp_ring_point(raw_aim, player)
	var last: Vector3 = preview_points[-1]
	var seg := Vector2(clamped.x - last.x, clamped.z - last.z)
	var dist := seg.length()
	var spacing := float(Tuning.RING.sample_spacing)
	if dist < spacing:
		return
	var dir := seg / dist
	var cursor := Vector2(last.x, last.z)
	var left_to_walk := dist
	while left_to_walk >= spacing and preview_length < max_len - 1e-5:
		var step_len := minf(spacing, max_len - preview_length)
		if left_to_walk < spacing * 1.5:
			step_len = minf(left_to_walk, max_len - preview_length)
		cursor += dir * step_len
		preview_points.append(Vector3(cursor.x, 0.0, cursor.y))
		preview_length += step_len
		left_to_walk -= step_len
		if step_len < spacing:
			break
	_recompute_ring_preview_split()


func _recompute_ring_preview_split() -> void:
	preview_blocked = false
	preview_cutoff_point = Vector3.ZERO
	preview_unblocked_points.clear()
	preview_blocked_points.clear()
	if preview_points.is_empty():
		return
	var r_ring := float(Tuning.RING.radius)
	preview_unblocked_points.append(preview_points[0])
	if cover != null and preview_points.size() == 1:
		var init_clip: Dictionary = cover.clip_segment(preview_points[0], preview_points[0], r_ring)
		if bool(init_clip["blocked"]):
			preview_blocked = true
			preview_cutoff_point = preview_points[0]
			preview_blocked_points.append(preview_points[0])
			return
	for i in range(preview_points.size() - 1):
		var a: Vector3 = preview_points[i]
		var b: Vector3 = preview_points[i + 1]
		if not preview_blocked:
			if cover != null:
				var clip: Dictionary = cover.clip_segment(a, b, r_ring)
				if bool(clip["blocked"]):
					preview_blocked = true
					var cpos: Vector3 = clip["position"]
					preview_cutoff_point = Vector3(cpos.x, 0.0, cpos.z)
					if preview_unblocked_points[-1].distance_to(preview_cutoff_point) > 1e-5:
						preview_unblocked_points.append(preview_cutoff_point)
					preview_blocked_points.append(preview_cutoff_point)
					if preview_cutoff_point.distance_to(b) > 1e-5:
						preview_blocked_points.append(b)
					continue
			preview_unblocked_points.append(b)
		else:
			preview_blocked_points.append(b)


func _step_ring(w_delta: float, player: Node3D, enemies: Array) -> void:
	var time_left := w_delta
	var guard := 0
	var r_ring := float(Tuning.RING.radius)
	var arc_peak := _ring_arc_height()
	while time_left > 1e-6 and ring_phase != "idle" and guard < 256:
		guard += 1
		if ring_phase == "outbound":
			if ring_points.is_empty():
				ring_phase = "idle"
				break
			var target: Vector3 = ring_points[0]
			var cur_xz := Vector2(ring_pos.x, ring_pos.z)
			var target_xz := Vector2(target.x, target.z)
			var to_t := target_xz - cur_xz
			var dist := to_t.length()
			var speed := float(Tuning.RING.outbound_speed)
			var step_d := speed * time_left
			var start_xz := Vector2(ring_launch_origin.x, ring_launch_origin.z)
			var total_out_dist := start_xz.distance_to(target_xz)
			if dist <= step_d + 1e-5:
				ring_pos = Vector3(target.x, 0.0, target.z)
				time_left -= (dist / speed) if speed > 0.0 else time_left
				ring_phase = "stroke"
				ring_stroke_index = 0
			else:
				var next_xz := cur_xz + (to_t / dist) * step_d
				var u := clampf(start_xz.distance_to(next_xz) / total_out_dist, 0.0, 1.0) if total_out_dist > 1e-5 else 1.0
				var arc_y := 4.0 * arc_peak * u * (1.0 - u)
				ring_pos = Vector3(next_xz.x, arc_y, next_xz.y)
				time_left = 0.0
		elif ring_phase == "stroke":
			if ring_stroke_index >= ring_points.size() - 1:
				ring_pos.y = 0.0
				ring_phase = "return"
				continue
			var seg_target: Vector3 = ring_points[ring_stroke_index + 1]
			var prev := Vector3(ring_pos.x, 0.0, ring_pos.z)
			var to_s := Vector2(seg_target.x - prev.x, seg_target.z - prev.z)
			var dist := to_s.length()
			var speed := float(Tuning.RING.stroke_speed)
			var step_d := speed * time_left
			var reaching_waypoint := dist <= step_d + 1e-5
			var intended_end: Vector3
			var intended_dist: float
			if reaching_waypoint:
				intended_end = Vector3(seg_target.x, 0.0, seg_target.z)
				intended_dist = dist
			else:
				var move := (to_s / dist) * step_d
				intended_end = prev + Vector3(move.x, 0.0, move.y)
				intended_dist = step_d
			if cover != null:
				var clip: Dictionary = cover.clip_segment(prev, intended_end, r_ring)
				if bool(clip["blocked"]):
					var frac: float = float(clip["fraction"])
					var clip_pos: Vector3 = clip["position"]
					var reached_end := Vector3(clip_pos.x, 0.0, clip_pos.z)
					ring_pos = reached_end
					time_left -= ((intended_dist * frac) / speed) if speed > 0.0 else time_left
					if frac > 0.0 and prev.distance_to(reached_end) > 1e-6:
						_sweep_ring_segment(prev, reached_end, enemies)
					ring_phase = "return"
					if not last_feedback.begins_with("Ring hit"):
						last_feedback = "Ring stopped by cover"
					continue
			ring_pos = intended_end
			if reaching_waypoint:
				time_left -= (dist / speed) if speed > 0.0 else time_left
				_sweep_ring_segment(prev, ring_pos, enemies)
				ring_stroke_index += 1
				if ring_stroke_index >= ring_points.size() - 1:
					ring_phase = "return"
			else:
				time_left = 0.0
				_sweep_ring_segment(prev, ring_pos, enemies)
		elif ring_phase == "return":
			# Returning ring homes directly back to the current player harmlessly.
			var home := Vector3(player.global_position.x, 0.0, player.global_position.z)
			var to_h := Vector2(home.x - ring_pos.x, home.z - ring_pos.z)
			var dist := to_h.length()
			var speed := float(Tuning.RING.return_speed)
			var step_d := speed * time_left
			if dist <= step_d + 1e-5:
				ring_pos = home
				time_left = 0.0
				ring_phase = "idle"
				ring_points.clear()
				ring_hit_ids.clear()
				last_feedback = "Ring returned"
				combat_event.emit(&"ring_return", home, 0.5)
			else:
				var move := (to_h / dist) * step_d
				ring_pos = Vector3(ring_pos.x + move.x, 0.0, ring_pos.z + move.y)
				time_left = 0.0


func _sweep_ring_segment(seg_start: Vector3, seg_end: Vector3, enemies: Array) -> void:
	var a := Vector2(seg_start.x, seg_start.z)
	var b := Vector2(seg_end.x, seg_end.z)
	var d := b - a
	var r_ring := float(Tuning.RING.radius)
	var hits_along_segment: Array[Dictionary] = []

	for enemy in enemies:
		if not _is_live_enemy(enemy):
			continue
		var enemy_node := enemy as Node3D
		var id: int = _enemy_combat_id(enemy_node)
		if ring_hit_ids.has(id) and not enemy_node.has_method("lesson_state") and not (enemy_node.has_method("has_cuttable_part") and enemy_node.call("has_cuttable_part")):
			continue
		var c := Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		var r_enemy: float = float(enemy_node.get("radius"))
		var broad_radius: float = float(enemy_node.call("attack_radius", &"ring")) if enemy_node.has_method("attack_radius") else r_enemy
		var entry_t := _swept_circle_entry_t(a, b, c, r_ring + broad_radius)
		if entry_t < 0.0:
			continue
		var ring_center := a + d * entry_t
		var from_enemy := ring_center - c
		var dir: Vector2
		if from_enemy.length_squared() > 1e-6:
			dir = from_enemy.normalized()
		elif d.length_squared() > 1e-6:
			dir = -d.normalized()
		else:
			dir = Vector2(0.0, 1.0)
		var contact_xz := c + dir * r_enemy
		var contact_world := Vector3(contact_xz.x, 0.0, contact_xz.y)
		var ring_world := Vector3(ring_center.x, 0.0, ring_center.y)
		var enemy_world := Vector3(c.x, 0.0, c.y)
		if cover != null:
			var los: Dictionary = cover.clip_segment(ring_world, enemy_world, 0.0)
			if bool(los["blocked"]):
				continue
		hits_along_segment.append({
			"t": entry_t,
			"enemy": enemy_node,
			"id": id,
			"contact": contact_world
		})

	hits_along_segment.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["t"]) < float(y["t"]))
	for item in hits_along_segment:
		var enemy_node: Node3D = item["enemy"]
		var id: int = item["id"]
		if not _is_live_enemy(enemy_node):
			continue
		var res := _attack_enemy(enemy_node, &"ring", Tuning.RING.damage, item["contact"],
			{"segment_start": seg_start, "segment_end": seg_end, "radius": r_ring, "already_hit": ring_hit_ids.has(id)})
		if bool(res.get("connected", true)):
			ring_hit_ids[id] = true
			_record_hit_feedback("Ring", res)


# --- Tool 2: Charged Traveling Flash Pulses ---

# Value-only stable IDs, never object IDs in stored pulses when combat_id exists.
func _pulse_hit_ids(raw: Variant) -> Array[int]:
	var result: Array[int] = []
	if raw is Array:
		for id in raw:
			if int(id) > 0 and not result.has(int(id)): result.append(int(id))
	result.sort()
	return result


func _step_beam_pulses(w_delta: float, enemies: Array) -> void:
	if w_delta <= 0.0 or beam_pulses.is_empty(): return
	var surviving: Array[Dictionary] = []
	for pulse: Dictionary in beam_pulses:
		var start: Vector3 = pulse.pos
		var direction: Vector2 = pulse.dir
		var remaining := float(pulse.remaining_range)
		var distance := minf(remaining, float(pulse.speed) * w_delta)
		if distance <= 0.00001: continue
		var raw_end := start + Vector3(direction.x, 0, direction.y) * distance
		var end := raw_end
		var blocked := false
		if cover != null:
			var clip: Dictionary = cover.clip_segment(start, raw_end)
			blocked = clip.blocked
			end = clip.position
		var a := Vector2(start.x, start.z)
		var b := Vector2(end.x, end.z)
		var hit_ids := _pulse_hit_ids(pulse.get("hit_ids", []))
		var piercing := bool(pulse.get("piercing", float(pulse.get("charge", 0)) >= beam_pierce_threshold))
		var hits: Array[Dictionary] = []
		for enemy in enemies:
			if not _is_live_enemy(enemy): continue
			var node := enemy as Node3D
			var id := _enemy_combat_id(node)
			if hit_ids.has(id): continue
			var center := Vector2(node.global_position.x, node.global_position.z)
			var radius := float(node.get("radius"))
			var t := _swept_circle_entry_t(a, b, center, float(pulse.radius) + radius)
			if t < 0.0: continue
			var toward := a.lerp(b, t) - center
			var normal := toward.normalized() if toward.length_squared() > 0.000001 else -direction
			var contact := center + normal * radius
			var contact3 := Vector3(contact.x, 0, contact.y)
			# A wide pulse touching an edge must never hit through solid cover.
			if cover != null and (cover.clip_segment(start, node.global_position).blocked or cover.clip_segment(start, contact3).blocked): continue
			hits.append({"t": t, "node": node, "id": id, "contact": contact3})
		hits.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return float(x.t) < float(y.t) if not is_equal_approx(float(x.t), float(y.t)) else int(x.id) < int(y.id))
		beam_start = start
		beam_visual_origin = pulse.get("muzzle", start)
		beam_flash_charge = float(pulse.get("charge", 0))
		var consumed := false
		for hit: Dictionary in hits:
			if not _is_live_enemy(hit.node): continue
			# The authoritative swept segment is clipped at the wall, with no
			# target search beyond this straight pulse or bonus chain targeting.
			var result := _attack_enemy(hit.node, &"beam", float(pulse.damage), hit.contact,
				{"segment_start": start, "segment_end": end, "radius": float(pulse.radius),
				"charge": float(pulse.get("charge", 0)), "piercing": piercing})
			hit_ids.append(int(hit.id))
			beam_flash_timer = 0.14
			_record_hit_feedback("Piercing flash" if piercing else "Flash", result)
			if not piercing:
				end = hit.contact
				consumed = true
				break
		beam_end = end
		if blocked:
			beam_flash_timer = 0.14
			last_feedback = "Flash stopped by cover"
		if consumed or blocked: continue
		pulse.pos = raw_end
		pulse.remaining_range = maxf(0, remaining - distance)
		pulse.hit_ids = hit_ids
		pulse.piercing = piercing
		if pulse.remaining_range > 0.00001: surviving.append(pulse)
	beam_pulses = surviving


# --- Tool 3: Cone Repeating Pulses & Edge-Volume Sector ---

func _update_cone_aim(origin_world: Vector3, aim_world: Vector3) -> void:
	cone_origin = Vector3(origin_world.x, 0.0, origin_world.z)
	cone_forward = _aim_dir_xz(origin_world, aim_world)


func _step_cone(delta: float, w_delta: float, player: Node3D, enemies: Array) -> void:
	if delta <= 0.0:
		return
	if not _can_use_tool(&"cone"):
		cone_active = false
		_cone_fresh_press = false
		if w_delta > 0.0:
			cone_burst_cooldown = maxf(0.0, cone_burst_cooldown - w_delta)
		last_feedback = "Cone empty — hold E for Repair"
		return

	# Continuous wear uses REAL delta; continuous damage & pulse cadence use WORLD delta.
	var actual_real_dt := _spend_tool(&"cone", delta)
	if actual_real_dt <= 0.0:
		cone_active = false
		_cone_fresh_press = false
		if w_delta > 0.0:
			cone_burst_cooldown = maxf(0.0, cone_burst_cooldown - w_delta)
		last_feedback = "Cone empty — hold E for Repair"
		return

	var afford_fraction := clampf(actual_real_dt / delta, 0.0, 1.0)
	var actual_world_dt := maxf(0.0, w_delta) * afford_fraction

	var do_burst := false
	var burst_scale := 0.0
	var pulse_interval := _cone_pulse_interval()
	var pulse_cost := _cone_pulse_cost()

	if _cone_fresh_press:
		_cone_fresh_press = false
		if cone_burst_cooldown <= 1e-6 and w_delta > 0.0:
			var pulse_spent := _spend_tool(&"cone", pulse_cost)
			if pulse_spent > 1e-6:
				do_burst = true
				burst_scale = clampf(pulse_spent / pulse_cost, 0.0, 1.0)
				cone_burst_cooldown = maxf(0.0, pulse_interval - actual_world_dt)
		else:
			cone_burst_cooldown -= actual_world_dt
			if cone_burst_cooldown <= 1e-6 and w_delta > 0.0:
				var pulse_spent := _spend_tool(&"cone", pulse_cost)
				if pulse_spent > 1e-6:
					do_burst = true
					burst_scale = clampf(pulse_spent / pulse_cost, 0.0, 1.0)
					cone_burst_cooldown = maxf(0.0, cone_burst_cooldown + pulse_interval)
				else:
					cone_burst_cooldown = 0.0
	else:
		cone_burst_cooldown -= actual_world_dt
		if cone_burst_cooldown <= 1e-6 and w_delta > 0.0:
			var pulse_spent := _spend_tool(&"cone", pulse_cost)
			if pulse_spent > 1e-6:
				do_burst = true
				burst_scale = clampf(pulse_spent / pulse_cost, 0.0, 1.0)
				cone_burst_cooldown = maxf(0.0, cone_burst_cooldown + pulse_interval)
			else:
				cone_burst_cooldown = 0.0

	if do_burst:
		combat_event.emit(&"cone_pulse", Presentation.muzzle(player, 3), burst_scale)
	var p_xz := Vector2(player.global_position.x, player.global_position.z)
	var origin_3d := Vector3(p_xz.x, 0.0, p_xz.y)
	var max_r := float(Tuning.CONE.range)
	var half_ang := float(Tuning.CONE.half_angle)
	var amount := float(Tuning.CONE.damage_per_second) * actual_world_dt
	var burst_impulse := _cone_pulse_impulse() * burst_scale
	var burst_stagger := _cone_pulse_stagger() * burst_scale
	var sustained_impulse := float(Tuning.CONTROL.get("sustained_push", 5.0)) * actual_world_dt
	var hit_any := false
	var any_armored := false
	var total_dealt := 0.0

	for enemy in enemies:
		if not _is_live_enemy(enemy):
			continue
		var enemy_node := enemy as Node3D
		var c := Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		var r_enemy: float = float(enemy_node.get("radius"))
		var to_enemy := c - p_xz
		var dist := to_enemy.length()
		if dist - r_enemy > max_r:
			continue
		if dist > 1e-5:
			var ang := absf(cone_forward.angle_to(to_enemy))
			var edge_allowance: float = asin(clampf(r_enemy / dist, 0.0, 1.0)) if dist > r_enemy else PI
			if ang > half_ang + edge_allowance:
				continue
		var dir_from_enemy := (p_xz - c).normalized() if dist > 1e-5 else -cone_forward
		var contact_xz := c + dir_from_enemy * r_enemy
		var contact_world := Vector3(contact_xz.x, 0.0, contact_xz.y)
		var enemy_world := Vector3(c.x, 0.0, c.y)
		if cover != null:
			var los: Dictionary = cover.clip_segment(origin_3d, enemy_world, 0.0)
			if bool(los["blocked"]):
				continue

		var push_2d := to_enemy.normalized() if dist > 1e-5 else cone_forward
		var push_dir := Vector3(push_2d.x, 0.0, push_2d.y)
		if do_burst and burst_impulse > 0.0:
			enemy_node.call("apply_control", push_dir, burst_impulse, burst_stagger)
		elif sustained_impulse > 0.0:
			enemy_node.call("apply_control", push_dir, sustained_impulse, 0.0)

		if amount > 0.0:
			var res := _attack_enemy(enemy_node, &"cone", amount, contact_world,
				{"segment_start": origin_3d, "segment_end": enemy_world, "radius": 0.0, "dt": actual_world_dt})
			var dealt := float(res.get("dealt", 0.0))
			if dealt > 0.0:
				hit_any = true
				total_dealt += dealt
				if bool(res.get("armored", false)):
					any_armored = true

	if hit_any:
		var burst_tag := " PULSE" if do_burst else ""
		var armor_tag := " (ARMORED)" if any_armored else ""
		last_feedback = "Cone%s %.1f dmg%s" % [burst_tag, total_dealt, armor_tag]
	elif do_burst:
		last_feedback = "Cone pulse"

	if not _can_use_tool(&"cone"):
		cone_active = false
		if not hit_any:
			last_feedback = "Cone empty — hold E for Repair"


func _attack_enemy(enemy: Node3D, tool: StringName, amount: float, contact: Vector3, context: Dictionary) -> Dictionary:
	var result: Dictionary = enemy.call("receive_attack", tool, amount, contact, context) if enemy.has_method("receive_attack") else enemy.call("hit", amount, contact)
	var cue := StringName(result.get("cue", &""))
	if not cue.is_empty():
		combat_event.emit(cue, contact, 1.0)
	elif float(result.get("dealt", 0.0)) > 0.0:
		combat_event.emit(&"hit", contact, clampf(float(result.dealt) / 80.0, 0.15, 1.2))
	return result


func _record_hit_feedback(tool_label: String, res: Dictionary) -> void:
	var dealt := float(res.get("dealt", 0.0))
	var armored := bool(res.get("armored", false))
	var killed := bool(res.get("killed", false))
	var tags := ""
	if armored:
		tags += " ARMORED"
	if killed:
		tags += " KILLED"
	last_feedback = "%s hit %.1f dmg%s" % [tool_label, dealt, tags]


func _is_live_enemy(enemy: Variant) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if float(enemy.get("health")) <= 0.0:
		return false
	return true


func _aim_dir_xz(origin_world: Vector3, aim_world: Vector3) -> Vector2:
	var d := Vector2(aim_world.x - origin_world.x, aim_world.z - origin_world.z)
	if d.length_squared() > 1e-6:
		return d.normalized()
	return Vector2(0.0, -1.0)


func _swept_circle_entry_t(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var f := a - center
	var r_sq := radius * radius
	if f.length_squared() <= r_sq:
		return 0.0
	var d := b - a
	var a_coef := d.length_squared()
	if a_coef <= 1e-10:
		return -1.0
	var b_coef := 2.0 * f.dot(d)
	var c_coef := f.length_squared() - r_sq
	var disc := b_coef * b_coef - 4.0 * a_coef * c_coef
	if disc < 0.0:
		return -1.0
	var root := sqrt(disc)
	var t1 := (-b_coef - root) / (2.0 * a_coef)
	var t2 := (-b_coef + root) / (2.0 * a_coef)
	if t1 >= 0.0 and t1 <= 1.0:
		return t1
	if t1 < 0.0 and t2 >= 0.0:
		return 0.0
	return -1.0


# --- Visuals ---

func _rebuild_visuals(player: Node3D, aim: Vector3) -> void:
	if _draw_mesh == null:
		return
	_draw_mesh.clear_surfaces()
	presentation.rebuild(self,player,aim)

	if ring_drawing and preview_points.size() >= 1:
		if player != null:
			var p_ground := Vector3(player.global_position.x, 0.06, player.global_position.z)
			_draw_circle_outline(p_ground, float(Tuning.RING.range), Color(0.4, 0.78, 0.96, 0.22))
			_draw_arc_ribbon(p_ground, preview_points[0], _ring_arc_height(), 0.07, Color(0.55, 0.85, 1.0, 0.45))
		if preview_unblocked_points.size() >= 2:
			_draw_stroke_ribbon(preview_unblocked_points, 0, preview_unblocked_points.size() - 1, 0.12, ToolStyle.RING, 0.10)
		if preview_blocked:
			_draw_circle_outline(Vector3(preview_cutoff_point.x, 0.16, preview_cutoff_point.z), float(Tuning.RING.radius), Color("ff5c4d"))
			if preview_blocked_points.size() >= 2:
				_draw_stroke_ribbon(preview_blocked_points, 0, preview_blocked_points.size() - 1, 0.09, Color(0.95, 0.34, 0.28, 0.45), 0.08)

	if ring_phase != "idle" and ring_points.size() >= 2:
		if ring_phase == "outbound":
			_draw_arc_ribbon(ring_launch_origin, ring_points[0], _ring_arc_height(), 0.08, Color(0.55, 0.85, 1.0, 0.55))
			_draw_circle_outline(Vector3(ring_pos.x, 0.08, ring_pos.z), float(Tuning.RING.radius) * 0.75, Color(0.2, 0.35, 0.45, 0.35))
		if ring_stroke_index > 0:
			_draw_stroke_ribbon(ring_points, 0, ring_stroke_index, 0.10, Color("4b8a63"), 0.08)
		if ring_stroke_index < ring_points.size() - 1:
			_draw_stroke_ribbon(ring_points, ring_stroke_index, ring_points.size() - 1, 0.14, Color(ToolStyle.RING, 0.45), 0.11)
		var ring_col := ToolStyle.RING.lightened(0.25) if ring_phase == "stroke" else ToolStyle.RING
		var ring_y := maxf(0.22, ring_pos.y + 0.22) if ring_phase == "outbound" else 0.22
		_draw_circle_outline(Vector3(ring_pos.x, ring_y, ring_pos.z), float(Tuning.RING.radius), ring_col)

	var overlay := presentation_state()
	if int(overlay.tool) == 3 and bool(overlay.air) and player != null:
		# A faint floor footprint retains range information; moving air is drawn
		# separately from the real nozzle by WeaponPresentation.
		_draw_cone_sector(Vector3(player.global_position.x,.08,player.global_position.z), cone_forward,
			float(Tuning.CONE.range),float(Tuning.CONE.half_angle),Color(1,.58,.22,.055))


func _draw_arc_ribbon(start_pos: Vector3, end_pos: Vector3, peak_height: float, half_width: float, col: Color) -> void:
	var steps := 16
	var diff_xz := Vector2(end_pos.x - start_pos.x, end_pos.z - start_pos.z)
	if diff_xz.length_squared() <= 1e-6:
		return
	var n := Vector2(-diff_xz.y, diff_xz.x).normalized() * half_width
	_draw_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(steps):
		var u0 := float(i) / float(steps)
		var u1 := float(i + 1) / float(steps)
		var c0 := start_pos.lerp(end_pos, u0)
		var c1 := start_pos.lerp(end_pos, u1)
		c0.y = 0.12 + 4.0 * peak_height * u0 * (1.0 - u0)
		c1.y = 0.12 + 4.0 * peak_height * u1 * (1.0 - u1)
		var p1 := Vector3(c0.x + n.x, c0.y, c0.z + n.y)
		var p2 := Vector3(c0.x - n.x, c0.y, c0.z - n.y)
		var p3 := Vector3(c1.x + n.x, c1.y, c1.z + n.y)
		var p4 := Vector3(c1.x - n.x, c1.y, c1.z - n.y)
		_draw_mesh.surface_set_color(col)
		_draw_mesh.surface_add_vertex(p1)
		_draw_mesh.surface_add_vertex(p2)
		_draw_mesh.surface_add_vertex(p3)
		_draw_mesh.surface_add_vertex(p2)
		_draw_mesh.surface_add_vertex(p4)
		_draw_mesh.surface_add_vertex(p3)
	_draw_mesh.surface_end()


func display_stroke(points: Array[Vector3]) -> Array[Vector3]:
	return Presentation.stroke_display(points, cover) if cutter_display_smoothing else points.duplicate()


func _draw_stroke_ribbon(points: Array[Vector3], start: int, end: int, width: float, color: Color, height: float) -> void:
	if end <= start: return
	var raw: Array[Vector3] = []
	raw.assign(points.slice(start, end + 1))
	# Anchor the active ring head; only the rendered, untraveled guide changes.
	if points == ring_points and ring_phase == "stroke":
		if end == ring_stroke_index: raw.append(ring_pos)
		elif start == ring_stroke_index: raw[0] = ring_pos
	var shown := display_stroke(raw)
	_draw_polyline_ribbon(shown, 0, shown.size() - 1, width, color, height)


func _draw_polyline_ribbon(pts: Array[Vector3], start_idx: int, end_idx: int, half_width: float, col: Color, y_height: float) -> void:
	if end_idx <= start_idx or start_idx < 0 or end_idx >= pts.size():
		return
	_draw_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(start_idx, end_idx):
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var seg := b - a
		if seg.length_squared() <= 1e-6:
			continue
		var n := Vector2(-seg.y, seg.x).normalized() * half_width
		var p1 := Vector3(a.x + n.x, y_height, a.y + n.y)
		var p2 := Vector3(a.x - n.x, y_height, a.y - n.y)
		var p3 := Vector3(b.x + n.x, y_height, b.y + n.y)
		var p4 := Vector3(b.x - n.x, y_height, b.y - n.y)
		_draw_mesh.surface_set_color(col)
		_draw_mesh.surface_add_vertex(p1)
		_draw_mesh.surface_add_vertex(p2)
		_draw_mesh.surface_add_vertex(p3)
		_draw_mesh.surface_add_vertex(p2)
		_draw_mesh.surface_add_vertex(p4)
		_draw_mesh.surface_add_vertex(p3)
	_draw_mesh.surface_end()


func _draw_circle_outline(center: Vector3, radius: float, col: Color) -> void:
	var steps := 24
	var ring_pts: Array[Vector3] = []
	for i in range(steps + 1):
		var ang := TAU * float(i) / float(steps)
		ring_pts.append(Vector3(center.x + cos(ang) * radius, center.y, center.z + sin(ang) * radius))
	_draw_polyline_ribbon(ring_pts, 0, ring_pts.size() - 1, 0.05, col, center.y)


func _draw_cone_sector(origin: Vector3, forward_xz: Vector2, max_range: float, half_angle: float, col: Color) -> void:
	var steps := 18
	var base_ang := atan2(forward_xz.y, forward_xz.x)
	_draw_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(steps):
		var a0 := base_ang - half_angle + (2.0 * half_angle) * float(i) / float(steps)
		var a1 := base_ang - half_angle + (2.0 * half_angle) * float(i + 1) / float(steps)
		var p1 := Vector3(origin.x + cos(a0) * max_range, origin.y, origin.z + sin(a0) * max_range)
		var p2 := Vector3(origin.x + cos(a1) * max_range, origin.y, origin.z + sin(a1) * max_range)
		parent_cone_vertex(origin, p1, p2, col)
	_draw_mesh.surface_end()


func parent_cone_vertex(origin: Vector3, p1: Vector3, p2: Vector3, col: Color) -> void:
	var end1 := p1
	var end2 := p2
	if cover != null:
		var c1: Dictionary = cover.clip_segment(Vector3(origin.x, 0.0, origin.z), Vector3(p1.x, 0.0, p1.z), 0.0)
		var c2: Dictionary = cover.clip_segment(Vector3(origin.x, 0.0, origin.z), Vector3(p2.x, 0.0, p2.z), 0.0)
		if bool(c1["blocked"]):
			var pos1: Vector3 = c1["position"]
			end1 = Vector3(pos1.x, origin.y, pos1.z)
		if bool(c2["blocked"]):
			var pos2: Vector3 = c2["position"]
			end2 = Vector3(pos2.x, origin.y, pos2.z)
	_draw_mesh.surface_set_color(col)
	_draw_mesh.surface_add_vertex(origin)
	_draw_mesh.surface_add_vertex(end1)
	_draw_mesh.surface_add_vertex(end2)
