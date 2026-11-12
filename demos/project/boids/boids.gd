extends Node2D
## Boids: separation, alignment and cohesion over a wrapping field, with neighbours found through a
## uniform grid. Every boid reads every nearby boid each frame, so the cost grows with the flock:
## the kind of tight float loop Odin compiles to machine code and GDScript interprets.

const SEED: int = 4242
const MIN_COUNT: int = 500
const MAX_COUNT: int = 64000
## Push (left button) or pull (right button) strength of the pointer.
const POINTER: float = 60000.0

var _odin_backend: bool = true
var _count: int = 4000
var _odin: BoidsOdin = BoidsOdin.new()
var _gd: BoidsSim = BoidsSim.new()
var _multimesh: MultiMesh = MultiMesh.new()
var _hud: DemoHud = DemoHud.new(
	"Boids",
	"Up/Down double/halve the flock   left mouse push, right mouse pull",
)


func _ready() -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array(
		[Vector2(6.0, 0.0), Vector2(-4.0, 3.0), Vector2(-4.0, -3.0)]
	)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(
		[Color(1.0, 0.9, 0.5), Color(0.4, 0.7, 1.0), Color(0.4, 0.7, 1.0)]
	)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.mesh = mesh
	var instance: MultiMeshInstance2D = MultiMeshInstance2D.new()
	instance.multimesh = _multimesh
	add_child(instance)
	_hud.backend_toggled.connect(_on_backend_toggled)
	_hud.reset_requested.connect(_reset)
	add_child(_hud)
	_reset()


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed:
		return
	if key.keycode == KEY_UP and _count < MAX_COUNT:
		_count *= 2
		_reset()
	elif key.keycode == KEY_DOWN and _count > MIN_COUNT:
		@warning_ignore("integer_division")
		_count /= 2
		_reset()


func _process(delta: float) -> void:
	var strength: float = 0.0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		strength = POINTER
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		strength = -POINTER
	var mouse: Vector2 = get_global_mouse_position()
	var dt: float = minf(delta, 1.0 / 30.0)
	var start: int = Time.get_ticks_usec()
	if _odin_backend:
		_odin.set_pointer(mouse.x, mouse.y, strength)
		_odin.step(dt)
	else:
		_gd.set_pointer(mouse.x, mouse.y, strength)
		_gd.step(dt)
	var spent: int = Time.get_ticks_usec() - start
	_multimesh.buffer = _odin.buffer if _odin_backend else _gd.buffer
	_hud.show_frame(_odin_backend, spent, "%d boids" % _count)


func _on_backend_toggled() -> void:
	_odin_backend = not _odin_backend
	_reset()


## Scatters the flock again from the same seed on the current backend.
func _reset() -> void:
	var size: Vector2 = get_viewport_rect().size
	_multimesh.instance_count = _count
	if _odin_backend:
		_odin.setup(_count, size.x, size.y, SEED)
		_gd.setup(0, size.x, size.y, SEED)
	else:
		_gd.setup(_count, size.x, size.y, SEED)
		_odin.setup(0, size.x, size.y, SEED)
	_multimesh.buffer = _odin.buffer if _odin_backend else _gd.buffer
	_hud.restart()
