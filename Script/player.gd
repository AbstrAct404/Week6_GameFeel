extends CharacterBody2D

signal weapon_changed(new_weapon: int)
signal weapon_cooldown_ratio(ratio: float)

signal hp_changed(current: int, max_hp: int)

@export var speed: float = 230.0
@export var auto_range: float = 550.0

@export var max_hp: int = 40
@export var crit_chance_default: float = 0.30
var hp: int

@export var bullet_scene: PackedScene
@export var bullet_spawn_offset: float = 12.0

# Per-weapon cooldowns (seconds)
@export var pistol_cooldown: float = 0.5
@export var rifle_cooldown: float = 0.34
@export var shotgun_cooldown: float = 0.48
@export var sniper_cooldown: float = 1.10

# NEW: cooldown multipliers (extend shotgun/sniper)
@export var shotgun_cooldown_mult: float = 1.35
@export var sniper_cooldown_mult: float = 1.45

# Shotgun spread
@export var shotgun_pellets: int = 5
@export var shotgun_spread_degrees: float = 18.0

# ---------------- Game Feel: Camera Shake ----------------
@export var shake_rifle_strength: float = 3.0
@export var shake_shotgun_strength: float = 8.0
@export var shake_sniper_strength: float = 15.0

@export var shake_rifle_duration: float = 0.08
@export var shake_shotgun_duration: float = 0.12
@export var shake_sniper_duration: float = 0.18

# Optional: small "kick" bias along aim direction (0 = off)
@export var shake_kick_bias: float = 0.35
# --------------------------------------------------------

@onready var anim: AnimatedSprite2D = $Sprite
@onready var muzzle: Node2D = $MuzzlePivot
@onready var weapon_holder: Node2D = $MuzzlePivot/WeaponHolder
@onready var sfx_fire: AudioStreamPlayer = $SFXFire
@onready var sfx_hit: AudioStreamPlayer = $SFXHit

enum WeaponType { PISTOL, RIFLE, SHOTGUN, SNIPER }

var _weapon: int = WeaponType.PISTOL
var _cooldown_t: float = 0.0

var _weapon_scenes := {
	WeaponType.PISTOL: preload("res://Scene/Weapons/Weapon_Pistol.tscn"),
	WeaponType.RIFLE: preload("res://Scene/Weapons/Weapon_Rifle.tscn"),
	WeaponType.SHOTGUN: preload("res://Scene/Weapons/Weapon_Shotgun.tscn"),
	WeaponType.SNIPER: preload("res://Scene/Weapons/Weapon_Sniper.tscn"),
}

var _muzzle_flash_tex := {
	WeaponType.RIFLE: preload("res://Assets/Effects/GunShotRifle.png"),
	WeaponType.SHOTGUN: preload("res://Assets/Effects/GunShotPistol.png"), # 按你要求 shotgun 用 pistol 的
	WeaponType.SNIPER: preload("res://Assets/Effects/GunShotSniper.png"),
}
var _muzzle_frames_cache := {} # weapon -> SpriteFrames
var _muzzle_flash: AnimatedSprite2D = null

var _weapon_instance: Node2D = null
var _weapon_sprite: Sprite2D = null
var _weapon_fire_point: Node2D = null

# NOTE: user requested sniper/shotgun bullet swap already applied.
var _bullet_textures := {
	WeaponType.PISTOL: preload("res://Assets/Weapons/Extras/bullet.png"),
	WeaponType.RIFLE: preload("res://Assets/Weapons/Extras/rifle_bullet.png"),
	WeaponType.SHOTGUN: preload("res://Assets/Weapons/Extras/sniper_bullet.png"),
	WeaponType.SNIPER: preload("res://Assets/Weapons/Extras/shotgun_bullet.png"),
}

# Weapon damages (per bullet)
var _weapon_damage := {
	WeaponType.PISTOL: 8,
	WeaponType.RIFLE: 5,
	WeaponType.SHOTGUN: 9,
	WeaponType.SNIPER: 50,
}

