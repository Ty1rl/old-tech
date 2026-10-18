extends "res://scenes/ui/menu_layout.gd"
var won := false
@onready var retry: Button = %RetryButton
@onready var title: Label = %Title
@onready var subtitle: Label = %Subtitle
func setup(data: Dictionary) -> void:
	won = bool(data.get("won", false))
func _ready() -> void:
	super._ready()
	if won:
		title.text = "The museum is quiet"
		subtitle.text = "The burial device is dismantled. You made it out."
		retry.text = "Play again"
	UI.focus_on_open(self, retry)
func _on_retry() -> void:
	if won: SceneManager.start_play()
	else: SceneManager.request_restart_room()
func _on_settings() -> void: SceneManager.push_popup(&"Settings")
func _on_main() -> void: SceneManager.return_main()
func _on_quit() -> void: get_tree().quit()
