extends Node2D
## Falling sand: a 480 by 270 grid of cells, every one visited each frame, sand sinking through
## water and both piling on walls. The work is byte reads and writes over a flat array, cell by
## cell, then a full RGBA image for the screen.

const SEED: int = 777
const WIDTH: int = 480
const HEIGHT: int = 270
const MAX_RADIUS: int = 40

var _odin_backend: bool = true
var _material: int = SandSim.SAND
var _radius: int = 6
var _emitting: bool = true
var _odin: SandOdin = SandOdin.new()
var _gd: SandSim = SandSim.new()
var _image: Image = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
var _texture: ImageTexture = ImageTexture.create_from_image(_image)
var _sprite: Sprite2D = Sprite2D.new()
var _names: PackedStringArray = ["erase", "sand", "water", "wall"]
var _hud: DemoHud = DemoHud.new(
	"Falling sand",
	"left mouse paint, right mouse erase   1 sand  2 water  3 wall  4 erase   wheel radius   E emitters",
)


func _ready() -> void:
	_sprite.centered = false
	_sprite.texture = _texture
	add_child(_sprite)
	_hud.backend_toggled.connect(_on_backend_toggled)
	_hud.reset_requested.connect(_reset)
	add_child(_hud)
	_reset()


func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_radius = mini(_radius + 1, MAX_RADIUS)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_radius = maxi(_radius - 1, 0)
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_1:
		_material = SandSim.SAND
	elif key.keycode == KEY_2:
		_material = SandSim.WATER
	elif key.keycode == KEY_3:
		_material = SandSim.WALL
	elif key.keycode == KEY_4:
		_material = SandSim.EMPTY
	elif key.keycode == KEY_E:
		_emitting = not _emitting


func _process(_delta: float) -> void:
	var cell: Vector2 = get_global_mouse_position() / _sprite.scale
	var start: int = Time.get_ticks_usec()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_paint(int(cell.x), int(cell.y), _radius, _material)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_paint(int(cell.x), int(cell.y), _radius, SandSim.EMPTY)
	if _emitting:
		_paint(120, 3, 2, SandSim.SAND)
		_paint(240, 3, 2, SandSim.WATER)
		_paint(360, 3, 2, SandSim.SAND)
	if _odin_backend:
		_odin.step()
	else:
		_gd.step()
	var spent: int = Time.get_ticks_usec() - start
	_show()
	_hud.show_frame(
		_odin_backend,
		spent,
		"%d cells    painting %s, radius %d" % [WIDTH * HEIGHT, _names[_material], _radius],
	)


func _paint(x: int, y: int, radius: int, material: int) -> void:
	if _odin_backend:
		_odin.paint(x, y, radius, material)
	else:
		_gd.paint(x, y, radius, material)


func _show() -> void:
	var data: PackedByteArray = _odin.image_data if _odin_backend else _gd.image_data
	_image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8, data)
	_texture.update(_image)


func _on_backend_toggled() -> void:
	_odin_backend = not _odin_backend
	_reset()


## An empty grid from the same seed, with two slanted shelves and a cup, on the current backend.
@warning_ignore("integer_division")
func _reset() -> void:
	var size: Vector2 = get_viewport_rect().size
	_sprite.scale = Vector2(size.x / WIDTH, size.y / HEIGHT)
	if _odin_backend:
		_odin.setup(WIDTH, HEIGHT, SEED)
	else:
		_gd.setup(WIDTH, HEIGHT, SEED)
	for k: int in 140:
		_paint(60 + k, 90 + k / 3, 1, SandSim.WALL)
		_paint(420 - k, 150 + k / 3, 1, SandSim.WALL)
	for k: int in 60:
		_paint(200 + k, 255, 1, SandSim.WALL)
	for k: int in 30:
		_paint(200, 225 + k, 1, SandSim.WALL)
		_paint(260, 225 + k, 1, SandSim.WALL)
	if _odin_backend:
		_odin.step()
	else:
		_gd.step()
	_show()
	_hud.restart()
