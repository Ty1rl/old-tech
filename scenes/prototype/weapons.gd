extends Node3D

const Tuning = preload("res://scenes/prototype/tuning.gd")
var equipment: RefCounted
var cover: RefCounted

var selected_tool: int = 1

# Tool 1 (Ring) state
var ring_drawing: bool = false
var preview_points: Array[Vector3] = []
var preview_length: float = 0.0
var ring_phase: String = "idle" # "idle" | "outbound" | "stroke" | "return"
var ring_pos: Vector3 = Vector3.ZERO
var ring_points: Array[Vector3] = []
var ring_stroke_index: int = 0
var ring_hit_ids: Dictionary = {}

# Tool 2 (Flash / Beam) state
var beam_cooldown: float = 0.0
var beam_flash_timer: float = 0.0
var beam_start: Vector3 = Vector3.ZERO
var beam_end: Vector3 = Vector3.ZERO
var _pending_beam: bool = false
var _pending_beam_origin: Vector3 = Vector3.ZERO
var _pending_beam_aim: Vector3 = Vector3.ZERO

# Tool 3 (Cone) state
var cone_active: bool = false
var cone_origin: Vector3 = Vector3.ZERO
var cone_forward: Vector2 = Vector2(0.0, -1.0)

# Input & feedback state
var mouse_held: bool = false
var require_fresh_press: bool = false
var last_aim: Vector3 = Vector3(0.0, 0.0, -6.0)
var last_feedback: String = "Ready"

# Visual nodes
var _draw_mesh: ImmediateMesh
var _draw_instance: MeshInstance3D


func _ready() -> void:
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


func select_tool(tool_index: int) -> void:
	var target_tool := clampi(tool_index, 1, 3)
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
			ring_drawing = true
			preview_points.clear()
			preview_length = 0.0
			preview_points.append(_clamp_ring_point(aim, player))
			last_feedback = "Drawing ring path"
		2:
			if beam_cooldown > 0.0 or _pending_beam:
				last_feedback = "Flash cooling (%.2fs)" % beam_cooldown
				return
			beam_cooldown = float(Tuning.BEAM.cooldown)
			# Resolve on the next simulation tick against the arena's explicit
			# roster. Keep the click position even if the player moves meanwhile.
			_pending_beam = true
			_pending_beam_origin = player.global_position
			_pending_beam_aim = aim
			last_feedback = "Flash pulse"
		3:
			cone_active = true
			_update_cone_aim(player.global_position, aim)
			last_feedback = "Cone active"


func _on_left_release(player: Node3D, aim: Vector3) -> void:
	match selected_tool:
		1:
			if not ring_drawing:
				return
			if player != null:
				_add_ring_sample(aim, player)
			ring_drawing = false
			if preview_length < float(Tuning.RING.minimum_length) or preview_points.size() < 2:
				preview_points.clear()
				preview_length = 0.0
				last_feedback = "Stroke too short (<%.1fm)" % float(Tuning.RING.minimum_length)
				return
			ring_points = preview_points.duplicate()
			preview_points.clear()
			preview_length = 0.0
			ring_phase = "outbound"
			ring_stroke_index = 0
			ring_hit_ids.clear()
			if player != null:
				ring_pos = Vector3(player.global_position.x, 0.0, player.global_position.z)
			else:
				ring_pos = ring_points[0]
			last_feedback = "Ring launched"
		3:
			if cone_active:
				cone_active = false
				last_feedback = "Cone released"


func step(delta: float, player: Node3D, aim: Vector3, enemies: Array) -> void:
	last_aim = aim

	if _pending_beam:
		_pending_beam = false
		_fire_beam(_pending_beam_origin, _pending_beam_aim, enemies)
	beam_cooldown = maxf(0.0, beam_cooldown - delta)

	beam_flash_timer = maxf(0.0, beam_flash_timer - delta)

	if ring_drawing and player != null and not require_fresh_press:
		_add_ring_sample(aim, player)

	if ring_phase != "idle" and player != null:
		_step_ring(delta, player, enemies)

	if selected_tool == 3 and cone_active and player != null and not require_fresh_press:
		_update_cone_aim(player.global_position, aim)
		_step_cone(delta, player, enemies)

	_rebuild_visuals(player, aim)


func cancel_input() -> void:
	ring_drawing = false
	preview_points.clear()
	preview_length = 0.0
	cone_active = false
	_pending_beam = false
	if mouse_held:
		require_fresh_press = true
	_rebuild_visuals(null, last_aim)


