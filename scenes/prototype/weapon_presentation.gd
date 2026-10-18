class_name WeaponPresentation
extends MeshInstance3D

# A single batched surface for light and moving air. This changes presentation,
# not hit tests, damage, projectile speed or the world/real-time policy.
const CoverGeometry = preload("res://scenes/prototype/cover.gd")
var batch := ImmediateMesh.new()
var phase := 0.0
var vertices := 0
var last_beam_start := Vector3.ZERO
var last_air_origin := Vector3.ZERO
var charge_glow_radius := 0.0
var pierce_ready := false
const STROKE_DEVIATION := 0.04 # 1/10 cutter radius, well below cut tolerance.


# Conservative broad phase: only sweep against cover near these points. Include
# the entire bend and smoothing deviation, so this never skips a possible hit.
static func _near_cover(a: Vector3, b: Vector3, c: Vector3, cover: CoverGeometry, padding: float) -> bool:
	var bounds := Rect2(Vector2(a.x,a.z), Vector2.ZERO).expand(Vector2(b.x,b.z)).expand(Vector2(c.x,c.z)).grow(padding + 0.0001)
	for rectangle: Rect2 in cover.rectangles:
		if bounds.intersects(rectangle, true): return true
	return false


static func stroke_display(raw: Array[Vector3], cover: CoverGeometry = null, radius: float = 0.4) -> Array[Vector3]:
	var shown: Array[Vector3] = raw.duplicate()
	for i in range(1, raw.size() - 1):
		var incoming := raw[i] - raw[i - 1]
		var outgoing := raw[i + 1] - raw[i]
		if incoming.length_squared() < 0.000001 or outgoing.length_squared() < 0.000001: continue
		# Pin deliberate turns; endpoints and duplicates are never moved.
		if incoming.normalized().dot(outgoing.normalized()) < cos(deg_to_rad(30)): continue
		var target := (raw[i - 1] + raw[i] * 2 + raw[i + 1]) * 0.25
		var candidate := raw[i] + (target - raw[i]).limit_length(STROKE_DEVIATION)
		if cover != null and _near_cover(raw[i-1],raw[i],raw[i+1],cover,radius+STROKE_DEVIATION):
			var blocked := false
			for pair in [[raw[i - 1], raw[i]], [raw[i], raw[i + 1]], [raw[i - 1], candidate], [candidate, raw[i + 1]]]:
				if cover.clip_segment(pair[0], pair[1], radius).blocked:
					blocked = true
					break
			if blocked: continue
		shown[i] = candidate
	# Test the combined moved edge too, so adjacent changes cannot round cover.
	if cover != null:
		for i in range(raw.size() - 1):
			if _near_cover(shown[i],shown[i+1],shown[i+1],cover,radius) and cover.clip_segment(shown[i], shown[i + 1], radius).blocked:
				shown[i] = raw[i]
				shown[i + 1] = raw[i + 1]
	return shown


func _ready() -> void:
	mesh = batch


func reset() -> void:
	phase = 0
	batch.clear_surfaces()
	vertices = 0
	charge_glow_radius = 0
	pierce_ready = false


func rebuild(flash: FocusedFlash, bellows: HeatBellows, overlay: Dictionary, player_ground: Vector3, flash_muzzle: Vector3, air_muzzle: Vector3, view_basis: Basis) -> void:
	batch.clear_surfaces()
	vertices = 0
	charge_glow_radius = 0
	pierce_ready = false
	var tool := int(overlay.tool)
	var charging := bool(overlay.charging)
	var charge := float(overlay.charge)
	var blowing := bool(overlay.air)
	pierce_ready = charging and bool(overlay.get("ready", charge >= flash.settings.pierce_threshold))
	if flash.pulses.is_empty() and flash.flash_timer <= 0 and not charging and not blowing:
		return
	batch.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if tool == 2 and charging :
		var source := flash_muzzle
		last_beam_start = source
		charge_glow_radius = lerpf(.06,.24,charge)
		# A growing halo on the aperture, with no forward beam until release.
		var right := view_basis.x.normalized()
		var up := view_basis.y.normalized()
		for index in range(16):
			var a := TAU * float(index)/16
			var b := TAU * float(index+1)/16
			var start := source + (right*cos(a)+up*sin(a))*charge_glow_radius
			var end := source + (right*cos(b)+up*sin(b))*charge_glow_radius
			for point in [source,start,end]:
				batch.surface_set_color(Color(1,.95,.65,(.35+.6*charge) if point == source else 0))
				batch.surface_set_uv(Vector2(.5,.5))
				batch.surface_add_vertex(point)
				vertices += 1
			ribbon(start,end,.045,Color(1,.85,.3,.3+charge*.6))
		ribbon(source-right*.045,source+right*.045,.04,Color(1,.98,.75,.45+charge*.5))
		if pierce_ready:
			# Four bright aperture ticks lock on at ready; no forward sight line.
			for axis in [right, -right, up, -up]:
				ribbon(source + axis * .25, source + axis * .31, .025, Color(1, 1, .8, .95))
	for pulse: Dictionary in flash.pulses:
		var source: Vector3 = pulse.get("muzzle", Vector3(pulse.pos.x, 1.2, pulse.pos.z))
		var head := Vector3(pulse.pos.x, source.y, pulse.pos.z)
		# The collision pulse begins at the player root. Don't draw a backwards
		# flash during its first few centimetres behind the visible lens.
		var direction := Vector3(pulse.dir.x, 0, pulse.dir.y)
		if (head-source).dot(direction) > 0:
			light(source, head, pulse.charge, .85)
	if flash.flash_timer > 0 and flash.pulses.is_empty():
		var source: Vector3 = flash.visual_origin
		var end := Vector3(flash.end_point.x, source.y, flash.end_point.z)
		light(source, end, flash.flash_charge, clampf(flash.flash_timer/.14,0,1))
	if tool == 3 and blowing :
		air(bellows, player_ground, air_muzzle)
		cone_footprint(bellows, player_ground)
	# ImmediateMesh rejects an empty surface (e.g. a pulse still inside the gun).
	if vertices == 0: ribbon(Vector3.ZERO, Vector3(.001,0,0), .001, Color(0,0,0,0))
	batch.surface_end()