# Weapon fire SFX
var _weapon_fire_sfx := {
	WeaponType.PISTOL: preload("res://Assets/Sound effects/Pistol.wav"),
	WeaponType.RIFLE: preload("res://Assets/Sound effects/Rifle.wav"),
	WeaponType.SHOTGUN: preload("res://Assets/Sound effects/Shotgun.wav"),
	WeaponType.SNIPER: preload("res://Assets/Sound effects/Sniper.wav"),
}

var _hit_sfx: AudioStream = preload("res://Assets/Sound effects/PlayerGetHit.mp3")

# Invincibility: 0.2s after taking damage, no damage and no collision with enemies (can pass through)
const INVINCIBLE_DURATION := 0.2
var _invincible_timer: float = 0.0
var _collision_mask_walls_only: int = 1
var _collision_mask_normal: int = 1

# ---- Camera shake runtime state ----
var _rng := RandomNumberGenerator.new()
var _cam: Camera2D = null
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _shake_strength: float = 0.0
var _shake_base_offset: Vector2 = Vector2.ZERO
var _last_aim_dir: Vector2 = Vector2.RIGHT
# per-weapon muzzle flash offset in LOCAL space (x forward, y down)
var _muzzle_flash_offset_local := {
	WeaponType.RIFLE: Vector2(32, 0),
	# WeaponType.SNIPER: Vector2(14, -2),
	WeaponType.SHOTGUN: Vector2(-20, 0),
}

# -----------------------------------


func _ready() -> void:
	_rng.randomize()

	hp = max_hp
	emit_signal("hp_changed", hp, max_hp)
	_apply_weapon_visuals()

	# Collision: layer 1 = walls, layer 2 = enemies; invincible = walls only (pass through enemies)
	_collision_mask_walls_only = 1
	_collision_mask_normal = 3
	collision_mask = _collision_mask_normal

	# Cache main camera (Main/Camera2D)
	# Cache camera (it is a child of the Player instance in Main.tscn: World/Player/Camera2D)
	_cam = get_node_or_null("Camera2D") as Camera2D
	if _cam == null:
		# fallback: active camera from viewport
		_cam = get_viewport().get_camera_2d()
	if _cam != null:
		_shake_base_offset = _cam.offset
		
	_setup_muzzle_flash_node()
	emit_signal("weapon_changed", _weapon)
	emit_signal("weapon_cooldown_ratio", 1.0) 
	
	
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				set_weapon(WeaponType.PISTOL)
			KEY_2:
				set_weapon(WeaponType.RIFLE)
			KEY_3:
				set_weapon(WeaponType.SHOTGUN)
			KEY_4:
				set_weapon(WeaponType.SNIPER)

func set_weapon(w: int) -> void:
	if w == _weapon:
		return

	_weapon = w
	_apply_weapon_visuals()

	emit_signal("weapon_changed", _weapon)

	_cooldown_t = 0.5

	emit_signal("weapon_cooldown_ratio", 1.0)

func take_damage(amount: int = 1) -> void:
	if _invincible_timer > 0.0:
		return
	_invincible_timer = INVINCIBLE_DURATION

	hp = clamp(hp - max(1, amount), 0, max_hp)
	emit_signal("hp_changed", hp, max_hp)
	var main := get_tree().current_scene
	var sfx_ok = main == null or not main.has_method("is_effect_enabled") or main.call("is_effect_enabled", 6)
	if sfx_ok and sfx_hit:
		sfx_hit.stream = _hit_sfx
		sfx_hit.play()
	if hp <= 0:
		get_tree().reload_current_scene()

func is_invincible() -> bool:
	return _invincible_timer > 0.0

