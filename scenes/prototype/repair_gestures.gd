extends RefCounted

# Pure gesture and tool-specification helpers for Round K tool-specific repairs:
# - Orange (cone):  1. Fan Spin        -> 2. Leather Trace     -> 3. Heating-Coil Contacts (open fan cover & front grille)
# - Yellow (beam):  1. Lens Ring Spin  -> 2. Ceramic Terminals -> 3. Bellows Trace
# - Blue   (ring):  1. Cassette Spin   -> 2. Arch Contacts     -> 3. Blade Alignment Trace
# - Purple (clock): 1. Side-Key Spin   -> 2. Pendulum Trace    -> 3. Cassette Contacts

const BOARD_SIZE := Vector2(520.0, 260.0)
const TRACE_CORRIDOR := 24.0
const TRACE_CONTACT := 20.0
const SPIN_RADIAL_INNER_PAD := 26.0
const SPIN_RADIAL_OUTER_PAD := 30.0
const SPIN_MIN_RADIANS := PI * 0.55
const SPIN_FULL_RADIANS := PI * 1.35
const CONNECT_RADIUS := 22.0
const CONNECT_CORRIDOR := 46.0

const TOOL_SPECS := {
	"ring": {
		"id": &"ring",
		"title": "Ring Cutter",
		"accent": Color("67c9f5"),
		"glb": "res://assets/equipment/ring_caster.glb",
		"cam_pos": Vector3(0.0, 1.45, 1.15),
		"cam_target": Vector3(0.0, 0.0, 0.0),
		"cam_size": 0.62,
		"model_pos": Vector3(-0.12, -0.04, -0.02),
		"model_rot_deg": Vector3(14.0, -132.0, 4.0),
		"operations": [
			{
				"index": 0,
				"kind": &"spin",
				"tag": "1 · WIND TAPE",
				"short": "Wind Tape",
				"prompt": "Drag around the cassette reel to wind the tape.",
				"center": Vector2(194.0, 78.0),
				"radius": 34.0,
				"dir": 1.0,
				"start_angle": -PI * 0.65,
				"badge_pos": Vector2(68.0, 32.0),
			},
			{
				"index": 1,
				"kind": &"connect",
				"tag": "2 · PAIR CONTACTS",
				"short": "Pair Contacts",
				"prompt": "Click matching ▲A and ■B contacts along the arch.",
				"badge_pos": Vector2(46.0, 166.0),
				"pairs": [
					{
						"pair_id": &"A",
						"shape": &"triangle",
						"label": "A",
						"a": Vector2(192.0, 142.0),
						"b": Vector2(204.0, 178.0),
					},
					{
						"pair_id": &"B",
						"shape": &"square",
						"label": "B",
						"a": Vector2(198.0, 218.0),
						"b": Vector2(240.0, 206.0),
					},
				],
			},
			{
				"index": 2,
				"kind": &"trace",
				"tag": "3 · TRACE TO ALIGN",
				"short": "Align Blade",
				"prompt": "Trace along the saw ring arc from start to end.",
				"badge_pos": Vector2(302.0, 116.0),
				"points": [
					Vector2(290.0, 190.0),
					Vector2(328.0, 162.0),
					Vector2(374.0, 158.0),
					Vector2(418.0, 182.0),
				],
			},
		],
	},
	"beam": {
		"id": &"beam",
		"title": "Focused Flash",
		"accent": Color("f3d56b"),
		"glb": "res://assets/equipment/flash_camera.glb",
		"cam_pos": Vector3(0.0, 1.25, 1.35),
		"cam_target": Vector3(0.0, 0.0, 0.0),
		"cam_size": 0.60,
		"model_pos": Vector3(-0.14, -0.04, -0.10),
		"model_rot_deg": Vector3(8.0, 142.0, 0.0),
		"operations": [
			{
				"index": 0,
				"kind": &"spin",
				"tag": "1 · SPIN LENS",
				"short": "Lens Spin",
				"prompt": "Drag around the brass lens barrel to focus the aperture.",
				"center": Vector2(172.0, 180.0),
				"radius": 42.0,
				"dir": -1.0,
				"start_angle": -PI * 0.5,
				"badge_pos": Vector2(46.0, 118.0),
			},
			{
				"index": 1,
				"kind": &"connect",
				"tag": "2 · CONNECT TERMINALS",
				"short": "Terminals",
				"prompt": "Click matching ▲A and ■B ceramic insulator terminals.",
				"badge_pos": Vector2(218.0, 28.0),
				"pairs": [
					{
						"pair_id": &"A",
						"shape": &"triangle",
						"label": "A",
						"a": Vector2(246.0, 66.0),
						"b": Vector2(304.0, 72.0),
					},
					{
						"pair_id": &"B",
						"shape": &"square",
						"label": "B",
						"a": Vector2(346.0, 84.0),
						"b": Vector2(394.0, 96.0),
					},
				],
			},
			{
				"index": 2,
				"kind": &"trace",
				"tag": "3 · DRAW BELLOWS",
				"short": "Bellows Trace",
				"prompt": "Trace the pleated bellows seam from bottom to top.",
				"badge_pos": Vector2(336.0, 212.0),
				"points": [
					Vector2(278.0, 218.0),
					Vector2(298.0, 190.0),
					Vector2(322.0, 164.0),
					Vector2(340.0, 124.0),
				],
			},
		],
	},
	"cone": {
		"id": &"cone",
		"title": "Heat Bellows",
		"accent": Color("f2985a"),
		"glb": "res://assets/equipment/heat_bellows.glb",
		"cam_pos": Vector3(0.0, 1.15, 1.45),
		"cam_target": Vector3(0.0, 0.0, 0.0),
		"cam_size": 0.68,
		"model_pos": Vector3(0.10, -0.03, -0.08),
		"model_rot_deg": Vector3(6.0, 112.0, -4.0),
		"open_cover_and_grille": true,
		"operations": [
			{
				"index": 0,
				"kind": &"spin",
				"tag": "1 · SPIN FAN",
				"short": "Fan Spin",
				"prompt": "With the rear fan cover open, spin the intake fan.",
				"center": Vector2(412.0, 116.0),
				"radius": 38.0,
				"dir": 1.0,
				"start_angle": -PI * 0.6,
				"badge_pos": Vector2(368.0, 168.0),
			},
			{
				"index": 1,
				"kind": &"trace",
				"tag": "2 · TRACE LEATHER",
				"short": "Leather Trace",
				"prompt": "Trace across the leather bellows stitch seams in order.",
				"badge_pos": Vector2(216.0, 178.0),
				"points": [
					Vector2(226.0, 112.0),
					Vector2(294.0, 106.0),
					Vector2(232.0, 148.0),
					Vector2(298.0, 142.0),
				],
			},
			{
				"index": 2,
				"kind": &"connect",
				"tag": "3 · COIL CONTACTS",
				"short": "Coil Contacts",
				"prompt": "With the front grille open, click matching ▲A and ■B heating coils.",
				"badge_pos": Vector2(56.0, 82.0),
				"pairs": [
					{
						"pair_id": &"A",
						"shape": &"triangle",
						"label": "A",
						"a": Vector2(92.0, 136.0),
						"b": Vector2(154.0, 144.0),
					},
					{
						"pair_id": &"B",
						"shape": &"square",
						"label": "B",
						"a": Vector2(92.0, 178.0),
						"b": Vector2(154.0, 186.0),
					},
				],
			},
		],
	},
	"clock": {
		"id": &"clock",
		"title": "Time Device",
		"accent": Color("b88cf2"),
		"glb": "res://assets/equipment/time_device.glb",
		"cam_pos": Vector3(0.0, 1.05, 1.35),
		"cam_target": Vector3(0.0, 0.0, 0.0),
		"cam_size": 0.44,
		"model_pos": Vector3(-0.11, -0.09, -0.02),
		"model_rot_deg": Vector3(6.0, 148.0, 0.0),
		"operations": [
			{
				"index": 0,
				"kind": &"spin",
				"tag": "1 · SPIN KEY",
				"short": "Key Spin",
				"prompt": "Drag around the brass side key to wind the mainspring.",
				"center": Vector2(368.0, 158.0),
				"radius": 36.0,
				"dir": 1.0,
				"start_angle": -PI * 0.65,
				"badge_pos": Vector2(342.0, 92.0),
			},
			{
				"index": 1,
				"kind": &"trace",
				"tag": "2 · TRACE PENDULUM",
				"short": "Pendulum Trace",
				"prompt": "Trace along the metronome scale and pendulum rod.",
				"badge_pos": Vector2(288.0, 34.0),
				"points": [
					Vector2(256.0, 132.0),
					Vector2(260.0, 98.0),
					Vector2(264.0, 62.0),
					Vector2(286.0, 94.0),
				],
			},
			{
				"index": 2,
				"kind": &"connect",
				"tag": "3 · CASSETTE CONTACTS",
				"short": "Contacts",
				"prompt": "Click matching ▲A and ■B contacts on the cassette plate.",
				"badge_pos": Vector2(46.0, 168.0),
				"pairs": [
					{
						"pair_id": &"A",
						"shape": &"triangle",
						"label": "A",
						"a": Vector2(182.0, 154.0),
						"b": Vector2(282.0, 168.0),
					},
					{
						"pair_id": &"B",
						"shape": &"square",
						"label": "B",
						"a": Vector2(182.0, 198.0),
						"b": Vector2(282.0, 212.0),
					},
				],
			},
		],
	},
}


