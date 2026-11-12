extends SceneTree

# Runs the example's classes from GDScript and quits 0 on success, 1 on any failure.
#   godot --headless --path example/project -s test.gd

var _arrived: int = -1
var _ticker: Ticker
var _failures: int = 0
var _frames: int = 0
# A Bag whose `defer` calls run at the end of the first frame, and `proc_total` before them.
var _deferred: Bag
var _deferred_from: int = 0


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
	failures += _check_bag()
	failures += _check_extras()
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


class ScriptedBag extends Bag:
	func _score(x: int) -> int:
		return x * 3


# Bag's dynamic slots, revert values, validation and _to_string.
func _check_bag() -> int:
	var failures: int = 0
	var b: Bag = Bag.new()
	b.set(&"slot_2", 7)
	if b.get(&"slot_2") != 7 or b.get(&"slot_0") != 0:
		print("FAIL: Bag slots read %s and %s, not 7 and 0" % [b.get(&"slot_2"), b.get(&"slot_0")])
		failures += 1
	if b.get(&"slot_9") != null:
		print("FAIL: Bag.slot_9 is %s, not null" % b.get(&"slot_9"))
		failures += 1
	if str(b) != "Bag(0, 0, 7, 0)":
		print("FAIL: str(Bag) is %s" % str(b))
		failures += 1
	if not b.property_can_revert(&"slot_2") or b.property_can_revert(&"slot_1") or b.property_get_revert(&"slot_2") != 0:
		print("FAIL: Bag slot revert is wrong")
		failures += 1
	var slots: int = 0
	var note_usage: int = -1
	var note_hint: String = ""
	for p: Dictionary in b.get_property_list():
		if String(p.name).begins_with("slot_"):
			slots += 1
		if p.name == "note":
			note_usage = p.usage
			note_hint = p.hint_string
	if slots != 4:
		print("FAIL: Bag lists %d slots, not 4" % slots)
		failures += 1
	if note_usage & PROPERTY_USAGE_EDITOR or note_hint != "a note":
		print("FAIL: Bag.note usage %d, hint %s; validate did not run" % [note_usage, note_hint])
		failures += 1
	b.show_note = true
	for p: Dictionary in b.get_property_list():
		if p.name == "note" and not (p.usage & PROPERTY_USAGE_EDITOR):
			print("FAIL: Bag.note hidden with show_note set")
			failures += 1
	if b.score(2) != -1 or ScriptedBag.new().score(2) != 6:
		print("FAIL: Bag.score answered %d and %d, not -1 and 6" % [b.score(2), ScriptedBag.new().score(2)])
		failures += 1
	return failures