func _apply_weapon_visuals() -> void:
	# Replace weapon scene under WeaponHolder
	if weapon_holder == null:
		return

	# Clear old
	for c in weapon_holder.get_children():
		c.queue_free()

	_weapon_instance = null
	_weapon_sprite = null
	_weapon_fire_point = null

	if not _weapon_scenes.has(_weapon):
		return

	var packed: PackedScene = _weapon_scenes[_weapon]
	_weapon_instance = packed.instantiate() as Node2D
	weapon_holder.add_child(_weapon_instance)

	_weapon_sprite = _weapon_instance.get_node_or_null("Sprite") as Sprite2D
	_weapon_fire_point = _weapon_instance.get_node_or_null("FirePoint") as Node2D

func _physics_process(delta: float) -> void:
	# --- invincibility: no damage and no collision with enemies (can pass through) ---
	if _invincible_timer > 0.0:
		_invincible_timer -= delta
		collision_mask = _collision_mask_walls_only
	else:
		collision_mask = _collision_mask_normal

	# --- movement ---
	var effective_speed := speed
	if _weapon == WeaponType.PISTOL:
		effective_speed += 10.0
	elif _weapon == WeaponType.SNIPER:
		effective_speed -= 10.0
	var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = move_dir * effective_speed
	move_and_slide()

	# --- movement animation ---
	_update_move_anim(move_dir)

	# --- target selection ---
	var target: Node2D = null
	if _weapon == WeaponType.SNIPER:
		target = find_sniper_target()
	else:
		target = find_closest_enemy()

	# --- auto aim (always face the chosen target) ---
	if target != null:
		_aim_at(target.global_position)

	# --- shoot on key with cooldown ---
	_cooldown_t = maxf(_cooldown_t - delta, 0.0)
	_emit_cooldown_ratio()

	if target != null and Input.is_action_pressed("shoot") and _cooldown_t <= 0.0:
		_cooldown_t = _get_weapon_cooldown()
		_play_fire_sfx()
		_shoot_with_weapon(target.global_position)
		_apply_weapon_shake()
		_play_muzzle_flash()  # every shot (including rifle hold)
	# --- camera shake update ---
	_update_camera_shake(delta)

func _play_fire_sfx() -> void:
	if sfx_fire == null:
		return
	var main := get_tree().current_scene
	if main != null and main.has_method("is_effect_enabled") and not main.call("is_effect_enabled", 6):
		return
	if _weapon_fire_sfx.has(_weapon):
		sfx_fire.stream = _weapon_fire_sfx[_weapon]
		sfx_fire.play()
		# Sniper tail (simple echo-like repeats)
		if _weapon == WeaponType.SNIPER:
			var stream := sfx_fire.stream
			if stream != null:
				# two quiet delayed replays
				_play_sniper_tail(stream, 0.12, -10.0, 0.98)
				_play_sniper_tail(stream, 0.26, -14.0, 0.96)

func _get_weapon_cooldown() -> float:
	match _weapon:
		WeaponType.RIFLE:
			return rifle_cooldown
		WeaponType.SHOTGUN:
			return shotgun_cooldown * maxf(1.0, shotgun_cooldown_mult)
		WeaponType.SNIPER:
			return sniper_cooldown * maxf(1.0, sniper_cooldown_mult)
		_:
			return pistol_cooldown

func _emit_cooldown_ratio() -> void:
	var cd := _get_weapon_cooldown()
	var ratio := 1.0
	if cd > 0.0:
		ratio = clamp(1.0 - (_cooldown_t / cd), 0.0, 1.0)
	emit_signal("weapon_cooldown_ratio", ratio)

func _update_move_anim(move_dir: Vector2) -> void:
	if move_dir.length_squared() > 0.0:
		if anim.animation != "walk":
			anim.play("walk")
	else:
		if anim.animation != "idle":
			anim.play("idle")

	if move_dir.x != 0.0:
		anim.flip_h = move_dir.x < 0.0

