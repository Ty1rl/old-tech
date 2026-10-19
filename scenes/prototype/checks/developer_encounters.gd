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
	var scenes := root.get_node("SceneManager")
	scenes.developer_tools = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var picker: Node = scenes.push_popup(&"Developer")
	expect(picker != null and picker.difficulty_picker.item_count == 2, "Developer encounter menu has explicit Easy and Hard choices")
	picker.difficulty_picker.select(1)
	picker.difficulty_picker.item_selected.emit(1)
	picker.room_picker.select(3)
	picker.room_picker.item_selected.emit(3)
	var rooms: Array = load("res://scenes/prototype/rooms.gd").definitions(&"hard")
	var last_wave: int = rooms[3].waves.size() - 1
	picker.encounter_picker.select(last_wave)
	picker.encounter_picker.item_selected.emit(last_wave)
	expect(not picker.phase_picker.disabled, "Final boss encounter exposes its phase selector")
	picker.phase_picker.select(1)
	picker.get_node("%StartEncounter").pressed.emit()
	for tick in range(800):
		if not scenes.is_transitioning(): break
		await create_timer(.01).timeout
	expect(not scenes.is_transitioning(), "Actual developer launch finishes loading")
	var campaign := current_scene
	expect(scenes.params.get("difficulty") == &"hard" and campaign.get("difficulty_id") == &"hard", "Selected Hard difficulty reaches the actual campaign")
	expect(campaign.room_index == 3 and campaign.wave_index == last_wave, "Selected boss encounter reaches the requested room and wave")
	expect(campaign.director.combat_difficulty.id == &"hard", "Enemy damage and behavior use Hard tuning")
	expect(campaign.equipment.wear_scale == campaign.difficulty_spec.weapon_wear_scale, "Weapon wear uses the same selected difficulty")
	var reopened: Node = scenes.push_popup(&"Developer")
	expect(reopened.difficulty_picker.selected == 1, "Reopening encounter selection retains the running campaign's difficulty")
	scenes.close_popup(&"Developer")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	if failures.is_empty(): root.get_node("AudioManager").request_quit()
	else: quit(1)
