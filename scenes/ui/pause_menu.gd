extends "res://scenes/ui/menu_layout.gd"
@onready var resume_button: Button = %ResumeButton
func _ready() -> void:
	super._ready()
	UI.focus_on_open(self, resume_button)
func _on_continue_button_pressed() -> void: GameState.resume()
func _on_settings_button_pressed() -> void: SceneManager.push_popup(&"Settings")
func _on_exit_button_pressed() -> void: SceneManager.return_main()
func _on_restart() -> void: SceneManager.request_restart_room()
func _on_quit() -> void: AudioManager.request_quit()
