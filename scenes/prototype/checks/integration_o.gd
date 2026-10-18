extends SceneTree
## Exercise the actual Wave A composition, including native music teardown.
## Campaign pacing/difficulty are checked after Wave B, not asserted here.
var checks := 0
var failures: Array[String] = []
var arena: Node3D

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func pending(cue: StringName) -> bool:
	for voice in arena.feedback._voices:
		if voice.pending and voice.cue == cue: return true
	return false
func fresh() -> void:
	arena.feedback.reset_state()
	arena.feedback.muted = false

func run() -> void:
	create_timer(25, true).timeout.connect(func(): push_error("Integration watchdog"); quit(1))
	var game := root.get_node("GameState")
	var manager := root.get_node("SceneManager")
	var prefs: Dictionary = game.preferences()
	game.set_setting("tutorial", false)
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	arena.set_physics_process(false)
	arena.debug_start(1, 1)
	arena.director.clear()
	fresh()
	var enemy: Node3D = arena.director.spawn(&"swarmer", Vector3(0, 0, -4))
	enemy.receive_attack(&"beam", 1, enemy.global_position, {})
	expect(pending(&"enemy_swarmer_hurt"), "Actual enemy damage reaches archetype audio")
	fresh()
	enemy.receive_attack(&"beam", 10000, enemy.global_position, {})
	expect(pending(&"enemy_swarmer_death"), "Actual death reaches archetype audio once")
	fresh()
	var target: Node3D = arena.director.spawn(&"target", Vector3(3, 0, -5))
	arena.weapons.flash._attack_enemy(target, &"beam", 1, target.global_position, {"piercing": true})
	expect(pending(&"pierce_hit"), "Resolved piercing contact reaches its own cue")
	fresh()
	arena.equipment.set_training_protection([])
	arena.equipment.spend(&"beam", arena.equipment.capacity(&"beam"))
	var session: int = arena.equipment.begin_repair(&"beam")
	arena.equipment.complete_step(&"beam", session)
	expect(pending(&"repair_step") and not pending(&"repair_full"), "Partial repair uses the checkpoint cue")
	for stage in range(arena.equipment.repair_steps):
		if arena.equipment.is_full(&"beam"): break
		fresh()
		arena.equipment.complete_step(&"beam", session)
	expect(arena.equipment.is_full(&"beam") and pending(&"repair_full"), "Final checkpoint uses the full-repair cue")
	arena.equipment.end_repair(session)
	fresh()
	arena.museum.set_exit_open(false)
	arena.museum.set_exit_open(true)
	expect(pending(&"room_open") and arena.feedback.accepted_cues == 1, "Real gate opening has exactly one completion cue")
	arena.museum.set_exit_open(true)
	expect(arena.feedback.accepted_cues == 1, "Repeated open state does not replay room completion")
	fresh()
	manager.push_popup(&"PauseMenu")
	var popup: Node = manager.get_popup(&"PauseMenu")
	var buttons: Array[Node] = popup.find_children("*", "BaseButton", true, false)
	expect(not buttons.is_empty(), "Actual pause content exposes its native buttons")
	if not buttons.is_empty():
		buttons[0].pressed.emit()
		expect(pending(&"ui_click"), "Popup button emits one responsive click")
	manager.clear_popups()
	game.start_game()
	fresh()
	arena.feedback.set_music_playing(true)
	arena.feedback.step(.1, .1, 1, false, 0, arena.weapons, arena.equipment)
	await create_timer(.15).timeout
	expect(arena.feedback._music.playing, "Integrated arena starts native compressed music")
	arena.feedback.reset_state()
	arena.queue_free()
	await process_frame
	# The native audio mixer releases compressed stream playback asynchronously.
	await create_timer(.3).timeout
	expect(not is_instance_valid(arena), "Composition exits with active music released")
	for setting in prefs: game.set_setting(setting, prefs[setting])
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
