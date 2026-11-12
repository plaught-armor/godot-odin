extends SceneTree

# Runs the example's classes from GDScript and quits 0 on success, 1 on any failure.
#   godot --headless --path example/project -s test.gd

var _arrived: int = -1
var _ticker: Ticker
var _failures: int = 0
var _frames: int = 0


func _initialize() -> void:
	var failures: int = 0
	var w: Walker = Walker.new()
	w.arrived.connect(func(steps: int) -> void: _arrived = steps)
	if not is_equal_approx(w.speed, 1.5):
		print("FAIL: default speed %s, not 1.5" % w.speed)
		failures += 1
	w.speed = 2.0
	var moved: float = w.walk(Vector3(1, 0, 0), 3.0)
	if not is_equal_approx(moved, 6.0) or not w.position.is_equal_approx(Vector3(6, 0, 0)):
		print("FAIL: walk moved %s to %s, not 6 to (6, 0, 0)" % [moved, w.position])
		failures += 1
	w.walk(Vector3(0, 0, 1))
	if w.steps != 2 or _arrived != 2:
		print("FAIL: steps %d, arrived %d, not 2 and 2" % [w.steps, _arrived])
		failures += 1
	if not is_equal_approx(WalkMath.distance(0.5, 4.0), 2.0):
		print("FAIL: WalkMath.distance(0.5, 4.0) is not 2")
		failures += 1
	if not is_equal_approx(WalkMath.apply(func(x: float) -> float: return x + 1.0, 2.0), 3.0):
		print("FAIL: WalkMath.apply through Callable.call is not 3")
		failures += 1
	if not is_equal_approx(WalkMath.call_float(self, &"twice", 2.0), 4.0):
		print("FAIL: WalkMath.call_float through Object.call is not 4")
		failures += 1
	_failures = failures


# Called from Odin through Object.call.
func twice(x: float) -> float:
	return x * 2.0


# Frames run after `_initialize`, with the root in the tree: the first adds a Ticker and checks
# its `_ready` and `_input`, the fourth that its `_process` ran on the frames between.
func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_add_ticker()
	if _frames < 4:
		return false
	if _ticker.ticks < 2:
		print("FAIL: Ticker._process ran %d times in %d frames" % [_ticker.ticks, _frames])
		_failures += 1
	print("example: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)
	return false


func _add_ticker() -> void:
	_ticker = Ticker.new()
	root.add_child(_ticker)
	if not _ticker.readied:
		print("FAIL: Ticker._ready did not run")
		_failures += 1
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	root.push_input(key)
	if _ticker.last_key != KEY_A:
		print("FAIL: Ticker._input got key %d, not %d" % [_ticker.last_key, KEY_A])
		_failures += 1
