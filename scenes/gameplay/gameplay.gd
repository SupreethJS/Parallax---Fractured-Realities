class_name Gameplay
extends Node2D

## Gameplay
## Central gameplay orchestrator for RESPawn: PARALLAX.
## Integrates ParallaxBackdrop, active Stage geometry, Player, Camera, HUD, Pause & Victory screens.

signal return_to_main_menu_requested()

# Preloaded Stages & Scenes
const STAGE_1_SCENE: PackedScene = preload("res://scenes/gameplay/stages/stage_1_first_contact.tscn")
const STAGE_2_SCENE: PackedScene = preload("res://scenes/gameplay/stages/stage_2_fracture.tscn")
const STAGE_3_SCENE: PackedScene = preload("res://scenes/gameplay/stages/stage_3_singularity.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const BACKDROP_SCENE: PackedScene = preload("res://scenes/environment/parallax_backdrop.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/ui/hud.tscn")
const PAUSE_SCENE: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const DEATH_SCENE: PackedScene = preload("res://scenes/ui/death_screen.tscn")
const VICTORY_SCENE: PackedScene = preload("res://scenes/ui/victory_screen.tscn")

var backdrop: ParallaxBackdrop = null
var current_stage: StageBase = null
var player: PuzzlePlayer = null
var hud: GameHUD = null
var pause_menu: PauseMenu = null
var settings_menu: SettingsMenu = null
var death_screen: DeathScreen = null
var victory_screen: VictoryScreen = null

var stage_container: Node2D = null
var stage_container2: Node2D = null
var current_stage_id: int = 1
var is_multiplayer: bool = false
var player2: PuzzlePlayer = null
var camera2: Camera2D = null
var viewport_container: Control = null
var viewport1: SubViewport = null
var viewport2: SubViewport = null
var current_stage2: StageBase = null
var _stage_transition_pending: bool = false
var _player1_reached_exit: bool = false
var _player2_reached_exit: bool = false
var _coop_links: Array[CoopPuzzleLink] = []
var _reality_rift: RealityRiftDivider

# Campaign Statistics
var campaign_timer: float = 0.0
var reality_shifts_count: int = 0
var death_count: int = 0
var is_game_paused: bool = false
var is_campaign_won: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# 1. Instantiate Parallax Backdrop (strictly in background at z_index = -100)
	backdrop = BACKDROP_SCENE.instantiate() as ParallaxBackdrop
	backdrop.name = "ParallaxBackdrop"
	add_child(backdrop)

	# 2. Stage Container
	stage_container = Node2D.new()
	stage_container.name = "StageContainer"
	stage_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(stage_container)

	# 3. Setup for single/multiplayer
	if is_multiplayer:
		_setup_multiplayer()
	else:
		_setup_singleplayer()

	# 4. Instantiate HUD and UI Modals in CanvasLayer
	var ui_canvas: CanvasLayer = CanvasLayer.new()
	ui_canvas.name = "GameplayUILayer"
	ui_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_canvas)

	hud = HUD_SCENE.instantiate() as GameHUD
	ui_canvas.add_child(hud)

	death_screen = DEATH_SCENE.instantiate() as DeathScreen
	death_screen.visible = false
	death_screen.respawn_requested.connect(_respawn_player)
	ui_canvas.add_child(death_screen)

	pause_menu = PAUSE_SCENE.instantiate() as PauseMenu
	pause_menu.visible = false
	pause_menu.resume_requested.connect(_toggle_pause)
	pause_menu.restart_requested.connect(_restart_current_stage)
	pause_menu.settings_requested.connect(_open_settings_from_pause)
	pause_menu.main_menu_requested.connect(_return_to_main_menu)
	ui_canvas.add_child(pause_menu)

	settings_menu = SETTINGS_SCENE.instantiate() as SettingsMenu
	settings_menu.visible = false
	settings_menu.closed.connect(_close_settings)
	ui_canvas.add_child(settings_menu)

	victory_screen = VICTORY_SCENE.instantiate() as VictoryScreen
	victory_screen.visible = false
	victory_screen.play_again_requested.connect(_restart_campaign)
	victory_screen.main_menu_requested.connect(_return_to_main_menu)
	ui_canvas.add_child(victory_screen)

	# Hook RealityManager to count shifts
	var rm: Node = get_node_or_null("/root/RealityManager")
	if rm and rm.has_signal("reality_changed"):
		rm.reality_changed.connect(_on_reality_changed)

	# Load initial stage (default Stage 1)
	load_stage(current_stage_id)