func reset_state() -> void:
	selected_tool = 1
	mouse_held = false
	require_fresh_press = false
	cancel_input()
	ring_phase = "idle"
	ring_pos = Vector3.ZERO
	ring_points.clear()
	ring_stroke_index = 0
	ring_hit_ids.clear()
	beam_cooldown = 0.0
	beam_flash_timer = 0.0
	last_feedback = "Ready"
	_rebuild_visuals(null, last_aim)


func status_text() -> String:
	var names := {1: "1:Ring", 2: "2:Flash", 3: "3:Cone"}
	var rem_len := maxf(0.0, float(Tuning.RING.length) - preview_length)
	var ring_info := "idle"
	if ring_drawing:
		ring_info = "draw %.1f/%.1fm (rem %.1fm)" % [preview_length, float(Tuning.RING.length), rem_len]
	elif ring_phase != "idle":
		ring_info = ring_phase
	var flash_info := "ready" if beam_cooldown <= 0.0 else "%.2fs" % beam_cooldown
	var cone_info := "HOLD" if cone_active else "idle"
	return "Tool [%s] | Ring: %s | Flash: %s | Cone: %s\n%s" % [
		names.get(selected_tool, "1:Ring"), ring_info, flash_info, cone_info, last_feedback
	]


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


func _step_ring(delta: float, player: Node3D, enemies: Array) -> void:
	var time_left := delta
	var guard := 0
	while time_left > 1e-6 and ring_phase != "idle" and guard < 256:
		guard += 1
		if ring_phase == "outbound":
			if ring_points.is_empty():
				ring_phase = "idle"
				break
			var target: Vector3 = ring_points[0]
			var to_t := Vector2(target.x - ring_pos.x, target.z - ring_pos.z)
			var dist := to_t.length()
			var speed := float(Tuning.RING.outbound_speed)
			var step_d := speed * time_left
			if dist <= step_d + 1e-5:
				ring_pos = target
				time_left -= (dist / speed) if speed > 0.0 else time_left
				ring_phase = "stroke"
				ring_stroke_index = 0
			else:
				var move := (to_t / dist) * step_d
				ring_pos += Vector3(move.x, 0.0, move.y)
				time_left = 0.0
		elif ring_phase == "stroke":
			if ring_stroke_index >= ring_points.size() - 1:
				ring_phase = "return"
				continue
			var seg_target: Vector3 = ring_points[ring_stroke_index + 1]
			var to_s := Vector2(seg_target.x - ring_pos.x, seg_target.z - ring_pos.z)
			var dist := to_s.length()
			var speed := float(Tuning.RING.stroke_speed)
			var step_d := speed * time_left
			var prev := ring_pos
			if dist <= step_d + 1e-5:
				ring_pos = seg_target
				time_left -= (dist / speed) if speed > 0.0 else time_left
				_sweep_ring_segment(prev, ring_pos, enemies)
				ring_stroke_index += 1
				if ring_stroke_index >= ring_points.size() - 1:
					ring_phase = "return"
			else:
				var move := (to_s / dist) * step_d
				ring_pos += Vector3(move.x, 0.0, move.y)
				time_left = 0.0
				_sweep_ring_segment(prev, ring_pos, enemies)
		elif ring_phase == "return":
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
			else:
				var move := (to_h / dist) * step_d
				ring_pos += Vector3(move.x, 0.0, move.y)
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
		var id: int = enemy_node.get_instance_id()
		if ring_hit_ids.has(id):
			continue
		var c := Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		var r_enemy: float = float(enemy_node.get("radius"))
		var entry_t := _swept_circle_entry_t(a, b, c, r_ring + r_enemy)
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
		hits_along_segment.append({
			"t": entry_t,
			"enemy": enemy_node,
			"id": id,
			"contact": Vector3(contact_xz.x, 0.0, contact_xz.y)
		})

	hits_along_segment.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["t"]) < float(y["t"]))
	for item in hits_along_segment:
		var enemy_node: Node3D = item["enemy"]
		var id: int = item["id"]
		if not _is_live_enemy(enemy_node) or ring_hit_ids.has(id):
			continue
		ring_hit_ids[id] = true
		var res: Dictionary = enemy_node.call("hit", float(Tuning.RING.damage), item["contact"])
		_record_hit_feedback("Ring", res)


