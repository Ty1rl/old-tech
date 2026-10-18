extends RefCounted

# A single batched surface for light and moving air. This changes presentation,
# not hit tests, damage, projectile speed or the world/real-time policy.
const Tuning = preload("res://scenes/prototype/tuning.gd")
var mesh := ImmediateMesh.new()
var phase := 0.0
var vertices := 0
var last_beam_start := Vector3.ZERO
var last_air_origin := Vector3.ZERO


func attach(parent: Node3D) -> void:
	var node := MeshInstance3D.new()
	node.name = "WeaponLightAndAir"
	node.mesh = mesh
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * smoothstep(0.0, 0.25, UV.x) * smoothstep(0.0, 0.25, 1.0-UV.x);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	node.material_override = material
	parent.add_child(node)


static func muzzle(player: Node3D, index: int) -> Vector3:
	if player == null: return Vector3.ZERO
	var visual: Variant = player.get("visual")
	if is_instance_valid(visual) and visual.has_method("muzzle_position"):
		return visual.muzzle_position(index)
	return Vector3(player.global_position.x, .8, player.global_position.z)


func reset() -> void:
	phase = 0
	mesh.clear_surfaces()
	vertices = 0


func rebuild(weapons: Node3D, player: Node3D, aim: Vector3) -> void:
	mesh.clear_surfaces()
	vertices = 0
	if weapons.beam_pulses.is_empty() and weapons.beam_flash_timer <= 0 and not weapons.beam_charging and not weapons.cone_active:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if weapons.selected_tool == 2 and weapons.beam_charging and player != null:
		var source := muzzle(player, 2)
		var direction := Vector3(aim.x-player.global_position.x, 0, aim.z-player.global_position.z).normalized()
		light(source, source + direction * lerpf(.35, 1.4, weapons.beam_charge), weapons.beam_charge, .6)
	for pulse: Dictionary in weapons.beam_pulses:
		var source: Vector3 = pulse.get("muzzle", Vector3(pulse.pos.x, 1.2, pulse.pos.z))
		var head := Vector3(pulse.pos.x, source.y, pulse.pos.z)
		# The collision pulse begins at the player root. Don't draw a backwards
		# flash during its first few centimetres behind the visible lens.
		var direction := Vector3(pulse.dir.x, 0, pulse.dir.y)
		if (head-source).dot(direction) > 0:
			light(source, head, pulse.charge, .85)
	if weapons.beam_flash_timer > 0 and weapons.beam_pulses.is_empty():
		var source: Vector3 = weapons.beam_visual_origin
		var end := Vector3(weapons.beam_end.x, source.y, weapons.beam_end.z)
		light(source, end, .7, clampf(weapons.beam_flash_timer/.14,0,1))
	if weapons.selected_tool == 3 and weapons.cone_active and player != null:
		air(weapons, player)
	# ImmediateMesh rejects an empty surface (e.g. a pulse still inside the gun).
	if vertices == 0: ribbon(Vector3.ZERO, Vector3(.001,0,0), .001, Color(0,0,0,0))
	mesh.surface_end()


func light(start: Vector3, end: Vector3, charge: float, alpha: float) -> void:
	last_beam_start = start
	ribbon(start, end, lerpf(.10,.20,charge), Color(1,.76,.2,.18*alpha))
	ribbon(start, end, lerpf(.025,.055,charge), Color(1,.99,.8,.95*alpha))
	# A small cross at the emitting lens reads as light rather than a bullet.
	ribbon(start-Vector3(.09,0,0),start+Vector3(.09,0,0),.025,Color(1,.96,.6,alpha))


func air(weapons: Node3D, player: Node3D) -> void:
	var source := muzzle(player,3)
	var player_ground := Vector3(player.global_position.x,0,player.global_position.z)
	var source_ground := Vector3(source.x,0,source.z)
	if weapons.cover != null:
		var blocked: Dictionary = weapons.cover.clip_segment(player_ground,source_ground)
		if blocked.blocked: return # Don't render wind emerging beyond a wall.
	last_air_origin = source
	var forward := Vector3(weapons.cone_forward.x,0,weapons.cone_forward.y)
	var right := Vector3(-forward.z,0,forward.x)
	var far := player_ground + forward * float(Tuning.CONE.range)
	far.y = source.y
	var spread := float(Tuning.CONE.range) * sin(float(Tuning.CONE.half_angle))
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
			point = clip_air(weapons, source, point)
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
			point = clip_air(weapons,source,point)
			ribbon(previous,point,.025,Color(.72,.88,1,.24*(1-t)))
			previous = point
	# Warm nozzle accent preserves orange tool identity without an opaque wedge.
	ribbon(source,source+forward*.3,.12,Color(1,.58,.2,.4))


func clip_air(weapons: Node3D, start: Vector3, end: Vector3) -> Vector3:
	if weapons.cover == null: return end
	var hit: Dictionary = weapons.cover.clip_segment(start,end)
	return start.lerp(end,float(hit.fraction)) if hit.blocked else end


func ribbon(start: Vector3, end: Vector3, width: float, color: Color) -> void:
	var direction := end-start
	var side := direction.cross(Vector3.UP).normalized()
	if side.length_squared() < .001: side = Vector3.RIGHT
	side *= width
	var points := [start-side,start+side,end-side,start+side,end+side,end-side]
	var uvs := [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for index in range(points.size()):
		mesh.surface_set_color(color)
		mesh.surface_set_uv(uvs[index])
		mesh.surface_add_vertex(points[index])
		vertices += 1
