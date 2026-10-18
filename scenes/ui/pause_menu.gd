extends Control
const UI = preload("res://scenes/ui/ui_style.gd")

func _ready() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var column := UI.shell(self, "Paused", "Your place in the museum is held.", 430)
	UI.button(column, "Resume", _on_continue_button_pressed, "ResumeButton").grab_focus.call_deferred()
	UI.button(column, "Settings", _on_settings_button_pressed)
	if SceneManager.developer_tools:
		UI.button(column, "Encounter select", func(): SceneManager.push_popup(&"Developer"))
	UI.button(column, "Restart room", func(): SceneManager.request_restart_room())
	UI.button(column, "Return to main menu", _on_exit_button_pressed)
	UI.button(column, "Quit", func(): get_tree().quit())

func _on_continue_button_pressed() -> void:
	GameState.resume()

func _on_settings_button_pressed() -> void:
	SceneManager.push_popup(&"Settings")

func _on_exit_button_pressed() -> void:
	SceneManager.return_main()
