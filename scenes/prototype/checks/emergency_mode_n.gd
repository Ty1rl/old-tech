extends SceneTree
# Round N Wave2: GameState EMERGENCY mode driven by the real time core.
# Covers pause over an emergency, retry while paused, exit to menu, rebinding and
# a scripted teaching depletion. Uses the autoloads through the root node.

const CORE_SCENE := preload("res://scenes/time/time_core.tscn")

var checks := 0
var failures: Array[String] = []
var counts := {}
var _loop_player: CombatPlayer


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func count(name: String) -> void:
	counts[name] = int(counts.get(name, 0)) + 1


func n(name: String) -> int:
	return int(counts.get(name, 0))


func run() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	var scenes: Node = root.get_node("SceneManager")
	for signal_name in ["emergency_entered", "emergency_exited", "game_started", "game_resumed", "game_paused"]:
		gs.connect(signal_name, count.bind(signal_name))
	var core: Node = CORE_SCENE.instantiate()
	root.add_child(core)
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	t.set_physics_process(false)
	e.history = ReplayHistory.new()
	e.capture_present = func() -> Dictionary: return {"now": true}
	gs.bind_emergency(e)
	gs.start_game()
	counts.clear()

	# Depletion enters EMERGENCY without pausing the tree.
	t.apply_hit(500.0)
	expect(gs.state == gs.State.EMERGENCY and gs.is_in_emergency() and not gs.is_playing(), "Depletion enters EMERGENCY")
	expect(not paused, "EMERGENCY does not pause the tree; frozen via world_scale")
	expect(n("emergency_entered") == 1 and t.charges_remaining == 2, "Entered once; one charge spent")

	# Pause over the emergency and resume back into it.
	expect(gs.toggle_pause() and gs.state == gs.State.PAUSED and paused, "Pause works over an emergency")
	expect(gs.is_in_emergency(), "Still in emergency while paused")
	expect(gs.resume() and gs.state == gs.State.EMERGENCY and not paused, "Resume returns to EMERGENCY, not PLAYING")
	expect(n("emergency_entered") == 1 and n("game_resumed") == 1, "Resume does not re-enter the emergency")

	# Confirm leaves the emergency exactly once without a 'game started'.
	e.confirm()
	expect(gs.state == gs.State.PLAYING and not gs.is_in_emergency(), "Confirm returns to PLAYING")
	expect(n("emergency_exited") == 1 and n("game_started") == 0, "Exited once; not reported as a new game")
	expect(t.charges_remaining == 2, "Mode changes never refund a charge")

	# Retry chosen from the pause menu during an emergency.
	t.advance(2.0)
	t.apply_hit(500.0)
	gs.pause()
	t.begin_attempt() # campaign retry: fresh attempt, session auto-abandons
	expect(not e.active and gs.state == gs.State.PAUSED and not gs.is_in_emergency(), "Retry under pause ends the emergency")
	expect(n("emergency_exited") == 2, "Retry reports the emergency exit once")
	gs.resume()
	expect(gs.state == gs.State.PLAYING and not paused, "Resume after retry returns to PLAYING")
	expect(t.charges_remaining == 3, "New attempt has a fresh charge budget")

	# Exit to the main menu during an emergency.
	t.apply_hit(500.0)
	expect(gs.state == gs.State.EMERGENCY, "Second emergency entered")
	gs.open_menu()
	expect(gs.state == gs.State.MENU and not gs.is_in_emergency() and not paused, "Exit to menu clears emergency mode")
	expect(n("emergency_exited") == 3, "Menu exit reports the emergency exit")
	e.abandon()
	expect(n("emergency_exited") == 3 and gs.state == gs.State.MENU, "Late session end after menu exit changes nothing")

	# begin_emergency only from PLAYING.
	expect(not gs.begin_emergency() and gs.state == gs.State.MENU, "No emergency mode outside PLAYING")

	# Scripted teaching depletion uses the same path and really spends a charge.
	gs.start_game()
	t.begin_attempt()
	t.apply_hit(10.0)
	t.force_depletion()
	e.confirm() # grace now active
	t.advance(0.2)
	var charges_before := t.charges_remaining
	expect(t.protected and t.force_depletion(), "Teaching depletion is not absorbed by recovery grace")
	expect(t.charges_remaining == charges_before - 1 and gs.state == gs.State.EMERGENCY and e.active, "Teaching depletion spends a real charge and opens the real session")
	e.confirm()

	# Rebinding disconnects the previous EmergencyRewind.
	var other := EmergencyRewind.new()
	root.add_child(other)
	gs.bind_emergency(other)
	t.advance(2.0)
	t.apply_hit(500.0)
	expect(e.active and gs.state == gs.State.PLAYING, "Unbound session no longer drives GameState")
	e.confirm()
	gs.bind_emergency(null)
	other.free()

	scenes.clear_popups()
	await mini_arena_loop(gs, t, e)
	gs.open_menu()
	core.free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


