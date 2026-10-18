extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var gear := Equipment.new()
	var rc: float = gear.capacity(&"ring")
	var bc: float = gear.capacity(&"beam")
	var cc: float = gear.capacity(&"cone")
	var kc: float = gear.capacity(&"clock")
	expect(is_equal_approx(gear.remaining(&"ring"), rc) and is_equal_approx(gear.remaining(&"beam"), bc)
		and is_equal_approx(gear.remaining(&"cone"), cc) and is_equal_approx(gear.remaining(&"clock"), kc),
		"All four tools start at full capacity")
	expect(gear.stage(&"ring") == 0 and gear.is_full(&"ring") and is_equal_approx(gear.condition(&"ring"), 1.0),
		"Full tool reports stage 0, full flag, and 1.0 condition")

	# Light wear: > 75% remaining derives stage 3 and repairs only missing portion to full (4/4)
	gear.spend(&"ring", rc / 16.0)
	expect(is_equal_approx(gear.remaining(&"ring"), rc * 15.0 / 16.0) and gear.stage(&"ring") == 3,
		"Light wear (93.75%) derives stage 3 from condition")
	var light_token: int = gear.begin_repair(&"ring")
	expect(is_equal_approx(gear.complete_step(&"ring", light_token), rc / 16.0) and is_equal_approx(gear.remaining(&"ring"), rc) and gear.stage(&"ring") == 0,
		"Completing checkpoint on lightly worn tool restores only the missing sixteenth of capacity to full")
	gear.end_repair(light_token)

	# Heavy wear & partial segment: < 25% remaining derives stage 0 and restores to 1/4 boundary
	gear.spend(&"ring", rc * 29.0 / 32.0)
	expect(is_equal_approx(gear.remaining(&"ring"), rc * 3.0 / 32.0) and gear.stage(&"ring") == 0,
		"Heavy wear (9.375%) derives stage 0 from condition")
	gear.begin_repair(&"ring")
	expect(is_equal_approx(gear.complete_step(&"ring"), rc * 5.0 / 32.0) and is_equal_approx(gear.remaining(&"ring"), rc * 0.25) and gear.stage(&"ring") == 1,
		"First checkpoint restores the missing portion to the quarter boundary (stage 1)")
	expect(is_equal_approx(gear.complete_step(&"ring"), rc * 0.25) and is_equal_approx(gear.remaining(&"ring"), rc * 0.5) and gear.stage(&"ring") == 2,
		"Second checkpoint advances from one-quarter to half capacity (stage 2)")
	gear.end_repair()
	expect(is_equal_approx(gear.remaining(&"ring"), rc * 0.5) and gear.stage(&"ring") == 2,
		"Leaving repair preserves completed checkpoint capacity and derived stage")

	# Partial wear within the second quarter derives stage 1
	gear.spend(&"ring", rc * 3.0 / 32.0)
	gear.begin_repair(&"ring")
	expect(is_equal_approx(gear.remaining(&"ring"), rc * 13.0 / 32.0) and gear.stage(&"ring") == 1,
		"Spending part of half capacity drops condition into the second quarter (stage 1)")
	expect(not gear.can_use(&"ring", 1) and gear.spend(&"ring", 1) == 0,
		"Item being repaired cannot fire")
	expect(gear.can_use(&"clock", 1) and gear.spend(&"clock", 1) == 1,
		"Clock remains usable while repairing another tool")
	expect(is_equal_approx(gear.complete_step(&"ring"), rc * 3.0 / 32.0) and is_equal_approx(gear.remaining(&"ring"), rc * 0.5) and gear.stage(&"ring") == 2,
		"Checkpoint completion from a partial segment restores exactly its missing capacity to the half boundary")
	gear.end_repair()
	expect(gear.complete_step(&"ring") == 0, "Closed repair cannot award background progress")

	# Clock self-repair restriction and empty clock repair
	gear.begin_repair(&"clock")
	expect(not gear.can_use(&"clock", 0.1), "Clock cannot power its own repair")
	gear.end_repair()
	expect(is_equal_approx(gear.spend(&"clock", kc * 2.0), kc - 1.0) and gear.remaining(&"clock") == 0,
		"Continuous use consumes only remaining capacity")
	gear.begin_repair(&"clock")
	expect(is_equal_approx(gear.complete_step(&"clock"), kc * 0.25) and gear.stage(&"clock") == 1 and gear.can_use(&"beam", 1),
		"Empty clock repairs its first quarter without requiring slow time")
	gear.end_repair()

	# Session token safety across overlapping repair sessions
	var old_session: int = gear.begin_repair(&"ring")
	var new_session: int = gear.begin_repair(&"beam")
	gear.end_repair(old_session)
	expect(gear.repairing == &"beam", "A closing old panel cannot cancel a newer repair")
	expect(gear.complete_step(&"beam", old_session) == 0.0, "Stale session token cannot complete step on active repair")
	gear.end_repair(new_session)

	# Snapshot capture_state / restore_state round-trip, isolation, and stale token invalidation
	gear.reset_state()
	gear.spend(&"ring", rc * 0.625) # 37.5% remaining (stage 1)
	gear.spend(&"beam", bc * 0.25) # 75% remaining (stage 3)
	gear.spend(&"cone", cc * 7.0 / 9.0) # 22.2% remaining (stage 0)
	gear.spend(&"clock", kc * 0.75) # 25% remaining (stage 1)
	var snap: Dictionary = gear.capture_state()
	var encoded: PackedByteArray = var_to_bytes(snap)
	var decoded: Variant = bytes_to_var(encoded)
	expect(decoded is Dictionary and encoded.size() > 0 and encoded.size() < 512,
		"Equipment snapshot is compact explicit value data with no object references")
	snap["remaining"]["ring"] = 0.0
	expect(is_equal_approx(gear.remaining(&"ring"), rc * 0.375), "Mutating captured snapshot dictionary does not mutate live Equipment")
	var clean_snap: Dictionary = decoded

	# Mutate live state and open an active repair session before restoring
	gear.spend(&"ring", gear.remaining(&"ring"))
	gear.spend(&"beam", gear.remaining(&"beam"))
	gear.spend(&"cone", gear.remaining(&"cone"))
	gear.spend(&"clock", gear.remaining(&"clock"))
	var pre_restore_token: int = gear.begin_repair(&"ring")
	expect(gear.repairing == &"ring" and gear.is_session_active(pre_restore_token, &"ring"),
		"Active repair session established before restore_state")

	gear.restore_state(clean_snap)
	expect(gear.repairing == &"" and not gear.is_session_active(pre_restore_token, &"ring"),
		"restore_state closes active repair session and invalidates old session token")
	expect(gear.complete_step(&"ring") == 0.0 and gear.complete_step(&"ring", pre_restore_token) == 0.0,
		"Restored equipment rejects completion from invalidated repair session")
	expect(is_equal_approx(gear.remaining(&"ring"), rc * 0.375) and gear.stage(&"ring") == 1
		and is_equal_approx(gear.remaining(&"beam"), bc * 0.75) and gear.stage(&"beam") == 3
		and is_equal_approx(gear.remaining(&"cone"), cc * 2.0 / 9.0) and gear.stage(&"cone") == 0
		and is_equal_approx(gear.remaining(&"clock"), kc * 0.25) and gear.stage(&"clock") == 1,
		"restore_state restores all four equipment levels and derived stages")

	# Stale pre-restore token cannot interfere with a new post-restore session on the same tool
	var post_restore_token: int = gear.begin_repair(&"ring")
	gear.end_repair(pre_restore_token)
	expect(gear.repairing == &"ring" and gear.is_session_active(post_restore_token, &"ring"),
		"Pre-restore token cannot end a post-restore repair session")
	expect(gear.complete_step(&"ring", pre_restore_token) == 0.0 and is_equal_approx(gear.remaining(&"ring"), rc * 0.375),
		"Pre-restore token cannot complete a step on a post-restore repair session")
	expect(is_equal_approx(gear.complete_step(&"ring", post_restore_token), rc * 0.125) and is_equal_approx(gear.remaining(&"ring"), rc * 0.5),
		"Post-restore token completes step normally to the next quarter boundary")
	gear.end_repair(post_restore_token)

	gear.reset_state()
	expect(is_equal_approx(gear.remaining(&"ring"), rc) and gear.stage(&"ring") == 0 and gear.repairing == &"",
		"Reset clears repair sessions and restores all equipment")

	var cover := Cover.new()
	var hit := cover.clip_segment(Vector3(-8, 0, -4), Vector3(-2, 0, -4))
	expect(hit.blocked and is_equal_approx(hit.position.x, -6) and hit.normal == Vector3.LEFT, "Cover sweep finds first wall and its normal")
	hit = cover.clip_segment(Vector3(-8, 0, -4), Vector3(-2, 0, -4), 0.5)
	expect(hit.blocked and is_equal_approx(hit.position.x, -6.5), "Cover sweeps account for entity radius")
	expect(not cover.clip_segment(Vector3.ZERO, Vector3(0, 0, -10)).blocked, "Open center lane remains clear")
	expect(not cover.clip_segment(Vector3(-8, 0, -4), Vector3(-10, 0, -4)).blocked, "Cover behind a segment does not block it")

	var arena = load("res://scenes/prototype/arena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await physics_frame
	await physics_frame
	arena.set_physics_process(false)
	var repair_key := InputEventKey.new()
	repair_key.physical_keycode = KEY_E
	repair_key.pressed = true
	arena.weapons.select_tool(4)
	arena.equipment.spend(&"clock", arena.equipment.capacity(&"clock"))
	arena._unhandled_input(repair_key)
	expect(not paused and root.get_node("SceneManager").has_popup(&"Repair"), "Repair popup opens without pausing")
	expect(arena.equipment.repairing == &"clock", "Empty clock can open its own repair panel")
	arena.equipment.complete_step(&"clock")
	repair_key.pressed = false
	arena._input(repair_key)
	await process_frame
	await process_frame
	expect(arena.equipment.repairing == &"" and arena.equipment.stage(&"clock") == 1,
		"Closing popup releases repair lock and preserves completed stage")
	repair_key.pressed = true
	arena._unhandled_input(repair_key)
	expect(arena.equipment.stage(&"clock") == 1 and is_equal_approx(arena.equipment.remaining(&"clock"), kc * 0.25),
		"Reopened popup resumes previous progress with restored capacity intact")
	arena.reset_arena()
	await process_frame
	expect(arena.equipment.repairing == &"" and is_equal_approx(arena.equipment.remaining(&"clock"), kc),
		"Arena reset clears repair popup and refills equipment")
	arena.queue_free()
	await process_frame
	# Allow the audio server to release generated playback after scene removal.
	await create_timer(0.10).timeout
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
