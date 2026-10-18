extends SceneTree
# Consumer checks against the frozen N1 API. CombatPlayer is supplied by jam-8;
# this health-free probe implements only that boundary and uses the real core.
const Director = preload("res://scenes/prototype/enemies.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
var checks := 0
var failures: Array[String] = []
var director: Node3D
var player: PlayerProbe
var controller: TimeController
var emergency: EmergencyRewind
var cues: Array[StringName] = []
var impact_present: Dictionary = {}
var depletion_events := 0

class PlayerProbe extends Node3D:
	var time_controller: TimeController
	var hits: Array[float] = []
	var can_act: bool:
		get: return not time_controller.emergency_active and not time_controller.exhausted
	func take_damage(amount: float) -> void:
		hits.append(amount)
		time_controller.apply_hit(amount)

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)

func fresh(meter := 100.0) -> void:
	director.clear()
	director.cover.set_rectangles([])
	emergency.history.clear()
	controller.begin_attempt()
	controller.try_spend(controller.capacity - meter)
	player.hits.clear()
	player.position = Vector3.ZERO
	cues.clear()
	impact_present = {}
	depletion_events = 0

func shot(position := Vector3(0, 1, -2), cost := 10.0, direction := Vector3.BACK) -> void:
	expect(director.launch_projectile(position, direction, cost), "launch bounded explicit-cost projectile")

