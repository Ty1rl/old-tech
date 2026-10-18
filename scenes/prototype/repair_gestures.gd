extends RefCounted

# Pure gesture and tool-specification helpers for three-weapon repairs:
# - Blue   (ring): 1. Cassette Spin   -> 2. Arch Contacts     -> 3. Blade Alignment Trace
# - Yellow (beam): 1. Lens Ring Spin  -> 2. Ceramic Terminals -> 3. Bellows Trace
# - Orange (cone): 1. Fan Spin        -> 2. Leather Trace     -> 3. Heating-Coil Contacts (open fan cover & front grille)

const TOOL_ORDER: Array[StringName] = [&"ring", &"beam", &"cone"]
const BOARD_SIZE := Vector2(520.0, 260.0)
const TRACE_CORRIDOR := 26.0
const TRACE_CONTACT := 20.0
const SPIN_RADIAL_INNER_PAD := 42.0
const SPIN_RADIAL_OUTER_PAD := 76.0
const SPIN_ACTIVE_OUTER_PAD := 105.0
const SPIN_HUB_DEADZONE := 10.0
const SPIN_MIN_RADIANS := PI * 0.45
const SPIN_FULL_RADIANS := PI * 1.15
const CONNECT_RADIUS := 24.0
const CONNECT_CORRIDOR := 52.0

const TOOL_SPEC_RESOURCES := {
	"ring": preload("res://scenes/prototype/settings/repair_ring.tres"),
	"beam": preload("res://scenes/prototype/settings/repair_beam.tres"),
	"cone": preload("res://scenes/prototype/settings/repair_cone.tres"),
}

static var _cached_specs: Dictionary = {}
static var TOOL_SPECS: Dictionary:
	get:
		for k in ["ring", "beam", "cone"]:
			if not _cached_specs.has(k):
				_cached_specs[k] = _build_spec_dict(k)
		return _cached_specs


# Exact orthogonal projection matching SubViewport (520x260) + PreviewCamera (keep_aspect = KEEP_HEIGHT).
static func project_local_to_board(
	cam_pos: Vector3,
	cam_target: Vector3,
	cam_size: float,
	model_pos: Vector3,
	model_rot_deg: Vector3,
	local_point: Vector3,
	viewport_size: Vector2 = BOARD_SIZE
) -> Vector2:
	var model_basis := Basis.from_euler(
		Vector3(deg_to_rad(model_rot_deg.x), deg_to_rad(model_rot_deg.y), deg_to_rad(model_rot_deg.z))
	)
	var world_pt := model_pos + model_basis * local_point
	var cam_xform := Transform3D(Basis.IDENTITY, cam_pos).looking_at(cam_target, Vector3.UP)
	var cam_local := cam_xform.affine_inverse() * world_pt
	var aspect := viewport_size.x / maxf(1.0, viewport_size.y)
	var half_h := maxf(0.01, cam_size * 0.5)
	var half_w := half_h * aspect
	var u := 0.5 + (cam_local.x / (half_w * 2.0))
	var v := 0.5 - (cam_local.y / (half_h * 2.0))
	return Vector2(u * viewport_size.x, v * viewport_size.y)


