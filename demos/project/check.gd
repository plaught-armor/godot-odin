extends SceneTree
## Runs each demo's Odin and GDScript backends from one seed, compares their outputs exactly, prints
## both timings, then opens every scene for a few frames on each backend. Quits 0 on success, 1 on any failure.
##   godot --headless --path demos/project -s check.gd

const SEED: int = 20261111
const SCENE_FRAMES: int = 6
## The frame of each scene that presses Tab, switching it to GDScript.
const TOGGLE_FRAME: int = 3

var _scenes: PackedStringArray = [
	"res://menu.tscn",
	"res://boids/boids.tscn",
	"res://sand/sand.tscn",
	"res://flow/flow.tscn",
	"res://terrain/terrain.tscn",
]
var _failures: int = 0
var _scene: int = -1
var _frames: int = 0


func _initialize() -> void:
	_check_boids()
	_check_sand()
	_check_flow()
	_check_terrain()


func _process(_delta: float) -> bool:
	_frames += 1
	if _scene >= 0 and _frames == TOGGLE_FRAME:
		var tab: InputEventKey = InputEventKey.new()
		tab.keycode = KEY_TAB
		tab.pressed = true
		Input.parse_input_event(tab)
	if _scene >= 0 and _frames < SCENE_FRAMES:
		return false
	_scene += 1
	_frames = 0
	if _scene >= _scenes.size():
		print("demos: PASS" if _failures == 0 else "demos: FAIL (%d)" % _failures)
		quit(0 if _failures == 0 else 1)
		return true
	var err: Error = change_scene_to_file(_scenes[_scene])
	if err != OK:
		_fail("cannot open %s: %s" % [_scenes[_scene], error_string(err)])
	return false


func _fail(what: String) -> void:
	print("FAIL: ", what)
	_failures += 1


## Prints the two timings; `odin_us` and `gd_us` cover the same work.
func _report(demo: String, odin_us: int, gd_us: int) -> void:
	var speedup: float = float(gd_us) / maxf(float(odin_us), 1.0)
	print(
		(
			"%-8s odin %8.2f ms   gdscript %9.2f ms   %6.1fx"
			% [demo, odin_us / 1000.0, gd_us / 1000.0, speedup]
		)
	)


func _same_floats(demo: String, a: PackedFloat32Array, b: PackedFloat32Array) -> void:
	if a.size() != b.size():
		_fail("%s: %d floats against %d" % [demo, a.size(), b.size()])
		return
	for i: int in a.size():
		if a[i] != b[i]:
			_fail("%s: float %d is %s in Odin, %s in GDScript" % [demo, i, a[i], b[i]])
			return


func _same_bytes(demo: String, a: PackedByteArray, b: PackedByteArray) -> void:
	if a.size() != b.size():
		_fail("%s: %d bytes against %d" % [demo, a.size(), b.size()])
		return
	for i: int in a.size():
		if a[i] != b[i]:
			_fail("%s: byte %d is %d in Odin, %d in GDScript" % [demo, i, a[i], b[i]])
			return


func _check_boids() -> void:
	const COUNT: int = 2000
	const STEPS: int = 60
	var odin: BoidsOdin = BoidsOdin.new()
	var gd: BoidsSim = BoidsSim.new()
	odin.setup(COUNT, 1280.0, 720.0, SEED)
	gd.setup(COUNT, 1280.0, 720.0, SEED)
	_same_floats("boids setup", odin.buffer, gd.buffer)
	odin.set_pointer(640.0, 360.0, 40000.0)
	gd.set_pointer(640.0, 360.0, 40000.0)
	var t0: int = Time.get_ticks_usec()
	for s: int in STEPS:
		odin.step(1.0 / 60.0)
	var t1: int = Time.get_ticks_usec()
	for s: int in STEPS:
		gd.step(1.0 / 60.0)
	var t2: int = Time.get_ticks_usec()
	_same_floats("boids", odin.buffer, gd.buffer)
	_report("boids", t1 - t0, t2 - t1)


func _check_sand() -> void:
	const W: int = 480
	const H: int = 270
	const STEPS: int = 120
	var odin: SandOdin = SandOdin.new()
	var gd: SandSim = SandSim.new()
	odin.setup(W, H, SEED)
	gd.setup(W, H, SEED)
	for sim: int in 2:
		for k: int in 6:
			var x: int = 40 + k * 80
			if sim == 0:
				odin.paint(x, 200, 30, SandOdin.WALL)
				odin.paint(x, 60, 25, SandOdin.SAND if k % 2 == 0 else SandOdin.WATER)
			else:
				gd.paint(x, 200, 30, SandSim.WALL)
				gd.paint(x, 60, 25, SandSim.SAND if k % 2 == 0 else SandSim.WATER)
	var grains: int = odin.count(SandOdin.SAND)
	var drops: int = odin.count(SandOdin.WATER)
	var t0: int = Time.get_ticks_usec()
	for s: int in STEPS:
		odin.step()
	var t1: int = Time.get_ticks_usec()
	for s: int in STEPS:
		gd.step()
	var t2: int = Time.get_ticks_usec()
	_same_bytes("sand", odin.image_data, gd.image_data)
	if odin.count(SandOdin.SAND) != grains or odin.count(SandOdin.WATER) != drops:
		_fail("sand: grains or drops appeared or vanished")
	_report("sand", t1 - t0, t2 - t1)


func _check_flow() -> void:
	const STEPS: int = 120
	var odin: FlowOdin = FlowOdin.new()
	var gd: FlowSim = FlowSim.new()
	odin.setup(256, 144, 5.0, 4000, SEED)
	gd.setup(256, 144, 5.0, 4000, SEED)
	_same_bytes("flow field", odin.field_image, gd.field_image)
	var t0: int = Time.get_ticks_usec()
	for s: int in STEPS:
		if s % 30 == 29:
			odin.set_target(200.0 + s * 5.0, 100.0 + s * 2.0)
		odin.step(1.0 / 60.0)
	var t1: int = Time.get_ticks_usec()
	for s: int in STEPS:
		if s % 30 == 29:
			gd.set_target(200.0 + s * 5.0, 100.0 + s * 2.0)
		gd.step(1.0 / 60.0)
	var t2: int = Time.get_ticks_usec()
	_same_bytes("flow field", odin.field_image, gd.field_image)
	_same_floats("flow units", odin.buffer, gd.buffer)
	if odin.rebuilds() != gd.rebuilds() or odin.rebuilds() < 2:
		_fail("flow: %d rebuilds in Odin, %d in GDScript" % [odin.rebuilds(), gd.rebuilds()])
	_report("flow", t1 - t0, t2 - t1)


func _check_terrain() -> void:
	const SIZE: int = 256
	var odin: TerrainOdin = TerrainOdin.new()
	var gd: TerrainSim = TerrainSim.new()
	var t0: int = Time.get_ticks_usec()
	odin.build(SIZE, 6, 4.0, 20.0, SEED)
	var t1: int = Time.get_ticks_usec()
	gd.build(SIZE, 6, 4.0, 20.0, SEED)
	var t2: int = Time.get_ticks_usec()
	if odin.vertices != gd.vertices:
		_fail("terrain: vertices differ")
	if odin.normals != gd.normals:
		_fail("terrain: normals differ")
	if odin.colors != gd.colors:
		_fail("terrain: colours differ")
	if odin.indices != gd.indices:
		_fail("terrain: indices differ")
	_report("terrain", t1 - t0, t2 - t1)
