extends SceneTree

# Runs the example's classes from GDScript and quits 0 on success, 1 on any failure.
#   godot --headless --path example/project -s test.gd

var _arrived: int = -1


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
	print("example: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
