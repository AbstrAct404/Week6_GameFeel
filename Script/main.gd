extends Node2D

@onready var player = $World/Player
@onready var hp_bar: ProgressBar = $UI/HpBar

@export var enemy_scene: PackedScene

@onready var enemies_parent: Node2D = $World/Enemies
@onready var spawn_points: Array[Node] = $World/SpawnPoints.get_children()


# marker -> enemy
var _corner_enemy := {}

func _ready() -> void:
	if enemy_scene == null:
		push_error("enemy_scene not set! Drag Enemy.tscn into main.gd -> enemy_scene.")
		return

	# Spawn one per corner
	for node in spawn_points:
		var m := node as Marker2D
		if m == null:
			continue
		_spawn_at_corner(m)
	
	hp_bar.min_value = 0
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp

	player.hp_changed.connect(_on_player_hp_changed)

func _spawn_at_corner(m: Marker2D) -> void:
	# If somehow there is still a living enemy in this slot, don't double-spawn
	if _corner_enemy.has(m):
		var existing: Node = _corner_enemy[m] as Node
		if is_instance_valid(existing):
			return

	var e := enemy_scene.instantiate() as Node2D
	e.global_position = m.global_position
	enemies_parent.add_child(e)

	_corner_enemy[m] = e

	# Respawn when this enemy dies
	# (enemy.gd must have `signal died`)
	if e.has_signal("died"):
		e.connect("died", Callable(self, "_on_enemy_died").bind(m))
	else:
		push_error("Enemy scene missing 'died' signal. Add: signal died  in enemy.gd")

func _on_enemy_died(m: Marker2D) -> void:
	_corner_enemy.erase(m)
	_spawn_at_corner(m)

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = current
