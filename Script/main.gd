extends Node2D

@onready var enemies_parent: Node2D = $World/Enemies
@onready var bosses_parent: Node2D = $World/Bosses
@onready var player: Node2D = $World/Player
@onready var hp_bar: ProgressBar = $UI/HpBar

@onready var music_normal: AudioStreamPlayer = $MusicNormal
@onready var music_boss: AudioStreamPlayer = $MusicBoss

# ---------------- Wave Config ----------------
const WAVE_DURATION := 30.0

# Total spawns per wave (1..7)
const WAVE_TOTAL := {
	1: 30,
	2: 60,
	3: 80,
	4: 100,
	5: 100,
	6: 100,
	7: 100,
}

# Ratios per wave: [e1,e2,e3,e4] as weights
const WAVE_RATIO := {
	1: [100, 0,   0,  0],   # only enemy1
	2: [80,  20,  0,  0],
	3: [40,  40,  20, 0],
	4: [10,  40,  40, 10],
	5: [10,  30,  40, 20],
	6: [0,   30,  30, 40],
	7: [0,   20,  40, 40],
}

# Enemy multipliers based on Enemy1 baseline
# Enemy1: default (1.0,1.0,1.0)
const ENEMY_MULT := {
	1: {"hp": 1.0, "speed": 1.0, "dmg": 1.0},
	2: {"hp": 1.5, "speed": 0.8, "dmg": 1.4},
	3: {"hp": 0.2, "speed": 2.4, "dmg": 1.1},
	4: {"hp": 1.5, "speed": 1.5, "dmg": 1.5},
}

# Boss wave rule
const BOSS_WAVE := 7
const BOSS_SPAWN_DELAY_IN_WAVE := 20.0
# --------------------------------------------

var rng := RandomNumberGenerator.new()

# Enemy scenes (explicit, so order is stable)
var enemy_scene_1: PackedScene
var enemy_scene_2: PackedScene
var enemy_scene_3: PackedScene
var enemy_scene_4: PackedScene

var _corner_markers: Array[Marker2D] = []

var _wave: int = 0
var _wave_spawned: int = 0
var _wave_quota: int = 0
var _wave_end_t: float = 0.0
var _spawning: bool = false

var _boss_spawned: bool = false
var _boss: Node2D = null

# ---- Pathfinding (AStarGrid2D) ----
var _astar: AStarGrid2D = AStarGrid2D.new()
var _astar_ready: bool = false
var _wall_layer: TileMapLayer = null

@onready var _tm_wall: TileMapLayer = $World/TM_Wall
# -----------------------------------

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

	# Load enemy scenes in a fixed order
	enemy_scene_1 = preload("res://Scene/Enemy1.tscn")
	enemy_scene_2 = preload("res://Scene/Enemy2.tscn")
	enemy_scene_3 = preload("res://Scene/Enemy3.tscn")
	enemy_scene_4 = preload("res://Scene/Enemy4.tscn")

	_corner_markers = _get_corner_spawn_markers()

	# UI HP bar
	if hp_bar != null and player != null:
		hp_bar.min_value = 0
		hp_bar.max_value = player.max_hp
		hp_bar.value = player.hp
		if player.has_signal("hp_changed"):
			player.hp_changed.connect(_on_player_hp_changed)

	# Start wave 1 immediately
	_start_wave(1)
	_build_astar_grid()

func _get_corner_spawn_markers() -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	var sp := $World/SpawnPoints
	if sp == null:
		push_error("World/SpawnPoints not found")
		return out

	for n in sp.get_children():
		var m := n as Marker2D
		if m == null:
			continue
		# Your project has "ConerTL" typo; keep compatible.
		if m.name == "ConerTL" or m.name == "CornerTR" or m.name == "CornerBL" or m.name == "CornerBR":
			out.append(m)

	if out.size() == 0:
		push_error("No corner markers found under World/SpawnPoints")
	return out

func _physics_process(delta: float) -> void:
	if not _spawning:
		return

	_wave_end_t -= delta
	if _wave_end_t <= 0.0:
		_end_wave()
		return

	# Spawn loop is timer-driven, so nothing else here.

