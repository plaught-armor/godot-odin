extends SceneTree

# Runs the example's classes from GDScript and quits 0 on success, 1 on any failure.
#   godot --headless --path example/project -s test.gd

var _arrived: int = -1
var _ticker: Ticker
var _failures: int = 0
var _frames: int = 0
# Checks that reached their end. A GDScript runtime error returns from the function it hits and
# lets its caller go on, so a check cut short by one would otherwise pass on what it never checked.
var _checks_ended: int = 0
const CHECKS: int = 5
# Frames before the run gives up: a runtime error in `_process` aborts it before `quit`, every
# frame, so without a cap a broken check would hang the run instead of failing it.
const MAX_FRAMES: int = 60
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
	_checks_ended += 1
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
	_checks_ended += 1
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
	if b2.ghost_seen(root) != 3 or b2.ghost_seen(Node.new()) != -2 or b2.ghost_seen(null) != -2:
		print("FAIL: Bag.ghost_seen gave %d, not 3" % b2.ghost_seen(root))
		failures += 1
	if b2.texts(&"héllo😀", NodePath("a/b:c")) != "héllo😀|a/b:c" or b2.texts(&"", NodePath()) != "|":
		print("FAIL: Bag.texts gave %s" % b2.texts(&"héllo😀", NodePath("a/b:c")))
		failures += 1
	var ghosts: Array[Ghost] = b2.typed_ghosts(g, 2)
	var mine: Array[Ghost] = [g]
	if ghosts.size() != 2 or ghosts[1] != g or ghosts.get_typed_class_name() != &"Ghost" or b2.typed_ghosts(g, 0).get_typed_class_name() != &"Ghost":
		print("FAIL: Bag.typed_ghosts gave %s typed %s" % [ghosts, ghosts.get_typed_class_name()])
		failures += 1
	if b2.ghost_total(ghosts) != 6 or b2.ghost_total(mine) != 3 or b2.ghost_total([g]) != -1 or b2.ghost_total(b2.typed_nodes(1)) != -1:
		print("FAIL: Bag.ghost_total gave %s" % [[b2.ghost_total(ghosts), b2.ghost_total(mine), b2.ghost_total([g]), b2.ghost_total(b2.typed_nodes(1))]])
		failures += 1
	var described := Node.new()
	if b2.describe(described, 0) != 0 or described.editor_description != "fixed" or b2.describe(described, 0) != 0:
		print("FAIL: Bag.describe(0) set %s" % described.editor_description)
		failures += 1
	if b2.describe(described, 7) != 21 or described.editor_description != "item 7" or Bag.temp_live() != 0:
		print("FAIL: Bag.describe(7) set %s, %d texts live after" % [described.editor_description, Bag.temp_live()])
		failures += 1
	described.free()
	b2.tint_g = 0.5
	b2.set_tint(2, 0.25)
	if b2.tint_r != 0.0 or b2.tint_g != 0.5 or b2.tint_b != 0.25 or b2.get_tint(1) != 0.5:
		print("FAIL: Bag tint is %s %s %s" % [b2.tint_r, b2.tint_g, b2.tint_b])
		failures += 1
	var tint_props := 0
	for p in b2.get_property_list():
		if String(p.name).begins_with("tint_") and p.type == TYPE_FLOAT and p.hint == PROPERTY_HINT_RANGE:
			tint_props += 1
	if tint_props != 3:
		print("FAIL: Bag lists %d tint properties, not 3" % tint_props)
		failures += 1
	if b2.brightness != 0.25:
		print("FAIL: Bag.brightness is %s, not 0.25" % b2.brightness)
		failures += 1
	b2.brightness = 1.0
	if b2.tint_r != 1.0 or b2.tint_b != 1.0 or b2.get_brightness() != 1.0:
		print("FAIL: Bag.brightness did not set the tint")
		failures += 1
	var tally_words := {"a": 2, 3: "three", "n": null}
	if not is_same(b2.lookup(tally_words, "a"), 2) or not is_same(b2.lookup(tally_words, 3), "three") or not is_same(b2.lookup(tally_words, "zz"), "missing") or b2.lookup(tally_words, "n") != null:
		print("FAIL: Bag.lookup read %s %s %s" % [b2.lookup(tally_words, "a"), b2.lookup(tally_words, 3), b2.lookup(tally_words, "zz")])
		failures += 1
	if not b2.tally(tally_words, "a") or not b2.tally(tally_words, "new") or not is_same(tally_words["a"], 3) or not is_same(tally_words.get("new"), 1):
		print("FAIL: Bag.tally left %s" % tally_words)
		failures += 1
	var typed_counts: Dictionary[String, int] = {"x": 1}
	if b2.put(typed_counts, "y", "not an int") or typed_counts.has("y") or not b2.put(typed_counts, "y", 5) or typed_counts["y"] != 5:
		print("FAIL: Bag.put on a typed Dictionary left %s" % typed_counts)
		failures += 1
	if not is_same(b2.member(Vector2(1.5, 2), "y"), 2.0) or not is_same(b2.member(Vector2(), "w"), "missing") or not is_same(b2.member({"k": 1}, "k"), 1):
		print("FAIL: Bag.member read %s %s" % [b2.member(Vector2(1.5, 2), "y"), b2.member(Vector2(), "w")])
		failures += 1
	var lib: String = Bag.lib_path()
	if not lib.ends_with(".so") or not FileAccess.file_exists(lib):
		print("FAIL: Bag.lib_path is %s" % lib)
		failures += 1
	var long_text := "x".repeat(1000)
	if b2.text_size("") != -1 or b2.text_size("abc") != 3 or b2.text_size("日本語") != 3 or b2.text_size(long_text) != 1000:
		print("FAIL: Bag.text_size %d %d %d %d" % [b2.text_size(""), b2.text_size("abc"), b2.text_size("日本語"), b2.text_size(long_text)])
		failures += 1
	# Equal pairs give 3 (both checks agree), unequal ones 0; "a2" against "ab" fails at the last
	# character, "abc" against "ab" on length, and a copy of `long_text` shares its storage.
	var same_cases: Array = [["", "", 3], ["ab", "ab", 3], ["日本語", "日本語", 3], ["é", "e", 0],
		["a2", "ab", 0], ["abc", "ab", 0], ["", "a", 0], [long_text, long_text, 3], ["日本", "日本語", 0]]
	# The engine's begins_with and ends_with are the reference.
	var end_cases: Array = [["", ""], ["abc", ""], ["", "a"], ["abc", "a"], ["abc", "c"], ["abc", "abc"],
		["abc", "abcd"], ["日本語", "日"], ["日本語", "語"], ["日本語", "本"], ["aé", "é"], ["éa", "é"],
		["x日本語x", "x日"], [long_text, "xx"], ["ab", "b"]]
	for c: Array in end_cases:
		var s: String = c[0]
		var want: int = int(s.begins_with(c[1])) | int(s.ends_with(c[1])) << 1
		if b2.text_ends(s, c[1]) != want:
			print("FAIL: Bag.text_ends(%s, %s) gave %d, not %d" % [s, c[1], b2.text_ends(s, c[1]), want])
			failures += 1
	var which_cases: Dictionary = {"jump": 0, "run": 1, "walk": 2, "日本": 3, "": 4, "runs": 5,
		"jo-p": 6, "rin": -1, "jamp": -1, "Jump": -1, "日": -1, "日本語": -1, "jumps": -1, "jo本p": -1}
	for w: String in which_cases:
		if b2.which(w) != which_cases[w]:
			print("FAIL: Bag.which(%s) gave %d, not %d" % [w, b2.which(w), which_cases[w]])
			failures += 1
	# The engine's find and contains are the reference, from several starts.
	var which_name_cases: Dictionary = {&"jump": 0, &"run": 1, &"日本": 2, &"": 3, &"runs": -1, &"Jump": -1}
	for w: StringName in which_name_cases:
		if b2.which_name(w) != which_name_cases[w]:
			print("FAIL: Bag.which_name(%s) gave %d, not %d" % [w, b2.which_name(w), which_name_cases[w]])
			failures += 1
	var find_cases: Array = [["", ""], ["abc", ""], ["", "a"], ["abcabc", "bc"], ["abcabc", "abcd"],
		["aaab", "aab"], ["日本語日本", "本"], ["日本語日本", "語日"], ["xéyé", "é"], ["abc", "c"],
		["abc", "abc"], [long_text + "y", "xy"], ["ab", "ba"]]
	# The match after 0 to 9 characters that hold no first character, so the four-wide skip lands
	# on it from every offset.
	for pad: int in 10:
		find_cases.append(["-".repeat(pad) + "ab--", "ab"])
		find_cases.append(["-".repeat(pad) + "日x", "日x"])
		find_cases.append(["--ab" + "-".repeat(pad), "ab"])
	for c: Array in find_cases:
		var s: String = c[0]
		for from: int in [-20, -3, -2, -1, 0, 1, 2, 4, 9, 20]:
			if b2.find_text(s, c[1], from) != s.find(c[1], from):
				print("FAIL: Bag.find_text(%s, %s, %d) gave %d, not %d" % [s, c[1], from, b2.find_text(s, c[1], from), s.find(c[1], from)])
				failures += 1
			if b2.rfind_text(s, c[1], from) != s.rfind(c[1], from):
				print("FAIL: Bag.rfind_text(%s, %s, %d) gave %d, not %d" % [s, c[1], from, b2.rfind_text(s, c[1], from), s.rfind(c[1], from)])
				failures += 1
		if b2.has_text(s, c[1]) != s.contains(c[1]):
			print("FAIL: Bag.has_text(%s, %s) gave %s" % [s, c[1], b2.has_text(s, c[1])])
			failures += 1
	if b2.lone_byte_matches():
		print("FAIL: Bag.lone_byte_matches: \"é\" matched the invalid byte 0xE9")
		failures += 1
	for c: Array in same_cases:
		if b2.same_text(c[0], c[1]) != c[2]:
			print("FAIL: Bag.same_text(%s, %s) gave %d, not %d" % [c[0], c[1], b2.same_text(c[0], c[1]), c[2]])
			failures += 1
	if b2.kinds("x") != "x:" or b2.kinds("x", 1, 2.0, "s", [3], &"n") != "x:2,3,4,28,21" or b2.callv("kinds", ["y", null]) != "y:0":
		print("FAIL: Bag.kinds gave %s" % b2.kinds("x", 1, 2.0, "s", [3], &"n"))
		failures += 1
	if Bag.count() != 0 or Bag.count(1, "two", [3], {}) != 4:
		print("FAIL: Bag.count gave %d, not 4" % Bag.count(1, "two", [3], {}))
		failures += 1
	if not b2.is_jump(&"jump") or b2.is_jump(&"jumps") or b2.is_jump(&""):
		print("FAIL: Bag.is_jump did not match only jump")
		failures += 1
	if b2.named("hello") != &"hello" or b2.named("") != &"" or b2.named("x".repeat(200)) != StringName("x".repeat(200)):
		print("FAIL: Bag.named gave the wrong ASCII names")
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
	if b2.greet("wörld€😀") != "hi, wörld€😀 (13 bytes)" or b2.greet("ascii") != "hi, ascii (5 bytes)":
		print("FAIL: Bag.greet gave %s" % b2.greet("wörld€😀"))
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
	_checks_ended += 1
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
	_checks_ended += 1
	return failures


# Each call gives back the temp memory it took: a small take, and one past the arena's 4 MiB block.
func _check_temp() -> int:
	var before: int = WalkMath.temp_in_use()
	for bytes: int in [64, 8 << 20, 64]:
		WalkMath.scratch(bytes)
		if WalkMath.temp_in_use() != before:
			print("FAIL: %d bytes of temp held after scratch(%d), not %d" % [WalkMath.temp_in_use(), bytes, before])
			return 1
	_checks_ended += 1
	return 0


# Called from Odin through Object.call.
func twice(x: float) -> float:
	return x * 2.0


# Frames run after `_initialize`, with the root in the tree: the first adds a Ticker and checks
# its `_ready` and `_input`, the fourth that its `_process` ran on the frames between.
func _process(_delta: float) -> bool:
	_frames += 1
	if _checks_ended != CHECKS or _frames > MAX_FRAMES:
		print("FAIL: a script error above stopped the checks (%d frames)" % _frames)
		quit(1)
		return true
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
