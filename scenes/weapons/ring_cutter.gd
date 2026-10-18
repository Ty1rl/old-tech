class_name RingCutter
extends WeaponComponent
## Raw world samples own collision; smoothing affects only the procedural guide.
const Presentation = preload("res://scenes/prototype/weapon_presentation.gd")
const WorldTuning = preload("res://scenes/prototype/tuning.gd")
const ToolStyle = preload("res://scenes/prototype/tool_style.gd")
@export var settings: RingCutterSettings = preload("res://scenes/weapons/settings/ring_cutter.tres")
@onready var stroke: MeshInstance3D = $Stroke
var drawing := false
var preview_points: Array[Vector3] = []
var preview_length := 0.0
var preview_blocked := false
var preview_cutoff_point := Vector3.ZERO
var preview_unblocked_points: Array[Vector3] = []
var preview_blocked_points: Array[Vector3] = []
var flight_phase := "idle"
var head := Vector3.ZERO
var launch_origin := Vector3.ZERO
var flight_points: Array[Vector3] = []
var stroke_index := 0
var hit_ids: Dictionary = {}
var _draw_mesh: ImmediateMesh

func _ready() -> void:
	_draw_mesh = ImmediateMesh.new()
	stroke.mesh = _draw_mesh

func press(origin: Vector3, aim: Vector3) -> void:
	if flight_phase != "idle":
		last_feedback = "Ring in flight"
		return
	if not _can_use_tool(&"ring", 1.0):
		last_feedback = "Ring empty — press E to repair"
		return
	drawing = true
	preview_points.clear()
	preview_length = 0.0
	preview_points.append(_clamp_point(aim, origin))
	_split_preview()
	last_feedback = "Drawing ring path"

func release(origin: Vector3, aim: Vector3, muzzle: Vector3) -> void:
	if not drawing:
		return
	sample(aim, origin)
	drawing = false
	if preview_length < settings.minimum_length or preview_points.size() < 2:
		clear_preview()
		last_feedback = "Stroke too short (<%.1fm)" % settings.minimum_length
		return
	if not _can_use_tool(&"ring", 1.0):
		clear_preview()
		last_feedback = "Ring empty — press E to repair"
		return
	_spend_tool(&"ring", 1.0)
	flight_points = preview_points.duplicate()
	clear_preview()
	flight_phase = "outbound"
	stroke_index = 0
	hit_ids.clear()
	launch_origin = Vector3(origin.x, 0.0, origin.z)
	head = launch_origin
	last_feedback = "Ring launched"
	combat_event.emit(&"ring_launch", muzzle, 1.0)

func clear_preview() -> void:
	preview_points.clear()
	preview_length = 0.0
	preview_blocked = false
	preview_cutoff_point = Vector3.ZERO
	preview_unblocked_points.clear()
	preview_blocked_points.clear()

func _clamp_point(raw_aim: Vector3, origin: Vector3) -> Vector3:
	var half: float = WorldTuning.ARENA_HALF_SIZE
	var p := Vector2(clampf(raw_aim.x, -half, half), clampf(raw_aim.z, -half, half))
	var origin_xz := Vector2(origin.x, origin.z)
	var offset := p - origin_xz
	var max_r := settings.range
	if offset.length() > max_r:
		p = origin_xz + offset.normalized() * max_r
		p.x = clampf(p.x, -half, half)
		p.y = clampf(p.y, -half, half)
	return Vector3(p.x, 0.0, p.y)

func sample(raw_aim: Vector3, origin: Vector3) -> void:
	if not drawing or preview_points.is_empty():
		return
	var max_len := settings.length
	if preview_length >= max_len - 1e-5 or preview_points.size() >= settings.max_samples:
		return
	var clamped := _clamp_point(raw_aim, origin)
	var last: Vector3 = preview_points[-1]
	var seg := Vector2(clamped.x - last.x, clamped.z - last.z)
	var dist := seg.length()
	var spacing := settings.sample_spacing
	if dist < spacing:
		return
	var dir := seg / dist
	var cursor := Vector2(last.x, last.z)
	var left_to_walk := dist
	while left_to_walk >= spacing and preview_length < max_len - 1e-5 and preview_points.size() < settings.max_samples:
		var step_len := minf(spacing, max_len - preview_length)
		if left_to_walk < spacing * 1.5:
			step_len = minf(left_to_walk, max_len - preview_length)
		cursor += dir * step_len
		preview_points.append(Vector3(cursor.x, 0.0, cursor.y))
		preview_length += step_len
		left_to_walk -= step_len
		if step_len < spacing:
			break
	_split_preview()

