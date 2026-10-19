extends "res://scenes/ui/menu_layout.gd"
const Rooms = preload("res://scenes/prototype/rooms.gd")
const PatternEnemy = preload("res://scenes/prototype/pattern_enemy.gd")
const DIFFICULTIES: Array[StringName] = [&"easy", &"hard"]
@onready var difficulty_picker: OptionButton = %DifficultyPicker
@onready var room_picker: OptionButton = %RoomPicker
@onready var encounter_picker: OptionButton = %EncounterPicker
@onready var phase_picker: OptionButton = %PhasePicker
@onready var action_picker: OptionButton = %ActionPicker
@onready var apply_action: Button = %ApplyAction
@onready var readout_picker: OptionButton = %ReadoutPicker
const ACTIONS := {
    "Spawn target": &"target", "Spawn blue": &"blue", "Spawn yellow": &"yellow",
    "Spawn orange": &"orange", "Spawn small pack": &"pack", "Spawn guard": &"side_guard",
    "Show front guard": &"front_guard", "Start sandbox encounter": &"encounter",
    "Clear enemies": &"clear", "Retry room / reset sandbox": &"reset",
}

func _ready() -> void:
	if not SceneManager.developer_tools:
		queue_free()
		return
	super._ready()
	difficulty_picker.add_item("Easy")
	difficulty_picker.add_item("Hard")
	var scene := SceneManager.get_current_scene()
	var current_difficulty: StringName = scene.difficulty_id if scene != null and scene.has_method("set_difficulty") else StringName(SceneManager.params.get("difficulty", &"easy"))
	difficulty_picker.select(maxi(0, DIFFICULTIES.find(current_difficulty)))
	for room: Dictionary in Rooms.definitions(_difficulty()): room_picker.add_item(room.title)
	_update_encounters()
	for label: String in ACTIONS: action_picker.add_item(label)
	apply_action.disabled = scene == null or not scene.has_method("run_developer_action")
	readout_picker.select(int(GameState.preferences().hud))
	UI.wire_focus(self)
	UI.focus_on_open(self, difficulty_picker)

func _difficulty() -> StringName:
	return DIFFICULTIES[difficulty_picker.selected]

func _update_encounters() -> void:
	encounter_picker.clear()
	var waves: Array = Rooms.definitions(_difficulty())[room_picker.selected].waves
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
	var wave: Dictionary = Rooms.definitions(_difficulty())[room_picker.selected].waves[encounter_picker.selected]
	phase_picker.disabled = not bool(wave.get("boss",false))
	if not phase_picker.disabled:
		for i in range(PatternEnemy.phases_for(wave.enemies[0])):
			phase_picker.add_item("Boss phase %d" % (i+1))
	UI.wire_focus(self)

func _launch() -> void:
	if not SceneManager.developer_tools or SceneManager.is_transitioning(): return
	if SceneManager.go_to(&"Campaign", {"debug_room": room_picker.selected,
		"debug_wave": encounter_picker.selected, "debug_phase": phase_picker.selected-1,
		"difficulty": _difficulty()}):
		GameState.start_game()

func _on_room(_index: int) -> void: _update_encounters()
func _on_difficulty(_index: int) -> void: _update_encounters()
func _on_encounter(_index: int) -> void: _update_phases()
func _on_sandbox() -> void:
	if SceneManager.developer_tools: SceneManager.start_play(true)
func _on_back() -> void: SceneManager.close_popup(&"Developer")

func _on_apply_action() -> void:
	if not SceneManager.developer_tools: return
	var scene := SceneManager.get_current_scene()
	if scene == null or not scene.has_method("run_developer_action"): return
	var action: StringName = ACTIONS[action_picker.get_item_text(action_picker.selected)]
	SceneManager.close_popup(&"Developer")
	scene.run_developer_action(action)

func _on_readout(value: int) -> void:
	if SceneManager.developer_tools: GameState.set_setting("hud", value)
