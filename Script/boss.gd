extends CharacterBody2D

@export var speed_chase := 75.0
@export var max_hp: int = 120

@onready var hitbox: Area2D = $Hitbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _player: Node2D
var hp: int

signal died

func _ready() -> void:
	hp = max_hp
	_player = get_tree().get_first_node_in_group("player") as Node2D

	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)

	# ---- Boss ignores wall + enemies collisions (body only) ----
	# This makes the boss pass through walls/enemies. Damage is still via Hitbox.
	collision_layer = 0
	collision_mask = 0

	# ---- Fix boss animation play ----
	if anim != null and anim.sprite_frames != null:
		# De-share frames to avoid being affected by other instances/resources
		anim.sprite_frames = anim.sprite_frames.duplicate(true)

		var to_play := ""
		if anim.sprite_frames.has_animation("idle"):
			to_play = "idle"
		elif anim.sprite_frames.has_animation("walk"):
			to_play = "walk"
		elif anim.sprite_frames.has_animation("default"):
			to_play = "default"
		else:
			var names := anim.sprite_frames.get_animation_names()
			if names.size() > 0:
				to_play = names[0]

		if to_play != "":
			anim.play(to_play)
			anim.frame = 0

func _physics_process(_delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return

	var dir := (_player.global_position - global_position)
	if dir.length_squared() > 0.001:
		dir = dir.normalized()
	velocity = dir * speed_chase
	move_and_slide()

	# optional: flip based on movement
	if anim != null and absf(velocity.x) > 0.01:
		anim.flip_h = velocity.x > 0.0

func _on_hitbox_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.call("take_damage", 1)
		else:
			get_tree().reload_current_scene()

func take_damage(amount: int = 1) -> void:
	hp -= max(1, amount)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()
