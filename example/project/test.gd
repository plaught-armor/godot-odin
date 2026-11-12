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
	failures += _check_instances(w)
	failures += _check_temp()
	failures += _check_untyped()
	_failures = failures


# A script on top of the extension class: its objects are still Walkers to Odin.
class ScriptedWalker extends Walker:
	pass


# Odin finds a Walker's struct behind the object, for its own and scripted Walkers only.
func _check_instances(w: Walker) -> int:
	var failures: int = 0
	var scripted: ScriptedWalker = ScriptedWalker.new()
	scripted.speed = 4.0
	var ticker: Ticker = Ticker.new()
	var cases: Array = [[w, true], [scripted, true], [Resource.new(), false], [ticker, false], [null, false]]
	for c: Array in cases:
		if WalkMath.is_walker(c[0]) != c[1]:
			print("FAIL: WalkMath.is_walker(%s) is not %s" % c)
			failures += 1
	ticker.free()
	if not is_equal_approx(WalkMath.speed_of(w), 2.0) or not is_equal_approx(WalkMath.speed_of(scripted), 4.0):
		print("FAIL: WalkMath.speed_of read %s and %s, not 2 and 4" % [WalkMath.speed_of(w), WalkMath.speed_of(scripted)])
		failures += 1
	if not is_equal_approx(WalkMath.speed_of(null), -1.0):
		print("FAIL: WalkMath.speed_of(null) is not -1")
		failures += 1
	return failures


# Untyped calls and property writes arrive as Variants, and an int, float or bool converts to the
# parameter's or field's type as the engine's own would.
func _check_untyped() -> int:
	var failures: int = 0
	var u: Variant = Walker.new()
	u.speed = 3
	u.steps = 2.9
	var moved: Variant = u.walk(Vector3.ZERO, 2)
	if typeof(moved) != TYPE_FLOAT or not is_equal_approx(moved, 6.0) or typeof(u.speed) != TYPE_FLOAT:
		print("FAIL: untyped walk answered %s (type %d), not the float 6" % [moved, typeof(moved)])
		failures += 1
	if typeof(u.steps) != TYPE_INT or u.steps != 3:
		print("FAIL: steps set from 2.9 then walked is %s, not the int 3" % u.steps)
		failures += 1
	u.steps = true
	if u.steps != 1:
		print("FAIL: steps set from true is %s, not 1" % u.steps)
		failures += 1
	var t: Variant = Ticker.new()
	for c: Array in [[1, true], [0.0, false], [2.5, true], [false, false]]:
		t.readied = c[0]
		if typeof(t.readied) != TYPE_BOOL or t.readied != c[1]:
			print("FAIL: readied set from %s is %s, not %s" % [c[0], t.readied, c[1]])
			failures += 1
	t.free()
	return failures


# Each call gives back the temp memory it took: a small take, and one past the arena's 4 MiB block.
func _check_temp() -> int:
	var before: int = WalkMath.temp_in_use()
	for bytes: int in [64, 8 << 20, 64]:
		WalkMath.scratch(bytes)
		if WalkMath.temp_in_use() != before:
			print("FAIL: %d bytes of temp held after scratch(%d), not %d" % [WalkMath.temp_in_use(), bytes, before])
			return 1
	return 0


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
