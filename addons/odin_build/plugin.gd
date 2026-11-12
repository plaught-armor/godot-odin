@tool
extends EditorPlugin

# Rebuilds the Odin extension when a .odin file under the watched directory changes, then reloads
# the extension, so live instances pick up the new code without restarting the editor. The build
# runs on a worker thread; its output goes to the Output panel. Set under Project Settings, Odin Build:
#   odin_build/watch_dir  the Odin sources, relative to the project directory or absolute
#   odin_build/command    the build command, run by the shell in the project directory
#   odin_build/extension  the .gdextension file to reload after a good build; empty reloads none
# The extension must set `reloadable = true`.

const WATCH_DIR: String = "odin_build/watch_dir"
const COMMAND: String = "odin_build/command"
const EXTENSION: String = "odin_build/extension"
# Seconds between scans of the watched directory.
const POLL_SECONDS: float = 1.0

var _timer: Timer
var _thread: Thread
# Newest modification time (Unix seconds) among the watched .odin files at the last scan.
var _stamp: int = 0
# A change arrived while a build ran: build again once it ends.
var _dirty: bool = false
# Ticks (ms) when the running build started.
var _started: int = 0


func _enter_tree() -> void:
	_add_setting(WATCH_DIR, "src")
	_add_setting(COMMAND, "odin build src -build-mode:shared -out:bin/libextension.so")
	_add_setting(EXTENSION, "")
	_stamp = _newest(_watch_root())
	_timer = Timer.new()
	_timer.wait_time = POLL_SECONDS
	_timer.timeout.connect(_poll)
	add_child(_timer)
	_timer.start()


func _exit_tree() -> void:
	_timer.queue_free()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _add_setting(name: String, default: String) -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default)
	ProjectSettings.set_initial_value(name, default)
	ProjectSettings.add_property_info({"name": name, "type": TYPE_STRING})


func _watch_root() -> String:
	var dir: String = ProjectSettings.get_setting(WATCH_DIR)
	if dir.is_absolute_path():
		return dir
	return ProjectSettings.globalize_path("res://").path_join(dir).simplify_path()


func _poll() -> void:
	var newest: int = _newest(_watch_root())
	if newest <= _stamp:
		return
	_stamp = newest
	if _thread != null:
		_dirty = true
		return
	_start_build()


func _start_build() -> void:
	var command: String = ProjectSettings.get_setting(COMMAND)
	var dir: String = ProjectSettings.globalize_path("res://")
	print("odin_build: building")
	_started = Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_compile.bind(command, dir))


# Runs on the worker thread: `command` through the shell in `dir`, then hands the exit code and
# the combined output to the main thread.
func _compile(command: String, dir: String) -> void:
	var output: Array = []
	var code: int
	if OS.get_name() == "Windows":
		code = OS.execute("cmd.exe", ["/c", "cd /d \"%s\" && %s" % [dir, command]], output, true)
	else:
		var quoted: String = "'%s'" % dir.replace("'", "'\\''")
		code = OS.execute("sh", ["-c", "cd %s && %s" % [quoted, command]], output, true)
	_built.call_deferred(code, "".join(output))


func _built(code: int, output: String) -> void:
	_thread.wait_to_finish()
	_thread = null
	var ms: int = Time.get_ticks_msec() - _started
	if not output.strip_edges().is_empty():
		print(output.strip_edges())
	if code != 0:
		push_error("odin_build: build failed (exit %d) after %d ms" % [code, ms])
	else:
		print("odin_build: built in %d ms" % ms)
		_reload()
	if _dirty:
		_dirty = false
		_start_build()


func _reload() -> void:
	var extension: String = ProjectSettings.get_setting(EXTENSION)
	if extension.is_empty():
		return
	var status: GDExtensionManager.LoadStatus = GDExtensionManager.reload_extension(extension)
	if status != GDExtensionManager.LOAD_STATUS_OK:
		push_error("odin_build: reloading %s failed (status %d)" % [extension, status])
	else:
		print("odin_build: reloaded %s" % extension)


# Newest modification time among the .odin files under `dir`, searched recursively; 0 for none.
func _newest(dir: String) -> int:
	var access: DirAccess = DirAccess.open(dir)
	if access == null:
		return 0
	var newest: int = 0
	for file: String in access.get_files():
		if file.get_extension() == "odin":
			newest = maxi(newest, FileAccess.get_modified_time(dir.path_join(file)))
	for sub: String in access.get_directories():
		if not sub.begins_with("."):
			newest = maxi(newest, _newest(dir.path_join(sub)))
	return newest
