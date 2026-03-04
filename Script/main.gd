extends Node2D

# Enemy spawning
@export var enemy_scene: PackedScene
@export var enemy_scenes: Array[PackedScene] = []

# Boss
@export var boss_spawn_time: float = 20.0
@export var boss_warning_time: float = 5.0

@onready var enemies_parent: Node2D = $World/Enemies
@onready var bosses_parent: Node2D = $World/Bosses
@onready var spawn_points: Array[Node] = $World/SpawnPoints.get_children()

@onready var player = $World/Player
@onready var hp_bar: ProgressBar = $UI/HpBar

@onready var music_normal: AudioStreamPlayer = $MusicNormal
@onready var music_boss: AudioStreamPlayer = $MusicBoss

func _find_sound_file(prefix: String, exts: Array[String]) -> String:
	var dir := DirAccess.open("res://Assets/Sound effects")
	if dir == null:
		push_error("Cannot open res://Assets/Sound effects")
		return ""
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var lower := name.to_lower()
			if lower.begins_with(prefix.to_lower()):
				for e in exts:
					if lower.ends_with(e.to_lower()):
						return "res://Assets/Sound effects/" + name
		name = dir.get_next()
	return ""

func _load_music_streams() -> void:
	if music_normal:
		music_normal.stream = load("res://Assets/Sound effects/BgmNormal.ogg")
	if music_boss:
		var p := _find_sound_file("Vanquish", [".mp3", ".ogg", ".wav"])
		if p != "":
			music_boss.stream = load(p)
		else:
			push_error("Vanquish music not found in Assets/Sound effects")


# marker -> enemy
var _corner_enemy := {}
var _boss: Node2D = null
var _boss_spawned: bool = false

func _ready() -> void:
	randomize()
	_load_music_streams()

	# Start normal BGM
	if music_normal:
		music_normal.play()
	if music_boss:
		music_boss.stop()

	# Boss scheduling
	_schedule_boss()

	# Backward-compatible: if you only set enemy_scene, it still works.
	if enemy_scenes.is_empty():
		if enemy_scene == null:
			push_error("No enemy scenes set! Set Main -> enemy_scenes (preferred) or enemy_scene in Inspector.")
			return
		# Populate from the legacy single scene
		enemy_scenes = [enemy_scene]

	# Filter nulls (in case Inspector array has empty slots)
	enemy_scenes = enemy_scenes.filter(func(s): return s != null)

	if enemy_scenes.is_empty():
		push_error("enemy_scenes is empty after filtering nulls.")
		return

	_spawn_initial_mix()

	# Spawn one per corner
	for node in spawn_points:
		var m := node as Marker2D
		if m == null:
			continue
		_spawn_at_corner(m)

	# --- UI HP bar ---
	if hp_bar != null and player != null:
		hp_bar.min_value = 0
		hp_bar.max_value = player.max_hp
		hp_bar.value = player.hp
		if player.has_signal("hp_changed"):
			player.hp_changed.connect(_on_player_hp_changed)


func _spawn_initial_mix() -> void:
	# Ensure at least one of each enemy type is present at game start.
	if enemy_scenes.size() < 4:
		return
	# Pick a base position: use first spawn point if available.
	var base := Vector2.ZERO
	if spawn_points.size() > 0 and spawn_points[0] is Marker2D:
		base = (spawn_points[0] as Marker2D).global_position
	# Spawn one of each with small offsets so they don't overlap perfectly.
	var offsets := [Vector2(-40, -40), Vector2(40, -40), Vector2(-40, 40), Vector2(40, 40)]
	for i in range(4):
		var packed := enemy_scenes[i]
		if packed == null:
			continue
		var e := packed.instantiate() as Node2D
		e.global_position = base + offsets[i]
		enemies_parent.add_child(e)


func _schedule_boss() -> void:
	# Play boss music boss_warning_time seconds before boss spawn.
	var warn_delay := maxf(0.0, boss_spawn_time - boss_warning_time)
	get_tree().create_timer(warn_delay).timeout.connect(_on_boss_warning)
	get_tree().create_timer(boss_spawn_time).timeout.connect(_spawn_boss)

func _on_boss_warning() -> void:
	# Start Vanquish 5s before boss appears
	if music_normal and music_normal.playing:
		music_normal.stop()
	if music_boss:
		music_boss.play()

func _spawn_boss() -> void:
	if _boss_spawned:
		return
	_boss_spawned = true

	var boss_scene: PackedScene = preload("res://Scene/Boss.tscn")
	_boss = boss_scene.instantiate() as Node2D
	if _boss == null:
		push_error("Failed to instantiate Boss.tscn")
		return

	# Spawn near center (or near player if available)
	var p := get_tree().get_first_node_in_group("player") as Node2D
	if p != null:
		_boss.global_position = p.global_position + Vector2(180, -60)
	else:
		_boss.global_position = Vector2.ZERO

	bosses_parent.add_child(_boss)

	if _boss.has_signal("died"):
		_boss.connect("died", Callable(self, "_on_boss_died"))

func _on_boss_died() -> void:
	# Stop boss music and return to normal BGM
	if music_boss and music_boss.playing:
		music_boss.stop()
	if music_normal:
		music_normal.play()

func _pick_enemy_scene() -> PackedScene:
	if enemy_scenes.is_empty():
		return enemy_scene
	return enemy_scenes[randi() % enemy_scenes.size()]

func _spawn_at_corner(m: Marker2D) -> void:
	# If somehow there is still a living enemy in this slot, don't double-spawn
	if _corner_enemy.has(m):
		var existing: Node = _corner_enemy[m] as Node
		if is_instance_valid(existing):
			return

	var packed := _pick_enemy_scene()
	if packed == null:
		push_error("Picked enemy scene is null.")
		return

	var e := packed.instantiate() as Node2D
	e.global_position = m.global_position
	$World/Enemies.call_deferred("add_child", e)

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
	if hp_bar == null:
		return
	hp_bar.max_value = max_hp
	hp_bar.value = current
