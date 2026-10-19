extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	for mode: StringName in [&"easy", &"hard"]:
		var gear := WeaponEquipment.new()
		gear.wear_scale = CampaignDifficulty.load_for(mode).weapon_wear_scale
		var rate := 1.2 if mode == &"easy" else 1.5
		for tool: StringName in gear.TOOLS:
			gear.reset_state()
			var cap := gear.capacity(tool)
			var used := gear.spend(tool, 1)
			expect(is_equal_approx(used, 1) and is_equal_approx(gear.remaining(tool), cap - rate), "%s %s spends difficulty wear without multiplying usable shot/damage time" % [mode,tool])
			var saved := gear.capture_state()
			gear.spend(tool, 1)
			gear.restore_state(saved)
			gear.spend(tool, 1)
			expect(is_equal_approx(gear.remaining(tool), cap - 2 * rate), "%s %s rewind does not compound wear scaling" % [mode,tool])
			gear.reset_state()
			gear.spend(tool, (cap - .5) / rate)
			expect(not gear.can_use(tool, 1), "%s %s cannot fire a whole shot without enough wear reserve" % [mode,tool])
			used = gear.spend(tool, 1)
			expect(is_equal_approx(used, .5 / rate) and is_zero_approx(gear.remaining(tool)), "%s %s final partial tick preserves damage fraction and reaches zero" % [mode,tool])
			gear.reset_state()
			gear.set_training_protection([tool])
			used = gear.spend(tool, 1)
			expect(is_equal_approx(used, 1) and gear.is_full(tool), "%s %s teaching protection still prevents wear" % [mode,tool])
			gear.set_training_protection([])
		var bulk := WeaponEquipment.new()
		bulk.wear_scale = rate
		gear.reset_state()
		for tick in 60: gear.spend(&"cone", 1.0 / 60)
		bulk.spend(&"cone", 1)
		expect(is_equal_approx(gear.remaining(&"cone"), bulk.remaining(&"cone")), "%s continuous wear is independent of tick size" % mode)
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
