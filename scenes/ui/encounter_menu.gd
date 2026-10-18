extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
const Rooms = preload("res://scenes/prototype/rooms.gd")
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
var room_picker: OptionButton
var encounter_picker: OptionButton
var phase_picker: OptionButton

func _ready() -> void:
	var column := UI.shell(self, "Encounter select", "Development shortcuts · starts with the equipment needed here.", 560)
	room_picker = OptionButton.new()
	room_picker.name = "RoomPicker"
	for room: Dictionary in Rooms.definitions(): room_picker.add_item(room.title)
	column.add_child(room_picker)
	encounter_picker = OptionButton.new()
	encounter_picker.name = "EncounterPicker"
	column.add_child(encounter_picker)
	phase_picker = OptionButton.new()
	phase_picker.name = "PhasePicker"
	column.add_child(phase_picker)
	UI.label(column, "Phase selection applies only to boss encounters.", 14).modulate = UI.MUTED
	room_picker.item_selected.connect(func(_index): _update_encounters())
	encounter_picker.item_selected.connect(func(_index): _update_phases())
	_update_encounters()
	UI.button(column, "Start encounter", _launch, "StartEncounter")
	UI.button(column, "Prototype sandbox", func(): SceneManager.start_play(true))
	UI.button(column, "Back", func(): SceneManager.close_popup(&"Developer"))
	room_picker.grab_focus.call_deferred()

func _update_encounters() -> void:
	encounter_picker.clear()
	var waves: Array = Rooms.definitions()[room_picker.selected].waves
	for i in range(waves.size()):
		var wave: Dictionary = waves[i]
		var names: Array[String] = []
		for kind: StringName in wave.get("enemies",[]): names.append(String(kind).replace("_"," "))
		var label := String(wave.get("lesson", "")).replace("_"," ")
		if label.is_empty(): label = "Encounter"
		if wave.has("acquire"): label = "Find equipment · " + label
		encounter_picker.add_item("%d · %s · %s" % [i+1, label.capitalize(), ", ".join(names)])

	_update_phases()

func _update_phases() -> void:
	phase_picker.clear()
	phase_picker.add_item("Boss: start normally")
	var wave: Dictionary = Rooms.definitions()[room_picker.selected].waves[encounter_picker.selected]
	phase_picker.disabled = not bool(wave.get("boss",false))
	if not phase_picker.disabled:
		for i in range(PatternEnemy.phases_for(wave.enemies[0])):
			phase_picker.add_item("Boss phase %d" % (i+1))

func _launch() -> void:
	if SceneManager.go_to(&"Campaign", {"debug_room": room_picker.selected,
		"debug_wave": encounter_picker.selected, "debug_phase": phase_picker.selected-1}):
		GameState.start_game()
