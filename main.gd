extends Node2D

## Main
## High-level master coordinator for RESPAWN: PARALLAX.
## Manages Title Screen (MainMenu), Settings, Stage Selection, and Gameplay transitions.

const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const OPENING_INTRO_SCENE: PackedScene = preload("res://scenes/ui/opening_intro.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const GAMEPLAY_SCENE: PackedScene = preload("res://scenes/gameplay/gameplay.tscn")
const BACKDROP_SCENE: PackedScene = preload("res://scenes/environment/parallax_backdrop.tscn")
const ORIENTATION_OVERLAY_SCENE: PackedScene = preload("res://scenes/ui/orientation_overlay.tscn")

var title_backdrop: ParallaxBackdrop = null
var title_canvas: CanvasLayer = null
var main_menu: MainMenu = null
var settings_menu: SettingsMenu = null
var opening_intro: OpeningIntro = null
var active_gameplay: Gameplay = null
var menu_camera: Camera2D = null
var orientation_overlay: OrientationOverlay = null

var _menu_pan_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_orientation_overlay()
	_setup_title_screen()
	_show_opening_intro()

func _setup_orientation_overlay() -> void:
	orientation_overlay = ORIENTATION_OVERLAY_SCENE.instantiate() as OrientationOverlay
	add_child(orientation_overlay)

func _process(delta: float) -> void:
	# Subtle celestial pan during title menu
	if main_menu and main_menu.visible and menu_camera:
		_menu_pan_time += delta
		menu_camera.position.x = sin(_menu_pan_time * 0.15) * 60.0
		menu_camera.position.y = cos(_menu_pan_time * 0.1) * 20.0

func _setup_title_screen() -> void:
	# 1. Background for Main Menu
	title_backdrop = BACKDROP_SCENE.instantiate() as ParallaxBackdrop
	title_backdrop.name = "TitleParallaxBackdrop"
	add_child(title_backdrop)

	# 2. Camera for Title Menu Parallax motion
	menu_camera = Camera2D.new()
	menu_camera.name = "MenuCamera"
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1152, 648)
	menu_camera.position = vp_size * 0.5
	add_child(menu_camera)

	# 3. Canvas Layer for Title UI
	title_canvas = CanvasLayer.new()
	title_canvas.name = "TitleUILayer"
	add_child(title_canvas)

	main_menu = MAIN_MENU_SCENE.instantiate() as MainMenu
	main_menu.visible = false
	main_menu.start_campaign_requested.connect(_on_start_campaign)
	main_menu.local_multiplayer_requested.connect(_on_local_multiplayer)
	main_menu.stage_selected.connect(_on_stage_selected)
	main_menu.settings_requested.connect(_open_settings)
	title_canvas.add_child(main_menu)

	settings_menu = SETTINGS_SCENE.instantiate() as SettingsMenu
	settings_menu.visible = false
	settings_menu.closed.connect(_close_settings)
	title_canvas.add_child(settings_menu)

func _show_opening_intro() -> void:
	if main_menu:
		main_menu.visible = false
	if settings_menu:
		settings_menu.visible = false
	opening_intro = OPENING_INTRO_SCENE.instantiate() as OpeningIntro
	opening_intro.finished.connect(_show_main_menu)
	title_canvas.add_child(opening_intro)

func _show_main_menu() -> void:
	if opening_intro and is_instance_valid(opening_intro):
		opening_intro.queue_free()
	opening_intro = null
	if main_menu:
		main_menu.visible = true
	if settings_menu:
		settings_menu.visible = false

func _on_start_campaign() -> void:
	_launch_gameplay(1)

func _on_stage_selected(stage_id: int) -> void:
	_launch_gameplay(stage_id)

func _launch_gameplay(stage_id: int) -> void:
	# Hide Title Screen and its menu camera / backdrop
	title_canvas.visible = false
	title_backdrop.visible = false
	menu_camera.enabled = false

	# Instantiate and launch Gameplay
	active_gameplay = GAMEPLAY_SCENE.instantiate() as Gameplay
	active_gameplay.name = "Gameplay"
	active_gameplay.return_to_main_menu_requested.connect(_on_return_to_menu)
	add_child(active_gameplay)
	active_gameplay.load_stage(stage_id)

func _on_return_to_menu() -> void:
	# Destroy active gameplay session cleanly
	if active_gameplay and is_instance_valid(active_gameplay):
		active_gameplay.queue_free()
		active_gameplay = null

	# Restore Title Screen
	menu_camera.enabled = true
	title_backdrop.visible = true
	title_canvas.visible = true
	_show_main_menu()

func _open_settings() -> void:
	if settings_menu:
		settings_menu.visible = true

func _close_settings() -> void:
	if settings_menu:
		settings_menu.visible = false

func _on_local_multiplayer() -> void:
	_launch_gameplay_multiplayer(1)

func _launch_gameplay_multiplayer(stage_id: int) -> void:
	title_canvas.visible = false
	title_backdrop.visible = false
	menu_camera.enabled = false
	active_gameplay = GAMEPLAY_SCENE.instantiate() as Gameplay
	active_gameplay.name = "Gameplay"
	active_gameplay.set_multiplayer_mode(true)
	active_gameplay.return_to_main_menu_requested.connect(_on_return_to_menu)
	add_child(active_gameplay)
	active_gameplay.load_stage(stage_id)