func values_only(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal: return false
	if value is Array:
		for item in value:
			if not values_only(item): return false
	if value is Dictionary:
		for key in value:
			if not values_only(key) or not values_only(value[key]): return false
	return true

func run() -> void:
	controller = TimeController.new()
	controller.auto_advance = false
	controller.settings = controller.settings.duplicate()
	root.add_child(controller)
	player = PlayerProbe.new()
	player.time_controller = controller
	root.add_child(player)
	director = Director.new()
	director.cover = Cover.new()
	root.add_child(director)
	director.combat_event.connect(func(kind, _point, _strength): cues.append(kind))
	emergency = EmergencyRewind.new()
	emergency.time_controller = controller
	emergency.capture_present = director.capture_state
	emergency.history = ReplayHistory.from_settings(controller.settings)
	root.add_child(emergency)
	emergency.selection_changed.connect(func(_index, _age, state):
		impact_present = state.duplicate(true)
		director.restore_state(state))
	emergency.confirmed.connect(func(_age, state): director.restore_state(state))
	controller.emergency_started.connect(func(_charges): depletion_events += 1)

	fresh()
	shot()
	director._step_projectiles(.3, player)
	expect(controller.meter == 90 and player.hits == [10.0], "projectile passes explicit base cost to the single time authority")
	expect(cues.count(&"player_hurt") == 1 and director.projectiles.is_empty(), "one impact consumes one shot and emits one cue")
	director._step_projectiles(1, player)
	expect(controller.meter == 90 and player.hits.size() == 1, "consumed shot cannot spend time twice")
	fresh()
	controller.settings.hit_multiplier = 2
	shot(Vector3(0, 1, -2), 7)
	director._step_projectiles(.3, player)
	expect(controller.meter == 86 and player.hits == [7.0], "caller preserves base cost; TimeSettings applies the multiplier once")
	controller.settings.hit_multiplier = 1
	fresh()
	shot(Vector3(0, 1, -8), 150)
	var expensive: Dictionary = director.capture_state()
	director.restore_state(expensive)
	expect(director.projectiles[0].damage == 150, "rewind retains explicit time costs above obsolete health cap")

	# Swept cover ordering and normal movement remain the defense.
	fresh()
	director.cover.set_rectangles([Rect2(-2, -4, 4, 1)])
	shot(Vector3(0, 1, -6))
	director._step_projectiles(1, player)
	expect(controller.meter == 100 and director.projectiles.is_empty(), "cover blocks before the player without tunneling")
	fresh()
	director.cover.set_rectangles([Rect2(-2, 1, 4, 1)])
	shot()
	director._step_projectiles(1, player)
	expect(controller.meter == 90, "cover behind player cannot shield an earlier hit")
	fresh()
	director.cover.set_rectangles([Rect2(-1, -1, 2, 2)])
	shot(Vector3(0, 1, 0))
	director._step_projectiles(.01, player)
	expect(controller.meter == 100, "cover wins overlapping zero-time collision tie")
	for rate in [30, 60, 240]:
		fresh()
		shot(Vector3(0, 1, -6))
		for frame in range(rate * 2):
			if frame >= int(rate * .25): player.position.x += 6.0 / rate
			director._step_projectiles(1.0 / rate, player)
		expect(controller.meter == 100, "delayed ordinary sidestep dodges at %d Hz" % rate)

	# NOW is captured synchronously during the hit, and restore may happen inside it.
	fresh(5)
	director.encounter_state = &"running"
	director.encounter_active = true
	shot()
	shot(Vector3(4, 1, -6), 12)
	var survivor: Dictionary = director.projectiles[1].duplicate(true)
	director.step(.3, player)
	expect(controller.emergency_active and controller.charges_remaining == 2 and depletion_events == 1, "depleting impact starts exactly one real emergency")
	expect(impact_present.projectiles.size() == 1 and impact_present.projectiles[0] == survivor, "synchronous NOW excludes spent impact and retains untouched remaining flight")
	expect(director.encounter_state == &"running" and director.encounter_active, "emergency is suspended encounter, never defeat")
	var frozen: Dictionary = director.capture_state()
	var visual: Vector3 = director._projectile_visuals[0].position
	for i in range(5):
		director.step(1, player)
		director._step_projectiles(1, player)
	expect(director.capture_state() == frozen and director._projectile_visuals[0].position == visual, "emergency ignores stale nonzero deltas: roster, flow, timers and flight stay frozen")
	expect(player.hits.size() == 1 and depletion_events == 1 and cues.count(&"player_hurt") == 1, "remaining burst cannot repeat depletion or impact cue")
	emergency.confirm()
	expect(player.can_act and controller.meter == controller.settings.recovery_floor and controller.charges_remaining == 2, "NOW confirmation restores flight and recovery without refund")
	shot()
	director._step_projectiles(.3, player)
	expect(controller.meter == controller.settings.recovery_floor and controller.charges_remaining == 2, "recovery grace absorbs a later impact without consuming another charge")
	expect(director.projectiles.size() == 1, "grace consumes only the impacting shot, retaining the other bolt")

	# Several simultaneous impacts must leave the pending burst in the frozen world.
	fresh(5)
	for i in range(3): shot(Vector3(0, 1, -1.5))
	director._step_projectiles(.2, player)
	expect(controller.emergency_active and player.hits.size() == 1 and depletion_events == 1, "overlapping burst depletes exactly once")
	expect(director.projectiles.size() == 2 and impact_present.projectiles.size() == 2, "NOW retains two unprocessed overlapping bolts")
	var pending: Array = director.projectiles.duplicate(true)
	director._step_projectiles(10, player)
	expect(director.projectiles == pending and controller.charges_remaining == 2, "pending simultaneous impacts remain frozen without another charge")
	emergency.confirm()
	director._step_projectiles(.2, player)
	expect(director.projectiles.is_empty() and controller.meter == controller.settings.recovery_floor and controller.charges_remaining == 2, "recovery grace consumes pending burst without another depletion")

	# A hit at voluntarily empty time still opens one emergency, with no fake life.
	fresh(0)
	shot()
	director._step_projectiles(.3, player)
	expect(controller.emergency_active and depletion_events == 1 and controller.charges_remaining == 2, "hit at voluntarily empty meter still depletes once")
	fresh(5)
	controller.settings.charges_per_attempt = 0
	controller.begin_attempt()
	controller.try_spend(95)
	director.encounter_state = &"running"
	director.encounter_active = true
	shot()
	shot(Vector3(4, 1, -6))
	director.step(.3, player)
	expect(controller.exhausted and director.encounter_state == &"defeat" and not director.encounter_active, "only exhausted attempt ends the encounter")
	expect(director.projectiles.is_empty() and player.hits.size() == 1, "exhaustion clears remaining hostile flight and stops further hits")
	var inactive_shooter: Node3D = director.spawn(&"ranged", Vector3(0, 0, -6))
	inactive_shooter.attack_phase = &"windup"
	inactive_shooter.attack_timer = .01
	inactive_shooter._step_ranged(1, player, 6)
	director.step(1, player)
	expect(director.projectiles.is_empty() and inactive_shooter.attack_timer == .01, "exhausted attempt cannot release a queued hostile attack")
	controller.settings.charges_per_attempt = 3

	# Campaign may start the next room attempt synchronously from exhaustion.
	fresh(5)
	controller.settings.charges_per_attempt = 0
	controller.begin_attempt()
	controller.try_spend(95)
	var restart := func():
		director.clear()
		controller.begin_attempt()
		director.launch_projectile(Vector3(4, 1, -8), Vector3.BACK, 10)
	controller.attempt_exhausted.connect(restart, CONNECT_ONE_SHOT)
	shot()
	director.step(.3, player)
	expect(controller.meter == 100 and player.hits.size() == 1, "synchronous retry starts a fresh attempt without a second hit")
	expect(director.projectiles.size() == 1 and director.projectiles[0].position == Vector3(4, 1, -8), "old tick must not advance newly composed retry-room flight")
	controller.settings.charges_per_attempt = 3

	# Native shooter state and snapshots are independent from meter/charges.
	fresh()
	var shooter: Node3D = director.spawn(&"ranged", Vector3(0, 0, -8))
	director.step(.01, player)
	var aim: Vector3 = shooter.ranged_aim
	var windup: Dictionary = director.capture_state()
	player.position.x = 3
	director.step(.5, player)
	expect(shooter.ranged_aim == aim and director.projectiles.is_empty(), "ranged warning retains locked aim")
	var timer: float = shooter.attack_timer
	director.step(0, player)
	expect(shooter.attack_timer == timer, "zero world delta preserves warning")
	director.step(.46, player)
	expect(director.projectiles.size() == 1 and shooter.attack_phase == &"recover", "original windup releases exactly one shot")
	var start: Vector3 = director.projectiles[0].position
	director._step_projectiles(.018, player)
	expect(is_equal_approx(start.distance_to(director.projectiles[0].position), 7.5 * .018), "slow world delta preserves flight velocity")
	var flying: Dictionary = director.capture_state()
	controller.try_spend(25)
	director._step_projectiles(.2, player)
	director.restore_state(flying)
	expect(director.capture_state() == flying and controller.meter == 75, "rewind restores flight exactly without refunding time")
	expect(values_only(flying) and not flying.has("meter") and not flying.has("charges_remaining"), "director snapshots remain world values only")
	controller.apply_hit(100)
	var stopped: Dictionary = director.capture_state()
	shooter.step_enemy(1, player)
	shooter._step_ranged(1, player, 8)
	director.step(1, player)
	expect(director.capture_state() == stopped, "direct shooter calls cannot advance AI or emit during emergency")
	controller.begin_attempt()
	director.restore_state(windup)
	shooter = director.enemies[0]
	shooter.health = 0
	director.step(1, player)
	expect(director.projectiles.is_empty() and director.enemies.is_empty(), "dead owner cannot finish queued release")
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -6))
	expect(director.launch_projectile(shooter.projectile_origin(Vector3.BACK), Vector3.BACK, 10, 7.5, shooter.combat_id()), "owner-bound shot launches")
	var owned: Dictionary = director.capture_state()
	shooter.health = 0
	director.step(.5, player)
	expect(director.projectiles.is_empty() and controller.meter == 100, "owner death removes in-flight threat before collision")
	director.restore_state(owned)
	expect(director.projectiles == owned.projectiles and director.enemies[0].health > 0, "rewind restores owner and its in-flight bolt together")
	director.clear()
	expect(director.projectiles.is_empty() and director._trail_mesh.get_surface_count() == 0, "room clear/retry clears heads and trails")
	fresh()
	shooter = director.spawn(&"ranged", Vector3(0, 0, -6))
	director.cover.set_rectangles([Rect2(-1, -5.5, 2, .3)])
	expect(not director.launch_projectile(shooter.projectile_origin(Vector3.BACK), Vector3.BACK, 10, 7.5, shooter.combat_id()), "cover still blocks body-to-muzzle emission")

	# Contact and windup attacks commit cooldown/recovery before emergency capture.
	fresh(5)
	var swarmer: Node3D = director.spawn(&"swarmer", Vector3.ZERO)
	director.step(.01, player)
	expect(controller.emergency_active and impact_present.enemies[0].contact_cooldown > 0, "contact cooldown is present in synchronous depletion snapshot")
	stopped = director.capture_state()
	director.step(1, player)
	expect(director.capture_state() == stopped and player.hits.size() == 1, "contact emergency freezes enemy movement and repeated hits")
	fresh(5)
	var warden: Node3D = director.spawn(&"blue", Vector3.ZERO)
	warden.attack_phase = &"windup"
	warden.attack_timer = .01
	warden._step_part_attack(.02, player, 0)
	expect(controller.emergency_active and impact_present.enemies[0].attack_phase == "recover", "windup strike commits recovery before synchronous snapshot")
	expect(impact_present.enemies[0].attack_timer > 0, "captured strike retains fair recovery time")
	stopped = director.capture_state()
	warden._step_part_attack(1, player, 0)
	expect(director.capture_state() == stopped, "direct committed strike also respects emergency freeze")

	# Pattern strike and pressure consumers use the same active-player contract.
	fresh(5)
	var boss: Node3D = director.spawn(&"loop_boss", Vector3.ZERO)
	player.position = Vector3(0, 0, -2)
	boss.attack_phase = &"commit"
	boss.attack_timer = .01
	boss.window_timer = 1
	boss._step_part_attack(.02, player, 2)
	expect(controller.emergency_active and player.hits.size() == 1 and cues.count(&"player_hurt") == 1, "loop boss strike spends time once through CombatPlayer boundary")
	expect(impact_present.enemies[0].attack_phase == "recover" and impact_present.enemies[0].attack_timer == 2.3, "boss NOW captures committed recovery before the depleting strike")
	stopped = director.capture_state()
	boss.step_enemy(2, player)
	boss._step_part_attack(2, player, 2)
	expect(director.capture_state() == stopped and player.hits.size() == 1, "direct pattern calls freeze partial window, motion, phase and repeated damage")
	emergency.confirm()
	expect(controller.charges_remaining == 2 and director.enemies[0].attack_phase == &"recover", "boss recovery restore cannot replay the strike or refund its charge")

	fresh()
	director.start_flow(player, 17)
	expect(director.enemies.size() == 3 and director.flow.pressure_active, "pressure schedule starts with three enemies and a health-free player")
	controller.apply_hit(100)
	var pressure: Dictionary = director.flow.capture_state()
	expect(director.flow.next_burst(100, player).is_empty() and director.flow.capture_state() == pressure, "direct pressure query during emergency preserves all schedule state")
	director.step(100, player)
	expect(director.flow.capture_state() == pressure and director.enemies.size() == 3, "emergency director cannot spawn reinforcements or advance cohorts")
	emergency.confirm()
	var resumed: Dictionary = director.flow.next_burst(8, player)
	expect(not resumed.is_empty() and director.flow.pressure_index == 2, "pressure resumes its next burst after recovery")
	controller.settings.charges_per_attempt = 0
	controller.begin_attempt()
	controller.apply_hit(100)
	expect(director.flow.next_burst(100, player).is_empty() and not director.flow.pressure_active, "exhaustion ends pressure instead of suspending it indefinitely")
	controller.settings.charges_per_attempt = 3

	# Choosing recorded flight restores only the world and keeps the spent charge.
	fresh()
	shot(Vector3(0, 1, -6))
	director._step_projectiles(.1, player)
	var recorded_flight: Dictionary = director.capture_state()
	emergency.history.validate_snapshots = true
	expect(emergency.history.push(recorded_flight), "real ReplayHistory accepts value-only director flight")
	controller.try_spend(95)
	shot()
	director._step_projectiles(.3, player)
	expect(emergency.active and emergency.choice_count == 2 and controller.charges_remaining == 2, "depletion offers NOW and previously recorded in-flight world")
	emergency.select(1)
	expect(director.capture_state() == recorded_flight and controller.meter == 0 and controller.charges_remaining == 2, "preview restores exact flight without restoring time or charges")
	emergency.confirm()
	expect(director.capture_state() == recorded_flight and controller.meter == controller.settings.recovery_floor and controller.charges_remaining == 2, "recorded flight commit grants recovery floor while preserving charge spent")

	emergency.queue_free()
	director.queue_free()
	player.queue_free()
	controller.queue_free()
	await process_frame
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