func _fire_beam(origin_world: Vector3, aim_world: Vector3, enemies: Array) -> void:
	var start_xz := Vector2(origin_world.x, origin_world.z)
	var dir := _aim_dir_xz(origin_world, aim_world)
	var max_range := float(Tuning.BEAM.range)
	var end_xz := start_xz + dir * max_range
	var r_beam := float(Tuning.BEAM.radius)

	var best_t := 2.0
	var best_enemy: Node3D = null
	var best_contact := Vector3.ZERO

	for enemy in enemies:
		if not _is_live_enemy(enemy):
			continue
		var enemy_node := enemy as Node3D
		var c := Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		var r_enemy: float = float(enemy_node.get("radius"))
		var t := _swept_circle_entry_t(start_xz, end_xz, c, r_beam + r_enemy)
		if t >= 0.0 and t < best_t:
			best_t = t
			best_enemy = enemy_node
			var beam_pt := start_xz + dir * (max_range * t)
			var from_enemy := beam_pt - c
			var c_dir := from_enemy.normalized() if from_enemy.length_squared() > 1e-6 else -dir
			var contact_xz := c + c_dir * r_enemy
			best_contact = Vector3(contact_xz.x, 0.0, contact_xz.y)

	beam_start = Vector3(start_xz.x, 0.0, start_xz.y)
	beam_flash_timer = 0.14
	if best_enemy != null:
		beam_end = best_contact
		var res: Dictionary = best_enemy.call("hit", float(Tuning.BEAM.damage), best_contact)
		_record_hit_feedback("Flash", res)
	else:
		beam_end = Vector3(end_xz.x, 0.0, end_xz.y)
		last_feedback = "Flash missed"


func _update_cone_aim(origin_world: Vector3, aim_world: Vector3) -> void:
	cone_origin = Vector3(origin_world.x, 0.0, origin_world.z)
	cone_forward = _aim_dir_xz(origin_world, aim_world)


func _step_cone(delta: float, player: Node3D, enemies: Array) -> void:
	if delta <= 0.0:
		return
	var p_xz := Vector2(player.global_position.x, player.global_position.z)
	var max_r := float(Tuning.CONE.range)
	var half_ang := float(Tuning.CONE.half_angle)
	var amount := float(Tuning.CONE.damage_per_second) * delta
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
			if ang > half_ang:
				continue
		var dir_from_enemy := (p_xz - c).normalized() if dist > 1e-5 else -cone_forward
		var contact_xz := c + dir_from_enemy * r_enemy
		var contact_world := Vector3(contact_xz.x, 0.0, contact_xz.y)
		var res: Dictionary = enemy_node.call("hit", amount, contact_world)
		var dealt := float(res.get("dealt", 0.0))
		if dealt > 0.0:
			hit_any = true
			total_dealt += dealt
			if bool(res.get("armored", false)):
				any_armored = true

	if hit_any:
		last_feedback = "Cone %.1f dmg%s" % [total_dealt, " (ARMORED)" if any_armored else ""]


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


func _rebuild_visuals(player: Node3D, _aim: Vector3) -> void:
	if _draw_mesh == null:
		return
	_draw_mesh.clear_surfaces()

	if ring_drawing and preview_points.size() >= 1:
		if player != null:
			_draw_circle_outline(Vector3(player.global_position.x, 0.06, player.global_position.z), float(Tuning.RING.range), Color(0.4, 0.78, 0.96, 0.25))
		_draw_polyline_ribbon(preview_points, 0, preview_points.size() - 1, 0.12, Color("67c9f5"), 0.10)

	if ring_phase != "idle" and ring_points.size() >= 2:
		if ring_stroke_index > 0:
			_draw_polyline_ribbon(ring_points, 0, ring_stroke_index, 0.10, Color("4b8a63"), 0.08)
		if ring_stroke_index < ring_points.size() - 1:
			_draw_polyline_ribbon(ring_points, ring_stroke_index, ring_points.size() - 1, 0.14, Color("f5c267"), 0.11)
		var ring_col := Color("ff7a59") if ring_phase == "stroke" else Color("67c9f5")
		_draw_circle_outline(Vector3(ring_pos.x, 0.22, ring_pos.z), float(Tuning.RING.radius), ring_col)

	if beam_flash_timer > 0.0:
		_draw_polyline_ribbon([beam_start, beam_end], 0, 1, 0.12, Color("fff07a"), 0.30)
		_draw_circle_outline(Vector3(beam_end.x, 0.30, beam_end.z), float(Tuning.BEAM.radius), Color("fff07a"))

	if selected_tool == 3 and cone_active and player != null:
		_draw_cone_sector(Vector3(player.global_position.x, 0.10, player.global_position.z), cone_forward, float(Tuning.CONE.range), float(Tuning.CONE.half_angle), Color(1.0, 0.58, 0.22, 0.28))


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
		_draw_mesh.surface_set_color(col)
		_draw_mesh.surface_add_vertex(origin)
		_draw_mesh.surface_add_vertex(p1)
		_draw_mesh.surface_add_vertex(p2)
	_draw_mesh.surface_end()