# Flags, a typed Dictionary, an unsigned byte, the singleton and the runtime class.
func _check_extras() -> int:
	var failures: int = 0
	var b: Bag = Bag.new()
	if Bag.RED != 1 or Bag.GREEN != 2 or Bag.BLUE != 4:
		print("FAIL: Bag.Mark is %d %d %d, not 1 2 4" % [Bag.RED, Bag.GREEN, Bag.BLUE])
		failures += 1
	b.marks = Bag.RED | Bag.BLUE
	if b.marks != 5 or not b.has_marks(Bag.BLUE) or b.has_marks(Bag.GREEN):
		print("FAIL: Bag.marks is %d, has_marks wrong" % b.marks)
		failures += 1
	b.counts["a"] = 1
	if not b.counts.is_typed() or b.counts.get_typed_key_builtin() != TYPE_STRING or b.counts.get_typed_value_builtin() != TYPE_INT:
		print("FAIL: Bag.counts is not Dictionary[String, int]")
		failures += 1
	b.level = 200
	if b.level != 200:
		print("FAIL: Bag.level reads %d, not 200" % b.level)
		failures += 1
	var box: RefCounted = b.box
	if box == null or box.get_reference_count() != 2:
		print("FAIL: Bag.box is %s, not a RefCounted the bag and this test hold" % box)
		failures += 1
	b = null
	if box != null and box.get_reference_count() != 1:
		print("FAIL: Bag.box holds %d references after its bag went, not 1" % box.get_reference_count())
		failures += 1
	var u: Variant = Bag.new()
	if u.total([1, 2, 3]) != 6 or u.total(PackedInt64Array([4, 5])) != 9:
		print("FAIL: untyped Bag.total answered %s and %s, not 6 and 9" % [u.total([1, 2, 3]), u.total(PackedInt64Array([4, 5]))])
		failures += 1
	var xs := PackedInt64Array([1, 2, 3])
	var b2: Bag = Bag.new()
	var twice: PackedInt64Array = b2.doubled(xs)
	if twice != PackedInt64Array([2, 4, 6]) or xs != PackedInt64Array([1, 2, 3]):
		print("FAIL: Bag.doubled gave %s and left %s, not [2, 4, 6] and [1, 2, 3]" % [twice, xs])
		failures += 1
	if u.total(PackedInt64Array()) != 0:
		print("FAIL: Bag.total of an empty array is %s, not 0" % u.total(PackedInt64Array()))
		failures += 1
	if b2.squares(4) != PackedInt64Array([0, 1, 4, 9]) or b2.squares(0) != PackedInt64Array():
		print("FAIL: Bag.squares gave %s and %s, not [0, 1, 4, 9] and []" % [b2.squares(4), b2.squares(0)])
		failures += 1
	if b2.colors() != PackedStringArray(["red", "green", "blue"]):
		print("FAIL: Bag.colors gave %s" % b2.colors())
		failures += 1
	if b2.vowels("héllo wörld") != 2 or b2.vowels("") != 0:
		print("FAIL: Bag.vowels counted %d and %d, not 2 and 0" % [b2.vowels("héllo wörld"), b2.vowels("")])
		failures += 1
	if b2.second([1, "two", 3]) != "two" or b2.second([1]) != null:
		print("FAIL: Bag.second gave %s and %s, not two and null" % [b2.second([1, "two", 3]), b2.second([1])])
		failures += 1
	var img: Image = Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 1, 1))
	b2.redden(img)
	if img.get_pixel(1, 1) != Color(1, 0, 1, 1):
		print("FAIL: Bag.redden gave %s, not (1, 0, 1, 1)" % img.get_pixel(1, 1))
		failures += 1
	var bytes := PackedByteArray()
	for i in 200:
		bytes.append(i)
	var fw: FileAccess = FileAccess.open("user://bag_sum.bin", FileAccess.WRITE)
	fw.store_buffer(bytes)
	fw.close()
	if b2.file_sum("user://bag_sum.bin") != 19900 or b2.file_sum("user://missing.bin") != -1:
		print("FAIL: Bag.file_sum gave %d and %d, not 19900 and -1" % [b2.file_sum("user://bag_sum.bin"), b2.file_sum("user://missing.bin")])
		failures += 1
	if b2.shout("hé") != "hé!¡?hé" or b2.shout("") != "!¡?":
		print("FAIL: Bag.shout gave %s and %s" % [b2.shout("hé"), b2.shout("")])
		failures += 1
	if b2.parallel_sum(100000) != 4999950000 or b2.parallel_sum(0) != 0:
		print("FAIL: Bag.parallel_sum gave %d, not 4999950000" % b2.parallel_sum(100000))
		failures += 1
	if not b2.worker_temp_freed():
		print("FAIL: a worker thread kept the temp memory of an earlier task")
		failures += 1
	if b2.task_text(1234) != 9:
		print("FAIL: Bag.task_text gave %d, not 9" % b2.task_text(1234))
		failures += 1
	var loose: Array = [1, 2, "x"]
	var typed: Array[int] = [1, 2]
	if not b2.bump_all(loose) or loose != [2, 3, "x"] or b2.bump_all(typed) or typed != [1, 2] or not b2.bump_all([]):
		print("FAIL: Bag.bump_all gave %s and %s" % [loose, typed])
		failures += 1
	if b2.range_of(4) != [0, 1, 2, 3] or b2.range_of(0) != []:
		print("FAIL: Bag.range_of(4) gave %s" % b2.range_of(4))
		failures += 1
	var ints: Array[int] = b2.typed_range(3)
	if ints != [0, 1, 2] or not ints.is_typed() or ints.get_typed_builtin() != TYPE_INT or b2.typed_range(0).get_typed_builtin() != TYPE_INT:
		print("FAIL: Bag.typed_range(3) gave %s" % ints)
		failures += 1
	var words: Array[String] = b2.typed_words()
	if words != ["a", "bc"] or words.get_typed_builtin() != TYPE_STRING:
		print("FAIL: Bag.typed_words gave %s" % words)
		failures += 1
	var nodes: Array[Node] = b2.typed_nodes(2)
	if nodes != [null, null] or nodes.get_typed_class_name() != &"Node":
		print("FAIL: Bag.typed_nodes(2) gave %s typed %s" % [nodes, nodes.get_typed_class_name()])
		failures += 1
	var floats: Array[float] = [1.5]
	var plain: Array = [1, 2]
	var frozen: Array[int] = [4]
	frozen.make_read_only()
	if not b2.typed_bump(ints) or ints != [1, 2, 3] or b2.typed_bump(floats) or b2.typed_bump(plain) or plain != [1, 2] or b2.typed_bump(frozen) or frozen != [4]:
		print("FAIL: Bag.typed_bump gave %s, %s and %s" % [ints, floats, plain])
		failures += 1
	if not b2.typed_shout(words) or words != ["a!", "bc!"] or b2.typed_shout(nodes):
		print("FAIL: Bag.typed_shout gave %s" % words)
		failures += 1
	if b2.weighted({2: 3, 5: 7, "s": 9}) != 41 or b2.weighted({}) != 0:
		print("FAIL: Bag.weighted gave %d, not 41" % b2.weighted({2: 3, 5: 7, "s": 9}))
		failures += 1
	var tally: Object = Engine.get_singleton(&"ExampleTally")
	if tally == null or tally.bump() != 1 or tally.bump() != 2:
		print("FAIL: the ExampleTally singleton is missing or miscounts")
		failures += 1
	var g: Node = Ghost.new()
	g.seen = 3
	if g.seen != 3:
		print("FAIL: Ghost.seen reads %s, not 3" % g.seen)
		failures += 1
	var root: Node = Node.new()
	var sprite: Node2D = Node2D.new()
	sprite.name = &"Sprite"
	root.add_child(sprite)
	g.name = &"Ghost"
	sprite.add_child(g)
	if b2.named("héllo") != &"héllo" or b2.pathed("a/b:c") != NodePath("a/b:c"):
		print("FAIL: Bag.named or Bag.pathed gave %s and %s" % [b2.named("héllo"), b2.pathed("a/b:c")])
		failures += 1
	if not b2.find_2d(root, "Sprite") or b2.find_2d(root, "Sprite/Ghost") or b2.find_2d(root, "Missing") or b2.find_2d(null, "Sprite"):
		print("FAIL: Bag.find_2d found the wrong nodes")
		failures += 1
	if b2.find_ghost(root, "Sprite/Ghost") != 3 or b2.find_ghost(root, "Sprite") != -1 or b2.find_ghost(root, "Nope") != -1:
		print("FAIL: Bag.find_ghost gave %d, not 3" % b2.find_ghost(root, "Sprite/Ghost"))
		failures += 1
	b2.say(42)
	var before: int = Bag.proc_total()
	var add: Callable = b2.adder(10)
	add.call(2)
	var to_slot: Callable = b2.slot_adder(1)
	to_slot.call(5)
	to_slot.call(6)
	if Bag.proc_total() - before != 20 or b2.get(&"slot_1") != 11 or add.get_argument_count() != 1:
		print("FAIL: Bag Callables gave %d and %s, not 20 and 11" % [Bag.proc_total() - before, b2.get(&"slot_1")])
		failures += 1
	var squares: Dictionary = b2.dict_squares(4)
	if squares != {0: 0.0, 1: 1.0, 2: 4.0, 3: 9.0} or squares.is_typed() or typeof(squares[3]) != TYPE_FLOAT or not b2.dict_squares(0).is_empty():
		print("FAIL: Bag.dict_squares gave %s" % squares)
		failures += 1
	var words_count: Dictionary = b2.dict_words()
	if words_count != {"a": 3, "bc": 2} or words_count.get_typed_key_builtin() != TYPE_STRING or words_count.get_typed_value_builtin() != TYPE_INT:
		print("FAIL: Bag.dict_words gave %s" % words_count)
		failures += 1
	var loose_dict: Dictionary = b2.dict_loose()
	if loose_dict != {1: "x", 2: null} or not loose_dict.is_typed_key() or loose_dict.is_typed_value():
		print("FAIL: Bag.dict_loose gave %s" % loose_dict)
		failures += 1
	var saved: Walker = Walker.new()
	saved.speed = 6.5
	if ResourceSaver.save(saved, "user://saved_walker.tres") != OK:
		print("FAIL: could not save user://saved_walker.tres")
		failures += 1
	if b2.load_kinds("user://saved_walker.tres") != 5 or b2.load_kinds("user://missing.tres") != 0:
		print("FAIL: Bag.load_kinds gave %d, not 5" % b2.load_kinds("user://saved_walker.tres"))
		failures += 1
	if not is_equal_approx(b2.load_speed("user://saved_walker.tres"), 6.5) or b2.load_speed("user://missing.tres") != -1.0:
		print("FAIL: Bag.load_speed gave %s, not 6.5" % b2.load_speed("user://saved_walker.tres"))
		failures += 1
	if b2.greet("wörld") != "hi, wörld (6 bytes)" or b2.call(&"greet", "") != "hi,  (0 bytes)":
		print("FAIL: Bag.greet gave %s" % b2.greet("wörld"))
		failures += 1
	_deferred = Bag.new()
	_deferred_from = Bag.proc_total()
	_deferred.defer(7)
	if Bag.proc_total() != _deferred_from or _deferred.get(&"slot_2") != 0:
		print("FAIL: Bag.defer ran before the frame ended")
		failures += 1
	root.free()
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
	if Bag.proc_total() - _deferred_from != 7 or _deferred.get(&"slot_2") != 7:
		print("FAIL: Bag.defer's calls gave %d and %s, not 7 and 7" % [Bag.proc_total() - _deferred_from, _deferred.get(&"slot_2")])
		_failures += 1
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
