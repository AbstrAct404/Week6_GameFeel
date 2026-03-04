extends Area2D

@export var speed: float = 350.0
@export var life_time: float = 1.2
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
var _life_left: float
var _consumed: bool = false
var weapon_type: int = 0
var is_crit: bool = false
# Pierce: pistol 2 enemies no wall, sniper 5 enemies + 1 wall, rifle/shotgun 2 enemies 50% after first. Set by player.
var max_pierce: int = 0
var max_wall_pierce: int = 0  # sniper 1, others 0
var _pierce_hit_ids: Array[int] = []
var _wall_pierce_count: int = 0
var _damage_halved: bool = false  # shotgun: true after first enemy hit

# Shotgun slow: apply to enemies/boss on hit
const SHOTGUN_SLOW_FACTOR: float = 0.35
const SHOTGUN_SLOW_DURATION: float = 1.2

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	# Collide with layer 1 (walls) and layer 2 (enemies) so we can distinguish and apply pierce rules
	collision_mask = 3  # 1 | 2
	_life_left = life_time
	rotation = direction.angle()
	add_to_group("bullets")

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()

func _apply_damage_to(target: Node, damage_mult: float = 1.0) -> void:
	if target == null:
		return

	var final_damage := int(float(damage) * damage_mult)
	if final_damage < 1:
		final_damage = 1
	if is_crit:
		final_damage = final_damage * 2  # crit = 2x damage for all weapons
	if target.has_method("take_damage"):
		target.call("take_damage", final_damage, is_crit, weapon_type)
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
	var target := _resolve_damage_receiver(collider)

	# Hit enemy/boss
	if target != null:
		var id := target.get_instance_id()
		if id in _pierce_hit_ids:
			return
		_pierce_hit_ids.append(id)
		# Rifle: first hit 100%, first pierce 80%, second pierce 50%
		var damage_mult := 1.0
		if weapon_type == 1:  # RIFLE
			match _pierce_hit_ids.size():
				0: damage_mult = 1.0
				1: damage_mult = 0.8
				2: damage_mult = 0.5
		_apply_damage_to(target, damage_mult)
		# Shotgun: apply slow to enemy/boss
		if weapon_type == 2 and target.has_method("apply_slow"):
			target.call("apply_slow", SHOTGUN_SLOW_FACTOR, SHOTGUN_SLOW_DURATION)
		# Shotgun: 50% after first enemy (rifle uses per-hit mult above)
		if weapon_type == 2 and not _damage_halved:
			_damage_halved = true
			damage = max(1, int(damage * 0.5))
		if _pierce_hit_ids.size() >= max_pierce:
			queue_free()
		return

	# Hit wall (not enemy): pistol/rifle/shotgun die, sniper pierce 1 wall
	if max_wall_pierce <= 0:
		queue_free()
		return
	_wall_pierce_count += 1
	if _wall_pierce_count > max_wall_pierce:
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