func _resolve_enemy_root(n: Node) -> Node2D:
	var node2d := n as Node2D
	if node2d == null:
		return null

	# group "enemies" is currently on the Hitbox Area2D, not on the Enemy root
	# Prefer: the node itself if it can be damaged, otherwise its parent.
	if node2d.has_method("take_damage") or node2d.has_method("die"):
		return node2d

	var p := node2d.get_parent()
	if p != null and (p.has_method("take_damage") or p.has_method("die")):
		return p as Node2D

	return node2d

func _unique_enemy_roots() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var seen := {}
	for n in get_tree().get_nodes_in_group("enemies"):
		var r := _resolve_enemy_root(n)
		if r == null:
			continue
		var id := r.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		out.append(r)
	return out

func find_closest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d2: float = auto_range * auto_range

	for e in _unique_enemy_roots():
		var d2 := (e.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = e

	return best

func _world_to_screen(pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * pos

func _is_in_view(pos: Vector2) -> bool:
	var screen := _world_to_screen(pos)
	return Rect2(Vector2.ZERO, get_viewport_rect().size).has_point(screen)

func find_sniper_target() -> Node2D:
	var best: Node2D = null
	var best_hp: int = -999999

	var range2 := auto_range * auto_range
	for e in _unique_enemy_roots():
		if (e.global_position - global_position).length_squared() > range2:
			continue
		if not _is_in_view(e.global_position):
			continue

		var hp_val := 1
		if e.has_method("get_hp"):
			hp_val = int(e.call("get_hp"))
		elif "hp" in e:
			hp_val = int(e.hp)

		if hp_val > best_hp:
			best_hp = hp_val
			best = e

	return best

func _shoot_with_weapon(target_pos: Vector2) -> void:
	match _weapon:
		WeaponType.SHOTGUN:
			shoot_shotgun(target_pos)
		_:
			shoot_single(target_pos)

func shoot_single(target_pos: Vector2) -> void:
	var spawn_pos := _get_spawn_pos()
	var dir_vec := target_pos - spawn_pos
	if dir_vec.length_squared() < 0.0001:
		return
	var dir := dir_vec.normalized()
	_last_aim_dir = dir
	_spawn_bullet(spawn_pos, dir)

func shoot_shotgun(target_pos: Vector2) -> void:
	var spawn_pos := _get_spawn_pos()
	var dir_vec := target_pos - spawn_pos
	if dir_vec.length_squared() < 0.0001:
		return

	var base_dir := dir_vec.normalized()
	_last_aim_dir = base_dir
	var base_ang := base_dir.angle()

	var pellets = max(1, shotgun_pellets)
	var spread := deg_to_rad(max(0.0, shotgun_spread_degrees))

	# Centered spread: e.g. 5 pellets => -2,-1,0,1,2
	var mid := float(pellets - 1) * 0.5
	for i in range(pellets):
		var t := (float(i) - mid)
		var ang = base_ang + (t / max(1.0, mid)) * (spread * 0.5) if pellets > 1 else base_ang
		var dir := Vector2.RIGHT.rotated(ang)
		_spawn_bullet(spawn_pos, dir)

func _get_spawn_pos() -> Vector2:
	if _weapon_fire_point != null:
		return _weapon_fire_point.global_position
	return muzzle.global_position

func _spawn_bullet(spawn_pos: Vector2, dir: Vector2) -> void:
	if bullet_scene == null:
		push_warning("bullet_scene is null. Drag Bullet.tscn into Player -> bullet_scene in Inspector.")
		return

	var b := bullet_scene.instantiate()
	b.direction = dir
	b.global_position = spawn_pos + dir * bullet_spawn_offset
	
	# Set bullet sprite per weapon
	var spr := b.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null and _bullet_textures.has(_weapon):
		spr.texture = _bullet_textures[_weapon]

	# Set bullet damage per weapon
	if _weapon_damage.has(_weapon):
		b.damage = int(_weapon_damage[_weapon])
		
	# Pass weapon type & pierce settings
	b.weapon_type = _weapon
	if _weapon == WeaponType.PISTOL:
		b.max_pierce = 2
		b.max_wall_pierce = 0  # cannot pierce walls
	elif _weapon == WeaponType.SNIPER:
		b.max_pierce = 5
		b.max_wall_pierce = 1  # can pierce 1 wall
		b.speed *= 2.0  # sniper bullet flight speed doubled
	elif _weapon == WeaponType.RIFLE:
		b.max_pierce = 3  # pierce 2: hit 3 enemies, 100% / 80% / 50%
		b.max_wall_pierce = 0
	elif _weapon == WeaponType.SHOTGUN:
		b.max_pierce = 1  # no pierce: hit one enemy only
		b.max_wall_pierce = 0

	var crit := false
	if _weapon == WeaponType.SNIPER:
		crit = true # sniper always shows popup
	else:
		crit = _rng.randf() < crit_chance_default

	b.is_crit = crit
	
	
	var bullets := get_tree().current_scene.get_node_or_null("World/Bullets") as Node2D
	if bullets != null:
		bullets.add_child(b)
	else:
		get_tree().current_scene.add_child(b)

func _aim_at(target_pos: Vector2) -> void:
	var dir := target_pos - muzzle.global_position
	if dir.length_squared() < 0.0001:
		return

	_last_aim_dir = dir.normalized()

	var ang := dir.angle()

	if dir.x < 0.0:
		muzzle.rotation = ang
		if _weapon_sprite:
			_weapon_sprite.flip_v = true
	else:
		muzzle.rotation = ang
		if _weapon_sprite:
			_weapon_sprite.flip_v = false

	if _weapon_sprite:
		_weapon_sprite.flip_h = false

# ---------------- Game Feel: Shake implementation (effect 7) ----------------
func _apply_weapon_shake() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_method("is_effect_enabled") and not main.call("is_effect_enabled", 7):
		return
	match _weapon:
		WeaponType.RIFLE:
			_start_shake(shake_rifle_strength, shake_rifle_duration)
		WeaponType.SHOTGUN:
			_start_shake(shake_shotgun_strength, shake_shotgun_duration)
		WeaponType.SNIPER:
			_start_shake(shake_sniper_strength, shake_sniper_duration)
		_:
			# pistol tiny shake (optional). If you want none, set strength to 0 in inspector.
			_start_shake(1.0, 0.04)

func _start_shake(strength: float, duration: float) -> void:
	if _cam == null:
		_cam = get_tree().current_scene.get_node_or_null("Camera2D") as Camera2D
		if _cam == null:
			return
		_shake_base_offset = _cam.offset

	_shake_strength = maxf(0.0, strength)
	_shake_dur = maxf(0.0, duration)
	_shake_t = _shake_dur

func _update_camera_shake(delta: float) -> void:
	if _cam == null:
		return
	if _shake_t <= 0.0 or _shake_dur <= 0.0 or _shake_strength <= 0.0:
		_cam.offset = _shake_base_offset
		return

	_shake_t = maxf(0.0, _shake_t - delta)
	var k := _shake_t / _shake_dur  # decay 1 -> 0

	# random jitter
	var jitter := Vector2(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	) * (_shake_strength * k)

	# small kick bias opposite aim direction (feel like recoil)
	if shake_kick_bias > 0.0:
		jitter += (-_last_aim_dir) * (_shake_strength * k * shake_kick_bias)

	_cam.offset = _shake_base_offset + jitter
# ----------------------------------------------------------------

func shake_external(strength: float, duration: float, bias_dir: Vector2 = Vector2.ZERO) -> void:
	# allow Main to trigger camera shake (boss summon / pressure)
	_last_aim_dir = bias_dir.normalized() if bias_dir.length_squared() > 0.0001 else _last_aim_dir
	_start_shake(strength, duration)

func _setup_muzzle_flash_node() -> void:
	if muzzle == null:
		return
	_muzzle_flash = muzzle.get_node_or_null("MuzzleFlash") as AnimatedSprite2D
	if _muzzle_flash == null:
		_muzzle_flash = AnimatedSprite2D.new()
		_muzzle_flash.name = "MuzzleFlash"
		_muzzle_flash.visible = false
		_muzzle_flash.z_index = 100

		# KEY: ignore parent transform to avoid mirrored/offset issues
		_muzzle_flash.top_level = true

		muzzle.add_child(_muzzle_flash)
		

func _get_muzzle_frames_for_weapon(w: int) -> SpriteFrames:
	if _muzzle_frames_cache.has(w):
		return _muzzle_frames_cache[w]

	if not _muzzle_flash_tex.has(w):
		return null

	var tex: Texture2D = _muzzle_flash_tex[w]
	if tex == null:
		return null

	var frames := SpriteFrames.new()
	frames.add_animation("flash")
	frames.set_animation_loop("flash", false)
	frames.set_animation_speed("flash", 30.0)

	var w_frame := int(tex.get_width() / 6)
	var h_frame := int(tex.get_height())

	for i in range(6):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * w_frame, 0, w_frame, h_frame)
		frames.add_frame("flash", at)

	_muzzle_frames_cache[w] = frames
	return frames

func _play_muzzle_flash() -> void:
	if _weapon == WeaponType.PISTOL:
		return

	_ensure_muzzle_flash()

	var frames := _get_muzzle_frames_for_weapon(_weapon)
	if frames == null:
		return

	_muzzle_flash.sprite_frames = frames
	_muzzle_flash.animation = "flash"
	_muzzle_flash.frame = 0
	_muzzle_flash.visible = true
	# Faster playback for rifle (and all): play every shot clearly
	_muzzle_flash.sprite_frames.set_animation_speed("flash", 45.0)

	var p := Vector2.ZERO
	if _weapon_fire_point != null:
		p = _weapon_fire_point.global_position
	else:
		p = muzzle.global_position

	var base := (_weapon_fire_point.global_position if _weapon_fire_point != null else muzzle.global_position)

	# default no offset
	var off_local := Vector2.ZERO
	if _muzzle_flash_offset_local.has(_weapon):
		off_local = _muzzle_flash_offset_local[_weapon]

	# convert local offset to world offset by rotating with muzzle direction
	var off_world := off_local.rotated(muzzle.global_rotation)

	_muzzle_flash.global_position = base + off_world

	var rot := muzzle.global_rotation
	if _weapon == WeaponType.SNIPER:
		rot += deg_to_rad(-45.0)
	elif _weapon == WeaponType.RIFLE:
		rot += deg_to_rad(315)
	elif _weapon == WeaponType.SHOTGUN:
		rot += deg_to_rad(180)
	_muzzle_flash.global_rotation = rot

	_muzzle_flash.flip_h = false
	_muzzle_flash.flip_v = false

	_muzzle_flash.play("flash")
	# Hide when animation ends (so each shot shows full flash; no timer conflict when holding fire)
	if not _muzzle_flash.animation_finished.is_connected(_on_muzzle_flash_finished):
		_muzzle_flash.animation_finished.connect(_on_muzzle_flash_finished)

func _on_muzzle_flash_finished() -> void:
	if is_instance_valid(_muzzle_flash) and _muzzle_flash.animation == "flash":
		_muzzle_flash.visible = false

func _ensure_muzzle_flash() -> void:
	if _muzzle_flash != null and is_instance_valid(_muzzle_flash):
		return

	_muzzle_flash = AnimatedSprite2D.new()
	_muzzle_flash.name = "MuzzleFlash"
	_muzzle_flash.visible = false
	_muzzle_flash.z_index = 100

	_muzzle_flash.top_level = true

	add_child(_muzzle_flash)

func _play_sniper_tail(stream: AudioStream, delay: float, vol_db: float, pitch: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = pitch
	add_child(p)
	get_tree().create_timer(delay).timeout.connect(func():
		if is_instance_valid(p):
			p.play()
	)
	# cleanup later
	get_tree().create_timer(delay + 1.5).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)