func _process(delta: float) -> void:
	if not is_game_paused and not is_campaign_won:
		campaign_timer += delta

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			if settings_menu.visible:
				_close_settings()
			elif not is_campaign_won:
				_toggle_pause()
			get_viewport().set_input_as_handled()
		elif not is_multiplayer and not is_game_paused and (event.keycode == KEY_R or event.physical_keycode == KEY_R):
			if player and player.current_state == PuzzlePlayer.State.DYING:
				_respawn_player()
				get_viewport().set_input_as_handled()

func set_multiplayer_mode(enabled: bool) -> void:
	is_multiplayer = enabled

func load_stage(stage_id: int) -> void:
	current_stage_id = stage_id
	_stage_transition_pending = false
	_player1_reached_exit = false
	_player2_reached_exit = false
	_clear_coop_links()

	# Remove existing stage
	for child in stage_container.get_children():
		child.queue_free()
	if is_multiplayer and stage_container2:
		for child in stage_container2.get_children():
			child.queue_free()

	# Instantiate target stage
	var new_stage: StageBase = null
	match stage_id:
		1:
			new_stage = STAGE_1_SCENE.instantiate() as StageBase
		2:
			new_stage = STAGE_2_SCENE.instantiate() as StageBase
		3:
			new_stage = STAGE_3_SCENE.instantiate() as StageBase
		_:
			new_stage = STAGE_1_SCENE.instantiate() as StageBase

	current_stage = new_stage
	current_stage2 = _instantiate_stage(stage_id) if is_multiplayer else null

	# Reset players BEFORE adding stage to tree
	if player:
		player.global_position = current_stage.default_spawn_position
		player.velocity = Vector2.ZERO
		player.current_checkpoint = current_stage.default_spawn_position
		player.current_state = PuzzlePlayer.State.IDLE
	if is_multiplayer and player2:
		player2.global_position = current_stage2.default_spawn_position
		player2.velocity = Vector2.ZERO
		player2.current_checkpoint = current_stage2.default_spawn_position
		player2.current_state = PuzzlePlayer.State.IDLE

	stage_container.add_child(current_stage)
	if is_multiplayer:
		stage_container2.add_child(current_stage2)
		_apply_stage_reality(current_stage, RealityManager.Reality.REALITY_A)
		_apply_stage_reality(current_stage2, RealityManager.Reality.REALITY_B)
		current_stage.configure_cooperative_reality(RealityManager.Reality.REALITY_A)
		current_stage2.configure_cooperative_reality(RealityManager.Reality.REALITY_B)
		_setup_cooperative_links()

	# Connect stage signals
	if is_multiplayer:
		current_stage.stage_completed.connect(_on_stage_completed.bind(current_stage))
	else:
		current_stage.stage_completed.connect(_on_stage_completed.bind(current_stage))
	current_stage.checkpoint_reached.connect(_on_checkpoint_reached)
	if is_multiplayer:
		current_stage2.stage_completed.connect(_on_stage_completed.bind(current_stage2))
		current_stage2.checkpoint_reached.connect(_on_player2_checkpoint_reached)

	# Ensure stage checkpoint state is fresh
	current_stage.active_checkpoint = current_stage.default_spawn_position
	current_stage.active_checkpoint_id = 0

	# Update HUD telemetry
	if hud:
		hud.set_stage_info(current_stage.stage_title, _stage_objective_text())

	# Sync backdrop palette to current reality immediately
	var rm: Node = get_node_or_null("/root/RealityManager")
	if rm and backdrop:
		backdrop.set_reality_palette(int(rm.current_reality), 0.0)
	if is_multiplayer:
		var backdrop2: ParallaxBackdrop = viewport2.get_node_or_null("ParallaxBackdrop")
		if backdrop2:
			backdrop2.set_reality_palette(RealityManager.Reality.REALITY_B, 0.0)

func _stage_objective_text() -> String:
	if not is_multiplayer:
		return current_stage.stage_objective
	match current_stage_id:
		1:
			return "P2: activate the Reality B relay to materialize P1's bridge. P1: use the A conduit to open P2's gate. Both operatives must reach transit."
		2:
			return "P2: clear the Reality A beam barrier. P1: align the mirror and power the receiver to open P2's gate. Both operatives must reach transit."
		3:
			return "P1: activate the Reality A override to open P2's gate. P2: cross it and activate the Reality B override to open P1's gate. Both reach the core."
	return current_stage.stage_objective

