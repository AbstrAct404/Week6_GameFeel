extends Node2D

@onready var enemies_parent: Node2D = $World/Enemies
@onready var bosses_parent: Node2D = $World/Bosses
@onready var player: Node2D = $World/Player
@onready var hp_bar: ProgressBar = $UI/HpBar

@onready var music_normal: AudioStreamPlayer = $MusicNormal
@onready var music_boss: AudioStreamPlayer = $MusicBoss

@onready var weapon_ui = $UI/HUD/WeaponUI


# ---------------- Wave Config (max 5 waves) ----------------
const WAVE_DURATION := 30.0

# Total spawns per wave (1..5): 30, 40, 50, 60, 50
const WAVE_TOTAL := {
	1: 30,
	2: 40,
	3: 50,
	4: 60,
	5: 50,
}

# Ratios per wave: [e1,e2,e3,e4] as weights
const WAVE_RATIO := {
	1: [100, 0,   0,  0],
	2: [80,  20,  0,  0],
	3: [40,  40,  20, 0],
	4: [10,  40,  40, 10],
	5: [5,   20,  30, 45],  # more Enemy4 in wave 5
}

# Enemy multipliers based on Enemy1 baseline
const ENEMY_MULT := {
	1: {"hp": 1.0, "speed": 1.0, "dmg": 1.0},
	2: {"hp": 1.5, "speed": 0.8, "dmg": 1.4},
	3: {"hp": 0.2, "speed": 2.4, "dmg": 1.1},
	4: {"hp": 1.5, "speed": 1.5, "dmg": 1.5},
}

# Boss wave = 5; wave 5: spawn all in 10s, at 10s screen red + BGM, at 25s boss + flash
const BOSS_WAVE := 5
const WAVE5_SPAWN_WINDOW := 25.0   # spawn all 50 enemies within first 25s
const WAVE5_RED_START := 10.0      # at 10s start screen red + boss BGM
const BOSS_SPAWN_DELAY_IN_WAVE := 25.0  # at 25s spawn boss + SFX + flash (delay +5s)
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

# Wave 5 screen effect
var _wave5_t: float = 0.0
var _screen_red: ColorRect = null
var _vignette_hit: ColorRect = null  # player hit vignette

# Effect toggles: 6=SFX, 7=shake, 8=enemy flash, 9=vignette, 0=damage numbers (all default true)
var _effect_flags: Dictionary = { 6: true, 7: true, 8: true, 9: true, 0: true }
var _player_prev_hp: int = -1

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

	# UI HP bar and hit vignette
	if hp_bar != null and player != null:
		hp_bar.min_value = 0
		hp_bar.max_value = player.max_hp
		hp_bar.value = player.hp
		_player_prev_hp = player.hp
		if player.has_signal("hp_changed"):
			player.hp_changed.connect(_on_player_hp_changed)

	# Start wave 1 immediately
	_start_wave(1)
	_build_astar_grid()
	_setup_screen_effects()
	_ensure_effect_flags()
	
	#weaponUI
	if weapon_ui != null and player != null:
		if player.has_signal("weapon_changed"):
			player.weapon_changed.connect(weapon_ui.set_weapon)
		if player.has_signal("weapon_cooldown_ratio"):
			player.weapon_cooldown_ratio.connect(weapon_ui.set_cooldown_ratio)
	
	_init_weapon_icons()
	
func _init_weapon_icons() -> void:
	if weapon_ui == null or player == null:
		return

	var weapon_scenes := {
		0: preload("res://Scene/Weapons/Weapon_Pistol.tscn"),
		1: preload("res://Scene/Weapons/Weapon_Rifle.tscn"),
		2: preload("res://Scene/Weapons/Weapon_Shotgun.tscn"),
		3: preload("res://Scene/Weapons/Weapon_Sniper.tscn"),
	}

	for w in weapon_scenes.keys():
		var inst = weapon_scenes[w].instantiate()
		var spr := inst.get_node_or_null("Sprite") as Sprite2D
		if spr != null and spr.texture != null:
			weapon_ui.set_weapon_icon(w, spr.texture)
		inst.queue_free()

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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			_skip_to_wave5()
			return
		# Effect toggles: 6=SFX, 7=shake, 8=enemy flash, 9=vignette, 0=damage numbers
		if event.keycode == KEY_6:
			_toggle_effect(6)
		elif event.keycode == KEY_7:
			_toggle_effect(7)
		elif event.keycode == KEY_8:
			_toggle_effect(8)
		elif event.keycode == KEY_9:
			_toggle_effect(9)
		elif event.keycode == KEY_0:
			_toggle_effect(0)

