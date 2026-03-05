extends CharacterBody2D

@export var max_hp: int = 1200
@export var contact_damage: int = 15  # damage per 20 frames while player in range

@onready var hitbox: Area2D = $Hitbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _player: Node2D
var hp: int
# Speed = player speed - 10 normally; when HP <= 50%, player default speed. Then multiplied by (1 - slow).
var _slow_factor: float = 0.0
var _slow_timer: float = 0.0

var _hitstop_t: float = 0.0
var _saved_speed_scale: float = 1.0
var _contact_dmg_frames: int = 0  # deal contact_damage per 20 frames while overlapping

# Teleport: when HP drops below 80%, 60%, 40%, 20%, 10%, 5% of max_hp (each triggers once), ~250 units ahead of player
const TELEPORT_HP_THRESHOLDS: Array[float] = [0.80, 0.60, 0.40, 0.20, 0.10, 0.05]
var _next_teleport_threshold_idx: int = 0
const TELEPORT_DISTANCE: float = 250.0

signal died

func _ready() -> void:
	hp = max_hp
	_next_teleport_threshold_idx = 0
	_player = get_tree().get_first_node_in_group("player") as Node2D
	if hitbox:
		hitbox.collision_mask = 1  # layer 1 = player
		hitbox.monitoring = true

	# Boss ignores wall/enemy collisions (body only)
	collision_layer = 0
	collision_mask = 0

	# ensure boss anim plays
	if anim != null and anim.sprite_frames != null:
		if anim.sprite_frames.has_animation("idle"):
			anim.play("idle")
		elif anim.sprite_frames.has_animation("walk"):
			anim.play("walk")
		else:
			var names := anim.sprite_frames.get_animation_names()
			if names.size() > 0:
				anim.play(names[0])

func _physics_process(delta: float) -> void:
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

	# Always face player
	if anim != null:
		if _player.global_position.x < global_position.x:
			anim.flip_h = false
		elif _player.global_position.x > global_position.x:
			anim.flip_h = true

	var base_speed: float = 190.0
	if _player != null and "speed" in _player:
		var player_speed: float = float(_player.get("speed"))
		if hp <= max_hp / 2:
			base_speed = player_speed  # phase 2: full player speed
		else:
			base_speed = player_speed - 10.0
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 0.0
	var effective_speed := base_speed * (1.0 - _slow_factor)
	var dir := (_player.global_position - global_position).normalized()
	velocity = dir * effective_speed
	move_and_slide()

	# Damage per 20 frames while player in hitbox range (skip if player invincible)
	const CONTACT_DAMAGE_INTERVAL_FRAMES := 20
	var overlapping := hitbox.get_overlapping_bodies()
	var player_in_range := false
	for body in overlapping:
		if body.is_in_group("player"):
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

func get_hp() -> int:
	return hp

func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = clampf(factor, 0.0, 1.0)
	_slow_timer = duration

func take_damage(amount: int = 1, is_crit: bool = false, weapon_type: int = -1) -> void:
	var actual = max(1, amount)
	hp -= actual

	_start_hitstop(is_crit, weapon_type)
	_hit_flash()

	# Teleport when HP crosses below 80%, 60%, 40%, 20%, 10%, 5% of max_hp (each once)
	while _next_teleport_threshold_idx < TELEPORT_HP_THRESHOLDS.size() and hp <= max_hp * TELEPORT_HP_THRESHOLDS[_next_teleport_threshold_idx]:
		_teleport_ahead_of_player()
		_next_teleport_threshold_idx += 1

	# Damage popup: all hits when effect 0 on; white = non-crit, red = crit
	var main := get_tree().current_scene
	if main != null and main.has_method("is_effect_enabled") and main.call("is_effect_enabled", 0):
		_spawn_damage_popup(amount, is_crit)

	if hp <= 0:
		die()

func _teleport_ahead_of_player() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
	if _player == null:
		return
	var dir: Vector2
	# Use player's movement direction; fallback to direction from boss to player if standing still
	if "velocity" in _player:
		var pv: Vector2 = _player.get("velocity")
		if pv.length_squared() > 25.0:
			dir = pv.normalized()
		else:
			dir = (_player.global_position - global_position).normalized()
	else:
		dir = (_player.global_position - global_position).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	global_position = _player.global_position + dir * TELEPORT_DISTANCE

func _start_hitstop(is_crit: bool, weapon_type: int) -> void:
	_saved_speed_scale = 1.0
	if anim != null:
		_saved_speed_scale = anim.speed_scale
		anim.speed_scale = 0.0
	_hitstop_t = 0.06 if (is_crit or weapon_type == 3) else 0.04

func _hit_flash() -> void:
	if anim == null:
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("is_effect_enabled") and not main.call("is_effect_enabled", 8):
		return
	anim.modulate = Color(1.8, 1.8, 1.8, 1)
	var tw := create_tween()
	tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _spawn_damage_popup(amount: int, is_crit: bool = false) -> void:
	var is_red := is_crit
	var color_start := Color(1, 1, 1, 0.0) if not is_red else Color(1, 0.25, 0.25, 0.0)
	var color_full := Color(1, 1, 1, 1.0) if not is_red else Color(1, 0.25, 0.25, 1.0)
	var color_end := Color(1, 1, 1, 0.0) if not is_red else Color(1, 0.25, 0.25, 0.0)

	var lbl := Label.new()
	lbl.top_level = true
	lbl.z_index = 2000
	lbl.text = ("!" if is_red else "") + str(amount)
	lbl.modulate = color_start
	lbl.scale = Vector2(0.7, 0.7)

	var start_pos := global_position + Vector2(0, -44)
	lbl.global_position = start_pos

	var settings := LabelSettings.new()
	settings.font_size = 26
	lbl.label_settings = settings

	get_tree().current_scene.add_child(lbl)

	var tw := create_tween()
	tw.tween_property(lbl, "modulate", color_full, 0.12)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.35, 1.35), 0.12)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -12), 0.12)
	tw.tween_property(lbl, "modulate", color_end, 0.26)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.05, 1.05), 0.26)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -40), 0.26)
	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

	get_tree().create_timer(0.45).timeout.connect(func(): if is_instance_valid(lbl): lbl.queue_free())

func die() -> void:
	died.emit()
	queue_free()
