extends SceneTree

# Hot-reloads the example extension under a live Walker and checks the instance keeps its state
# and its methods, and that the editor-level ExamplePlugin registers before and after. Reloading needs the editor:
#   godot --headless -e --path example/project -s reload_test.gd


func _initialize() -> void:
	var registered: bool = ClassDB.class_exists(&"ExamplePlugin")
	var w: Object = ClassDB.instantiate("Walker")
	w.speed = 3.0
	w.walk(Vector3(1, 0, 0), 2.0)
	var status: int = GDExtensionManager.reload_extension("res://example.gdextension")
	var moved: float = w.walk(Vector3(1, 0, 0), 1.0)
	if not registered:
		print("reload: FAIL ExamplePlugin not registered in the editor")
	elif status != GDExtensionManager.LOAD_STATUS_OK:
		print("reload: FAIL status %d" % status)
	elif not ClassDB.class_exists(&"ExamplePlugin"):
		print("reload: FAIL ExamplePlugin gone after the reload")
	elif not is_equal_approx(w.speed, 3.0) or w.steps != 2 or not is_equal_approx(moved, 3.0):
		print("reload: FAIL speed %s, steps %d, moved %s; not 3, 2, 3" % [w.speed, w.steps, moved])
	else:
		print("reload: PASS")
	quit(0)
