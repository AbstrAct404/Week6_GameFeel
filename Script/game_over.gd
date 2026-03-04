extends Control  # or Node2D

func _on_restart_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scene/Main.tscn") # or MainGame.tscn

func _on_quit_button_pressed() -> void:
	get_tree().quit()
