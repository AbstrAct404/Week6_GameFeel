extends CharacterBody2D

var can_hit := true
@export var contact_damage: int = 10

@export var speed_chase := 90.0
@export var max_hp: int = 3

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
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

	_update_anim()

func _update_anim() -> void:
	if velocity.length_squared() > 1.0:
		if anim.animation != "walk":
			anim.play("walk")
		if absf(velocity.x) > 0.01:
			anim.flip_h = velocity.x < 0.0
	else:
		if anim.animation != "idle":
			anim.play("idle")

func _on_hitbox_body_entered(body: Node) -> void:
	if not can_hit:
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		can_hit = false
		body.take_damage(contact_damage)
		await get_tree().create_timer(0.6).timeout
		can_hit = true

func get_hp() -> int:
	return hp

func take_damage(amount: int = 1) -> void:
	hp -= max(1, amount)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()