static func _project_operation_dict(
	raw_op: Dictionary,
	cam_pos: Vector3,
	cam_target: Vector3,
	cam_size: float,
	model_pos: Vector3,
	model_rot_deg: Vector3
) -> Dictionary:
	var op := raw_op.duplicate(true)
	var kind := StringName(op.get("kind", &"spin"))
	op["kind"] = kind
	var badge_pos: Vector2 = op.get("badge_pos", Vector2(32.0, 32.0))
	var badge_center := badge_pos + Vector2(64.0, 10.0)
	if kind == &"spin":
		var center_local: Vector3 = op.get("center_local", Vector3.ZERO)
		var center_2d := project_local_to_board(cam_pos, cam_target, cam_size, model_pos, model_rot_deg, center_local)
		op["center"] = center_2d
		var radius := float(op.get("radius", 32.0))
		var dir_to_badge := (badge_center - center_2d)
		if dir_to_badge.length() > 1.0:
			op["leader_target"] = center_2d + dir_to_badge.normalized() * radius
		else:
			op["leader_target"] = center_2d
	elif kind == &"connect":
		var raw_pairs: Array = op.get("pairs", [])
		var projected_pairs: Array = []
		var nearest_pt := badge_center
		var best_d := INF
		for p_raw in raw_pairs:
			var p: Dictionary = (p_raw as Dictionary).duplicate(true)
			p["pair_id"] = StringName(p.get("pair_id", &"A"))
			p["shape"] = StringName(p.get("shape", &"triangle"))
			var a_2d: Vector2 = p.get("a", Vector2.ZERO)
			var b_2d: Vector2 = p.get("b", Vector2.ZERO)
			if p.has("a_local"):
				a_2d = project_local_to_board(cam_pos, cam_target, cam_size, model_pos, model_rot_deg, p["a_local"])
			if p.has("b_local"):
				b_2d = project_local_to_board(cam_pos, cam_target, cam_size, model_pos, model_rot_deg, p["b_local"])
			p["a"] = a_2d
			p["b"] = b_2d
			for candidate in [a_2d, b_2d]:
				var d := badge_center.distance_to(candidate)
				if d < best_d:
					best_d = d
					nearest_pt = candidate
			projected_pairs.append(p)
		op["pairs"] = projected_pairs
		op["leader_target"] = nearest_pt
	elif kind == &"trace":
		var pts_2d: Array[Vector2] = []
		if op.has("points_local"):
			for pt3 in op["points_local"]:
				pts_2d.append(project_local_to_board(cam_pos, cam_target, cam_size, model_pos, model_rot_deg, Vector3(pt3)))
		elif op.has("points"):
			pts_2d.assign(op["points"])
		op["points"] = pts_2d
		var nearest_pt := badge_center
		var best_d := INF
		for candidate in pts_2d:
			var d := badge_center.distance_to(candidate)
			if d < best_d:
				best_d = d
				nearest_pt = candidate
		op["leader_target"] = nearest_pt
	return op


static func _unproject_to_board(cam: Camera3D, world_pos: Vector3) -> Vector2:
	var vp := cam.get_viewport()
	var vp_size := Vector2(vp.size) if vp != null else BOARD_SIZE
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = BOARD_SIZE
	var raw := cam.unproject_position(world_pos)
	return Vector2(raw.x * (BOARD_SIZE.x / vp_size.x), raw.y * (BOARD_SIZE.y / vp_size.y))


# Live 3D node-to-board projection when the SubViewport camera and model holder are active.
static func project_operation_with_camera(raw_op: Dictionary, holder: Node3D, cam: Camera3D) -> Dictionary:
	if holder == null or cam == null or not holder.is_inside_tree() or not cam.is_inside_tree():
		return raw_op
	var op := raw_op.duplicate(true)
	var kind := StringName(op.get("kind", &"spin"))
	var part_name := String(op.get("part_node", ""))
	var part_node: Node3D = holder.find_child(part_name, true, false) as Node3D if part_name != "" else null
	op["part_resolved"] = (part_node != null)
	var base_xform: Transform3D = holder.global_transform
	var badge_pos: Vector2 = op.get("badge_pos", Vector2(32.0, 32.0))
	var badge_center := badge_pos + Vector2(64.0, 10.0)
	if kind == &"spin" and op.has("center_local"):
		var world_center := base_xform * Vector3(op["center_local"])
		var center_2d := _unproject_to_board(cam, world_center)
		op["center"] = center_2d
		var radius := float(op.get("radius", 32.0))
		var dir_to_badge := badge_center - center_2d
		op["leader_target"] = center_2d + dir_to_badge.normalized() * radius if dir_to_badge.length() > 1.0 else center_2d
	elif kind == &"connect":
		var raw_pairs: Array = op.get("pairs", [])
		var projected_pairs: Array = []
		var nearest_pt := badge_center
		var best_d := INF
		for p_raw in raw_pairs:
			var p: Dictionary = (p_raw as Dictionary).duplicate(true)
			if p.has("a_local"):
				p["a"] = _unproject_to_board(cam, base_xform * Vector3(p["a_local"]))
			if p.has("b_local"):
				p["b"] = _unproject_to_board(cam, base_xform * Vector3(p["b_local"]))
			for candidate in [p["a"], p["b"]]:
				var d := badge_center.distance_to(candidate)
				if d < best_d:
					best_d = d
					nearest_pt = candidate
			projected_pairs.append(p)
		op["pairs"] = projected_pairs
		op["leader_target"] = nearest_pt
	elif kind == &"trace" and op.has("points_local"):
		var pts_2d: Array[Vector2] = []
		var nearest_pt := badge_center
		var best_d := INF
		for pt3 in op["points_local"]:
			var p2 := _unproject_to_board(cam, base_xform * Vector3(pt3))
			pts_2d.append(p2)
			var d := badge_center.distance_to(p2)
			if d < best_d:
				best_d = d
				nearest_pt = p2
		op["points"] = pts_2d
		op["leader_target"] = nearest_pt
	return op


