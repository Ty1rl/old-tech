extends Node

## EMERGENCY: a hit emptied the time meter; combat is frozen through
## TimeController.world_scale == 0 while the recovery choice is open. The tree is
## NOT paused, so the arena's emergency input and UI keep running. PAUSED may sit
## on top of PLAYING or EMERGENCY and resumes to whichever it interrupted.
enum State { MENU, PLAYING, PAUSED, GAME_OVER, EMERGENCY }

signal state_changed(old_state: State, new_state: State)
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal opened_menu
signal emergency_entered
signal emergency_exited
signal settings_changed(values: Dictionary)
signal settings_save_failed(path: String)

var state: State:
	get: return _state

var _state: State = State.MENU
## State that PAUSED returns to (PLAYING or EMERGENCY).
var _resume_state: State = State.PLAYING
var _emergency: EmergencyRewind
var _in_emergency := false
const SETTINGS_PATH := "user://museum-settings.cfg"
const AUDIO_PATH := "user://combat-audio.cfg"
const HUD_PATH := "user://combat-hud.cfg"
var _preferences := {"sound": true, "volume": 0.8, "fullscreen": false, "tutorial": true, "hud": 2}
var _sync_time := 0.0
var _applied_scene_id := 0



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload_preferences()
	SceneManager.scene_changed.connect(func(_key): apply_preferences())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if SceneManager.is_transitioning():
			return
		if SceneManager.has_popup(&"Developer"):
			SceneManager.close_popup(&"Developer")
		elif SceneManager.has_popup(&"Settings"):
			SceneManager.close_popup(&"Settings")
		elif not SceneManager.has_popup(&"RunResult"):
			toggle_pause()
		get_viewport().set_input_as_handled()


## Toggles PAUSED over PLAYING or EMERGENCY. Ignored in MENU and GAME_OVER.
func toggle_pause() -> bool:
	match _state:
		State.PLAYING, State.EMERGENCY:
			return pause()
		State.PAUSED:
			return resume()
	return false


func change_state(new_state: State) -> bool:
	if new_state == _state:
		return false
	
	var old_state: State = _state
	_state = new_state
	get_tree().paused = (_state in [State.PAUSED, State.GAME_OVER])
	var entered := _state == State.EMERGENCY and not _in_emergency
	var exited := _in_emergency and _state in [State.PLAYING, State.MENU, State.GAME_OVER]
	if entered:
		_in_emergency = true
	if exited:
		_in_emergency = false
	
	state_changed.emit(old_state, _state)
	_emit_state_signal(old_state, _state)
	if entered:
		emergency_entered.emit()
	if exited:
		emergency_exited.emit()
	return true


func start_game() -> bool:
	return change_state(State.PLAYING)


func end_game() -> bool:
	return change_state(State.GAME_OVER)


func open_menu() -> bool:
	return change_state(State.MENU)


func pause() -> bool:
	if _state not in [State.PLAYING, State.EMERGENCY]:
		return false
	_resume_state = _state
	SceneManager.push_popup("PauseMenu")
	return change_state(State.PAUSED)


func resume() -> bool:
	if _state != State.PAUSED or SceneManager.has_popup(&"Settings"):
		return false
	SceneManager.close_popup("PauseMenu")
	return change_state(_resume_state)


## Connects the arena's EmergencyRewind so its session drives EMERGENCY mode.
## Call once when the arena composes its time core; rebinding replaces the old one.
func bind_emergency(rewind: EmergencyRewind) -> void:
	if is_instance_valid(_emergency):
		_emergency.started.disconnect(_on_emergency_started)
		_emergency.ended.disconnect(end_emergency)
	_emergency = rewind
	if is_instance_valid(_emergency):
		_emergency.started.connect(_on_emergency_started)
		_emergency.ended.connect(end_emergency)


## PLAYING -> EMERGENCY. Returns false from any other state.
func begin_emergency() -> bool:
	if _state != State.PLAYING:
		return false
	return change_state(State.EMERGENCY)


## Leaves EMERGENCY. If a pause menu covers the emergency (e.g. retry chosen from
## pause), the pause will resume into PLAYING instead.
func end_emergency() -> bool:
	if _state == State.EMERGENCY:
		return change_state(State.PLAYING)
	if _state == State.PAUSED and _resume_state == State.EMERGENCY:
		_resume_state = State.PLAYING
		_in_emergency = false
		emergency_exited.emit()
		return true
	return false