static func tool_spec(tool: StringName) -> Dictionary:
	var key := String(tool)
	if TOOL_SPECS.has(key):
		return TOOL_SPECS[key]
	return TOOL_SPECS["ring"]


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
	return dist >= maxf(8.0, radius - SPIN_RADIAL_INNER_PAD) and dist <= radius + SPIN_RADIAL_OUTER_PAD


static func spin_step(op: Dictionary, prev_point: Vector2, next_point: Vector2, current_accum: float, locked_dir: float) -> Dictionary:
	var center: Vector2 = op["center"]
	var radius: float = float(op["radius"])
	var min_r := maxf(8.0, radius - SPIN_RADIAL_INNER_PAD)
	var max_r := radius + SPIN_RADIAL_OUTER_PAD
	var samples := maxi(1, ceili(prev_point.distance_to(next_point) / 6.0))
	var accum := current_accum
	var dir := locked_dir
	var last_pt := prev_point
	for i in range(1, samples + 1):
		var pt := prev_point.lerp(next_point, float(i) / float(samples))
		var dist := pt.distance_to(center)
		if dist < min_r or dist > max_r:
			return {
				"ok": false,
				"accum": accum,
				"locked_dir": dir,
				"point": pt,
				"message": "Left the spin ring. Completed checkpoints are safe; drag around the dial.",
			}
		var a0 := (last_pt - center).angle()
		var a1 := (pt - center).angle()
		var delta := wrapf(a1 - a0, -PI, PI)
		if dir == 0.0:
			if absf(delta) > 0.015:
				dir = 1.0 if delta > 0.0 else -1.0
			else:
				last_pt = pt
				continue
		var signed_step := delta * dir
		if signed_step < -0.35:
			return {
				"ok": false,
				"accum": accum,
				"locked_dir": dir,
				"point": pt,
				"message": "Reversed spin direction. Keep turning smoothly in one direction.",
			}
		accum = maxf(0.0, accum + signed_step)
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
