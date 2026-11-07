class_name GameHUD
extends CanvasLayer

## GameHUD
## Dynamic sci-fi telemetry interface for RESPawn: PARALLAX.

@onready var reality_badge: PanelContainer = $Root/TopMargin/HBox/RealityBadge
@onready var reality_label: Label = $Root/TopMargin/HBox/RealityBadge/RealityLabel
@onready var stage_title_label: Label = $Root/ObjectiveBox/StageTitleLabel
@onready var objective_label: Label = $Root/ObjectiveBox/ObjectiveLabel
@onready var checkpoint_banner: Label = $Root/CheckpointBanner
@onready var interact_hint: Label = $Root/InteractHint

var _checkpoint_timer: float = 0.0
var _notification_duration: float = 0.0
var _notification_fade_in_duration: float = 0.0
var _notification_fade_out_duration: float = 0.0

func _ready() -> void:
	var bottom_hint: Node = get_node_or_null("Root/BottomHint")
	if bottom_hint and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")):
		bottom_hint.visible = false

	var rm: Node = get_node_or_null("/root/RealityManager")
	if rm:
		if not rm.reality_changed.is_connected(_on_reality_changed):
			rm.reality_changed.connect(_on_reality_changed)
		if not rm.transition_pulse.is_connected(_on_transition_pulse):
			rm.transition_pulse.connect(_on_transition_pulse)
		update_reality_display(rm.current_reality)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var bottom_hint: Node = get_node_or_null("Root/BottomHint")
		if bottom_hint and bottom_hint.visible:
			bottom_hint.visible = false

func _process(delta: float) -> void:
	if _checkpoint_timer > 0.0:
		_checkpoint_timer = maxf(_checkpoint_timer - delta, 0.0)
		if checkpoint_banner:
			if _notification_duration > 0.0:
				var elapsed: float = _notification_duration - _checkpoint_timer
				var alpha: float = 1.0
				if _notification_fade_in_duration > 0.0:
					alpha = minf(alpha, clampf(elapsed / _notification_fade_in_duration, 0.0, 1.0))
				if _notification_fade_out_duration > 0.0 and _checkpoint_timer < _notification_fade_out_duration:
					alpha = minf(alpha, clampf(_checkpoint_timer / _notification_fade_out_duration, 0.0, 1.0))
				checkpoint_banner.modulate.a = alpha
			else:
				checkpoint_banner.modulate.a = clampf(_checkpoint_timer * 2.0, 0.0, 1.0)
	elif checkpoint_banner:
		checkpoint_banner.modulate.a = 0.0

func set_stage_info(title_text: String, objective_text: String) -> void:
	if stage_title_label:
		stage_title_label.text = title_text
	if objective_label:
		objective_label.text = objective_text

func show_checkpoint_notification(text: String = "CHECKPOINT ACTIVATED") -> void:
	if checkpoint_banner:
		checkpoint_banner.text = text
		checkpoint_banner.add_theme_color_override("font_color", Color(0.2, 0.95, 0.65, 1.0))
		checkpoint_banner.add_theme_color_override("font_outline_color", Color(0.025, 0.045, 0.08, 1.0))
		checkpoint_banner.add_theme_constant_override("outline_size", 0)
		checkpoint_banner.add_theme_font_size_override("font_size", 16)
		_checkpoint_timer = 2.4
		_notification_duration = 0.0
		_notification_fade_in_duration = 0.0
		_notification_fade_out_duration = 0.0

func show_link_established_notification(reality: int) -> void:
	if checkpoint_banner:
		checkpoint_banner.text = "REALITY LINK ESTABLISHED"
		checkpoint_banner.add_theme_color_override(
			"font_color",
			RealityManager.COLOR_REALITY_A_PRIMARY if reality == RealityManager.Reality.REALITY_A else RealityManager.COLOR_REALITY_B_PRIMARY
		)
		checkpoint_banner.add_theme_color_override("font_outline_color", Color(0.025, 0.045, 0.08, 1.0))
		checkpoint_banner.add_theme_constant_override("outline_size", 6)
		checkpoint_banner.add_theme_font_size_override("font_size", 20)
		_notification_duration = 1.5
		_notification_fade_in_duration = 0.12
		_notification_fade_out_duration = 0.24
		_checkpoint_timer = _notification_duration
		checkpoint_banner.modulate.a = 0.0

func set_interaction_hint(text: String, is_visible: bool) -> void:
	if interact_hint:
		interact_hint.text = text
		interact_hint.visible = is_visible

func _on_reality_changed(new_reality: RealityManager.Reality) -> void:
	update_reality_display(new_reality)

func _on_transition_pulse(intensity: float) -> void:
	if reality_badge:
		reality_badge.scale = Vector2.ONE * (1.0 + intensity * 0.12)

func update_reality_display(reality: RealityManager.Reality) -> void:
	var rm: Node = get_node_or_null("/root/RealityManager")
	var is_a: bool = (reality == RealityManager.Reality.REALITY_A)
	var col: Color = RealityManager.COLOR_REALITY_A_PRIMARY if is_a else RealityManager.COLOR_REALITY_B_PRIMARY
	var r_name: String = "REALITY A [CYAN]" if is_a else "REALITY B [MAGENTA]"

	if reality_label:
		reality_label.text = "%s  —  [PRESS Q TO SHIFT]" % r_name
		reality_label.add_theme_color_override("font_color", col)

	if reality_badge:
		var sb: StyleBoxFlat = reality_badge.get_theme_stylebox("panel") as StyleBoxFlat
		if sb:
			sb.border_color = col
