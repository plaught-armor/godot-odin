extends SceneTree

# Calls into an Odin class from a worker task. A debug build of the library stops the process with
# its own message; example/build.sh checks for it. Reaching the end is the failure.


func _initialize() -> void:
	var b: Bag = Bag.new()
	b.misuse_task()
	print("task guard: FAIL no stop")
	quit()
