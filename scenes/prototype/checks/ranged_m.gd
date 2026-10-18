extends SceneTree

const Director = preload("res://scenes/prototype/enemies.gd")
const Feedback = preload("res://scenes/prototype/combat_feedback.gd")
var checks := 0
var failures: Array[String] = []
var director: Node3D
var player: Node3D
var cues: Array[StringName] = []
var metrics := {}

class PlayerProbe extends Node3D:
	var health := 100.0
	func take_damage(amount: float) -> void: health = maxf(0, health - maxf(0, amount))


func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func fresh() -> void:
	director.clear()
	director.cover.set_rectangles([])
	player.position = Vector3.ZERO
	player.health = 100
	cues.clear()


func values_only(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal: return false
	if value is Array:
		for item in value:
			if not values_only(item): return false
	if value is Dictionary:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true


func fly(dt: float, duration: float, lateral_speed: float = 0) -> void:
	for i in range(int(ceil(duration / dt))):
		player.position.x += lateral_speed * dt
		director._step_projectiles(dt, player)


func run() -> void:
	director = Director.new()
	root.add_child(director)
	director.cover = preload("res://scenes/prototype/cover.gd").new()
	player = PlayerProbe.new()
	root.add_child(player)
	director.combat_event.connect(func(kind, _point, _strength): cues.append(kind))
	fresh()
	var shooter: Node3D = director.spawn(&"ranged", Vector3(0, 0, -8))
	director.step(.01, player)
	var aim: Vector3 = shooter.ranged_aim
	expect(shooter.attack_phase == &"windup" and shooter.ranged_warning.visible, "shooter has a visible pre-impact warning")
	expect(cues.count(&"hostile_warning") == 1, "windup cue is emitted once")
	expect(shooter.ranged_lens.global_position.distance_to(shooter.projectile_origin(aim)) < .001, "visible muzzle and emitted origin agree")
	var windup: Dictionary = director.capture_state()
	player.position.x = 3
	director.step(.5, player)
	expect(shooter.ranged_aim == aim and director.projectiles.is_empty(), "shooter never tracks the player's dodge after warning")
	var warning_left: float = shooter.attack_timer
	director.step(0, player)
	expect(shooter.attack_timer == warning_left, "freeze preserves warning and launches no shot")
	director.step(.46, player)
	expect(director.projectiles.size() == 1 and shooter.attack_phase == &"recover", "windup releases exactly one shot into recovery")
	var shot: Dictionary = director.projectiles[0]
	expect(shot.owner_id == shooter.combat_id() and shot.position == shooter.projectile_origin(aim), "emission carries stable owner ID and authoritative origin")
	expect(is_equal_approx(shot.radius, .24) and is_equal_approx(director._projectile_visuals[0].mesh.size.x, 2 * shot.radius), "visible head diameter equals collision diameter")
	expect(cues.count(&"hostile_fire") == 1, "release has one semantic cue")
	var start: Vector3 = shot.position
	director._step_projectiles(.1 * .18, player)
	expect(is_equal_approx(start.distance_to(director.projectiles[0].position), 7.5 * .018), "slow time drives the same velocity for flight and visuals")
	var flying: Dictionary = director.capture_state()
	expect(values_only(flying), "in-flight projectile snapshot contains values only")
	var visual_position: Vector3 = director._projectile_visuals[0].position
	director.step(0, player)
	expect(director.capture_state() == flying and director._projectile_visuals[0].position == visual_position, "freeze fixes both flight state and head location")
	director._step_projectiles(.2, player)
	director.restore_state(flying)
	expect(director.capture_state() == flying and director._projectile_visuals[0].position == flying.projectiles[0].position, "rewind restores radius, owner, age, flight and visuals exactly")
	var cue_count := cues.size()
	director.restore_state(windup)
	expect(cues.size() == cue_count and director.projectiles.is_empty() and shooter.ranged_warning.visible, "restoring windup redraws warning without replaying release/audio")
	# A human-scale delayed sidestep, using only ordinary movement speed.
	for dt: float in [1.0 / 30, 1.0 / 60, 1.0 / 240]:
		fresh()
		director.launch_projectile(Vector3(0, 1, -6), Vector3.BACK, 10, 7.5)
		fly(dt, .25)
		fly(dt, 1.0, 6.0)
		expect(player.health == 100, "reaction delay plus ordinary lateral movement dodges shot at dt " + str(dt))
	fresh()
	director.launch_projectile(Vector3(0, 1, -6), Vector3.BACK, 10)
	fly(1.0 / 60, 1.0)
	expect(player.health == 90 and cues.count(&"player_hurt") == 1, "standing in the actual path deals one visible/audible damage cue")
	fresh()
	director.cover.set_rectangles([Rect2(-2, -4, 4, 1)])
	director.launch_projectile(Vector3(0, 1, -6), Vector3.BACK, 10)
	director._step_projectiles(1, player)
	expect(player.health == 100 and director.projectiles.is_empty(), "cover sweep absorbs projectile before player without tunneling")
	fresh()
	director.cover.set_rectangles([Rect2(-2, 1, 4, 1)])
	director.launch_projectile(Vector3(0, 1, -4), Vector3.BACK, 10)
	director._step_projectiles(1, player)
	expect(player.health == 90, "cover behind the player cannot absorb an earlier body entry")
	fresh()
	director.cover.set_rectangles([Rect2(-1, -1, 2, 2)])
	director.launch_projectile(Vector3(0, 1, 0), Vector3.BACK, 10)
	director._step_projectiles(.01, player)
	expect(player.health == 100 and director.projectiles.is_empty(), "overlapping cover wins a zero-time body-entry tie")
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -6))
	director.cover.set_rectangles([Rect2(-1, -5.5, 2, .3)])
	expect(not director.launch_projectile(shooter.projectile_origin(Vector3.BACK), Vector3.BACK, 10, 7.5, shooter.combat_id()), "an emitter cannot launch through cover between body and muzzle")
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -6))
	director.launch_projectile(shooter.projectile_origin(Vector3.BACK), Vector3.BACK, 10, 7.5, shooter.combat_id())
	var alive_snapshot: Dictionary = director.capture_state()
	shooter.health = 0
	director.step(.8, player)
	expect(player.health == 100 and director.projectiles.is_empty() and director.enemies.is_empty(), "killing the final emitter prevents a late quiet-room hit")
	director.restore_state(alive_snapshot)
	shooter = director.enemies[0]
	expect(director.projectiles.size() == 1 and director.projectiles[0].owner_id == shooter.combat_id(), "rewind revives owner and its in-flight shot together")
	director.clear()
	director._step_projectiles(10, player)
	expect(player.health == 100 and director._trail_mesh.get_surface_count() == 0, "room clear/retry removes all hostile heads and trails")
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -6))
	shooter.health = 0
	shooter.attack_phase = &"windup"
	shooter.attack_timer = .01
	shooter._step_ranged(1, player, 6)
	expect(director.projectiles.is_empty(), "dead shooter cannot finish its queued release")
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -6))
	shooter.attack_phase = &"windup"
	shooter.attack_timer = .01
	player.health = 0
	director.step(1, player)
	expect(director.projectiles.is_empty(), "dead player cannot trigger a late enemy release")
	fresh()
	player.health = 5
	for i in range(3): director.launch_projectile(Vector3(0, 1, -1.5), Vector3.BACK, 10)
	director._step_projectiles(.2, player)
	expect(player.health == 0 and director.projectiles.is_empty() and cues.count(&"player_hurt") == 1, "lethal impact clears remaining flight and emits one damage cue")
	# Boss warning lanes, committed fan and roomy movement-only gaps.
	for kind: StringName in [&"sequence_boss", &"final_boss"]:
		fresh()
		var boss: Node3D = director.spawn(kind, Vector3(0, 0, -8))
		boss.facing = Vector3.BACK
		boss._step_part_attack(.01, player, 8)
		var directions: Array[Vector3] = boss.hostile_shot_directions()
		var boss_windup: Dictionary = director.capture_state()
		expect(boss.ranged_warning.visible and directions.size() == 3, "boss marks its three actual shot lanes " + String(kind))
		player.position = boss.position + Vector3.BACK.rotated(Vector3.UP, .39) * 3.2
		boss._step_part_attack(.6, player, 3.2)
		expect(boss.hostile_shot_directions() == directions, "boss fan remains fixed after player dodge " + String(kind))
		boss._step_part_attack(.51, player, 3.2)
		boss._step_part_attack(.19, player, 3.2)
		expect(director.projectiles.size() == 3 and boss.attack_phase == &"recover" and boss.attack_timer >= 2, "boss emits a finite fan then grants recovery " + String(kind))
		var anchors_agree := true
		for i in range(3):
			anchors_agree = anchors_agree and director.projectiles[i].position == boss.projectile_origin(directions[i]) and director.projectiles[i].velocity.normalized().distance_to(directions[i]) < .001
		expect(anchors_agree, "fan lanes and emitted positions/directions agree " + String(kind))
		fly(1.0 / 120, 2)
		expect(player.health == 100, "ordinary player fits gap at 3.2m with no defense ability " + String(kind))
		var clear_gap := 2 * 3.2 * sin(.39) - 2 * Director.PROJECTILE_RADIUS
		metrics["boss_clear_gap_m"] = clear_gap
		expect(clear_gap > 1.6, "boss gap leaves substantial margin beyond a 1m player")
		director.restore_state(boss_windup)
		boss = director.enemies[0]
		expect(boss.hostile_shot_directions() == directions and boss.ranged_warning.visible, "rewind restores committed boss fan and warning " + String(kind))
		boss.health = 0
		boss.attack_phase = &"commit"
		boss.attack_timer = .01
		boss._step_part_attack(1, player, 3)
		expect(director.projectiles.is_empty(), "dead boss cannot emit its pending fan " + String(kind))
	fresh()
	var boss: Node3D = director.spawn(&"final_boss", Vector3(0, 0, -8))
	for phase in [1, 3]:
		boss.debug_set_phase(phase)
		boss.attack_phase = &"approach"
		boss.facing = Vector3.BACK
		boss._step_part_attack(.01, player, 8)
		expect(boss.hostile_shot_directions().size() == 3, "zigzag/final-core phases retain readable fan API " + str(phase))
	# Limits and feedback lifecycle use existing bounded resources.
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -10))
	for i in range(20): director.launch_projectile(shooter.projectile_origin(Vector3.BACK), Vector3.BACK, 10, 7.5, shooter.combat_id())
	expect(director.projectiles.size() == Director.MAX_OWNER_PROJECTILES, "per-emitter cap prevents a single actor flooding the room")
	director.clear()
	for i in range(40): director.launch_projectile(Vector3(0, 1, -10), Vector3.RIGHT, 10)
	expect(director.projectiles.size() == 24 and director._projectile_visuals.size() == 24, "global shot and visual pool cap remains 24")
	var encoded: PackedByteArray = var_to_bytes(director.capture_state())
	expect(values_only(director.capture_state()) and encoded.size() < 16384, "full projectile pool stays value-only and compact")
	metrics["full_pool_bytes"] = encoded.size()
	director._step_projectiles(7, null)
	expect(director.projectiles.is_empty() and director._trail_mesh.get_surface_count() == 0, "all flight/trails expire in bounded world time")
	var feedback: Node3D = Feedback.new()
	root.add_child(feedback)
	feedback.muted = false
	feedback.cue(&"player_hurt", Vector3.ZERO, 1)
	var audible := false
	for voice in feedback._voices: audible = audible or voice.pending
	expect(audible and feedback._effects[-1].color.r > feedback._effects[-1].color.g * 2, "player damage queues sound and warm red impact ring")
	expect(feedback.samples.size() == 13 and feedback._effects[-1].life >= .45, "damage cue reuses original sample bank with readable visual duration")
	feedback.reset_state()
	feedback.queue_free()
	director.queue_free()
	player.queue_free()
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures, "metrics":metrics}))
	quit(0 if failures.is_empty() else 1)
