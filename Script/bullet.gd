extends Area2D

@export var speed: float = 350.0
@export var life_time: float = 1.2
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
var _life_left: float
var _consumed: bool = false
var weapon_type: int = 0
var is_crit: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_life_left = life_time
	rotation = direction.angle()
	add_to_group("bullets")

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()

func _apply_damage_to(target: Node) -> void:
	if target == null:
		return

	# Prefer take_damage(int)
	if target.has_method("take_damage"):
		target.call("take_damage", damage, is_crit, weapon_type)
	elif target.has_method("die"):
		target.call("die")

func _resolve_damage_receiver(n: Node) -> Node:
	# If we hit a Hitbox Area2D, its parent is the real enemy/boss script node.
	if n == null:
		return null
	if n.has_method("take_damage"):
		return n
	var p := n.get_parent()
	if p != null and p.has_method("take_damage"):
		return p
	return n

func _consume_hit(collider: Node) -> void:
	if _consumed:
		return
	_consumed = true

	var target := _resolve_damage_receiver(collider)
	_apply_damage_to(target)
	queue_free()

func _on_body_entered(body: Node) -> void:
	if body == self:
		return
	if body.is_in_group("bullets"):
		return
	if body != null and body.is_in_group("player"):
		return
	_consume_hit(body)

func _on_area_entered(area: Area2D) -> void:
	if area == self:
		return
	if area.is_in_group("bullets"):
		return
	if area != null and area.is_in_group("player"):
		return
	_consume_hit(area)
