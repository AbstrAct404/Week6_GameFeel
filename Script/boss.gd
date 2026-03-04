extends CharacterBody2D

@export var max_hp: int = 1200
@export var contact_damage: int = 10  # damage per second while player in range

@onready var hitbox: Area2D = $Hitbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _player: Node2D
var hp: int
# Speed = player speed + 10, then multiplied by (1 - slow). Slow can be applied by debuffs.
var _slow_factor: float = 0.0

var _hitstop_t: float = 0.0
var _saved_speed_scale: float = 1.0
var _contact_dmg_timer: float = 0.0  # deal contact_damage per second while overlapping

signal died

func _ready() -> void:
	hp = max_hp
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
		base_speed = float(_player.get("speed")) - 40.0
	var effective_speed := base_speed * (1.0 - _slow_factor)
	var dir := (_player.global_position - global_position).normalized()
	velocity = dir * effective_speed
	move_and_slide()

	# Damage per second while player in hitbox range (skip if player invincible)
	var overlapping := hitbox.get_overlapping_bodies()
	var player_in_range := false
	for body in overlapping:
		if body.is_in_group("player"):
			if body.has_method("is_invincible") and body.call("is_invincible"):
				break
			player_in_range = true
			_contact_dmg_timer += delta
			while _contact_dmg_timer >= 1.0:
				_contact_dmg_timer -= 1.0
				if body.has_method("take_damage"):
					body.call("take_damage", contact_damage)
				else:
					get_tree().reload_current_scene()
			break
	if not player_in_range:
		_contact_dmg_timer = 0.0

func get_hp() -> int:
	return hp

func take_damage(amount: int = 1, is_crit: bool = false, weapon_type: int = -1) -> void:
	hp -= max(1, amount)

	_start_hitstop(is_crit, weapon_type)
	_hit_flash()

	# Damage popup: all hits when effect 0 on; white = non-crit, red = crit
	var main := get_tree().current_scene
	if main != null and main.has_method("is_effect_enabled") and main.call("is_effect_enabled", 0):
		_spawn_damage_popup(amount, is_crit)

	if hp <= 0:
		die()

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