func _instantiate_stage(stage_id: int) -> StageBase:
	match stage_id:
		1:
			return STAGE_1_SCENE.instantiate() as StageBase
		2:
			return STAGE_2_SCENE.instantiate() as StageBase
		3:
			return STAGE_3_SCENE.instantiate() as StageBase
		_:
			return STAGE_1_SCENE.instantiate() as StageBase

func _apply_stage_reality(stage: StageBase, reality: RealityManager.Reality) -> void:
	for node in stage.find_children("*", "ShiftableObject", true, false):
		(node as ShiftableObject).set_reality_override(reality)
	for node in stage.find_children("*", "LaserEmitter", true, false):
		(node as LaserEmitter).set_reality_override(reality)
	for node in stage.find_children("*", "MovingPlatform", true, false):
		(node as MovingPlatform).set_reality_override(reality)
	for node in stage.find_children("*", "SecurityDrone", true, false):
		(node as SecurityDrone).set_reality_override(reality)

func _on_checkpoint_reached(cp_id: int, pos: Vector2) -> void:
	if player:
		player.current_checkpoint = pos
	if hud:
		hud.show_checkpoint_notification("CHECKPOINT %d ACTIVATED" % cp_id)

func _on_player2_checkpoint_reached(_cp_id: int, pos: Vector2) -> void:
	if player2:
		player2.current_checkpoint = pos

func _on_stage_completed(next_stage: int, player_id: int = 0, source_stage: StageBase = null) -> void:
	if is_campaign_won or (is_multiplayer and _stage_transition_pending):
		return
	if not is_instance_valid(source_stage) or (source_stage != current_stage and (not is_multiplayer or source_stage != current_stage2)):
		return
	if next_stage >= 999 and current_stage_id != 3:
		return

	if is_multiplayer:
		if next_stage != current_stage_id + 1 and next_stage < 999:
			push_error("Player reached an unexpected stage exit: %d from stage %d." % [next_stage, current_stage_id])
			return
		var expected_player_id: int = 1 if source_stage == current_stage else 2
		if player_id != expected_player_id:
			push_error("Player %d reached the exit in Player %d's reality." % [player_id, expected_player_id])
			return
		if player_id == 1:
			_player1_reached_exit = true
		elif player_id == 2:
			_player2_reached_exit = true
		else:
			push_error("Multiplayer stage exit did not identify its player.")
			return
		if hud:
			var waiting_for: String = "PLAYER 2" if not _player2_reached_exit else "PLAYER 1"
			if _player1_reached_exit and _player2_reached_exit:
				waiting_for = ""
			elif player_id == 1 and _player1_reached_exit:
				waiting_for = "PLAYER 2"
			elif player_id == 2 and _player2_reached_exit:
				waiting_for = "PLAYER 1"
			if waiting_for != "":
				hud.show_checkpoint_notification("EXIT READY — WAITING FOR %s" % waiting_for)
		if not (_player1_reached_exit and _player2_reached_exit):
			return

	if next_stage >= 999:
		_stage_transition_pending = true
		is_campaign_won = true
		is_game_paused = true
		get_tree().paused = true
		if hud:
			hud.visible = false
		if victory_screen:
			victory_screen.set_stats(campaign_timer, reality_shifts_count, death_count)
			victory_screen.play_ending_sequence()
		if SoundManager.instance:
			SoundManager.instance.play_stage_complete()
		return

	_stage_transition_pending = true
	_advance_after_stage_completed(next_stage)

func _advance_after_stage_completed(next_stage: int) -> void:
	# Advance to the next stage seamlessly (deferred to avoid physics query flushing conflict).
	call_deferred("load_stage", next_stage)
	if hud:
		hud.show_checkpoint_notification("STAGE %02d CLEARED — BOTH OPERATIVES READY" % (next_stage - 1))

func _on_player_died(reason: String) -> void:
	death_count += 1
	if is_multiplayer:
		return
	if death_screen:
		death_screen.set_death_reason(reason)
		death_screen.visible = true

func _on_player_respawned() -> void:
	if death_screen:
		death_screen.visible = false

func _respawn_player() -> void:
	if death_screen:
		death_screen.visible = false
	if current_stage and player:
		player.current_checkpoint = current_stage.active_checkpoint
	if player and player.has_method("request_respawn"):
		player.call("request_respawn")
	if is_multiplayer and current_stage and player2:
		player2.current_checkpoint = current_stage.active_checkpoint + Vector2(30,0)
		if player2.has_method("request_respawn"):
			player2.call("request_respawn")

func _on_reality_changed(_new_reality: RealityManager.Reality) -> void:
	reality_shifts_count += 1