func _start_wave(w: int) -> void:
	_wave = w
	_wave_spawned = 0
	_wave_quota = int(WAVE_TOTAL.get(w, 0))
	_wave_end_t = WAVE_DURATION
	_spawning = true

	# Wave 7: switch to boss BGM immediately, spawn boss after 20s
	if _wave == BOSS_WAVE:
		_switch_to_boss_bgm()
		get_tree().create_timer(BOSS_SPAWN_DELAY_IN_WAVE).timeout.connect(_spawn_boss)

	# Start spawn timer
	_schedule_next_spawn()

func _end_wave() -> void:
	_spawning = false

	if _wave >= 7:
		return

	_start_wave(_wave + 1)

func _schedule_next_spawn() -> void:
	if not _spawning:
		return
	if _wave_spawned >= _wave_quota:
		return

	# Spread spawns across the remaining time (roughly uniform, with slight jitter)
	var remaining := maxf(0.01, _wave_end_t)
	var remaining_spawns = max(1, _wave_quota - _wave_spawned)
	var base_interval := remaining / float(remaining_spawns)
	var jitter := base_interval * 0.25
	var interval := clampf(base_interval + rng.randf_range(-jitter, jitter), 0.05, 1.2)

	get_tree().create_timer(interval).timeout.connect(func():
		_spawn_one_enemy_for_wave()
		_schedule_next_spawn()
	)

func _spawn_one_enemy_for_wave() -> void:
	if not _spawning:
		return
	if _wave_spawned >= _wave_quota:
		return
	if _corner_markers.is_empty():
		return

	var enemy_idx := _pick_enemy_index_for_wave(_wave) # 1..4
	var packed := _scene_for_enemy_index(enemy_idx)
	if packed == null:
		return

	var e := packed.instantiate() as Node2D
	if e == null:
		return

	# Pick a corner spawn
	var marker := _corner_markers[rng.randi_range(0, _corner_markers.size() - 1)]
	e.global_position = marker.global_position

	# Apply stats based on Enemy1 baseline
	_apply_enemy_stats(e, enemy_idx)

	enemies_parent.add_child(e)
	_wave_spawned += 1

func _pick_enemy_index_for_wave(w: int) -> int:
	var weights: Array = WAVE_RATIO.get(w, [100, 0, 0, 0])
	# weights for [1,2,3,4]
	var total := 0
	for x in weights:
		total += int(x)
	if total <= 0:
		return 1

	var r := rng.randi_range(1, total)
	var acc := 0
	for i in range(4):
		acc += int(weights[i])
		if r <= acc:
			return i + 1
	return 1

func _scene_for_enemy_index(i: int) -> PackedScene:
	match i:
		1: return enemy_scene_1
		2: return enemy_scene_2
		3: return enemy_scene_3
		4: return enemy_scene_4
		_: return enemy_scene_1

func _apply_enemy_stats(enemy_node: Node, idx: int) -> void:
	# Baseline from Enemy1 numbers (hard source: Enemy script exports)
	# Enemy script fields in your project: speed_chase, max_hp, contact_damage, hp
	var base_hp := 20
	var base_speed := 90.0
	var base_dmg := 4

	# If you later change Enemy1 defaults, update these three to match Enemy1 exports.
	# (Keeping it explicit avoids having to instantiate a hidden Enemy1.)

	var mult = ENEMY_MULT.get(idx, {"hp": 1.0, "speed": 1.0, "dmg": 1.0})
	var hp_val := int(ceil(float(base_hp) * float(mult["hp"])))
	var spd_val := float(base_speed) * float(mult["speed"])
	var dmg_val := int(ceil(float(base_dmg) * float(mult["dmg"])))

	hp_val = max(1, hp_val)
	spd_val = max(10.0, spd_val)
	dmg_val = max(1, dmg_val)

	# Apply to enemy script if fields exist
	if "max_hp" in enemy_node:
		enemy_node.max_hp = hp_val
	if "hp" in enemy_node:
		enemy_node.hp = hp_val
	if "speed_chase" in enemy_node:
		enemy_node.speed_chase = spd_val
	if "contact_damage" in enemy_node:
		enemy_node.contact_damage = dmg_val