func is_in_menu() -> bool:
	return _state == State.MENU


func is_playing() -> bool:
	return _state == State.PLAYING


func is_paused() -> bool:
	return _state == State.PAUSED


func is_game_over() -> bool:
	return _state == State.GAME_OVER


## True from emergency start until it ends, including while paused over it.
func is_in_emergency() -> bool:
	return _in_emergency


func get_current_scene() -> Node:
	return get_tree().current_scene


func _on_emergency_started(_choice_count: int) -> void:
	begin_emergency()


func _emit_state_signal(old_state: State, new_state: State) -> void:
	match new_state:
		State.PLAYING:
			if old_state == State.PAUSED:
				game_resumed.emit()
			elif old_state != State.EMERGENCY:
				game_started.emit()
		State.EMERGENCY:
			if old_state == State.PAUSED:
				game_resumed.emit()
		State.PAUSED:
			game_paused.emit()
		State.GAME_OVER:
			game_over.emit()
		State.MENU:
			opened_menu.emit()


func preferences() -> Dictionary:
	_sync_existing_controls()
	return _preferences.duplicate()

func reload_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_preferences.volume = clampf(float(config.get_value("settings", "volume", 0.8)), 0, 1)
		_preferences.fullscreen = bool(config.get_value("settings", "fullscreen", false))
		_preferences.tutorial = bool(config.get_value("settings", "tutorial", true))
	config = ConfigFile.new()
	if config.load(AUDIO_PATH) == OK:
		_preferences.sound = not bool(config.get_value("audio", "muted", false))
	config = ConfigFile.new()
	if config.load(HUD_PATH) == OK:
		_preferences.hud = clampi(int(config.get_value("hud", "readout", 1)), 0, 2)
	apply_preferences()

func set_setting(key: String, value: Variant) -> bool:
	if not _preferences.has(key):
		return false
	if key == "volume":
		value = clampf(float(value), 0, 1)
	elif key == "hud":
		value = clampi(int(value), 0, 2)
	else:
		value = bool(value)
	_preferences[key] = value
	var config := ConfigFile.new()
	var path := SETTINGS_PATH
	if key == "sound":
		path = AUDIO_PATH
		config.load(path)
		config.set_value("audio", "muted", not value)
	elif key == "hud":
		path = HUD_PATH
		config.load(path)
		config.set_value("hud", "readout", value)
	else:
		config.load(path)
		config.set_value("settings", key, value)
	var saved := config.save(path) == OK
	if not saved:
		settings_save_failed.emit(path)
	apply_preferences()
	settings_changed.emit(_preferences.duplicate())
	return saved

func _component(name: StringName) -> Node:
	var scene := get_tree().current_scene
	if scene:
		for property in scene.get_property_list():
			if property.name == name:
				return scene.get(name) as Node
	return null

# Optional explicit adapters let the campaign pass its real feedback/HUD nodes.
func apply_preferences(feedback: Node = null, hud: Node = null) -> void:
	AudioServer.set_bus_mute(0, not _preferences.sound)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, _preferences.volume)))
	if DisplayServer.get_name() != "headless":
		var desired := DisplayServer.WINDOW_MODE_FULLSCREEN if _preferences.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != desired:
			DisplayServer.window_set_mode(desired)
	if feedback == null:
		feedback = _component(&"feedback")
	if hud == null:
		hud = _component(&"status_hud")
	if is_instance_valid(feedback):
		feedback.set("muted", not _preferences.sound)
	if is_instance_valid(hud):
		hud.set("readout_mode", _preferences.hud)

func _sync_existing_controls() -> void:
	var feedback := _component(&"feedback")
	var hud := _component(&"status_hud")
	var changed := false
	if is_instance_valid(feedback) and _preferences.sound == bool(feedback.get("muted")):
		_preferences.sound = not bool(feedback.get("muted"))
		changed = true
	if is_instance_valid(hud) and _preferences.hud != int(hud.get("readout_mode")):
		_preferences.hud = int(hud.get("readout_mode"))
		changed = true
	if changed:
		AudioServer.set_bus_mute(0, not _preferences.sound)
		settings_changed.emit(_preferences.duplicate())

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	var id := scene.get_instance_id() if scene else 0
	if id != _applied_scene_id:
		_applied_scene_id = id
		apply_preferences()
	_sync_time += delta
	if _sync_time >= 0.25:
		_sync_time = 0
		_sync_existing_controls()
