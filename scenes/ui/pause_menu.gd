extends "res://scenes/ui/menu_layout.gd"
@onready var resume_button: Button = %ResumeButton
@onready var developer_button: Button = %DeveloperButton
func _ready() -> void:
	super._ready()
	developer_button.visible = SceneManager.developer_tools
	UI.focus_on_open(self, resume_button)
func _on_continue_button_pressed() -> void: GameState.resume()
func _on_settings_button_pressed() -> void: SceneManager.push_popup(&"Settings")
func _on_exit_button_pressed() -> void: SceneManager.return_main()
func _on_developer() -> void: SceneManager.push_popup(&"Developer")
func _on_restart() -> void: SceneManager.request_restart_room()
func _on_quit() -> void: get_tree().quit()
