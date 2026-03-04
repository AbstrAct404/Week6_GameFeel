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

@onready var wall_layer: TileMapLayer = $World/TM_Wall

var rng := RandomNumberGenerator.new()

# marker -> enemy
var _corner_enemy := {}
var _boss: Node2D = null
var _boss_spawned: bool = false

# A* grid for enemies
var _astar: AStarGrid2D = AStarGrid2D.new()
var _astar_ready: bool = false
var _tile_size: Vector2 = Vector2(16, 16)

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

func _ready() -> void:
	rng.randomize()
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
		enemy_scenes = [enemy_scene]

	# Filter nulls
	enemy_scenes = enemy_scenes.filter(func(s): return s != null)
	if enemy_scenes.is_empty():
		push_error("enemy_scenes is empty after filtering nulls.")
		return

	_build_astar_grid()

	# Spawn enemies ONLY at 4 corner points (your scene has: ConerTL, CornerTR, CornerBL, CornerBR)
	var corner_markers := _get_corner_spawn_markers()
	for m in corner_markers:
		_spawn_at_corner(m)

	# --- UI HP bar ---
	if hp_bar != null and player != null:
		hp_bar.min_value = 0
		hp_bar.max_value = player.max_hp
		hp_bar.value = player.hp
		if player.has_signal("hp_changed"):
			player.hp_changed.connect(_on_player_hp_changed)

func _get_corner_spawn_markers() -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	for node in spawn_points:
		var m := node as Marker2D
		if m == null:
			continue
		# 注意：你的左上角点拼成了 ConerTL（少了一个 r），这里要兼容
		if m.name == "ConerTL" or m.name.begins_with("Corner"):
			# SpawnBoss 也 begins_with("Corner")? 不是，所以不会被选中
			if m.name == "SpawnBoss":
				continue
			out.append(m)
	return out

func _pick_enemy_scene() -> PackedScene:
	if enemy_scenes.is_empty():
		return enemy_scene
	return enemy_scenes[rng.randi_range(0, enemy_scenes.size() - 1)]

func _spawn_at_corner(m: Marker2D) -> void:
	# Prevent double spawn at same marker
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
	enemies_parent.call_deferred("add_child", e)

	_corner_enemy[m] = e

	# Respawn when this enemy dies
	if e.has_signal("died"):
		e.connect("died", Callable(self, "_on_enemy_died").bind(m))
	else:
		push_error("Enemy scene missing 'died' signal. Add: signal died in enemy.gd")

func _on_enemy_died(m: Marker2D) -> void:
	_corner_enemy.erase(m)
	_spawn_at_corner(m)

# ---------------- Boss ----------------

func _schedule_boss() -> void:
	var warn_delay := maxf(0.0, boss_spawn_time - boss_warning_time)
	get_tree().create_timer(warn_delay).timeout.connect(_on_boss_warning)
	get_tree().create_timer(boss_spawn_time).timeout.connect(_spawn_boss)

func _on_boss_warning() -> void:
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

	# Use SpawnBoss marker if exists; fallback to near player
	var spawn_boss := $World/SpawnPoints.get_node_or_null("SpawnBoss") as Marker2D
	var pos := Vector2.ZERO
	if spawn_boss != null:
		pos = spawn_boss.global_position
	else:
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null:
			pos = p.global_position + Vector2(180, -60)

	# Snap boss position to nearest walkable cell (avoid spawning into wall)
	pos = _snap_global_to_walkable(pos)

	_boss.global_position = pos
	bosses_parent.add_child(_boss)

	if _boss.has_signal("died"):
		_boss.connect("died", Callable(self, "_on_boss_died"))

func _on_boss_died() -> void:
	if music_boss and music_boss.playing:
		music_boss.stop()
	if music_normal:
		music_normal.play()

# ---------------- UI ----------------

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	if hp_bar == null:
		return
	hp_bar.max_value = max_hp
	hp_bar.value = current

# ---------------- Pathfinding Service for enemies ----------------
# Enemy calls: get_next_path_point(enemy_global, player_global) -> Vector2 (world)
func get_next_path_point(from_global: Vector2, to_global: Vector2) -> Vector2:
	if not _astar_ready:
		_build_astar_grid()
		if not _astar_ready:
			return Vector2.ZERO

	var from_cell := _global_to_cell(from_global)
	var to_cell := _global_to_cell(to_global)

	from_cell = _nearest_walkable_cell(from_cell)
	to_cell = _nearest_walkable_cell(to_cell)

	if from_cell == Vector2i(999999, 999999) or to_cell == Vector2i(999999, 999999):
		return Vector2.ZERO

	var path: Array[Vector2i] = _astar.get_id_path(from_cell, to_cell)
	if path.size() < 2:
		return Vector2.ZERO

	# path[0] is current cell, path[1] is next step
	return _cell_to_global(path[1])

func _build_astar_grid() -> void:
	_astar_ready = false
	if wall_layer == null:
		return

	# Try read tile size from tileset, fallback to 16x16
	if wall_layer.tile_set != null:
		_tile_size = wall_layer.tile_set.tile_size
		if _tile_size == Vector2.ZERO:
			_tile_size = Vector2(16, 16)

	var used_rect: Rect2i = wall_layer.get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		# No tiles -> no obstacles
		return

	_astar = AStarGrid2D.new()
	_astar.region = used_rect
	_astar.cell_size = _tile_size
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()

	# Mark wall cells as solid
	var used_cells := wall_layer.get_used_cells()
	for c in used_cells:
		_astar.set_point_solid(c, true)

	_astar_ready = true

func _global_to_cell(world_pos: Vector2) -> Vector2i:
	var local := wall_layer.to_local(world_pos)
	return wall_layer.local_to_map(local)

func _cell_to_global(cell: Vector2i) -> Vector2:
	var local := wall_layer.map_to_local(cell)
	return wall_layer.to_global(local)

func _nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	if not _astar_ready:
		return cell

	# If inside region and not solid, accept
	if _astar.region.has_point(cell) and not _astar.is_point_solid(cell):
		return cell

	# Search outward for nearest non-solid cell
	var max_r := 20
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := cell + Vector2i(dx, dy)
				if not _astar.region.has_point(c):
					continue
				if not _astar.is_point_solid(c):
					return c

	# Sentinel for failure
	return Vector2i(999999, 999999)

func _snap_global_to_walkable(world_pos: Vector2) -> Vector2:
	if not _astar_ready:
		return world_pos
	var c := _global_to_cell(world_pos)
	c = _nearest_walkable_cell(c)
	if c == Vector2i(999999, 999999):
		return world_pos
	return _cell_to_global(c)
