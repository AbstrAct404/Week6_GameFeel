extends CharacterBody2D

@export var speed_chase := 80.0
@export var max_hp: int = 20
@export var contact_damage: int = 3  # damage per 20 frames while player in range

# Pathfinding: use waypoints from Main so we go around walls, not shortest line
@export var repath_interval: float = 0.25
@export var waypoint_reach_dist: float = 12.0

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox

var _last_hit_weapon_type: int = -1
var _player: Node2D
var hp: int
var _main: Node
var _repath_cd: float = 0.0
var _waypoint: Vector2 = Vector2.ZERO
var _last_waypoint_dist: float = -1.0
var _stuck_timer: float = 0.0
const STUCK_TIME_THRESHOLD: float = 0.4

# hit stop state
var _hitstop_t: float = 0.0
var _saved_speed_scale: float = 1.0
var _contact_dmg_frames: int = 0  # deal contact_damage per 20 frames while overlapping
var _slow_factor: float = 0.0
var _slow_timer: float = 0.0

signal died

func _ready() -> void:
	hp = max_hp
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_main = get_tree().current_scene
	# Enemies on layer 2 so player can disable collision with them during invincibility
	collision_layer = 2
	if hitbox:
		hitbox.collision_mask = 1  # layer 1 = player, so overlapping_bodies() can detect player
		hitbox.monitoring = true

func _physics_process(delta: float) -> void:
	# Hit stop: pause only this enemy
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		velocity = Vector2.ZERO
		return
	else:
		if anim != null:
			anim.speed_scale = _saved_speed_scale

	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	if _main == null:
		_main = get_tree().current_scene

	_repath_cd -= delta
	if _repath_cd <= 0.0 or (_waypoint != Vector2.ZERO and global_position.distance_to(_waypoint) <= waypoint_reach_dist):
		_repath_cd = repath_interval
		_waypoint = _get_waypoint()

	var target := _player.global_position
	if _waypoint != Vector2.ZERO:
		target = _waypoint

	var dir := target - global_position
	if dir.length_squared() > 0.001:
		dir = dir.normalized()

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 0.0
	var move_speed := speed_chase * (1.0 - _slow_factor)
	velocity = dir * move_speed
	move_and_slide()

	# Wall collision: slide along wall and force repath
	var col := get_last_slide_collision()
	if col != null:
		var n := col.get_normal()
		var slide_dir := velocity - (velocity.dot(n) * n)
		if slide_dir.length_squared() > 100.0:
			velocity = slide_dir.normalized() * move_speed
		_repath_cd = 0.0

	# Stuck detection
	if _waypoint != Vector2.ZERO:
		var d := global_position.distance_to(_waypoint)
		if _last_waypoint_dist >= 0.0 and d >= _last_waypoint_dist - 1.0:
			_stuck_timer += delta
			if _stuck_timer >= STUCK_TIME_THRESHOLD:
				_repath_cd = 0.0
				_waypoint = Vector2.ZERO
				_stuck_timer = 0.0
		else:
			_stuck_timer = 0.0
		_last_waypoint_dist = d
	else:
		_last_waypoint_dist = -1.0
		_stuck_timer = 0.0

	# Damage per 20 frames while player in hitbox range (skip if player invincible)
	const CONTACT_DAMAGE_INTERVAL_FRAMES := 20
	var overlapping := hitbox.get_overlapping_bodies()
	var player_in_range := false
	for body in overlapping:
		if body != null and body.is_in_group("player"):
			if body.has_method("is_invincible") and body.call("is_invincible"):
				break
			player_in_range = true
			_contact_dmg_frames += 1
			if _contact_dmg_frames >= CONTACT_DAMAGE_INTERVAL_FRAMES:
				_contact_dmg_frames = 0
				if body.has_method("take_damage"):
					body.call("take_damage", contact_damage)
				else:
					get_tree().reload_current_scene()
			break
	if not player_in_range:
		_contact_dmg_frames = 0

	_update_anim()

func _get_waypoint() -> Vector2:
	if _main != null and _main.has_method("get_next_path_point"):
		var p = _main.call("get_next_path_point", global_position, _player.global_position)
		if typeof(p) == TYPE_VECTOR2:
			return p
	return Vector2.ZERO

func _update_anim() -> void:
	if velocity.length_squared() > 1.0:
		if anim.animation != "walk":
			anim.play("walk")
		if absf(velocity.x) > 0.01:
			anim.flip_h = velocity.x < 0.0
	else:
		if anim.animation != "idle":
			anim.play("idle")

func get_hp() -> int:
	return hp

func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = clampf(factor, 0.0, 1.0)
	_slow_timer = duration

func take_damage(amount: int = 1, is_crit: bool = false, weapon_type: int = -1) -> void:
	_last_hit_weapon_type = weapon_type
	hp -= max(1, amount)
	if hp <= 0:
		_on_killed()
		die()

	# 1) Hit stop
	_start_hitstop(is_crit, weapon_type)

	# 2) Hit flash
	_hit_flash()

	# 3) Popup damage: all hits when effect 0 on; white = non-crit, red = crit
	if _main == null:
		_main = get_tree().current_scene
	if _main == null or not _main.has_method("is_effect_enabled") or _main.call("is_effect_enabled", 0):
		_spawn_damage_popup(amount, is_crit)

func _on_killed() -> void:
	if _last_hit_weapon_type == 0:
		var main := get_tree().current_scene
		if main != null and main.has_method("on_pistol_kill"):
			main.call("on_pistol_kill")
			
func _start_hitstop(is_crit: bool, weapon_type: int) -> void:
	_saved_speed_scale = 1.0
	if anim != null:
		_saved_speed_scale = anim.speed_scale
		anim.speed_scale = 0.0

	# base 0.04; crit/sniper 0.06
	_hitstop_t = 0.06 if (is_crit or weapon_type == 3) else 0.04

func _hit_flash() -> void:
	if anim == null:
		return
	# Effect toggle 8: enemy on-hit turn white
	if _main != null and _main.has_method("is_effect_enabled") and not _main.call("is_effect_enabled", 8):
		return
	anim.modulate = Color(1.8, 1.8, 1.8, 1)
	var tw := create_tween()
	tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _spawn_damage_popup(amount: int, is_crit: bool = false) -> void:
	var is_red := is_crit
	var color_start := Color(1, 1, 1, 0.0) if not is_red else Color(1, 0.25, 0.25, 0.0)
	var color_full := Color(1, 1, 1, 1.0) if not is_red else Color(1, 0.25, 0.25, 1.0)
	var color_end := Color(1, 1, 1, 0.0) if not is_red else Color(1, 0.25, 0.25, 0.0)

	var lbl := Label.new()
	lbl.top_level = true
	lbl.z_index = 2000
	lbl.text = str(amount) + (" !" if is_red else "")
	lbl.modulate = color_start
	lbl.scale = Vector2(0.7, 0.7)

	var start_pos := global_position + Vector2(0, -28)
	lbl.global_position = start_pos

	var settings := LabelSettings.new()
	settings.font_size = 22
	lbl.label_settings = settings

	get_tree().current_scene.add_child(lbl)

	var tw := create_tween()
	tw.tween_property(lbl, "modulate", color_full, 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.25, 1.25), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -10), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate", color_end, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -32), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

	get_tree().create_timer(0.38).timeout.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

func die() -> void:
	died.emit()
	queue_free()
