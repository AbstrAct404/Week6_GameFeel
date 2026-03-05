# game_over.gd
extends Control

@export var main_scene_path: String = "res://Scene/Main.tscn"

@onready var restart_btn: Button = $Restart
@onready var quit_btn: Button = $Quit

# OPTIONAL: if you add a Label named ResultLabel under GameOver, this will auto-use it.
@onready var result_label: Label = get_node_or_null("ResultLabel") as Label

func _ready() -> void:
	# Show / print result
	var text := "LOST"
	if Global.result_text == "WIN":
		text = "WIN"

	print(text)
	if result_label != null:
		result_label.text = text

	# Connect buttons (works for mouse click)
	restart_btn.pressed.connect(_on_restart_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

func _on_restart_pressed() -> void:
	# optional reset
	Global.result_text = ""
	get_tree().change_scene_to_file(main_scene_path)

func _on_quit_pressed() -> void:
	get_tree().quit()
