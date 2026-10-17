extends SceneTree

const Equipment = preload("res://scenes/prototype/equipment.gd")
const Cover = preload("res://scenes/prototype/cover.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var gear := Equipment.new()
	expect(gear.remaining(&"ring") == 32 and gear.remaining(&"clock") == 24, "Generous capacities start full")
	gear.spend(&"ring", 24)
	gear.begin_repair(&"ring")
	expect(gear.complete_step(&"ring") == 8 and gear.stage(&"ring") == 1, "Completed section restores capacity and advances stage")
	gear.end_repair()
	expect(gear.remaining(&"ring") == 16 and gear.stage(&"ring") == 1, "Interruption preserves restored capacity and completed step")
	gear.spend(&"ring", 1)
	gear.begin_repair(&"ring")
	expect(gear.stage(&"ring") == 1, "Using the tool between repairs does not erase progress")
	expect(not gear.can_use(&"ring", 1) and gear.spend(&"ring", 1) == 0, "Item being repaired cannot fire")
	expect(gear.can_use(&"clock", 1) and gear.spend(&"clock", 1) == 1, "Clock remains usable while repairing another tool")
	gear.end_repair()
	expect(gear.complete_step(&"ring") == 0, "Closed repair cannot award background progress")
	gear.begin_repair(&"clock")
	expect(not gear.can_use(&"clock", 0.1), "Clock cannot power its own repair")
	gear.end_repair()
	expect(gear.spend(&"clock", 100) == 23 and gear.remaining(&"clock") == 0, "Continuous use consumes only remaining capacity")
	gear.begin_repair(&"clock")
	expect(gear.complete_step(&"clock") == 6 and gear.can_use(&"beam", 1), "Empty clock repairs without requiring slow time")
	gear.end_repair()
	var old_session: int = gear.begin_repair(&"ring")
	var new_session: int = gear.begin_repair(&"beam")
	gear.end_repair(old_session)
	expect(gear.repairing == &"beam", "A closing old panel cannot cancel a newer repair")
	gear.end_repair(new_session)
	gear.reset_state()
	expect(gear.remaining(&"ring") == 32 and gear.stage(&"ring") == 0 and gear.repairing == &"", "Reset clears repair sessions and restores all equipment")
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
	arena.equipment.spend(&"clock", 24)
	arena._toggle_repair(&"clock")
	expect(not paused and root.get_node("SceneManager").has_popup(&"Repair"), "Repair popup opens without pausing")
	expect(arena.equipment.repairing == &"clock", "Empty clock can open its own repair panel")
	arena.equipment.complete_step(&"clock")
	arena._toggle_repair(&"clock")
	await process_frame
	await process_frame
	expect(arena.equipment.repairing == &"" and arena.equipment.stage(&"clock") == 1,
		"Closing popup releases repair lock and preserves completed stage")
	arena._toggle_repair(&"clock")
	expect(arena.equipment.stage(&"clock") == 1 and arena.equipment.remaining(&"clock") == 6,
		"Reopened popup resumes previous progress with restored capacity intact")
	arena.reset_arena()
	await process_frame
	expect(arena.equipment.repairing == &"" and arena.equipment.remaining(&"clock") == 24,
		"Arena reset clears repair popup and refills equipment")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
