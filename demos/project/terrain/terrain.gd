extends Node3D
## Procedural terrain: fractal Perlin noise sampled at every vertex of a grid, then normals,
## colours and indices for one ArrayMesh surface. Up to 512 by 512 vertices and 10 octaves: millions
## of noise samples per build, which Odin finishes inside a frame. Morph rebuilds every frame.

const SEED: int = 31337
const MORPH_SWING: float = 0.15

var _odin_backend: bool = true
var _morph: bool = false
var _morph_time: float = 0.0
var _yaw: float = 0.6
var _pitch: float = -0.6
var _distance: float = 150.0
var _upload_usec: int = 0
var _last_build_usec: int = 0
var _odin: TerrainOdin = TerrainOdin.new()
var _gd: TerrainSim = TerrainSim.new()
var _mesh: ArrayMesh = ArrayMesh.new()
var _camera: Camera3D = Camera3D.new()
var _size: HSlider = HSlider.new()
var _octaves: HSlider = HSlider.new()
var _frequency: HSlider = HSlider.new()
var _height: HSlider = HSlider.new()
var _seed: SpinBox = SpinBox.new()
var _morph_box: CheckBox = CheckBox.new()
var _hud: DemoHud = DemoHud.new(
	"Procedural terrain",
	"right mouse drag orbits   wheel zooms   sliders rebuild   M morph",
)


func _ready() -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = _mesh
	instance.material_override = material
	add_child(instance)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.45, 0.6, 0.8)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	add_child(_camera)
	_build_controls()
	_hud.backend_toggled.connect(_on_backend_toggled)
	_hud.reset_requested.connect(_reset)
	add_child(_hud)
	_reset()


func _unhandled_input(event: InputEvent) -> void:
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and motion.button_mask & MOUSE_BUTTON_MASK_RIGHT != 0:
		_yaw -= motion.relative.x * 0.008
		_pitch = clampf(_pitch - motion.relative.y * 0.008, -1.5, -0.1)
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance * 0.9, 30.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * 1.1, 400.0)
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_M:
		_morph_box.button_pressed = not _morph_box.button_pressed


func _process(delta: float) -> void:
	var look: Basis = Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_camera.position = look * Vector3(0.0, 0.0, _distance)
	_camera.basis = look
	if _morph:
		_morph_time += delta
		_rebuild()
	else:
		_hud.show_frame(_odin_backend, _last_build_usec, _info())


func _build_controls() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	panel.add_child(grid)
	_add_slider(grid, "size", _size, 64.0, 512.0, 64.0, 256.0)
	_add_slider(grid, "octaves", _octaves, 1.0, 10.0, 1.0, 6.0)
	_add_slider(grid, "frequency", _frequency, 0.5, 12.0, 0.5, 4.0)
	_add_slider(grid, "height", _height, 0.0, 40.0, 1.0, 20.0)
	var seed_label: Label = Label.new()
	seed_label.text = "seed"
	grid.add_child(seed_label)
	_seed.min_value = 1.0
	_seed.max_value = 1000000.0
	_seed.value = SEED
	_seed.value_changed.connect(_on_value_changed)
	grid.add_child(_seed)
	var morph_label: Label = Label.new()
	morph_label.text = "morph"
	grid.add_child(morph_label)
	_morph_box.toggled.connect(_on_morph_toggled)
	grid.add_child(_morph_box)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.add_child(panel)
	add_child(layer)


func _add_slider(
	grid: GridContainer,
	label: String,
	slider: HSlider,
	low: float,
	high: float,
	step: float,
	value: float,
) -> void:
	var name_label: Label = Label.new()
	name_label.text = label
	grid.add_child(name_label)
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(220.0, 0.0)
	slider.value_changed.connect(_on_value_changed)
	grid.add_child(slider)


func _on_value_changed(_value: float) -> void:
	if not _morph:
		_rebuild()


func _on_morph_toggled(on: bool) -> void:
	_morph = on
	_morph_time = 0.0


func _on_backend_toggled() -> void:
	_odin_backend = not _odin_backend
	_reset()


func _reset() -> void:
	_morph_time = 0.0
	_hud.restart()
	_rebuild()


## Builds the arrays on the current backend, timing that apart from the mesh upload.
func _rebuild() -> void:
	var size: int = int(_size.value)
	var octaves: int = int(_octaves.value)
	var frequency: float = _frequency.value * (1.0 + MORPH_SWING * sin(_morph_time))
	var height: float = _height.value
	var seed: int = int(_seed.value)
	var start: int = Time.get_ticks_usec()
	if _odin_backend:
		_odin.build(size, octaves, frequency, height, seed)
	else:
		_gd.build(size, octaves, frequency, height, seed)
	var built: int = Time.get_ticks_usec()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	if _odin_backend:
		arrays[Mesh.ARRAY_VERTEX] = _odin.vertices
		arrays[Mesh.ARRAY_NORMAL] = _odin.normals
		arrays[Mesh.ARRAY_COLOR] = _odin.colors
		arrays[Mesh.ARRAY_INDEX] = _odin.indices
	else:
		arrays[Mesh.ARRAY_VERTEX] = _gd.vertices
		arrays[Mesh.ARRAY_NORMAL] = _gd.normals
		arrays[Mesh.ARRAY_COLOR] = _gd.colors
		arrays[Mesh.ARRAY_INDEX] = _gd.indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_upload_usec = Time.get_ticks_usec() - built
	_last_build_usec = built - start
	_hud.show_frame(_odin_backend, _last_build_usec, _info())


func _info() -> String:
	var size: int = int(_size.value)
	return (
		"%d vertices, %d octaves    mesh upload %.2f ms (engine, same for both)"
		% [size * size, int(_octaves.value), _upload_usec / 1000.0]
	)
