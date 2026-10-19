extends "res://scenes/ui/menu_layout.gd"
var won := false
var _open_frame := -1
var _suppress_accept_until_release := false
var _suppress_mouse_until_release := false
@onready var retry: Button = %RetryButton
@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
func setup(data: Dictionary) -> void:
	won = bool(data.get("won", false))
func _ready() -> void:
	super._ready()
	_open_frame = Engine.get_process_frames()
	_suppress_accept_until_release = (
		Input.is_key_pressed(KEY_ENTER)
		or Input.is_key_pressed(KEY_KP_ENTER)
		or Input.is_action_pressed(&"ui_accept")
	)
	_suppress_mouse_until_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if won:
		title.text = "The museum is quiet"
		subtitle.text = "The burial device is dismantled. You made it out."
		retry.text = "Play again"
	else:
		title.text = "Another chance"
		subtitle.text = "Retry this room with a fresh time meter and rewind budget."
		retry.text = "Retry room"
	UI.focus_on_open(self, retry)
func arm_held_input_guard(accept_held: bool, mouse_held: bool) -> void:
	if accept_held:
		_suppress_accept_until_release = true
	if mouse_held:
		_suppress_mouse_until_release = true
func _input(event: InputEvent) -> void:
	var same_frame := Engine.get_process_frames() == _open_frame
	if event is InputEventKey:
		var kcode: int = event.physical_keycode if event.physical_keycode else event.keycode
		var is_accept := kcode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] or event.is_action(&"ui_accept")
		if is_accept:
			if same_frame:
				_suppress_accept_until_release = event.pressed
				if is_instance_valid(retry):
					retry.button_pressed = false
				get_viewport().set_input_as_handled()
				return
			if _suppress_accept_until_release:
				if not event.pressed:
					_suppress_accept_until_release = false
				if is_instance_valid(retry):
					retry.button_pressed = false
				get_viewport().set_input_as_handled()
				return
			if event.echo:
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if same_frame:
			_suppress_mouse_until_release = event.pressed
			if is_instance_valid(retry):
				retry.button_pressed = false
			get_viewport().set_input_as_handled()
			return
		if _suppress_mouse_until_release:
			if not event.pressed:
				_suppress_mouse_until_release = false
			if is_instance_valid(retry):
				retry.button_pressed = false
			get_viewport().set_input_as_handled()
			return
func _on_retry() -> void:
	if won: SceneManager.push_popup(&"NewGame")
	else: SceneManager.request_restart_room()
func _on_settings() -> void: SceneManager.push_popup(&"Settings")
func _on_main() -> void: SceneManager.return_main()
func _on_quit() -> void: get_tree().quit()

