extends Control
const UI = preload("res://scenes/ui/ui_style.gd")
var won := false

func setup(data: Dictionary) -> void:
	won = bool(data.get("won", false))

func _ready() -> void:
	var column := UI.shell(self, "The museum is quiet" if won else "Another chance", "The burial device is dismantled. You made it out." if won else "A poor position need not be the end. Retry this room and choose a different opening.", 420)
	UI.button(column, "Play again" if won else "Retry room", func(): SceneManager.start_play() if won else SceneManager.request_restart_room()).grab_focus.call_deferred()
	UI.button(column, "Settings", func(): SceneManager.push_popup(&"Settings"))
	UI.button(column, "Return to main menu", func(): SceneManager.return_main())
	UI.button(column, "Quit", func(): get_tree().quit())