func _toggle_pause() -> void:
	is_game_paused = not is_game_paused
	get_tree().paused = is_game_paused
	if pause_menu:
		pause_menu.visible = is_game_paused

func _restart_current_stage() -> void:
	_toggle_pause()
	load_stage(current_stage_id)

func _restart_campaign() -> void:
	is_campaign_won = false
	is_game_paused = false
	get_tree().paused = false
	campaign_timer = 0.0
	reality_shifts_count = 0
	death_count = 0
	if hud:
		hud.visible = true
	if victory_screen:
		victory_screen.reset_ending_sequence()
	load_stage(1)

func _open_settings_from_pause() -> void:
	if pause_menu:
		pause_menu.visible = false
	if settings_menu:
		settings_menu.visible = true

func _close_settings() -> void:
	if settings_menu:
		settings_menu.visible = false
	if is_game_paused and pause_menu:
		pause_menu.visible = true

func _return_to_main_menu() -> void:
	if is_game_paused:
		_toggle_pause()
	return_to_main_menu_requested.emit()


func _setup_singleplayer() -> void:
	# 3. Spawn Player
	player = PLAYER_SCENE.instantiate() as PuzzlePlayer
	player.name = "Player"
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.player_died.connect(_on_player_died)
	player.player_respawned.connect(_on_player_respawned)
	add_child(player)

func _setup_multiplayer() -> void:
	viewport_container = Control.new()
	viewport_container.name = "Viewports"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(viewport_container)
	viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS

	var left_view: SubViewportContainer = _create_viewport_container("Player1Viewport", 0)
	var right_view: SubViewportContainer = _create_viewport_container("Player2Viewport", 1)
	viewport_container.add_child(left_view)
	viewport_container.add_child(right_view)
	_reality_rift = RealityRiftDivider.new()
	_reality_rift.name = "RealityRiftDivider"
	viewport_container.add_child(_reality_rift)
	viewport1 = left_view.get_child(0) as SubViewport
	viewport2 = right_view.get_child(0) as SubViewport

	# Each operative gets an isolated copy of the same stage in their own reality.
	remove_child(stage_container)
	viewport1.add_child(stage_container)
	stage_container2 = Node2D.new()
	stage_container2.name = "StageContainer"
	stage_container2.process_mode = Node.PROCESS_MODE_PAUSABLE
	viewport2.add_child(stage_container2)
	var backdrop1: ParallaxBackdrop = BACKDROP_SCENE.instantiate() as ParallaxBackdrop
	backdrop1.name = "ParallaxBackdrop"
	backdrop1.set_reality_override(RealityManager.Reality.REALITY_A)
	viewport1.add_child(backdrop1)
	var backdrop2: ParallaxBackdrop = BACKDROP_SCENE.instantiate() as ParallaxBackdrop
	backdrop2.name = "ParallaxBackdrop"
	backdrop2.set_reality_override(RealityManager.Reality.REALITY_B)
	viewport2.add_child(backdrop2)

	# Player 1
	player = PLAYER_SCENE.instantiate() as PuzzlePlayer
	player.name = "Player1"
	player.player_id = 1
	player.local_multiplayer_controls = true
	player.fixed_reality = RealityManager.Reality.REALITY_A
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.player_died.connect(_on_player_died)
	player.player_respawned.connect(_on_player_respawned)
	viewport1.add_child(player)
	# Player 2
	player2 = PLAYER_SCENE.instantiate() as PuzzlePlayer
	player2.name = "Player2"
	player2.player_id = 2
	player2.local_multiplayer_controls = true
	player2.fixed_reality = RealityManager.Reality.REALITY_B
	player2.process_mode = Node.PROCESS_MODE_PAUSABLE
	player2.player_died.connect(_on_player_died)
	player2.player_respawned.connect(_on_player_respawned)
	viewport2.add_child(player2)
	# Cameras - player1 in viewport1, player2 in viewport2
	var cam1 = player.get_node("PlayerCamera")
	if cam1 and cam1 is Camera2D:
		cam1.enabled = true
	var cam2 = player2.get_node("PlayerCamera")
	if cam2 and cam2 is Camera2D:
		cam2.enabled = true
		cam2.make_current()

