extends SceneTree

# Focused check suite for Round M (JAM-4):
# - Moderate service interval increases in Tuning.GEAR (24/64/24/18)
# - Equipment.training_protection policy/hook and anti-bypass guarantees
# - Campaign wear-free yellow training through Waves 0–2 until deliberate Wave 3 repair break
# - Safe yellow empty/equip on Wave 3, E toggle + matching-shape tutorial copy, and full restoration after repair lesson
# - Permanent teaching progress ownership across rewind snapshots, retry_room, and debug_start
# - Shorter early wave intervals/recovery and prompt refill when active group is cleared or almost empty (<= 1)

const Tuning = preload("res://scenes/prototype/tuning.gd")
const Equipment = preload("res://scenes/prototype/equipment.gd")
const Rooms = preload("res://scenes/prototype/rooms.gd")

var checks := 0
var failures: Array[String] = []
var arena: Node3D


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func tick(dt: float = 0.01) -> void:
	arena._physics_process(dt)


func run() -> void:
	# 1. Moderate service interval increases
	var gear := Equipment.new()
	expect(is_equal_approx(gear.capacity(&"ring"), 24.0), "Ring capacity increased moderately to 24 launches")
	expect(is_equal_approx(gear.capacity(&"beam"), 64.0), "Beam capacity increased moderately to 64 shots")
	expect(is_equal_approx(gear.capacity(&"cone"), 24.0), "Cone capacity increased moderately to 24 seconds")
	expect(is_equal_approx(gear.capacity(&"clock"), 18.0), "Clock capacity increased moderately to 18 seconds")

	# 2. Equipment.training_protection policy and anti-bypass guarantees
	expect(gear.training_protection.is_empty(), "Equipment starts with empty training_protection by default")
	gear.set_training_protection([&"beam"])
	expect(gear.training_protection == [&"beam"] and gear.is_training_protected(&"beam"), "set_training_protection enables protection on beam")
	expect(gear.can_use(&"beam", 1.0) and is_equal_approx(gear.spend(&"beam", 1.0), 1.0), "Protected beam accepts positive quick-shot spend")
	expect(gear.can_use(&"beam", 3.0) and is_equal_approx(gear.spend(&"beam", 3.0), 3.0), "Protected beam accepts positive charged-shot spend")
	expect(is_equal_approx(gear.remaining(&"beam"), 64.0) and gear.is_full(&"beam"), "Protected beam spend does not reduce remaining capacity")
	expect(is_equal_approx(gear.spend(&"cone", 4.0), 4.0) and is_equal_approx(gear.remaining(&"cone"), 20.0), "Unprotected cone spends and reduces remaining normally while beam is protected")

	var repair_session: int = gear.begin_repair(&"beam")
	expect(not gear.can_use(&"beam", 1.0) and is_equal_approx(gear.spend(&"beam", 1.0), 0.0), "Protected tool still respects active repair session lock")
	gear.end_repair(repair_session)

	var injected_snap: Dictionary = gear.capture_state()
	injected_snap["training_protection"] = []
	gear.restore_state(injected_snap)
	expect(gear.training_protection == [&"beam"], "restore_state ignores snapshot training_protection and preserves live policy")
	gear.reset_state()
	expect(gear.training_protection == [&"beam"], "reset_state does not wipe campaign-owned training_protection policy")
	gear.set_training_protection([])
	expect(gear.training_protection.is_empty() and is_equal_approx(gear.spend(&"beam", 10.0), 10.0) and is_equal_approx(gear.remaining(&"beam"), 54.0), "Removing protection restores normal beam wear")

	# 3. Updated tutorial copy for E toggle, matching-shape contacts, and Space slow
	var tutorial_script: Script = load("res://scenes/ui/tutorial.gd")
	var repair_copy: String = String(tutorial_script.LESSONS["repair"][1])
	var slow_copy: String = String(tutorial_script.LESSONS["slow"][1])
	expect("press E to toggle" in repair_copy and "matching-shape contacts" in repair_copy and "1–3" in repair_copy, "Repair lesson copy teaches E toggle, matching-shape contacts, and 1–3 tools")
	expect(not ("hold E" in repair_copy), "Repair lesson copy no longer instructs holding E")
	expect("hold Space" in slow_copy, "Slow lesson copy teaches holding Space to slow the world")

	# 4. Sandbox arena is completely unaffected by training_protection
	var sandbox: Node3D = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(sandbox)
	current_scene = sandbox
	await physics_frame
	await physics_frame
	sandbox.set_physics_process(false)
	expect(sandbox.equipment.training_protection.is_empty(), "Sandbox arena has no training_protection enabled")
	sandbox.equipment.spend(&"beam", 5.0)
	expect(is_equal_approx(sandbox.equipment.remaining(&"beam"), 59.0), "Sandbox yellow spends capacity normally from the start")
	sandbox.feedback.reset_state()
	sandbox.queue_free()
	await process_frame

	# 5. Campaign wear-free early yellow training -> deliberate Wave 3 break -> full restoration -> normal wear
	var game: Node = root.get_node("GameState")
	var prior: Dictionary = game.preferences().duplicate(true)
	game.set_setting("tutorial", true)
	root.get_node("SceneManager").params = {}
	arena = load("res://scenes/prototype/campaign.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	game.start_game()

	expect(arena.equipment.training_protection == [&"beam"], "Fresh campaign starts with yellow protected")
	tick(2.1)
	arena.player.position = arena.museum.pickup_position + Vector3.UP * 0.55
	tick()
	expect(arena.lesson == &"shot" and arena.equipment.training_protection == [&"beam"], "Wave 0 shot lesson keeps yellow protected")
	arena.tutorial.request_practice()
	expect(is_equal_approx(arena.equipment.spend(&"beam", 12.0), 12.0) and is_equal_approx(arena.equipment.remaining(&"beam"), 64.0), "Wave 0 practice yellow shots are wear-free")
	var spec0: Node3D = arena.specimens[0]
	spec0.health = 0
	arena._on_resolved_hit(&"beam", {"killed": true}, {}, spec0.rewind_id)
	arena.director._prune_dead_enemies()
	tick()
	expect(arena.mode == &"pressure" and arena.equipment.training_protection == [&"beam"], "Wave 0 pressure keeps yellow protected")
	expect(is_equal_approx(arena.equipment.spend(&"beam", 20.0), 20.0) and is_equal_approx(arena.equipment.remaining(&"beam"), 64.0), "Wave 0 pressure combat yellow shots are wear-free")

	# Verify prompt refill when active group is almost empty (1 enemy left out of initial burst of 2)
	expect(arena.director.enemies.size() == 2 and arena._pending == 6, "Wave 0 starts with 2 active enemies and 6 pending")
	expect(arena._spawn_timer > 3.5, "Initial spawn timer is set to wave interval (> 3.5s)")
	arena.director.enemies[0].health = 0
	arena.director._prune_dead_enemies()
	expect(arena.director.enemies.size() == 1, "Killing one enemy leaves almost-empty active group of 1")
	tick(0.4)
	expect(arena.director.enemies.size() == 1 and arena._pending == 6, "Refill waits briefly (0.75s) rather than spawning instantaneously")
	tick(0.45)
	expect(arena.director.enemies.size() == 3 and arena._pending == 4, "Almost-empty active group refills promptly within 0.85s instead of waiting full interval")
	expect(not arena.director.flow.cohorts.is_empty(), "Prompt refill still routes through formation flow warnings")

	# Capture a rewind snapshot while yellow is protected in Wave 0
	var protected_snapshot: Dictionary = arena.capture_state()

	# Check Wave 1 (charge) and Wave 2 (heat) remain wear-free for yellow
	arena.debug_start(0, 1)
	expect(arena.equipment.training_protection == [&"beam"] and is_equal_approx(arena.equipment.remaining(&"beam"), 64.0), "Wave 1 charge checkpoint keeps yellow protected")
	arena.debug_start(0, 2)
	expect(arena.equipment.training_protection == [&"beam"] and is_equal_approx(arena.equipment.remaining(&"beam"), 64.0), "Wave 2 heat checkpoint keeps yellow protected")
	arena.equipment.spend(&"beam", 15.0)
	arena.equipment.spend(&"cone", 5.0)
	expect(is_equal_approx(arena.equipment.remaining(&"beam"), 64.0) and is_equal_approx(arena.equipment.remaining(&"cone"), 19.0), "Wave 2 protects yellow while allowing orange heat wear")

	# Advance into Wave 3 deliberate repair lesson
	arena.tutorial.learned.erase(&"repair")
	arena.director.clear()
	arena.wave_index = 2
	arena._begin_wave()
	expect(arena.wave_index == 3 and arena.lesson == &"repair", "Wave 3 begins deliberate repair lesson")
	expect(arena.director.enemies.is_empty(), "Deliberate repair lesson takes place in complete safety with no active enemies")
	expect(arena.equipment.training_protection.is_empty(), "Deliberate repair lesson explicitly removes yellow training protection")
	expect(is_equal_approx(arena.equipment.remaining(&"beam"), 0.0) and arena.weapons.selected_tool == 2, "Deliberate repair lesson empties and equips yellow")

	arena.tutorial.request_practice()
	var session: int = arena.equipment.begin_repair(&"beam")
	var step_restored: float = arena.equipment.complete_step(&"beam", session)
	expect(is_equal_approx(step_restored, 16.0) and is_equal_approx(arena.equipment.remaining(&"beam"), 16.0), "One real repair step restores 1/4 yellow capacity (16 shots)")
	arena.equipment.end_repair(session)
	tick()
	expect(arena.tutorial.is_learned(&"repair"), "Completing repair step marks repair lesson learned")
	expect(arena.equipment.is_full(&"beam") and arena.equipment.is_full(&"cone"), "Deliberate repair completion restores full useful condition on acquired tools before combat continues")
	expect(arena.equipment.training_protection.is_empty(), "Yellow protection stays off after repair lesson completes")

	# Advance to Wave 4 normal combat after short post-repair transition and verify normal yellow wear
	tick()
	expect(arena.mode == &"recovery" and arena.timer <= 0.4, "Zero-enemy repair wave uses brief transition recovery (<= 0.4s)")
	tick(0.4)
	expect(arena.wave_index == 4 and arena.mode == &"pressure", "Recovery after repair lesson advances promptly to Wave 4 combat")
	arena.equipment.spend(&"beam", 6.0)
	expect(is_equal_approx(arena.equipment.remaining(&"beam"), 58.0), "Normal combat after repair lesson spends yellow capacity normally")

	# 6. Anti-bypass: rewind snapshot, retry_room, and debug_start respect permanent teaching progress
	arena.restore_campaign_state(protected_snapshot)
	expect(arena.equipment.training_protection.is_empty(), "Restoring an early rewind snapshot after repair is learned does not re-enable protection")
	var rem_before: float = arena.equipment.remaining(&"beam")
	arena.equipment.spend(&"beam", 4.0)
	expect(is_equal_approx(arena.equipment.remaining(&"beam"), rem_before - 4.0), "Yellow continues to wear normally after restoring pre-repair snapshot")

	arena.retry_room()
	expect(arena.equipment.training_protection.is_empty(), "Retrying Room 0 after repair is permanently learned keeps protection off")

	arena.debug_start(0, 1)
	expect(arena.equipment.training_protection == [&"beam"], "Debug jump back to Room 0 Wave 1 recomputes prerequisites and enables protection")
	arena.debug_start(0, 4)
	expect(arena.equipment.training_protection.is_empty(), "Debug jump to Room 0 Wave 4 disables protection")
	arena.debug_start(1, 0)
	expect(arena.equipment.training_protection.is_empty(), "Debug jump to Room 1 disables protection")

	# 7. Verify TimeController slow drain and tutorial layout caching
	arena.debug_start(1, 2)
	arena.director.clear()
	arena._pending = 0
	arena.mode = &"pressure"
	arena.weapons.select_tool(1)
	arena.time_controller.apply_hit(20.0)
	expect(is_equal_approx(arena.time_controller.meter, 80.0), "Hit spends time from TimeController meter")
	var space_down := InputEventKey.new()
	space_down.physical_keycode = KEY_SPACE
	space_down.pressed = true
	arena._input(space_down)
	tick(2.0)
	expect(arena.time_controller.world_scale < 0.3 and arena.time_controller.meter < 80.0,
		"Under time slow, holding Space drains TimeController meter and slows world_scale")
	var space_up := InputEventKey.new()
	space_up.physical_keycode = KEY_SPACE
	space_up.pressed = false
	arena._input(space_up)

	arena.tutorial.reset_run()
	var lesson_targets: Array[Vector3] = [Vector3.ZERO]
	arena.tutorial.show_known_lesson(&"cut", lesson_targets)
	expect(not arena.tutorial._layout_dirty and arena.tutorial._layout_size == arena.tutorial.size, "Tutorial card caches layout size on show_lesson")
	arena.tutorial._process(0.016)
	expect(not arena.tutorial._layout_dirty, "Tutorial _process updates position without marking layout dirty every frame")

	root.get_node("SceneManager").clear_popups()
	game.start_game()
	for key in prior:
		game.set_setting(key, prior[key])
	arena.feedback.reset_state()
	arena.free()
	await process_frame
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
