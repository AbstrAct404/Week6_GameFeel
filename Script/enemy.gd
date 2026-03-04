extends CharacterBody2D

@export var speed_chase := 90.0
@export var max_hp: int = 20
@export var contact_damage: int = 1

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Area2D = $Hitbox

var _player: Node2D
var hp: int

# hit stop state
var _hitstop_t: float = 0.0
var _saved_speed_scale: float = 1.0

signal died

func _ready() -> void:
	hp = max_hp
	_player = get_tree().get_first_node_in_group("player") as Node2D
	hitbox.body_entered.connect(_on_hitbox_body_entered)

func _physics_process(delta: float) -> void:
	# Hit stop: pause only this enemy
	if _hitstop_t > 0.0:
		_hitstop_t -= delta
		velocity = Vector2.ZERO
		return
	else:
		# ensure animation resumes
		if anim != null:
			anim.speed_scale = _saved_speed_scale

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
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.call("take_damage", contact_damage)
		else:
			get_tree().reload_current_scene()

func get_hp() -> int:
	return hp

func take_damage(amount: int = 1, is_crit: bool = false, weapon_type: int = -1) -> void:
	hp -= max(1, amount)

	# 1) Hit stop
	_start_hitstop(is_crit, weapon_type)

	# 2) Hit flash
	_hit_flash()

	# 3) Popup damage (only crit or sniper)
	if is_crit or weapon_type == 3:
		_spawn_damage_popup(amount)

	if hp <= 0:
		die()

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
	# instant brighten -> quickly back
	anim.modulate = Color(1.8, 1.8, 1.8, 1)
	var tw := create_tween()
	tw.tween_property(anim, "modulate", Color(1, 1, 1, 1), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _spawn_damage_popup(amount: int) -> void:
	var lbl := Label.new()
	lbl.top_level = true
	lbl.z_index = 2000
	lbl.text = str(amount) + " !" 
	lbl.modulate = Color(1, 0.25, 0.25, 0.0) # start transparent red
	lbl.scale = Vector2(0.7, 0.7)

	# place above head
	var start_pos := global_position + Vector2(0, -28)
	lbl.global_position = start_pos

	# readable size without custom font
	var settings := LabelSettings.new()
	settings.font_size = 22
	lbl.label_settings = settings

	get_tree().current_scene.add_child(lbl)

	# Animate: fade in + grow + move up, then fade out while moving up
	var tw := create_tween()

	tw.tween_property(lbl, "modulate", Color(1, 0.25, 0.25, 1.0), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.25, 1.25), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -10), 0.10).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tw.tween_property(lbl, "modulate", Color(1, 0.25, 0.25, 0.0), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "global_position", start_pos + Vector2(0, -32), 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tw.tween_callback(func(): if is_instance_valid(lbl): lbl.queue_free())

func die() -> void:
	died.emit()
	queue_free()