func _split_preview() -> void:
	preview_blocked = false
	preview_cutoff_point = Vector3.ZERO
	preview_unblocked_points.clear()
	preview_blocked_points.clear()
	if preview_points.is_empty():
		return
	var r_ring := settings.radius
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

func step(w_delta: float, origin: Vector3, enemies: Array) -> void:
	var time_left := w_delta
	var guard := 0
	var r_ring := settings.radius
	var arc_peak := settings.arc_height
	while time_left > 1e-6 and flight_phase != "idle" and guard < 256:
		guard += 1
		if flight_phase == "outbound":
			if flight_points.is_empty():
				flight_phase = "idle"
				break
			var target: Vector3 = flight_points[0]
			var cur_xz := Vector2(head.x, head.z)
			var target_xz := Vector2(target.x, target.z)
			var to_t := target_xz - cur_xz
			var dist := to_t.length()
			var speed := settings.outbound_speed
			var step_d := speed * time_left
			var start_xz := Vector2(launch_origin.x, launch_origin.z)
			var total_out_dist := start_xz.distance_to(target_xz)
			if dist <= step_d + 1e-5:
				head = Vector3(target.x, 0.0, target.z)
				time_left -= (dist / speed) if speed > 0.0 else time_left
				flight_phase = "stroke"
				stroke_index = 0
			else:
				var next_xz := cur_xz + (to_t / dist) * step_d
				var u := clampf(start_xz.distance_to(next_xz) / total_out_dist, 0.0, 1.0) if total_out_dist > 1e-5 else 1.0
				var arc_y := 4.0 * arc_peak * u * (1.0 - u)
				head = Vector3(next_xz.x, arc_y, next_xz.y)
				time_left = 0.0
		elif flight_phase == "stroke":
			if stroke_index >= flight_points.size() - 1:
				head.y = 0.0
				flight_phase = "return"
				continue
			var seg_target: Vector3 = flight_points[stroke_index + 1]
			var prev := Vector3(head.x, 0.0, head.z)
			var to_s := Vector2(seg_target.x - prev.x, seg_target.z - prev.z)
			var dist := to_s.length()
			var speed := settings.stroke_speed
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
					head = reached_end
					time_left -= ((intended_dist * frac) / speed) if speed > 0.0 else time_left
					if frac > 0.0 and prev.distance_to(reached_end) > 1e-6:
						_sweep_segment(prev, reached_end, enemies)
					flight_phase = "return"
					if not last_feedback.begins_with("Ring hit"):
						last_feedback = "Ring stopped by cover"
					continue
			head = intended_end
			if reaching_waypoint:
				time_left -= (dist / speed) if speed > 0.0 else time_left
				_sweep_segment(prev, head, enemies)
				stroke_index += 1
				if stroke_index >= flight_points.size() - 1:
					flight_phase = "return"
			else:
				time_left = 0.0
				_sweep_segment(prev, head, enemies)
		elif flight_phase == "return":
			# Returning ring homes directly back to the current player harmlessly.
			var home := Vector3(origin.x, 0.0, origin.z)
			var to_h := Vector2(home.x - head.x, home.z - head.z)
			var dist := to_h.length()
			var speed := settings.return_speed
			var step_d := speed * time_left
			if dist <= step_d + 1e-5:
				head = home
				time_left = 0.0
				flight_phase = "idle"
				flight_points.clear()
				hit_ids.clear()
				last_feedback = "Ring returned"
				combat_event.emit(&"ring_return", home, 0.5)
			else:
				var move := (to_h / dist) * step_d
				head = Vector3(head.x + move.x, 0.0, head.z + move.y)
				time_left = 0.0

func _sweep_segment(seg_start: Vector3, seg_end: Vector3, enemies: Array) -> void:
	var a := Vector2(seg_start.x, seg_start.z)
	var b := Vector2(seg_end.x, seg_end.z)
	var d := b - a
	var r_ring := settings.radius
	var hits_along_segment: Array[Dictionary] = []

	for enemy in enemies:
		if not _is_live_enemy(enemy):
			continue
		var enemy_node := enemy as Node3D
		var id: int = _enemy_combat_id(enemy_node)
		if hit_ids.has(id) and not enemy_node.has_method("lesson_state") and not enemy_node.has_cuttable_part():
			continue
		var c := Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		var r_enemy: float = float(enemy_node.radius)
		var broad_radius: float = float(enemy_node.attack_radius(&"ring"))
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
		var res := _attack_enemy(enemy_node, &"ring", settings.damage, item["contact"],
			{"segment_start": seg_start, "segment_end": seg_end, "radius": r_ring, "already_hit": hit_ids.has(id)})
		if bool(res.get("connected", true)):
			hit_ids[id] = true
			_record_hit_feedback("Ring", res)


