extends Control


func _on_continue_button_pressed() -> void:
	GameState.resume()


func _on_settings_button_pressed() -> void:
	pass # Replace with function body.


func _on_exit_button_pressed() -> void:
	SceneManager.go_to("Main")
	SceneManager.clear_popups()
	GameState.open_menu()