func _switch_to_boss_bgm() -> void:
	if music_normal and music_normal.playing:
		music_normal.stop()
	if music_boss and not music_boss.playing:
		music_boss.play()

func _spawn_boss() -> void:
	if _boss_spawned:
		return
	_boss_spawned = true

	var boss_scene: PackedScene = preload("res://Scene/Boss.tscn")
	_boss = boss_scene.instantiate() as Node2D
	if _boss == null:
		return

	# Spawn at SpawnBoss marker if exists; fallback near player
	var spawn_boss := $World/SpawnPoints.get_node_or_null("SpawnBoss") as Marker2D
	if spawn_boss != null:
		_boss.global_position = spawn_boss.global_position
	elif player != null:
		_boss.global_position = player.global_position + Vector2(180, -60)
	else:
		_boss.global_position = Vector2.ZERO

	bosses_parent.add_child(_boss)

	if _boss.has_signal("died"):
		_boss.connect("died", Callable(self, "_on_boss_died"))

func _on_boss_died() -> void:
	# optional: return to normal BGM after boss dies
	if music_boss and music_boss.playing:
		music_boss.stop()
	if music_normal:
		music_normal.play()

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	if hp_bar == null:
		return
	hp_bar.max_value = max_hp
	hp_bar.value = current
	
func on_pistol_kill() -> void:
	if player == null:
		return
	if "hp" in player and "max_hp" in player:
		player.hp = min(player.max_hp, player.hp + 1)
		if player.has_signal("hp_changed"):
			player.emit_signal("hp_changed", player.hp, player.max_hp)

func _build_astar_grid() -> void:
	_wall_layer = _tm_wall
	if _wall_layer == null:
		_astar_ready = false
		return

	# 用 TileMapLayer 的 used rect 来定义寻路网格范围
	var rect := _wall_layer.get_used_rect()
	if rect.size == Vector2i.ZERO:
		# 如果 used_rect 为空，说明 TM_Wall 上没放 tile（或者墙在别的 layer）
		_astar_ready = false
		return

	_astar.region = rect
	_astar.cell_size = Vector2(16, 16) # 你工程 tile 大小一般是 16；如果不是，改成你的 tile size
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()

	# 把墙格子标为不可走
	var wall_cells := _wall_layer.get_used_cells()
	for c in wall_cells:
		# 只标记在 region 内的
		if rect.has_point(c):
			_astar.set_point_solid(c, true)

	_astar_ready = true

func _global_to_cell(p: Vector2) -> Vector2i:
	# TileMapLayer 的本地/全局换算：先转到 layer 的本地坐标，再转 cell
	var local := _wall_layer.to_local(p)
	return _wall_layer.local_to_map(local)

func _cell_to_global(c: Vector2i) -> Vector2:
	# cell -> local -> global，并取 cell 中心点
	var local := _wall_layer.map_to_local(c)
	return _wall_layer.to_global(local)

func _is_walkable(c: Vector2i) -> bool:
	if not _astar_ready:
		return true
	return not _astar.is_point_solid(c)

func _nearest_walkable_cell(c: Vector2i) -> Vector2i:
	if _is_walkable(c):
		return c

	var max_r := 8
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var nc := c + Vector2i(dx, dy)
				if _is_walkable(nc):
					return nc

	return Vector2i(999999, 999999)
	
func get_next_path_point(from_world: Vector2, to_world: Vector2) -> Vector2:
	# Ensure A* is ready (in case scene reload order changes)
	if not _astar_ready:
		_build_astar_grid()
		if not _astar_ready:
			return to_world

	var from_cell := _nearest_walkable_cell(_global_to_cell(from_world))
	var to_cell := _nearest_walkable_cell(_global_to_cell(to_world))
	if from_cell == Vector2i(999999, 999999) or to_cell == Vector2i(999999, 999999):
		return to_world

	var path: PackedVector2Array = _astar.get_point_path(from_cell, to_cell)
	# path points are in CELL coordinates
	if path.size() < 2:
		return to_world

	# Return the NEXT step (index 1), not index 0 (which is current cell)
	var next_cell := Vector2i(int(path[1].x), int(path[1].y))
	return _cell_to_global(next_cell)