func light(start: Vector3, end: Vector3, charge: float, alpha: float) -> void:
	last_beam_start = start
	ribbon(start, end, lerpf(.10,.20,charge), Color(1,.76,.2,.18*alpha))
	ribbon(start, end, lerpf(.025,.055,charge), Color(1,.99,.8,.95*alpha))
	# A small cross at the emitting lens reads as light rather than a bullet.
	ribbon(start-Vector3(.09,0,0),start+Vector3(.09,0,0),.025,Color(1,.96,.6,alpha))


func air(bellows: HeatBellows, player_ground: Vector3, source: Vector3) -> void:
	var source_ground := Vector3(source.x,0,source.z)
	if bellows.cover != null:
		var blocked: Dictionary = bellows.cover.clip_segment(player_ground,source_ground)
		if blocked.blocked: return # Don't render wind emerging beyond a wall.
	last_air_origin = source
	var forward := Vector3(bellows.forward.x,0,bellows.forward.y)
	var right := Vector3(-forward.z,0,forward.x)
	var far := player_ground + forward * bellows.settings.range
	far.y = source.y
	var spread := bellows.settings.range * sin(bellows.settings.half_angle)
	# Soft curved wisps stream outward; no particle objects or RNG/state
	# copies. Their speed follows world time, so time slow visibly slows the air.
	for lane in range(9):
		var side := float(lane-4)/4
		var progress := fposmod(phase*1.4 + float(lane)*.17,1)
		var previous := source
		for sample in range(6):
			var t := clampf(progress + float(sample)*.04,0,1)
			var point := source.lerp(far,t) + right*(side*spread*t + sin(t*10+lane)*.08)
			point.y += sin(t*9 + float(lane))* .09*t
			point = clip_air(bellows, source, point)
			if sample > 0:
				ribbon(previous,point,.11+.05*t,Color(.8,.94,1,.17*(1-t)))
				ribbon(previous,point,.035,Color(.86,.96,1,.65*(1-t)))
			previous = point
	# Expanding cross-section arcs make the blast feel like displaced air.
	for index in range(3):
		var t := fposmod(phase*.9 + float(index)/3,1)
		var center := source.lerp(far,t)
		var width := spread*t
		var previous := center + right*width
		for segment in range(1,17):
			var angle := TAU*float(segment)/16
			var point := center + right*(cos(angle)*width) + Vector3.UP*sin(angle)*(.12+width*.17)
			point = clip_air(bellows,source,point)
			ribbon(previous,point,.025,Color(.72,.88,1,.24*(1-t)))
			previous = point
	# Warm nozzle accent preserves orange tool identity without an opaque wedge.
	ribbon(source,source+forward*.3,.12,Color(1,.58,.2,.4))


func cone_footprint(bellows: HeatBellows, ground: Vector3) -> void:
	# The old faint floor range cue shares the light/air batch; collision still
	# uses the component's actual range, angle and cover geometry.
	var origin := Vector3(ground.x, .08, ground.z)
	var angle := bellows.forward.angle()
	for i in range(18):
		var a := angle - bellows.settings.half_angle + 2 * bellows.settings.half_angle * i / 18.0
		var b := angle - bellows.settings.half_angle + 2 * bellows.settings.half_angle * (i + 1) / 18.0
		var end_a := clip_air(bellows, origin, origin + Vector3(cos(a), 0, sin(a)) * bellows.settings.range)
		var end_b := clip_air(bellows, origin, origin + Vector3(cos(b), 0, sin(b)) * bellows.settings.range)
		for point: Vector3 in [origin, end_a, end_b]:
			batch.surface_set_color(Color(1, .58, .22, .055))
			batch.surface_set_uv(Vector2(.5, .5))
			batch.surface_add_vertex(point)
			vertices += 1


func clip_air(bellows: HeatBellows, start: Vector3, end: Vector3) -> Vector3:
	if bellows.cover == null: return end
	var hit: Dictionary = bellows.cover.clip_segment(start,end)
	return start.lerp(end,float(hit.fraction)) if hit.blocked else end


func ribbon(start: Vector3, end: Vector3, width: float, color: Color) -> void:
	var direction := end-start
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() < .001: side = Vector3.RIGHT
	side *= width
	var points := [start-side,start+side,end-side,start+side,end+side,end-side]
	var uvs := [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for index in range(points.size()):
		batch.surface_set_color(color)
		batch.surface_set_uv(uvs[index])
		batch.surface_add_vertex(points[index])
		vertices += 1
