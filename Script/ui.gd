# UI.gd (Godot 4)
extends CanvasLayer
class_name UI

signal effects_changed(effects: Dictionary)

# --- Paths (edit these to match your tree) ---
@export var effects_panel_path: NodePath = ^"HUD/EffectsPanel"
@export var sfx_box_path: NodePath     = ^"HUD/EffectsPanel/VBoxContainer/SFXBox"
@export var shake_box_path: NodePath   = ^"HUD/EffectsPanel/VBoxContainer/ShakeBox"
@export var flash_box_path: NodePath   = ^"HUD/EffectsPanel/VBoxContainer/FlashBox"
@export var vignette_box_path: NodePath= ^"HUD/EffectsPanel/VBoxContainer/VignetteBox"
@export var damage_box_path: NodePath  = ^"HUD/EffectsPanel/VBoxContainer/DamageBox"

const SAVE_SECTION := "effects"
const SAVE_FILE := "user://settings.cfg"

# Current effects state (other scripts can read UI.effects)
var effects := {
	"sfx": true,
	"shake": true,
	"flash": true,
	"vignette": true,
	"damage": true,
}

@onready var effects_panel: Control = get_node_or_null(effects_panel_path) as Control
@onready var sfx_box: CheckBox = get_node_or_null(sfx_box_path) as CheckBox
@onready var shake_box: CheckBox = get_node_or_null(shake_box_path) as CheckBox
@onready var flash_box: CheckBox = get_node_or_null(flash_box_path) as CheckBox
@onready var vignette_box: CheckBox = get_node_or_null(vignette_box_path) as CheckBox
@onready var damage_box: CheckBox = get_node_or_null(damage_box_path) as CheckBox


func _ready() -> void:
	_load_effects()

	# Apply loaded values to UI without re-triggering spam
	_apply_effects_to_checkboxes()

	# Ensure the checkboxes accept mouse + keyboard
	_prepare_checkbox(sfx_box)
	_prepare_checkbox(shake_box)
	_prepare_checkbox(flash_box)
	_prepare_checkbox(vignette_box)
	_prepare_checkbox(damage_box)

	# Connect signals (toggled fires on mouse click + keyboard)
	_connect_box(sfx_box, "sfx")
	_connect_box(shake_box, "shake")
	_connect_box(flash_box, "flash")
	_connect_box(vignette_box, "vignette")
	_connect_box(damage_box, "damage")

	_emit_effects_changed()


# ---------- Public helpers ----------
func set_effect(key: String, enabled: bool) -> void:
	if not effects.has(key):
		return
	effects[key] = enabled
	_save_effects()
	_emit_effects_changed()

func get_effect(key: String) -> bool:
	return effects.get(key, true)

func toggle_effects_panel() -> void:
	if effects_panel:
		effects_panel.visible = not effects_panel.visible


# ---------- Internal ----------
func _prepare_checkbox(box: CheckBox) -> void:
	if box == null:
		return
	# Mouse + keyboard focus
	box.focus_mode = Control.FOCUS_ALL
	box.mouse_filter = Control.MOUSE_FILTER_STOP

func _connect_box(box: CheckBox, key: String) -> void:
	if box == null:
		push_warning("UI.gd: Missing CheckBox for key: %s (check NodePath exports)" % key)
		return

	# Avoid double connections if scene reloads
	if box.toggled.is_connected(_on_box_toggled):
		return

	# Bind key so one function handles all boxes
	box.toggled.connect(_on_box_toggled.bind(key))

func _on_box_toggled(pressed: bool, key: String) -> void:
	effects[key] = pressed
	_save_effects()
	_emit_effects_changed()

func _emit_effects_changed() -> void:
	emit_signal("effects_changed", effects.duplicate(true))

func _apply_effects_to_checkboxes() -> void:
	if sfx_box: sfx_box.button_pressed = effects["sfx"]
	if shake_box: shake_box.button_pressed = effects["shake"]
	if flash_box: flash_box.button_pressed = effects["flash"]
	if vignette_box: vignette_box.button_pressed = effects["vignette"]
	if damage_box: damage_box.button_pressed = effects["damage"]

func _load_effects() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_FILE)
	if err != OK:
		return

	for k in effects.keys():
		effects[k] = cfg.get_value(SAVE_SECTION, k, effects[k])

func _save_effects() -> void:
	var cfg := ConfigFile.new()
	# Load existing first (so you can add more settings later)
	cfg.load(SAVE_FILE)

	for k in effects.keys():
		cfg.set_value(SAVE_SECTION, k, effects[k])

	cfg.save(SAVE_FILE)
