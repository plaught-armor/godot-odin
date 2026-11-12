extends Node2D
## Pathfinding swarm: Dijkstra from one target over a 256 by 144 grid gives every cell its cost,
## and thousands of units each walk downhill to the cheapest neighbour. Dragging the target rebuilds
## the whole field every frame: a heap, integer costs and a grid walk, the kind of code Odin keeps
## in registers.

const SEED: int = 9001
const COLS: int = 256
const ROWS: int = 144
const CELL: float = 5.0
const MIN_UNITS: int = 1000
const MAX_UNITS: int = 32000

var _odin_backend: bool = true
var _units: int = 4000
var _rebuilt: int = -1
var _odin: FlowOdin = FlowOdin.new()
var _gd: FlowSim = FlowSim.new()
var _image: Image = Image.create_empty(COLS, ROWS, false, Image.FORMAT_RGBA8)
var _texture: ImageTexture = ImageTexture.create_from_image(_image)
var _multimesh: MultiMesh = MultiMesh.new()
var _marker: ColorRect = ColorRect.new()
var _hud: DemoHud = DemoHud.new(
	"Pathfinding swarm",
	"left mouse (hold to drag) moves the target   Up/Down double/halve the units",
)


func _ready() -> void:
	var field: Sprite2D = Sprite2D.new()
	field.centered = false
	field.scale = Vector2(CELL, CELL)
	field.texture = _texture
	add_child(field)
	var mesh: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array(
		[Vector2(3.0, 0.0), Vector2(-2.0, 2.0), Vector2(-2.0, -2.0)]
	)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.mesh = mesh
	var instance: MultiMeshInstance2D = MultiMeshInstance2D.new()
	instance.multimesh = _multimesh
	instance.modulate = Color(1.0, 0.85, 0.3)
	add_child(instance)
	_marker.color = Color(1.0, 0.2, 0.3)
	_marker.size = Vector2(CELL * 2.0, CELL * 2.0)
	add_child(_marker)
	_hud.backend_toggled.connect(_on_backend_toggled)
	_hud.reset_requested.connect(_reset)
	add_child(_hud)
	_reset()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_UP and _units < MAX_UNITS:
		_units *= 2
		_reset()
	elif key.keycode == KEY_DOWN and _units > MIN_UNITS:
		@warning_ignore("integer_division")
		_units /= 2
		_reset()


func _process(delta: float) -> void:
	var dt: float = minf(delta, 1.0 / 30.0)
	var mouse: Vector2 = get_global_mouse_position()
	var dragging: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var start: int = Time.get_ticks_usec()
	if _odin_backend:
		if dragging:
			_odin.set_target(mouse.x, mouse.y)
		_odin.step(dt)
	else:
		if dragging:
			_gd.set_target(mouse.x, mouse.y)
		_gd.step(dt)
	var spent: int = Time.get_ticks_usec() - start
	if dragging:
		_place_marker(mouse)
	_show()
	_hud.show_frame(_odin_backend, spent, "%d units    %d field rebuilds" % [_units, _rebuilt])


## Puts the marker on the cell under `at` if that cell is now the target (cost 0).
func _place_marker(at: Vector2) -> void:
	var cx: int = int(at.x / CELL)
	var cy: int = int(at.y / CELL)
	if cx < 0 or cy < 0 or cx >= COLS or cy >= ROWS:
		return
	var cost: int = _odin.cost_at(cx, cy) if _odin_backend else _gd.cost_at(cx, cy)
	if cost == 0:
		_marker.position = Vector2(cx * CELL, cy * CELL) - Vector2(CELL, CELL) * 0.5


## Uploads the units, and the field when it was rebuilt since the last upload.
func _show() -> void:
	var rebuilt: int = _odin.rebuilds() if _odin_backend else _gd.rebuilds()
	if rebuilt != _rebuilt:
		_rebuilt = rebuilt
		var data: PackedByteArray = _odin.field_image if _odin_backend else _gd.field_image
		_image.set_data(COLS, ROWS, false, Image.FORMAT_RGBA8, data)
		_texture.update(_image)
	_multimesh.buffer = _odin.buffer if _odin_backend else _gd.buffer


func _on_backend_toggled() -> void:
	_odin_backend = not _odin_backend
	_reset()


## The same walls and units from the seed on the current backend, target back at the centre.
@warning_ignore("integer_division")
func _reset() -> void:
	if _odin_backend:
		_odin.setup(COLS, ROWS, CELL, _units, SEED)
	else:
		_gd.setup(COLS, ROWS, CELL, _units, SEED)
	_multimesh.instance_count = _units
	_rebuilt = -1
	_place_marker(Vector2((COLS / 2 + 0.5) * CELL, (ROWS / 2 + 0.5) * CELL))
	_show()
	_hud.restart()
