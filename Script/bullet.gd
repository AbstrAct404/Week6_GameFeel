extends Area2D

@export var speed: float = 350.0
@export var life_time: float = 1.2
@export var damage: int = 1

# Set by player
var weapon_type: int = 0
var is_crit: bool = false

var direction: Vector2 = Vector2.RIGHT
var _life_left: float

# Sniper trail
var _trail: Line2D = null
var _trail_points: Array[Vector2] = []
const _TRAIL_MAX_POINTS := 10

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_life_left = life_time
	rotation = direction.angle()

	# Sniper bullet gets a trail
	# WeaponType enum in player.gd: 0 pistol,1 rifle,2 shotgun,3 sniper
	if weapon_type == 3:
		_trail = Line2D.new()
		_trail.top_level = true
		_trail.width = 2.5
		_trail.default_color = Color(1, 1, 1, 0.85)
		add_child(_trail)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

	# Update trail
	if _trail != null:
		_trail_points.append(global_position)
		if _trail_points.size() > _TRAIL_MAX_POINTS:
			_trail_points.pop_front()
		_trail.clear_points()
		for p in _trail_points:
			_trail.add_point(p)

	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()

func _apply_damage(target: Node) -> void:
	if target == null:
		return

	# Prefer take_damage(dmg, is_crit, weapon_type)
	if target.has_method("take_damage"):
		# call with 3 args; enemy/boss will accept optional params
		target.call("take_damage", damage, is_crit, weapon_type)
	elif target.has_method("die"):
		target.call("die")

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		return

	# In your project, group "enemies" is on Hitbox Area2D sometimes.
	# If we hit a Hitbox, try parent as real enemy root.
	var real_target := body
	if body != null and not body.has_method("take_damage"):
		var p := body.get_parent()
		if p != null and p.has_method("take_damage"):
			real_target = p

	_apply_damage(real_target)
	queue_free()