# The arena wiring from CONTRACT.md, minus weapons/enemies: a moving CombatPlayer,
# history fed with world time, a real depletion, a choice one second back, restore.
func mini_arena_loop(gs: Node, t: TimeController, e: EmergencyRewind) -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var player := (load("res://scenes/prototype/combat_player.tscn") as PackedScene).instantiate() as CombatPlayer
	root.add_child(player)
	player.time_controller = t
	var history := ReplayHistory.from_settings(t.settings)
	history.validate_snapshots = true
	e.history = history
	var capture := func() -> Dictionary: return {"player": player.capture_state()}
	e.capture_present = capture
	_loop_player = player
	e.confirmed.connect(_on_loop_confirmed)
	gs.bind_emergency(e)
	gs.start_game()
	t.begin_attempt()
	player.reset_state()
	history.clear()
	expect(history.seed_checkpoint(capture.call()), "Room checkpoint seeded after composition")
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	Input.action_press(&"move_right")
	for i in range(60): # two seconds of movement
		await physics_frame
		t.advance(dt)
		player.step(dt, player.global_position + Vector3.RIGHT)
		history.record(dt * t.world_scale, capture)
	Input.action_release(&"move_right")
	var samples := history.snapshot_count
	var x_before_hit := player.global_position.x
	expect(samples >= 23 and samples <= 25 and history.rejected_count == 0, "History records validated value snapshots at 12 Hz of world time (%d)" % samples)
	player.take_damage(1000.0)
	expect(gs.state == gs.State.EMERGENCY and e.active and e.choice_count == samples + 1, "Hit depletion opens NOW + every recorded moment")
	for i in range(15):
		await physics_frame
		t.advance(dt)
		player.step(dt, player.global_position + Vector3.RIGHT)
		history.record(dt * t.world_scale, capture)
	expect(history.snapshot_count == samples and near_x(player, x_before_hit), "Frozen world neither moves nor records")
	e.step_selection(12) # twelve moments at 12 Hz ~ one second back
	var chosen_index := e.selected_index
	var age := e.choice_age(e.selected_index)
	var chosen: Dictionary = e.choice_state(e.selected_index)
	e.confirm()
	expect(absf(age - 0.95) < 0.1, "Twelve wheel steps choose about one second back (%.2f)" % age)
	expect(player.position.is_equal_approx(chosen.player.position) and player.global_position.x < x_before_hit - 3.0, "Confirm restores the player to the chosen moment")
	expect(gs.state == gs.State.PLAYING and player.can_act and t.meter >= t.settings.recovery_floor - 0.001, "Play resumes with the recovery floor")
	expect(history.snapshot_count == samples - chosen_index + 1, "History newer than the chosen moment is discarded")
	player.free()
	floor_body.free()


func _on_loop_confirmed(_age: float, state: Dictionary) -> void:
	if state.has("player") and is_instance_valid(_loop_player):
		_loop_player.restore_state(state.player)


func near_x(player: CombatPlayer, x: float) -> bool:
	return absf(player.global_position.x - x) < 0.0001