func _toggle_effect(key: int) -> void:
	_effect_flags[key] = not _effect_flags.get(key, true)

func is_effect_enabled(key: int) -> bool:
	return _effect_flags.get(key, true)

func _ensure_effect_flags() -> void:
	for k in [6, 7, 8, 9, 0]:
		if not _effect_flags.has(k):
			_effect_flags[k] = true

func _physics_process(delta: float) -> void:
	if _wave == BOSS_WAVE:
		_wave5_t += delta
		_update_wave5_screen(delta)

	if not _spawning:
		return

	_wave_end_t -= delta
	if _wave_end_t <= 0.0:
		_end_wave()
		return

func _start_wave(w: int) -> void:
	_wave = w
	_wave_spawned = 0
	_wave_quota = int(WAVE_TOTAL.get(w, 0))
	_wave_end_t = WAVE_DURATION
	_spawning = true
	_wave5_t = 0.0
	if _screen_red != null:
		_screen_red.visible = false
		_screen_red.modulate.a = 0.0

	# Wave 5: BGM from start; spawn all within 25s; at 10s screen red; at 25s boss + SFX + flash
	if _wave == BOSS_WAVE:
		_switch_to_boss_bgm()  # BGM immediately when wave 5 starts
		get_tree().create_timer(WAVE5_RED_START).timeout.connect(_on_wave5_red_start)
		get_tree().create_timer(BOSS_SPAWN_DELAY_IN_WAVE).timeout.connect(_on_wave5_boss_spawn)

	# Start spawn timer (wave 5 uses compressed window)
	_schedule_next_spawn()

func _end_wave() -> void:
	_spawning = false

	if _wave >= BOSS_WAVE:
		return

	_start_wave(_wave + 1)

func _on_wave5_red_start() -> void:
	if _screen_red != null:
		_screen_red.visible = true

func _on_wave5_boss_spawn() -> void:
	_spawn_boss()
	_play_boss_spawn_sfx()
	_flash_screen_boss()

func _play_boss_spawn_sfx() -> void:
	var path := _find_sound_file("bosssummon", [".mp3", ".ogg", ".wav"])
	if path != "":
		var asp := AudioStreamPlayer.new()
		asp.stream = load(path)
		add_child(asp)
		asp.finished.connect(asp.queue_free)
		asp.play()

func _flash_screen_boss() -> void:
	if _screen_red == null:
		return
	# Max red then: quick bright (flash) -> dark -> bright -> back to current red
	var tw := create_tween()
	var max_red := Color(0.85, 0.0, 0.0, 0.55)
	var flash := Color(1.0, 0.2, 0.2, 0.9)
	tw.tween_property(_screen_red, "modulate", flash, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_screen_red, "modulate", Color(0.5, 0.0, 0.0, 0.7), 0.08).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_screen_red, "modulate", flash, 0.06).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_screen_red, "modulate", max_red, 0.1).set_trans(Tween.TRANS_SINE)

func _schedule_next_spawn() -> void:
	if not _spawning:
		return
	if _wave_spawned >= _wave_quota:
		return

	# Wave 5: spawn all within WAVE5_SPAWN_WINDOW (10s); others spread over wave duration
	var window: float = _wave_end_t
	if _wave == BOSS_WAVE:
		var elapsed := _wave5_t
		window = maxf(0.3, WAVE5_SPAWN_WINDOW - elapsed)
		window = minf(window, WAVE5_SPAWN_WINDOW)
	var remaining_spawns = max(1, _wave_quota - _wave_spawned)
	var base_interval := window / float(remaining_spawns)
	var jitter := base_interval * 0.2
	var interval := clampf(base_interval + rng.randf_range(-jitter, jitter), 0.08, 0.8)

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
	var base_speed := 80.0
	var base_dmg := 3

	# If you later change Enemy1 defaults, update these three to match Enemy1 exports.
	# (Keeping it explicit avoids having to instantiate a hidden Enemy1.)

	var mult = ENEMY_MULT.get(idx, {"hp": 1.0, "speed": 1.0, "dmg": 1.0})
	var hp_val := int(ceil(float(base_hp) * float(mult["hp"])))
	var spd_val := float(base_speed) * float(mult["speed"])
	var dmg_val := int(ceil(float(base_dmg) * float(mult["dmg"])))

	hp_val = max(1, hp_val)
	spd_val = max(10.0, spd_val)
	if idx == 3:
		spd_val = max(10.0, spd_val - 10.0)  # Enemy3: reduce speed by 10
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
	if music_boss and music_boss.playing:
		music_boss.stop()
	if music_normal:
		music_normal.play()

