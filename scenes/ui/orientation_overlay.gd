class_name OrientationOverlay
extends CanvasLayer

## OrientationOverlay
## Detects portrait phone orientation on mobile browsers and prompts the player
## to rotate to landscape for optimal gameplay, plus provides a one-tap fullscreen button.

@onready var root_panel: Control = $Root
@onready var fullscreen_btn: Button = $Root/Center/VBox/FullscreenBtn
@onready var dismiss_btn: Button = $Root/Center/VBox/DismissBtn
@onready var phone_graphic: Control = $Root/Center/VBox/PhoneGraphicContainer/PhoneGraphic

var _dismissed: bool = false
var _anim_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	visible = false
	
	UIHelper.style_button(fullscreen_btn, Color(0.08, 0.82, 0.98))
	UIHelper.style_button(dismiss_btn, Color(0.6, 0.7, 0.85))
	
	fullscreen_btn.pressed.connect(_on_fullscreen_pressed)
	dismiss_btn.pressed.connect(func(): _dismissed = true; visible = false)

func _process(delta: float) -> void:
	_anim_time += delta
	
	var is_portrait: bool = _check_is_portrait()
	var is_mobile: bool = _check_is_mobile()
	
	if not is_portrait:
		_dismissed = false
		if visible:
			visible = false
	elif is_mobile and not _dismissed:
		if not visible:
			visible = true
		if phone_graphic:
			# Gentle rhythmic 0 -> -90 deg rotation animation demonstrating rotation to landscape
			var t: float = fposmod(_anim_time, 2.4) / 2.4
			var angle: float = 0.0
			if t > 0.35 and t < 0.85:
				var sub_t: float = (t - 0.35) / 0.5
				angle = sin(sub_t * PI * 0.5) * (-PI * 0.5)
			elif t >= 0.85:
				angle = -PI * 0.5
			phone_graphic.rotation = angle

func _check_is_portrait() -> bool:
	if OS.has_feature("web"):
		var w = JavaScriptBridge.eval("window.innerWidth")
		var h = JavaScriptBridge.eval("window.innerHeight")
		if w != null and h != null:
			return float(h) > float(w)
	var ws: Vector2i = DisplayServer.window_get_size()
	return ws.y > ws.x

func _check_is_mobile() -> bool:
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if OS.has_feature("web"):
		var js_touch = JavaScriptBridge.eval("Boolean(navigator.maxTouchPoints > 0 || 'ontouchstart' in window)")
		if js_touch:
			return true
	# Also return true on very narrow vertical screens
	var ws: Vector2i = DisplayServer.window_get_size()
	return ws.x > 0 and ws.y > ws.x and ws.x < 768

func _on_fullscreen_pressed() -> void:
	if SoundManager.instance:
		SoundManager.instance.play_ui_click()
	
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	if OS.has_feature("web"):
		JavaScriptBridge.eval("""
			(function() {
				var el = document.documentElement;
				if (el.requestFullscreen) {
					el.requestFullscreen().catch(function(){});
				} else if (el.webkitRequestFullscreen) {
					el.webkitRequestFullscreen();
				}
				if (screen.orientation && screen.orientation.lock) {
					screen.orientation.lock('landscape').catch(function(){});
				}
			})();
		""")

