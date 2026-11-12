class_name DemoHud
extends CanvasLayer
## The readout every demo shares: which backend runs, its smoothed simulation time per frame, the
## frame rate and the demo's own counts, over the key hints. Tab asks to switch backend, R to reset,
## Esc returns to the menu.

signal backend_toggled
signal reset_requested

const MENU: String = "res://menu.tscn"
## Weight of the newest frame in the smoothed time.
const SMOOTHING: float = 0.1

var _title: String = ""
var _hints: String = ""
var _ms: float = 0.0
var _label: Label = Label.new()


## `title` heads the readout; `hints` lists the demo's own keys under the shared ones.
func _init(title: String, hints: String) -> void:
	_title = title
	_hints = hints


func _ready() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(8.0, 8.0)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override(&"panel", style)
	_label.add_theme_font_size_override(&"font_size", 15)
	panel.add_child(_label)
	add_child(panel)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_TAB:
		backend_toggled.emit()
	elif key.keycode == KEY_R:
		reset_requested.emit()
	elif key.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file.call_deferred(MENU)
	else:
		return
	get_viewport().set_input_as_handled()


## Shows one frame: `odin` names the backend, `sim_usec` the time its simulation took, `info` the
## demo's counts. A switch of backend should call `restart` so the smoothing starts over.
func show_frame(odin: bool, sim_usec: int, info: String) -> void:
	var ms: float = sim_usec / 1000.0
	_ms = ms if _ms == 0.0 else lerpf(_ms, ms, SMOOTHING)
	_label.text = (
		"%s    backend: %s\nsim %.2f ms    %d fps    %s\nTab Odin/GDScript   R reset   Esc menu\n%s"
		% [
			_title,
			"Odin" if odin else "GDScript",
			_ms,
			Engine.get_frames_per_second(),
			info,
			_hints,
		]
	)


## Drops the smoothed time, for a new backend or setup.
func restart() -> void:
	_ms = 0.0
