extends Control


func _on_play_button_pressed() -> void:
	SceneManager.go_to("Game")


func _on_settings_button_pressed() -> void:
	pass # Replace with function body.


func _on_exit_button_pressed() -> void:
	get_tree().quit()
