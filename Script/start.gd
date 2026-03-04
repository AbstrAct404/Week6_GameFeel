extends Node2D

func _on_button_pressed():
	print("START CLICKED")
	get_tree().change_scene_to_file("res://Scene/Main.tscn")
