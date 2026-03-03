extends CharacterBody2D

@export var speed: float = 220.0
@export var auto_range: float = 550.0

@export var bullet_scene: PackedScene
@export var shoot_cooldown: float = 0.45
@export var bullet_spawn_offset: float = 12.0

@onready var anim: AnimatedSprite2D = $Sprite
@onready var fire_point: Node = get_node_or_null("MuzzlePivot/FirePoint")

@onready var muzzle: Node2D = $MuzzlePivot
@onready var gun: Sprite2D = $MuzzlePivot/Gun

var _cooldown_t: float = 0.0

func _physics_process(delta: float) -> void:
	# --- movement ---
	var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = move_dir * speed
	move_and_slide()

	# --- movement animation ---
	_update_move_anim(move_dir)

	# --- auto aim ---
	var target := find_closest_enemy()
	if target != null:
		_aim_at(target.global_position)

	# --- shoot on key with cooldown ---
	_cooldown_t = maxf(_cooldown_t - delta, 0.0)

	if target != null and Input.is_action_pressed("shoot") and _cooldown_t <= 0.0:
		_cooldown_t = shoot_cooldown
		shoot_at(target.global_position)

func _update_move_anim(move_dir: Vector2) -> void:
	if move_dir.length_squared() > 0.0:
		if anim.animation != "walk":
			anim.play("walk")
	else:
		if anim.animation != "idle":
			anim.play("idle")

	if move_dir.x != 0.0:
		anim.flip_h = move_dir.x < 0.0

func find_closest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d2: float = auto_range * auto_range

	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Node2D
		if e == null:
			continue
		var d2 := (e.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = e

	return best

func shoot_at(pos: Vector2) -> void:
	if bullet_scene == null:
		push_warning("bullet_scene is null. Drag Bullet.tscn into Player -> bullet_scene in Inspector.")
		return

	# Fire point fallback: if FirePoint node is missing, use muzzle position
	var spawn_pos: Vector2
	if fire_point != null and fire_point is Node2D:
		spawn_pos = (fire_point as Node2D).global_position
	else:
		spawn_pos = muzzle.global_position

	var dir_vec := pos - spawn_pos
	if dir_vec.length_squared() < 0.0001:
		return
	var dir := dir_vec.normalized()

	var b := bullet_scene.instantiate()
	# bullet.gd should have: var direction: Vector2
	b.direction = dir
	b.global_position = spawn_pos + dir * bullet_spawn_offset

	var bullets := get_tree().current_scene.get_node_or_null("World/Bullets") as Node2D
	if bullets != null:
		bullets.add_child(b)
	else:
		get_tree().current_scene.add_child(b)	
		


func _aim_at(target_pos: Vector2) -> void:
	var dir := target_pos - muzzle.global_position
	if dir.length_squared() < 0.0001:
		return

	var ang := dir.angle()
	muzzle.rotation = ang

	# 1) left/right mirror
	if gun:
		gun.flip_h = dir.x < 0.0   # target on left => flip horizontally

	# 2) keep visually upright (avoid upside-down)
	var a := wrapf(muzzle.rotation, -PI, PI)
	if a > PI * 0.5 or a < -PI * 0.5:
		muzzle.rotation += PI
		if gun: gun.flip_v = true
	else:
		if gun: gun.flip_v = false
