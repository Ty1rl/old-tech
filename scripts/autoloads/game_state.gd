extends Node

enum State { MENU, PLAYING, PAUSED, GAME_OVER }

signal state_changed(old_state: State, new_state: State)
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal opened_menu

var state: State:
	get: return _state

var _state: State = State.MENU


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()


## Only toggles between PLAYING and PAUSED.
## Ignored when in MENU and GAME_OVER.
func toggle_pause() -> bool:
	match _state:
		State.PLAYING:
			return pause()
		State.PAUSED:
			return resume()
	return false


func change_state(new_state: State) -> bool:
	if new_state == _state:
		return false
	
	var old_state: State = _state
	_state = new_state
	get_tree().paused = (_state == State.PAUSED)
	
	state_changed.emit(old_state, _state)
	_emit_state_signal(old_state, _state)
	return true


func start_game() -> bool:
	return change_state(State.PLAYING)


func end_game() -> bool:
	return change_state(State.GAME_OVER)


func open_menu() -> bool:
	return change_state(State.MENU)


func pause() -> bool:
	SceneManager.push_popup("PauseMenu")
	return change_state(State.PAUSED)


func resume() -> bool:
	SceneManager.close_popup("PauseMenu")
	return change_state(State.PLAYING)


func is_in_menu() -> bool:
	return _state == State.MENU


func is_playing() -> bool:
	return _state == State.PLAYING


func is_paused() -> bool:
	return _state == State.PAUSED


func is_game_over() -> bool:
	return _state == State.GAME_OVER


func get_current_scene() -> Node:
	return get_tree().current_scene


func _emit_state_signal(old_state: State, new_state: State) -> void:
	match new_state:
		State.PLAYING:
			if old_state == State.PAUSED:
				game_resumed.emit()
			else:
				game_started.emit()
		State.PAUSED:
			game_paused.emit()
		State.GAME_OVER:
			game_over.emit()
		State.MENU:
			opened_menu.emit()