func _setup_cooperative_links() -> void:
	match current_stage_id:
		1:
			var stage_a := current_stage as Stage1FirstContact
			var stage_b := current_stage2 as Stage1FirstContact
			_create_cooperative_link("BRelayToABridge", stage_b.get_node("BRelaySwitch") as PuzzleSwitch, stage_a.get_node("CrossRealityBridgeA"), &"set_linked_active")
			_create_cooperative_link("AConduitToBDoor", stage_a.get_node("SwitchS1") as PuzzleSwitch, stage_b.get_node("DoorS1"), &"set_linked_powered")
		2:
			var stage_a := current_stage as Stage2Fracture
			var stage_b := current_stage2 as Stage2Fracture
			_create_cooperative_link("BRelayToABarrier", stage_b.get_node("BRelaySwitchS2") as PuzzleSwitch, stage_a.get_node("LaserBarrier_A"), &"set_linked_phase_out")
			var receiver_a := stage_a.get_node("OverheadReceiver") as LaserReceiver
			_create_cooperative_signal_link("AReceiverToBDoor", receiver_a.powered_changed, receiver_a, stage_b.get_node("BlastDoorS2"), &"set_linked_powered", receiver_a.is_powered)
		3:
			var stage_a := current_stage as Stage3Singularity
			var stage_b := current_stage2 as Stage3Singularity
			_create_cooperative_link("AOverrideToBGate", stage_a.get_node("DroneOverrideSwitch") as PuzzleSwitch, stage_b.get_node("ReactorSecurityGate"), &"set_linked_powered")
			_create_cooperative_link("BOverrideToAGate", stage_b.get_node("DroneOverrideSwitch") as PuzzleSwitch, stage_a.get_node("ReactorSecurityGate"), &"set_linked_powered")

func _create_cooperative_link(link_name: String, source: PuzzleSwitch, target: Node, method: StringName) -> void:
	var link := CoopPuzzleLink.new()
	link.name = link_name
	add_child(link)
	if link.bind(source, target, method):
		link.state_changed.connect(_on_cooperative_link_changed.bind(link))
		_coop_links.append(link)
	else:
		link.queue_free()

func _create_cooperative_signal_link(link_name: String, source_signal: Signal, source: Object, target: Node, method: StringName, initial_state: bool) -> void:
	var link := CoopPuzzleLink.new()
	link.name = link_name
	add_child(link)
	if link.bind_signal(source_signal, source, target, method, initial_state):
		link.state_changed.connect(_on_cooperative_link_changed.bind(link))
		_coop_links.append(link)
	else:
		link.queue_free()

func _on_cooperative_link_changed(is_active: bool, link: CoopPuzzleLink) -> void:
	var target: Node = link.target
	var source: Object = link.source
	var source_node: Node = source as Node if is_instance_valid(source) else null
	var source_stage: StageBase = source_node.get_parent() as StageBase if source_node else null
	var target_stage: StageBase = target.get_parent() as StageBase if is_instance_valid(target) else null
	if not source_stage or not target_stage:
		return

	var source_reality: int = source_stage.get_visual_reality()
	var target_reality: int = target_stage.get_visual_reality()
	if _reality_rift:
		_reality_rift.pulse(source_reality, is_active)
	if hud and is_active:
		hud.show_link_established_notification(source_reality)
	if target is ShiftableObject:
		_add_linked_action_pulse(target, (target as ShiftableObject).object_size, target_reality, is_active)
	elif target is PuzzleDoor:
		_add_linked_action_pulse(target, (target as PuzzleDoor).door_size, target_reality, is_active)
	if SoundManager.instance:
		SoundManager.instance.play_linked_action()

func _add_linked_action_pulse(target: Node2D, effect_size: Vector2, reality: int, is_active: bool) -> void:
	if not is_instance_valid(target):
		return
	var effect: LinkedActionPulse = target.get_node_or_null("LinkedActionPulse") as LinkedActionPulse
	if not effect:
		effect = LinkedActionPulse.new()
		effect.name = "LinkedActionPulse"
		target.add_child(effect)
	effect.position = Vector2.ZERO
	effect.z_index = 10
	var effect_color: Color = RealityManager.COLOR_REALITY_A_PRIMARY if reality == RealityManager.Reality.REALITY_A else RealityManager.COLOR_REALITY_B_PRIMARY
	effect.start(effect_size, effect_color, is_active)

func _clear_coop_links() -> void:
	for link in _coop_links:
		link.clear()
		link.queue_free()
	_coop_links.clear()

func _create_viewport_container(container_name: String, player_index: int) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.name = container_name
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1152, 648)
	var half_w: float = vp_size.x * 0.5
	var h: float = vp_size.y
	container.position = Vector2(player_index * half_w, 0)
	container.size = Vector2(half_w, h)
	container.stretch = true
	var sub_viewport := SubViewport.new()
	sub_viewport.name = "SubViewport"
	sub_viewport.size = Vector2i(int(half_w), int(h))
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(sub_viewport)
	return container
