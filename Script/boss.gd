extends CharacterBody2D

@export var speed_chase := 75.0
@export var max_hp: int = 120

@onready var hitbox: Area2D = $Hitbox

var _player: Node2D
var hp: int

signal died

func _ready() -> void:
	hp = max_hp
	_player = get_tree().get_first_node_in_group("player") as Node2D
	hitbox.body_entered.connect(_on_hitbox_body_entered)

func _physics_process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return

	var dir := (_player.global_position - global_position).normalized()
	velocity = dir * speed_chase
	move_and_slide()

func _on_hitbox_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.call("take_damage", 1)
		else:
			get_tree().reload_current_scene()

func get_hp() -> int:
	return hp

func take_damage(amount: int = 1) -> void:
	hp -= max(1, amount)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()
