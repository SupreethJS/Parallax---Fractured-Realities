class_name TouchControls
extends CanvasLayer

## TouchControls
## Clean, responsive mobile on-screen controls for PARALLAX: FRACTURED REALITIES.
## Features multi-touch support, reality shift, jump, interaction, and fullscreen toggle.

signal pause_requested()

@onready var root_control: Control = $Root
@onready var move_left_btn: TouchScreenButton = $Root/MoveLeftBtn
@onready var move_right_btn: TouchScreenButton = $Root/MoveRightBtn
@onready var jump_btn: TouchScreenButton = $Root/JumpBtn
@onready var shift_btn: TouchScreenButton = $Root/ShiftBtn
@onready var interact_btn: TouchScreenButton = $Root/InteractBtn
@onready var pause_btn: TouchScreenButton = $Root/PauseBtn
@onready var fullscreen_btn: TouchScreenButton = $Root/FullscreenBtn

var _force_visible: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	
	pause_btn.pressed.connect(_on_pause_pressed)
	fullscreen_btn.pressed.connect(_on_fullscreen_pressed)
	
	_update_visibility()

func _input(event: InputEvent) -> void:
	if not visible:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			_force_visible = true
			visible = true

func _update_visibility() -> void:
	if _force_visible:
		visible = true
		return
		
	var is_touch: bool = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if OS.has_feature("web"):
		var js_touch = JavaScriptBridge.eval("Boolean(navigator.maxTouchPoints > 0 || 'ontouchstart' in window)")
		if js_touch:
			is_touch = true
			
	visible = is_touch

func _on_pause_pressed() -> void:
	if SoundManager.instance:
		SoundManager.instance.play_ui_click()
	pause_requested.emit()

func _on_fullscreen_pressed() -> void:
	if SoundManager.instance:
		SoundManager.instance.play_ui_click()
	toggle_fullscreen()

func toggle_fullscreen() -> void:
	var is_fs: bool = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	if is_fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(function() {
				if (!document.fullscreenElement) {
					var el = document.documentElement;
					if (el.requestFullscreen) el.requestFullscreen().catch(function(){});
					else if (el.webkitRequestFullscreen) el.webkitRequestFullscreen();
				} else {
					if (document.exitFullscreen) document.exitFullscreen().catch(function(){});
					else if (document.webkitExitFullscreen) document.webkitExitFullscreen();
				}
				if (screen.orientation && screen.orientation.lock) {
					screen.orientation.lock('landscape').catch(function(){});
				}
			})();
		""")
