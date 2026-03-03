extends Area2D

@export var speed: float = 350.0
@export var life_time: float = 1.2

var direction: Vector2 = Vector2.RIGHT
var _life_left: float

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_life_left = life_time
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta

	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	# Ignore the player so bullets don't delete instantly
	if body.is_in_group("player"):
		return

	# Only kill enemies
	if body.has_method("die"):
		body.call("die")
		queue_free()
