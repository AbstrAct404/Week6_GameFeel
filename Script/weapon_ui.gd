# Script/weapon_ui.gd
extends Control

@export var active_alpha: float = 1.0
@export var inactive_alpha: float = 0.35

@onready var slots := [
	$Panel/HBox/Slot1/Icon,
	$Panel/HBox/Slot2/Icon,
	$Panel/HBox/Slot3/Icon,
	$Panel/HBox/Slot4/Icon
]

var current_weapon: int = 0
var cooldown_ratio: float = 0.0 # 0..1

@export var margin: Vector2 = Vector2(0, 0)

func _ready() -> void:
	call_deferred("_snap_top_right")
	top_level = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		call_deferred("_snap_top_right")

func _snap_top_right() -> void:
	await get_tree().process_frame

	var vr: Rect2 = get_viewport().get_visible_rect()
	global_position = vr.position + Vector2(vr.size.x - size.x - margin.x, margin.y + 0.0)
	
func set_weapon(index: int) -> void:
	current_weapon = index
	_refresh_slots()

func set_cooldown_ratio(r: float) -> void:
	pass

func _refresh_slots() -> void:
	for i in range(slots.size()):
		var icon: TextureRect = slots[i]
		var c = icon.modulate
		c.a = active_alpha if i == current_weapon else inactive_alpha
		icon.modulate = c

func set_weapon_icon(index: int, tex: Texture2D) -> void:
	if index < 0 or index >= slots.size():
		return
	if slots[index] == null:
		return
	slots[index].texture = tex