func _setup_screen_effects() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	# Wave 5 red overlay (full screen, dark red tint)
	_screen_red = ColorRect.new()
	_screen_red.name = "ScreenRed"
	_screen_red.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_red.offset_left = 0
	_screen_red.offset_top = 0
	_screen_red.offset_right = 0
	_screen_red.offset_bottom = 0
	_screen_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_red.color = Color(0.6, 0.0, 0.0, 0.0)
	_screen_red.visible = false
	ui.add_child(_screen_red)

	# Player hit vignette: red edges, transparent center (use a TextureRect with radial gradient or ColorRect with shader; Godot has no built-in radial. We use a large ColorRect and a simple shader or multiple rects. Simpler: full-screen ColorRect with color that has alpha gradient via script - we can't do that with one ColorRect. Use a SubViewport + sprite with vignette texture, or draw a circle in the center with a custom draw. Easiest: full screen semi-transparent red that fades out quickly - center still visible.)
	_vignette_hit = ColorRect.new()
	_vignette_hit.name = "VignetteHit"
	_vignette_hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_hit.offset_left = 0
	_vignette_hit.offset_top = 0
	_vignette_hit.offset_right = 0
	_vignette_hit.offset_bottom = 0
	_vignette_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_hit.color = Color(1, 1, 1, 1)
	_vignette_hit.visible = false
	var shader := load("res://Assets/vignette_hit.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("color", Color(0.75, 0.0, 0.0, 0.5))
		mat.set_shader_parameter("center_radius", 0.3)
		_vignette_hit.material = mat
	else:
		_vignette_hit.color = Color(0.7, 0.0, 0.0, 0.35)
	ui.add_child(_vignette_hit)

func _update_wave5_screen(_delta: float) -> void:
	if _screen_red == null or not _screen_red.visible:
		return
	# Ramp red from 10s to 20s (0.0 -> ~0.5 alpha), then stay max until flash
	var t := _wave5_t - WAVE5_RED_START
	if t <= 0.0:
		_screen_red.modulate = Color(0.6, 0.0, 0.0, 0.0)
		return
	var ramp := clampf(t / (BOSS_SPAWN_DELAY_IN_WAVE - WAVE5_RED_START), 0.0, 1.0)
	_screen_red.color = Color(0.55, 0.0, 0.0, 0.08 + ramp * 0.5)
	_screen_red.modulate = Color(1, 1, 1, 1)

func _skip_to_wave5() -> void:
	# Clear all enemies
	for c in enemies_parent.get_children():
		c.queue_free()
	if _boss != null and is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	_boss_spawned = false
	_spawning = false
	_start_wave(BOSS_WAVE)

func _show_hit_vignette() -> void:
	if _vignette_hit == null:
		return
	_vignette_hit.visible = true
	_vignette_hit.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_vignette_hit, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(_vignette_hit):
			_vignette_hit.visible = false
	)

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	if hp_bar != null:
		hp_bar.max_value = max_hp
		hp_bar.value = current
	# Player hit vignette (effect 9): edges red, center faded
	if _player_prev_hp >= 0 and current < _player_prev_hp and is_effect_enabled(9):
		_show_hit_vignette()
	_player_prev_hp = current
	
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

	var rect := _wall_layer.get_used_rect()
	if rect.size == Vector2i.ZERO:
		_astar_ready = false
		return

	_astar.region = rect
	_astar.cell_size = Vector2(16, 16)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.update()

	var wall_cells := _wall_layer.get_used_cells()
	for c in wall_cells:
		if rect.has_point(c):
			_astar.set_point_solid(c, true)

	# Prefer paths away from walls: higher cost for cells adjacent to walls (no shortest path through tight gaps)
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		for y in range(rect.position.y, rect.position.y + rect.size.y):
			var c := Vector2i(x, y)
			if _astar.is_point_solid(c):
				continue
			var weight := 1.0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nc := c + Vector2i(dx, dy)
					if rect.has_point(nc) and _astar.is_point_solid(nc):
						weight += 0.35
			_astar.set_point_weight_scale(c, weight)

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

	var path: Array = _astar.get_id_path(from_cell, to_cell)
	if path.size() < 2:
		return to_world

	var next_cell := Vector2i(path[1].x, path[1].y)
	var pos := _cell_to_global(next_cell)
	# Random offset so enemies don't all stack on the same point (reduces lining up)
	pos += Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0))
	return pos
