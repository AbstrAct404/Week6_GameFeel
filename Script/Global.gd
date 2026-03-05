extends Node

var result_text: String = "" # "WIN" or "LOST"

func set_win() -> void:
	result_text = "WIN"

func set_lost() -> void:
	result_text = "LOST"
