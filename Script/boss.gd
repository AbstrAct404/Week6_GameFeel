extends CharacterBody2D

@export var speed_chase := 75.0
@export var max_hp: int = 120

@onready var hitbox: Area2D = $Hitbox
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var _player: Node2D
var hp: int

var _hitstop_t: float = 0.0
var _saved_speed_scale: float = 1.0

signal died

func _ready() -> void:
	hp = max_hp
	_player = get_tree().get_first_node_in_group("player") as Node2D
	hitbox.body_entered.connect(_on_hitbox_body_entered)

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

func take_damage(amount: int = 1, is_crit: bool = false, weapon_type: int = -1) -> void:
	hp -= max(1, amount)

	_start_hitstop(is_crit, weapon_type)
	_hit_flash()

	if is_crit or weapon_type == 3:
		_spawn_damage_popup(amount)

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
	anim.modulate = Color(1.8, 1.8, 1.8, 1)
	var tw := create_tween()
	tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _spawn_damage_popup(amount: int) -> void:
	var lbl := Label.new()
	lbl.top_level = true
	lbl.z_index = 2000
	lbl.text = "!" + str(amount)
	lbl.modulate = Color(1, 0.25, 0.25, 0.0)
	lbl.scale = Vector2(0.7, 0.7)

	var start_pos := global_position + Vector2(0, -44)
	lbl.global_position = start_pos

	var settings := LabelSettings.new()
	settings.font_size = 26
	lbl.label_settings = settings

	get_tree().current_scene.add_child(lbl)

	var tw := create_tween()
	tw.tween_property(lbl, "modulate", Color(1, 0.25, 0.25, 1.0), 0.12)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.35, 1.35), 0.12)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -12), 0.12)

	tw.tween_property(lbl, "modulate", Color(1, 0.25, 0.25, 0.0), 0.26)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.05, 1.05), 0.26)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -40), 0.26)

	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

func die() -> void:
	died.emit()
	queue_free()