static func _build_spec_dict(key: String) -> Dictionary:
	var res: Resource = TOOL_SPEC_RESOURCES.get(key, TOOL_SPEC_RESOURCES["ring"])
	var cam_pos: Vector3 = res.get("cam_pos")
	var cam_target: Vector3 = res.get("cam_target")
	var cam_size: float = float(res.get("cam_size"))
	var model_pos: Vector3 = res.get("model_pos")
	var model_rot_deg: Vector3 = res.get("model_rot_deg")
	var ops_out: Array = []
	var raw_ops: Array = res.get("operations")
	for raw_op in raw_ops:
		ops_out.append(_project_operation_dict(raw_op, cam_pos, cam_target, cam_size, model_pos, model_rot_deg))
	return {
		"id": StringName(res.get("id")),
		"title": String(res.get("title")),
		"accent": Color(res.get("accent")),
		"glb": String(res.get("glb")),
		"cam_pos": cam_pos,
		"cam_target": cam_target,
		"cam_size": cam_size,
		"model_pos": model_pos,
		"model_rot_deg": model_rot_deg,
		"open_cover_and_grille": bool(res.get("open_cover_and_grille")),
		"spin_part_pivots": (res.get("spin_part_pivots") as Dictionary).duplicate(true),
		"operations": ops_out,
		"resource": res,
	}


static func tool_spec(tool: StringName) -> Dictionary:
	var key := String(tool)
	if not TOOL_SPEC_RESOURCES.has(key):
		key = "ring"
	if not _cached_specs.has(key):
		_cached_specs[key] = _build_spec_dict(key)
	return _cached_specs[key]


# Selects the repair target: equipped weapon if damaged, otherwise the most damaged
# owned weapon by normalized condition (with stable tie-breaking in owned order).
# Returns &"" when all owned weapons are full.
static func pick_repair_tool(equipment: RefCounted, owned_tools: Array, preferred_tool: StringName = &"") -> StringName:
	if equipment == null:
		return &""
	var valid_owned: Array[StringName] = []
	for item in owned_tools:
		var candidate: StringName
		if item is int:
			var idx := int(item)
			if idx >= 1 and idx <= TOOL_ORDER.size():
				candidate = TOOL_ORDER[idx - 1]
			else:
				continue
		else:
			candidate = StringName(item)
		if candidate in TOOL_ORDER and not (candidate in valid_owned):
			valid_owned.append(candidate)
	if valid_owned.is_empty():
		valid_owned.assign(TOOL_ORDER)
	if preferred_tool in valid_owned and not equipment.is_full(preferred_tool):
		return preferred_tool
	var best_tool: StringName = &""
	var best_condition := INF
	for candidate in valid_owned:
		if equipment.is_full(candidate):
			continue
		var cond := float(equipment.condition(candidate))
		if cond < best_condition - 0.000001:
			best_condition = cond
			best_tool = candidate
	return best_tool


# Maps the 4 internal capacity checkpoints (stage 0..3) onto the 3 visible tool operations (0..2).
# Stage 0 -> Operation 0 (0%..25%)
# Stage 1 -> Operation 1 (25%..50%)
# Stage 2, 3 -> Operation 2 (50%..100%)
static func operation_index_for_stage(stage_idx: int) -> int:
	if stage_idx <= 0:
		return 0
	if stage_idx == 1:
		return 1
	return 2


static func active_operation(tool: StringName, stage_idx: int) -> Dictionary:
	var spec := tool_spec(tool)
	var ops: Array = spec["operations"]
	var idx := clampi(operation_index_for_stage(stage_idx), 0, ops.size() - 1)
	return ops[idx]


static func sample_spin_arc(center: Vector2, radius: float, start_angle: float, dir: float, sweep_radians: float, steps: int = 8) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var count := maxi(2, steps)
	for i in range(count + 1):
		var frac := float(i) / float(count)
		var ang := start_angle + dir * sweep_radians * frac
		out.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return out


static func path_length(points: Array[Vector2]) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


