extends CharacterBody2D

@export var speed_chase: float = 90.0
@export var max_hp: int = 3
@export var contact_damage: int = 1

# how often to request a new path waypoint from Main
@export var repath_interval: float = 0.25
@export var waypoint_reach_dist: float = 10.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox

var hp: int
var _player: Node2D
var _main: Node
var _repath_cd: float = 0.0
var _waypoint: Vector2 = Vector2.ZERO

signal died

func _ready() -> void:
	hp = max_hp

	# ---- IMPORTANT: de-share SpriteFrames per instance to avoid override/flicker ----
	if anim != null and anim.sprite_frames != null:
		# Duplicate with subresources to ensure each enemy instance has its own frames
		anim.sprite_frames = anim.sprite_frames.duplicate(true)
		# Start from a stable animation/frame
		if anim.sprite_frames.has_animation("idle"):
			anim.play("idle")
		elif anim.sprite_frames.has_animation("walk"):
			anim.play("walk")
		else:
			# if user named animations differently, just play the first available
			var names := anim.sprite_frames.get_animation_names()
			if names.size() > 0:
				anim.play(names[0])
		anim.frame = 0

	_player = get_tree().get_first_node_in_group("player") as Node2D
	_main = get_tree().current_scene

	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return

	if _main == null:
		_main = get_tree().current_scene

	_repath_cd -= delta

	# refresh waypoint periodically or when close to current waypoint
	if _repath_cd <= 0.0 or (_waypoint != Vector2.ZERO and global_position.distance_to(_waypoint) <= waypoint_reach_dist):
		_repath_cd = repath_interval
		_waypoint = _get_waypoint()

	var target := _player.global_position
	if _waypoint != Vector2.ZERO:
		target = _waypoint

	var dir := target - global_position
	if dir.length_squared() > 0.001:
		dir = dir.normalized()

	velocity = dir * speed_chase
	move_and_slide()

	_update_anim()

func _get_waypoint() -> Vector2:
	if _main != null and _main.has_method("get_next_path_point"):
		var p = _main.call("get_next_path_point", global_position, _player.global_position)
		if typeof(p) == TYPE_VECTOR2:
			return p
	return Vector2.ZERO

func _update_anim() -> void:
	if anim == null or anim.sprite_frames == null:
		return

	var want := "idle"
	if velocity.length_squared() > 1.0:
		want = "walk"

	# Only play if the animation exists in this enemy's SpriteFrames
	if anim.sprite_frames.has_animation(want):
		if anim.animation != want:
			anim.play(want)

	# face direction
	if absf(velocity.x) > 0.01:
		anim.flip_h = velocity.x < 0.0

func _on_hitbox_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.call("take_damage", contact_damage)
		else:
			get_tree().reload_current_scene()

func take_damage(amount: int = 1) -> void:
	hp -= max(1, amount)
	if hp <= 0:
		die()

func die() -> void:
	died.emit()
	queue_free()
