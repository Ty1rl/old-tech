extends SceneTree

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL: " + message)


func run() -> void:
	var policy := ProtagonistVoice.new()
	policy.step(60, true, false, false)
	policy.offer(&"protagonist.multi_kill")
	expect(policy.choose().is_empty(), "Early combat cannot consume the reserved first repair opportunity")
	policy.offer(&"protagonist.repair_started")
	policy.step(0, true, true, false)
	expect(policy.choose().event == &"protagonist.repair_started", "First ordinary repair takes the reserved opportunity")
	policy.played(&"protagonist.repair_started")
	expect(policy.total == 1 and policy.interval() == 150, "Accepted speech counts once and preserves 150-second spacing")
	policy.step(150, true, false, false)
	policy.offer(&"protagonist.repair_completed")
	policy.offer(&"protagonist.multi_kill")
	expect(policy.choose().event == &"protagonist.multi_kill", "A new combat family takes precedence over another repair remark")
	policy.played(&"protagonist.multi_kill")
	policy.step(150, true, false, false)
	policy.offer(&"protagonist.under_pressure")
	policy.offer(&"protagonist.rewind_recovered")
	expect(policy.choose().event == &"protagonist.rewind_recovered", "Recovery gets heard instead of repeated combat")
	policy.played(&"protagonist.rewind_recovered")
	policy.step(150, true, false, false)
	policy.offer(&"protagonist.room_cleared")
	policy.offer(&"protagonist.boss_defeated")
	expect(policy.choose().event == &"protagonist.boss_defeated", "Boss victory beats coincident room completion")
	policy.played(&"protagonist.boss_defeated")
	expect(policy.total == 4 and policy.family_counts.size() == 4 and policy.interval() == 300,
		"Four lines cover four families, then extend the quiet interval")
	policy.step(150, true, false, false)
	policy.offer(&"protagonist.enemy_exposed")
	expect(policy.choose().is_empty(), "A fifth line cannot play at the old cadence")
	policy.step(150, true, false, false)
	expect(policy.choose().is_empty(), "An expired combat event is never delivered late")
	policy.offer(&"protagonist.enemy_exposed")
	expect(policy.choose().event == &"protagonist.enemy_exposed", "Long combat remains eligible for fresh reactions")
	policy.played(&"protagonist.enemy_exposed")
	policy.step(300, true, false, true)
	expect(policy.choose().event == &"protagonist.room_cleared" and policy.choose().variant == 1,
		"Five safe idle minutes use only Let's keep moving")
	policy.step(0, true, false, false)
	expect(policy.choose().is_empty(), "Resuming movement or combat immediately cancels the idle cue")
	policy.step(0, false, false, false)
	expect(policy.choose().is_empty(), "Teaching, menus and emergency scrub clear incidental opportunities")
	policy.reset()
	policy.step(121, true, false, false)
	policy.offer(&"protagonist.under_pressure")
	expect(policy.choose().event == &"protagonist.under_pressure", "A player who never repairs does not remain silent indefinitely")
	policy.played(&"protagonist.under_pressure")
	policy.step(150, true, false, false)
	policy.offer(&"protagonist.multi_kill")
	expect(policy.choose().is_empty(), "Common combat cannot repeatedly claim every 150-second opening")
	policy.step(150, true, false, false)
	policy.offer(&"protagonist.multi_kill")
	expect(not policy.choose().is_empty(), "Prolonged combat still speaks after five minutes")
	policy.reset()
	policy.step(0, true, true, false)
	policy.step(100, true, false, false)
	expect(policy.choose().is_empty(), "Closing repair discards its old opportunity")
	# A running repair can become eligible after the global speech cooldown ends.
	policy.step(150, true, true, false)
	expect(policy.choose().event == &"protagonist.repair_started", "Repair context refreshes while the player is actually repairing")
	policy.reset()
	expect(policy.total == 0 and policy.event_counts.is_empty() and policy.family_counts.is_empty(),
		"New runs reset coverage without needing replay history in rewind snapshots")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