func rebuild(origin: Vector3, show_origin: bool = true) -> void:
	if _draw_mesh == null:
		return
	_draw_mesh.clear_surfaces()

	if drawing and preview_points.size() >= 1:
		if show_origin:
			var p_ground := Vector3(origin.x, 0.06, origin.z)
			_draw_circle_outline(p_ground, settings.range, Color(0.4, 0.78, 0.96, 0.22))
			_draw_arc_ribbon(p_ground, preview_points[0], settings.arc_height, 0.07, Color(0.55, 0.85, 1.0, 0.45))
		if preview_unblocked_points.size() >= 2:
			_draw_stroke_ribbon(preview_unblocked_points, 0, preview_unblocked_points.size() - 1, 0.12, ToolStyle.RING, 0.10)
		if preview_blocked:
			_draw_circle_outline(Vector3(preview_cutoff_point.x, 0.16, preview_cutoff_point.z), settings.radius, Color("ff5c4d"))
			if preview_blocked_points.size() >= 2:
				_draw_stroke_ribbon(preview_blocked_points, 0, preview_blocked_points.size() - 1, 0.09, Color(0.95, 0.34, 0.28, 0.45), 0.08)

	if flight_phase != "idle" and flight_points.size() >= 2:
		if flight_phase == "outbound":
			_draw_arc_ribbon(launch_origin, flight_points[0], settings.arc_height, 0.08, Color(0.55, 0.85, 1.0, 0.55))
			_draw_circle_outline(Vector3(head.x, 0.08, head.z), settings.radius * 0.75, Color(0.2, 0.35, 0.45, 0.35))
		if stroke_index > 0:
			_draw_stroke_ribbon(flight_points, 0, stroke_index, 0.10, Color("4b8a63"), 0.08)
		if stroke_index < flight_points.size() - 1:
			_draw_stroke_ribbon(flight_points, stroke_index, flight_points.size() - 1, 0.14, Color(ToolStyle.RING, 0.45), 0.11)
		var ring_col := ToolStyle.RING.lightened(0.25) if flight_phase == "stroke" else ToolStyle.RING
		var ring_y := maxf(0.22, head.y + 0.22) if flight_phase == "outbound" else 0.22
		_draw_circle_outline(Vector3(head.x, ring_y, head.z), settings.radius, ring_col)

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

func display_stroke(path: Array[Vector3]) -> Array[Vector3]:
	return Presentation.stroke_display(path, cover, settings.radius) if settings.display_smoothing else path.duplicate()

func _draw_stroke_ribbon(path: Array[Vector3], start: int, end: int, width: float, color: Color, height: float) -> void:
	if end <= start: return
	var raw: Array[Vector3] = []
	raw.assign(path.slice(start, end + 1))
	# Anchor the active ring head; only the rendered, untraveled guide changes.
	if path == flight_points and flight_phase == "stroke":
		if end == stroke_index: raw.append(head)
		elif start == stroke_index: raw[0] = head
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

func cancel_input() -> void:
	drawing = false
	clear_preview()

func reset_state() -> void:
	cancel_input()
	flight_phase = "idle"
	head = Vector3.ZERO
	launch_origin = Vector3.ZERO
	flight_points.clear()
	stroke_index = 0
	hit_ids.clear()
	if _draw_mesh != null: _draw_mesh.clear_surfaces()

func capture_state() -> Dictionary:
	var ids: Array[int] = []
	for id in hit_ids: ids.append(int(id))
	ids.sort()
	return {"phase": flight_phase, "head": head, "launch_origin": launch_origin,
		"points": flight_points.duplicate(), "stroke_index": stroke_index, "hit_ids": ids}

func restore_state(data: Dictionary) -> void:
	cancel_input()
	flight_phase = String(data.get("phase", "idle"))
	head = data.get("head", Vector3.ZERO)
	launch_origin = data.get("launch_origin", head)
	flight_points.clear()
	for point: Vector3 in data.get("points", []):
		if flight_points.size() >= settings.max_samples: break
		flight_points.append(point)
	stroke_index = clampi(int(data.get("stroke_index", 0)), 0, maxi(0, flight_points.size() - 1))
	hit_ids.clear()
	for id in data.get("hit_ids", []):
		if hit_ids.size() >= 32: break
		hit_ids[int(id)] = true
	if flight_points.size() < 2 or flight_phase not in ["idle", "outbound", "stroke", "return"]: flight_phase = "idle"
