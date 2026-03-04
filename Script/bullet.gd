extends Area2D

@export var speed: float = 350.0
@export var life_time: float = 1.2
@export var damage: int = 1

var direction: Vector2 = Vector2.RIGHT
var _life_left: float
var _prev_pos: Vector2

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_life_left = life_time
	rotation = direction.angle()
	_prev_pos = global_position

func _physics_process(delta: float) -> void:
	var new_pos := global_position + direction * speed * delta

	# --- Raycast to prevent tunneling through walls ---
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_prev_pos, new_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [self]

	var result := space.intersect_ray(query)

	if result.size() > 0:
		var collider: Object = result.get("collider")
		# Ignore player
		if collider != null and collider is Node and (collider as Node).is_in_group("player"):
			global_position = new_pos
		else:
			# Snap to hit point and resolve hit
			global_position = result.get("position")
			_handle_hit(collider)
			return
	else:
		global_position = new_pos

	_prev_pos = global_position

	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()

func _handle_hit(collider: Object) -> void:
	if collider == null:
		queue_free()
		return

	if collider is Node:
		var body := collider as Node

		# Damage enemies (prefer take_damage, fallback to die)
		if body.has_method("take_damage"):
			body.call("take_damage", damage)
		elif body.has_method("die"):
			body.call("die")

	# Hit wall or anything else -> destroy bullet
	queue_free()

func _on_body_entered(body: Node) -> void:
	# Still keep this as backup for low-speed collisions
	if body.is_in_group("player"):
		return

	if body.has_method("take_damage"):
		body.call("take_damage", damage)
		queue_free()
	elif body.has_method("die"):
		body.call("die")
		queue_free()
	else:
		# Likely wall/obstacle area
		queue_free()
