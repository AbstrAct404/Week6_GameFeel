extends CharacterBody2D

signal hp_changed(current: int, max_hp: int)

@export var speed: float = 220.0
@export var auto_range: float = 550.0

@export var max_hp: int = 40
var hp: int

@export var bullet_scene: PackedScene
@export var bullet_spawn_offset: float = 12.0

# Per-weapon cooldowns (seconds)
@export var pistol_cooldown: float = 0.45
@export var rifle_cooldown: float = 0.20
@export var shotgun_cooldown: float = 0.75
@export var sniper_cooldown: float = 1.10

# Shotgun spread
@export var shotgun_pellets: int = 5
@export var shotgun_spread_degrees: float = 18.0

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
	WeaponType.RIFLE: 4,
	WeaponType.SHOTGUN: 6,
	WeaponType.SNIPER: 45,
}

# Weapon fire SFX
var _weapon_fire_sfx := {
	WeaponType.PISTOL: preload("res://Assets/Sound effects/Pistol.wav"),
	WeaponType.RIFLE: preload("res://Assets/Sound effects/Rifle.wav"),
	WeaponType.SHOTGUN: preload("res://Assets/Sound effects/Shotgun.wav"),
	WeaponType.SNIPER: preload("res://Assets/Sound effects/Sniper.wav"),
}

var _hit_sfx: AudioStream = preload("res://Assets/Sound effects/PlayerGetHit.mp3")

func _ready() -> void:
	hp = max_hp
	emit_signal("hp_changed", hp, max_hp)
	_apply_weapon_visuals()

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
	# small QoL: allow immediate shot after switching
	_cooldown_t = 0.0

func take_damage(amount: int = 1) -> void:
	hp = clamp(hp - max(1, amount), 0, max_hp)
	emit_signal("hp_changed", hp, max_hp)
	if sfx_hit:
		sfx_hit.stream = _hit_sfx
		sfx_hit.play()
	if hp <= 0:
		get_tree().reload_current_scene()

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
	# --- movement ---
	var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = move_dir * speed
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

	if target != null and Input.is_action_pressed("shoot") and _cooldown_t <= 0.0:
		_cooldown_t = _get_weapon_cooldown()
		_play_fire_sfx()
		_shoot_with_weapon(target.global_position)

func _play_fire_sfx() -> void:
	if sfx_fire == null:
		return
	if _weapon_fire_sfx.has(_weapon):
		sfx_fire.stream = _weapon_fire_sfx[_weapon]
		sfx_fire.play()

func _get_weapon_cooldown() -> float:
	match _weapon:
		WeaponType.RIFLE:
			return rifle_cooldown
		WeaponType.SHOTGUN:
			return shotgun_cooldown
		WeaponType.SNIPER:
			return sniper_cooldown
		_:
			return pistol_cooldown

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
	# Canvas transform maps world->screen for 2D nodes.
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
	_spawn_bullet(spawn_pos, dir)

func shoot_shotgun(target_pos: Vector2) -> void:
	var spawn_pos := _get_spawn_pos()
	var dir_vec := target_pos - spawn_pos
	if dir_vec.length_squared() < 0.0001:
		return

	var base_dir := dir_vec.normalized()
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

	var bullets := get_tree().current_scene.get_node_or_null("World/Bullets") as Node2D
	if bullets != null:
		bullets.add_child(b)
	else:
		get_tree().current_scene.add_child(b)

func _aim_at(target_pos: Vector2) -> void:
	var dir := target_pos - muzzle.global_position
	if dir.length_squared() < 0.0001:
		return

	# Weapon sprites are authored facing 3 o'clock (Vector2.RIGHT).
	# When aiming to the left side of the player (clock 6 -> 12, i.e. dir.x < 0),
	# we mirror the weapon and keep the rotation in a visually "upright" range.
	var ang := dir.angle()

	if dir.x < 0.0:
		muzzle.rotation = ang 
		if _weapon_sprite:
			_weapon_sprite.flip_v = true
	else:
		muzzle.rotation = ang
		if _weapon_sprite:
			_weapon_sprite.flip_v = false

	# Avoid double-flipping: keep horizontal flip off and use vertical mirror only.
	if _weapon_sprite:
		_weapon_sprite.flip_h = false