static func slice_polyline(points: Array[Vector2], start_frac: float, end_frac: float, min_vertex_gap: float = 0.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if points.size() < 2:
		return out
	var f0 := clampf(start_frac, 0.0, 1.0)
	var f1 := clampf(end_frac, 0.0, 1.0)
	if f1 <= f0 + 0.000001:
		return out
	if f0 <= 0.0001 and f1 >= 0.9999 and min_vertex_gap <= 0.0:
		out.assign(points)
		return out
	var total := path_length(points)
	if total <= 0.000001:
		return out
	var d0 := f0 * total
	var d1 := f1 * total
	var raw: Array[Vector2] = []
	var accum := 0.0
	for i in range(points.size() - 1):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var seg := a.distance_to(b)
		var next_accum := accum + seg
		if seg > 0.000001:
			if d0 >= accum - 0.0001 and d0 <= next_accum + 0.0001 and raw.is_empty():
				var t0 := clampf((d0 - accum) / seg, 0.0, 1.0)
				raw.append(a.lerp(b, t0))
			if not raw.is_empty() and d1 > next_accum + 0.0001:
				if raw[-1].distance_to(b) > 0.01:
					raw.append(b)
			if d1 >= accum - 0.0001 and d1 <= next_accum + 0.0001:
				var t1 := clampf((d1 - accum) / seg, 0.0, 1.0)
				var end_pt := a.lerp(b, t1)
				if raw.is_empty() or raw[-1].distance_to(end_pt) > 0.01:
					raw.append(end_pt)
				break
		accum = next_accum
	if raw.size() < 2:
		return out
	out.append(raw[0])
	for i in range(1, raw.size() - 1):
		if min_vertex_gap > 0.0 and (out[-1].distance_to(raw[i]) < min_vertex_gap or raw[i].distance_to(raw[-1]) < min_vertex_gap):
			continue
		out.append(raw[i])
	out.append(raw[-1])
	return out


static func canonical_stage_routes(tool: StringName) -> Array:
	var spec := tool_spec(tool)
	var ops: Array = spec["operations"]
	var routes := []
	for stage_idx in range(4):
		var op: Dictionary = ops[operation_index_for_stage(stage_idx)]
		var kind: StringName = op["kind"]
		if kind == &"spin":
			routes.append(sample_spin_arc(op["center"], float(op["radius"]), float(op["start_angle"]), float(op["dir"]), SPIN_FULL_RADIANS, 8))
		elif kind == &"trace":
			var pts: Array[Vector2] = []
			pts.assign(op["points"])
			if stage_idx == 3 and pts.size() >= 3:
				routes.append(slice_polyline(pts, 0.5, 1.0, TRACE_CONTACT * 0.6))
			else:
				routes.append(pts)
		elif kind == &"connect":
			var pairs: Array = op["pairs"]
			var cpts: Array[Vector2] = []
			if stage_idx == 3 and pairs.size() >= 2:
				cpts.append(pairs[1]["a"])
				cpts.append(pairs[1]["b"])
			else:
				for p in pairs:
					cpts.append(p["a"])
					cpts.append(p["b"])
			routes.append(cpts)
	return routes


# Pure Spin gesture evaluation
static func spin_required_radians(local_intact: float) -> float:
	var missing := clampf(1.0 - minf(local_intact, 0.82), 0.18, 1.0)
	return SPIN_FULL_RADIANS * missing


static func spin_can_start(op: Dictionary, point: Vector2) -> bool:
	var center: Vector2 = op["center"]
	var radius: float = float(op["radius"])
	var dist := point.distance_to(center)
	return dist <= radius + SPIN_RADIAL_OUTER_PAD


static func spin_step(op: Dictionary, prev_point: Vector2, next_point: Vector2, current_accum: float, locked_dir: float) -> Dictionary:
	var center: Vector2 = op["center"]
	var radius: float = float(op["radius"])
	var max_r := radius + SPIN_ACTIVE_OUTER_PAD
	var step_dist := prev_point.distance_to(next_point)
	if step_dist <= 0.001:
		return {
			"ok": true,
			"accum": current_accum,
			"locked_dir": locked_dir,
			"point": next_point,
			"message": "",
		}
	# Ignore single-frame noise/teleport jumps during an honest active turn rather than resetting progress.
	if step_dist > 170.0 and current_accum >= 0.22:
		return {
			"ok": true,
			"accum": current_accum,
			"locked_dir": locked_dir,
			"point": prev_point,
			"message": "",
		}
	var samples := maxi(1, ceili(step_dist / 4.0))
	var accum := current_accum
	var dir := locked_dir
	var last_pt := prev_point
	var reverse_accum := 0.0
	for i in range(1, samples + 1):
		var pt := prev_point.lerp(next_point, float(i) / float(samples))
		var dist := pt.distance_to(center)
		if dist > max_r:
			if accum >= 0.25 and dist <= max_r + 65.0:
				# Wide oval excursion during an established turn: preserve progress without aborting.
				last_pt = pt
				continue
			return {
				"ok": false,
				"accum": accum,
				"locked_dir": dir,
				"point": pt,
				"message": "Left the spin area. Completed checkpoints are safe; drag around the dial.",
			}
		var last_dist := last_pt.distance_to(center)
		if dist < SPIN_HUB_DEADZONE or last_dist < SPIN_HUB_DEADZONE:
			# Center crossing: glide across hub without polar angle spikes or resetting.
			if dir != 0.0 and accum > 0.05:
				accum += (last_pt.distance_to(pt) / maxf(radius, 24.0)) * 0.30
			last_pt = pt
			continue
		var a0 := (last_pt - center).angle()
		var a1 := (pt - center).angle()
		var delta := wrapf(a1 - a0, -PI, PI)
		if absf(delta) > 1.25:
			# Ignore angular noise spike on a single sub-step.
			last_pt = pt
			continue
		if dir == 0.0:
			if absf(delta) > 0.008:
				dir = 1.0 if delta > 0.0 else -1.0
				accum += absf(delta)
			last_pt = pt
			continue
		var signed_step := delta * dir
		if accum < 0.22 and signed_step < 0.0:
			# Smoothly adopt new direction if initial grip had a tiny opposite hook.
			accum += signed_step
			if accum < 0.0:
				dir = -dir
				accum = -accum
			last_pt = pt
			continue
		if signed_step >= 0.0:
			accum += signed_step
			reverse_accum = maxf(0.0, reverse_accum - signed_step * 0.5)
		else:
			# Interior return of a D-shape / off-center loop (dist < 0.72 * radius) ratchets without unwinding.
			if dist >= radius * 0.72 and last_dist >= radius * 0.72:
				reverse_accum += -signed_step
				accum = maxf(0.0, accum + signed_step)
				if reverse_accum > 0.40:
					return {
						"ok": false,
						"accum": 0.0,
						"locked_dir": 0.0,
						"point": pt,
						"message": "Reversed spin direction. Keep turning smoothly in one direction.",
					}
		last_pt = pt
	return {
		"ok": true,
		"accum": accum,
		"locked_dir": dir,
		"point": next_point,
		"message": "",
	}


# Pure Connect terminal lookup and matching helpers
static func find_terminal(op: Dictionary, point: Vector2, radius: float = CONNECT_RADIUS) -> Dictionary:
	var pairs: Array = op["pairs"]
	var best_dist := radius
	var found := {}
	for pair_idx in range(pairs.size()):
		var p: Dictionary = pairs[pair_idx]
		for side in ["a", "b"]:
			var pos: Vector2 = p[side]
			var d := point.distance_to(pos)
			if d <= best_dist:
				best_dist = d
				found = {
					"pair_index": pair_idx,
					"pair_id": p["pair_id"],
					"shape": p["shape"],
					"label": p["label"],
					"side": side,
					"position": pos,
				}
	return found


static func terminals_match(first: Dictionary, second: Dictionary) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	return (
		first.get("pair_id") == second.get("pair_id")
		and first.get("shape") == second.get("shape")
		and first.get("label") == second.get("label")
		and first.get("side") != second.get("side")
	)


static func point_near_connect_corridor(op: Dictionary, point: Vector2) -> bool:
	var pairs: Array = op["pairs"]
	var pts: Array[Vector2] = []
	for p in pairs:
		pts.append(p["a"])
		pts.append(p["b"])
	for i in range(pts.size()):
		if point.distance_to(pts[i]) <= CONNECT_CORRIDOR:
			return true
		if i + 1 < pts.size():
			var closest := Geometry2D.get_closest_point_to_segment(point, pts[i], pts[i + 1])
			if point.distance_to(closest) <= CONNECT_CORRIDOR:
				return true
	return false
