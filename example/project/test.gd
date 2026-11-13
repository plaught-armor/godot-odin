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
		["x日本語x", "x日"], [long_text, "xx"], ["ab", "b"], ["Hello World", "hELLO"], ["Hello World", "WORLD"],
		["\u0130stanbul", "is"], ["xxK\u212A", "kk"], ["\u00C9t\u00E9", "\u00E9T\u00C9"], ["abc", "ABCD"],
		["@[`{", "`{"], ["\u0131x", "Ix"], ["xi", "\u0130"], ["kx", "\u212A"]]
	for c: Array in end_cases:
		var s: String = c[0]
		var p: String = c[1]
		var want: int = int(s.begins_with(p)) | int(s.ends_with(p)) << 1
		want |= int(s.to_lower().begins_with(p.to_lower())) << 2 | int(s.to_lower().ends_with(p.to_lower())) << 3
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
	# Case pairs, with the characters the engine's tables fold into ASCII: U+0130 and the Kelvin
	# sign lower to i and k, U+0131 and long s raise to I and S.
	var nocase_cases: Array = [["Hello", "hello"], ["HELLO world", "WORLD"], ["abc", "ABD"], ["", ""],
		["x", ""], ["", "x"], ["İstanbul", "istanbul"], ["Kelvin", "kelvin"], ["ı", "I"],
		["ſun", "SUN"], ["ÉtÉ", "été"], ["Straße", "STRASSE"], ["Σσ", "σΣ"],
		["xxİAb-", "iab"], ["--a-b-ab", "AB"], ["@[`{", "`{"], ["İ", "i̇"], ["kKk", "KK"]]
	for pad: int in 6:
		nocase_cases.append(["é".repeat(pad) + "zZ" + "-".repeat(pad), "Zz"])
	for c: Array in nocase_cases:
		var s: String = c[0]
		for from: int in [-3, -1, 0, 1, 2, 5]:
			var want: int = ((s.findn(c[1], from) + 1) & 0xFFFF) | (((s.rfindn(c[1], from) + 1) & 0xFFFF) << 16)
			want |= int(s.containsn(c[1])) << 32 | int(s.nocasecmp_to(c[1]) == 0) << 33
			if b2.nocase(s, c[1], from) != want:
				print("FAIL: Bag.nocase(%s, %s, %d) gave %x, not %x" % [s, c[1], from, b2.nocase(s, c[1], from), want])
				failures += 1
	var count_cases: Array = [["", ""], ["abc", ""], ["aaaa", "aa"], ["aAaA", "aa"], ["abcABCabc", "abc"],
		["\u0130x\u0130", "ix"], ["\u65E5\u672C\u65E5\u672C", "\u672C"], ["ab", "abc"], ["--ab--ab-ab", "ab"]]
	for c: Array in count_cases:
		var s: String = c[0]
		for range_: Array in [[0, 0], [1, 0], [0, 3], [2, 5], [3, 3], [4, 2], [-1, 0], [0, -1], [0, 40], [20, 0]]:
			var got: int = b2.count_text(s, c[1], range_[0], range_[1])
			var want: int = s.count(c[1], range_[0], range_[1]) | s.countn(c[1], range_[0], range_[1]) << 32
			if got != want:
				print("FAIL: Bag.count_text(%s, %s, %d, %d) gave %x, not %x" % [s, c[1], range_[0], range_[1], got, want])
				failures += 1
	var replace_cases: Array = [["", "", "x"], ["abc", "", "x"], ["", "a", "x"], ["aaaa", "aa", "b"],
		["aaa", "a", ""], ["aAaA", "aa", "\u65E5"], ["abcABCabc", "abc", "xyzw"], ["\u0130x\u0130", "ix", "-"],
		["\u65E5\u672C\u65E5\u672C", "\u672C", "ab"], ["ab", "abc", "q"], ["--ab--ab-ab", "ab", "\u212A"],
		["abab", "abab", ""], [long_text + "y", "xy", "Z"], ["ab", "b", "bb"]]
	for pad: int in 10:
		replace_cases.append(["-".repeat(pad) + "ab--ab", "ab", "\u00E9!"])
	for c: Array in replace_cases:
		var s: String = c[0]
		if b2.replace_text(s, c[1], c[2], false) != s.replace(c[1], c[2]):
			print("FAIL: Bag.replace_text(%s, %s, %s) gave %s, not %s" % [s, c[1], c[2], b2.replace_text(s, c[1], c[2], false), s.replace(c[1], c[2])])
			failures += 1
		if b2.replace_text(s, c[1], c[2], true) != s.replacen(c[1], c[2]):
			print("FAIL: Bag.replace_text(%s, %s, %s, nocase) gave %s, not %s" % [s, c[1], c[2], b2.replace_text(s, c[1], c[2], true), s.replacen(c[1], c[2])])
			failures += 1
	var split_cases: Array = [["", ","], ["", ""], ["abc", ""], ["a,b,,c", ","], [",a,", ","], [",", ","],
		["a, b, c", ", "], ["\u65E5\u672C,\u65E5", ","], ["x\u672Cy\u672C", "\u672C"], ["abc", "abcd"], ["abc", "abc"],
		["a--b----c", "--"], ["aaa", "aa"]]
	for pad: int in 6:
		split_cases.append(["-".repeat(pad) + "ab--ab", "ab"])
	for c: Array in split_cases:
		var s: String = c[0]
		for allow: bool in [true, false]:
			for maxsplit: int in [-1, 0, 1, 2, 5]:
				var got: PackedStringArray = b2.split_text(s, c[1], allow, maxsplit)
				if got != s.split(c[1], allow, maxsplit):
					print("FAIL: Bag.split_text(%s, %s, %s, %d) gave %s, not %s" % [s, c[1], allow, maxsplit, got, s.split(c[1], allow, maxsplit)])
					failures += 1
	for c: Array in split_cases:
		var s: String = c[0]
		var lengths: PackedInt64Array = []
		for part: String in s.split(c[1]):
			lengths.append(part.length())
		if b2.split_lengths(s, c[1]) != lengths:
			print("FAIL: Bag.split_lengths(%s, %s) gave %s, not %s" % [s, c[1], b2.split_lengths(s, c[1]), lengths])
			failures += 1
	var strip_cases: Array = [["", ","], ["   ", ","], [" a , b ,c ", ","], ["\t x\n,\u0001y\u0020,\u00A0z\u00A0", ","],
		[" \u65E5 ; \u672C\t;;  ", ";"], ["a b", ""], ["\u0021 \u001F!", "|"]]
	for c: Array in strip_cases:
		var s: String = c[0]
		for sides: int in 4:
			var left: bool = sides & 1 != 0
			var right: bool = sides & 2 != 0
			var want: PackedStringArray = []
			for part: String in s.split(c[1]):
				want.append(part.strip_edges(left, right))
			if b2.split_strip(s, c[1], left, right) != want:
				print("FAIL: Bag.split_strip(%s, %s, %s, %s) gave %s, not %s" % [s, c[1], left, right, b2.split_strip(s, c[1], left, right), want])
				failures += 1
	var number_text: String = ",12,-3,--4,5-6,a7b,1.5,.5,-,  42 ,-0-7,\u0663,9223372036854775807,-9223372036854775808"
	number_text += ",9223372036854775808,-9223372036854775809,99999999999999999999,0000000000000000000000012"
	number_text += ",-" + "0".repeat(256) + "9999999999999999999," + "0".repeat(250) + "92233720368547758079"
	var want_ints: PackedInt64Array = []
	for part: String in number_text.split(","):
		want_ints.append(part.to_int())
	if b2.part_ints(number_text, ",") != want_ints:
		print("FAIL: Bag.part_ints gave %s, not %s" % [b2.part_ints(number_text, ","), want_ints])
		failures += 1
	var float_text: String = ";0;-;+;-0;1.5;  -1.5;\t\n+2.25;\r3;.5;5.;1e3;1E-3;1.5e;1.5e+;2.5e-x;1e600;1e-600;-1e-400"
	float_text += ";123456789012345678901234;0.000000000000000000001234567890123456789;1..2;12abc;abc;0e600"
	float_text += ";1.7976931348623157e308;4.9e-324;3.14159265358979323846;1_000;\u0661;inf;nan;0x10;99999999999999999999e-20"
	float_text += ";123456789.987654321;.;.5.5;-.e5;5e0005;1e2147483647"
	var want_floats: PackedFloat64Array = []
	for part: String in float_text.split(";"):
		want_floats.append(part.to_float())
	var got_floats: PackedFloat64Array = b2.part_floats(float_text, ";")
	if got_floats.to_byte_array() != want_floats.to_byte_array():
		print("FAIL: Bag.part_floats gave %s, not %s" % [got_floats, want_floats])
		failures += 1
	var int_values: PackedInt64Array = [0, 1, -1, 9, 10, -10, 35, 36, 255, -256, 123456789, -987654321, 9223372036854775807, -9223372036854775807 - 1]
	for base: int in [10, 2, 7, 16, 36]:
		for caps: bool in [false, true]:
			var want_digits: PackedStringArray = []
			for v: int in int_values:
				want_digits.append(String.num_int64(v, base, caps))
			var got_digits: PackedStringArray = b2.int_texts(int_values, base, caps)
			if got_digits != want_digits:
				print("FAIL: Bag.int_texts base %d gave %s, not %s" % [base, got_digits, want_digits])
				failures += 1
	var float_values: PackedFloat64Array = [0.0, -0.0, 1.0, -1.0, 1.5, -1.5, 0.1, 0.5, 2.5, 2.675, 1.005, 123.456, -123.456e-2, 10.0, 10.000000000000002, 9.999999999999998, 99.99999999999999, 999.9999999999999, 1000.0, 12345678.9, 1e15 + 0.3, 1e20, 1e300, 1.7976931348623157e308, 5e-324, 1e-5, 0.000123456, 3.14159265358979, 0.1 + 0.2, 9223372036854775807.0, -9223372036854775808.0, 1e19, 4294967296.5, 0.125, 0.375, -0.625, -1e-30, 1e22, 123456789012345678.0, 18446744073709551616.0, NAN, INF, -INF]
	# GDScript pools equal constants, so the literal -0.0 above is +0.0; append a run-time one.
	float_values.append(-float(Time.get_ticks_msec() * 0))
	for decimals: int in [-1, 0, 1, 2, 5, 14, 22, 23, 32, 40]:
		var want_nums: PackedStringArray = []
		for v: float in float_values:
			want_nums.append(String.num(v, decimals))
		var got_nums: PackedStringArray = b2.float_texts(float_values, decimals)
		if got_nums != want_nums:
			print("FAIL: Bag.float_texts %d places gave %s, not %s" % [decimals, got_nums, want_nums])
			failures += 1
	var want_reals: PackedStringArray = []
	for v: float in float_values:
		want_reals.append(str(v))
	var got_reals: PackedStringArray = b2.real_texts(float_values, true)
	if got_reals != want_reals:
		print("FAIL: Bag.real_texts gave %s, not %s" % [got_reals, want_reals])
		failures += 1
	for word: String in ["jump", "JUMP", "\u0130x", "ix", "", "jum", "jumps", "\u65E5"]:
		var keywords: String = "jump;Jump;;JUMP;jum;jumps;ix;IX;\u0130x;\u65E5;\u65E5\u672C"
		var want_is: PackedInt64Array = []
		for part: String in keywords.split(";"):
			want_is.append(int(part == word) | int(part.nocasecmp_to(word) == 0) << 1)
		if b2.part_is(keywords, ";", word) != want_is:
			print("FAIL: Bag.part_is(%s) gave %s, not %s" % [word, b2.part_is(keywords, ";", word), want_is])
			failures += 1
	var find_cases: Array = [["", ""], ["abc", ""], ["", "a"], ["abcabc", "bc"], ["abcabc", "abcd"],
		["aaab", "aab"], ["日本語日本", "本"], ["日本語日本", "語日"], ["xéyé", "é"], ["abc", "c"],
		["abc", "abc"], [long_text + "y", "xy"], ["ab", "ba"], ["ab", "AB"], ["ab", "abc"], ["b", "a"],
		["éa", "Éa"], ["-a--b-", "-"], ["日-日", "日"], ["a", "_"], ["_", "A"], ["-".repeat(63), "-"], ["x-".repeat(64) + "x", "-"], ["x".repeat(70), ""]]
	# The match after 0 to 9 characters that hold no first character, so the four-wide skip lands
	# on it from every offset.
	for pad: int in 10:
		find_cases.append(["-".repeat(pad) + "ab--", "ab"])
		find_cases.append(["-".repeat(pad) + "日x", "日x"])
		find_cases.append(["--ab" + "-".repeat(pad), "ab"])
	for c: Array in find_cases:
		var s: String = c[0]
		for from: int in [-20, -3, -2, -1, 0, 1, 2, 4, 9, 20, 1 << 32, (1 << 32) + 1, -(1 << 32) - 1]:
			for to: int in [0, 4, -1, (1 << 32) + 2]:
				failures += _check_replaced_ops(b2, s, c[1], from, to)
			if b2.find_text(s, c[1], from) != s.find(c[1], from):
				print("FAIL: Bag.find_text(%s, %s, %d) gave %d, not %d" % [s, c[1], from, b2.find_text(s, c[1], from), s.find(c[1], from)])
				failures += 1
			if b2.rfind_text(s, c[1], from) != s.rfind(c[1], from):
				print("FAIL: Bag.rfind_text(%s, %s, %d) gave %d, not %d" % [s, c[1], from, b2.rfind_text(s, c[1], from), s.rfind(c[1], from)])
				failures += 1
		for with: String in ["", "X", "日é"]:
			for allow_empty: bool in [true, false]:
				for maxsplit: int in [-1, 0, 1, 2, (1 << 32) + 1]:
					failures += _check_replaced_strs(b2, s, c[1], with, allow_empty, maxsplit)
		if b2.has_text(s, c[1]) != s.contains(c[1]):
			print("FAIL: Bag.has_text(%s, %s) gave %s" % [s, c[1], b2.has_text(s, c[1])])
			failures += 1
	failures += _check_replaced_random(b2)
	failures += _check_replaced_vectors(b2)
	failures += _check_replaced_vectorsi(b2)
	failures += _check_replaced_colors(b2)
	failures += _check_replaced_bases(b2)
	failures += _check_replaced_transforms(b2)
	failures += _check_replaced_quaternions(b2)
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
# The String procs that replace engine methods, from Bag.replaced_ops, against the engine's own
# methods called from GDScript, which do not go through the bindings. Returns 1 on a mismatch.
func _check_replaced_ops(b2: Bag, s: String, part: String, from: int, to: int) -> int:
	var want := PackedInt64Array([s.find(part, from), s.rfind(part, from), s.findn(part, from),
		s.rfindn(part, from), int(s.contains(part)), int(s.containsn(part)), s.count(part, from, to),
		s.countn(part, from, to), int(s.begins_with(part)), int(s.ends_with(part)), s.casecmp_to(part),
		s.nocasecmp_to(part)])
	var got: PackedInt64Array = b2.replaced_ops(s, part, from, to)
	if got != want:
		print("FAIL: Bag.replaced_ops(%s, %s, %d, %d) gave %s, not %s" % [s, part, from, to, got, want])
		return 1
	return 0


# The String procs that replace engine methods and make Strings, from Bag.replaced_strs: replace and
# replacen of `part` by `with`, then the parts of split on `part`. Returns 1 on a mismatch.
func _check_replaced_strs(b2: Bag, s: String, part: String, with: String, allow_empty: bool, maxsplit: int) -> int:
	var want := PackedStringArray([s.replace(part, with), s.replacen(part, with)])
	want.append_array(s.split(part, allow_empty, maxsplit))
	var got: PackedStringArray = b2.replaced_strs(s, part, with, allow_empty, maxsplit)
	if got != want:
		print("FAIL: Bag.replaced_strs(%s, %s, %s, %s, %d) gave %s, not %s" % [s, part, with, allow_empty, maxsplit, got, want])
		return 1
	return 0


# _check_replaced_ops on seeded random Strings over a small alphabet with both cases, so most
# needles match somewhere, with and without case. The seed is fixed so a failure repeats.
func _check_replaced_random(b2: Bag) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var alphabet: Array[String] = ["a", "A", "b", "-", "日", "é", "É"]
	var failures := 0
	for round: int in 3000:
		var hay := ""
		for k: int in rng.randi_range(0, 40):
			hay += alphabet[rng.randi_range(0, alphabet.size() - 1)]
		var needle := ""
		for k: int in rng.randi_range(0, 5):
			needle += alphabet[rng.randi_range(0, alphabet.size() - 1)]
		# Half the needles come from the String itself, so begins_with and ends_with also match.
		if round % 2 == 0 and not hay.is_empty():
			var at := rng.randi_range(0, hay.length() - 1)
			needle = hay.substr(at, rng.randi_range(1, 5))
		var from := rng.randi_range(-45, 45)
		var to := rng.randi_range(-5, 45)
		failures += _check_replaced_ops(b2, hay, needle, from, to)
		var with: String = ["", "x", "日é", "AbA"][rng.randi_range(0, 3)]
		failures += _check_replaced_strs(b2, hay, needle, with, rng.randi() % 2 == 0, rng.randi_range(-1, 3))
	return failures


# Appends `v` to `out` as floats, as Bag.replaced_vectors does: a vector by component, a Basis row
# by row, a boolean or an index as its number.
func _put_result(out: PackedFloat32Array, v: Variant) -> void:
	match typeof(v):
		TYPE_VECTOR2:
			out.append_array([v.x, v.y])
		TYPE_VECTOR3:
			out.append_array([v.x, v.y, v.z])
		TYPE_VECTOR4:
			out.append_array([v.x, v.y, v.z, v.w])
		TYPE_BASIS:
			for row: int in 3:
				for col: int in 3:
					out.append(v[col][row])
		_:
			out.append(float(v))


# The engine's own Vector2, Vector3 and Vector4 methods, in Bag.replaced_vectors' order.
func _vector_results(a: Vector4, b: Vector4, c: Vector4, d: Vector4, n2: Vector2, n3: Vector3, w: float, x: float, y: float, z: float) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	var a2 := Vector2(a.x, a.y)
	var b2 := Vector2(b.x, b.y)
	var c2 := Vector2(c.x, c.y)
	var d2 := Vector2(d.x, d.y)
	for v: Variant in [a2.angle(), a2.angle_to(b2), a2.angle_to_point(b2), a2.direction_to(b2),
			a2.distance_to(b2), a2.distance_squared_to(b2), a2.length(), a2.length_squared(),
			a2.limit_length(x), a2.normalized(), a2.is_normalized(), a2.is_equal_approx(b2),
			a2.is_zero_approx(), a2.is_finite(), a2.posmod(x), a2.posmodv(b2), a2.project(b2),
			a2.lerp(b2, w), a2.slerp(b2, w), a2.cubic_interpolate(b2, c2, d2, w),
			a2.cubic_interpolate_in_time(b2, c2, d2, w, x, y, z), a2.bezier_interpolate(b2, c2, d2, w),
			a2.bezier_derivative(b2, c2, d2, w), a2.max_axis_index(), a2.min_axis_index(),
			a2.move_toward(b2, x), a2.rotated(x), a2.orthogonal(), a2.floor(), a2.ceil(), a2.round(),
			a2.aspect(), a2.dot(b2), a2.slide(n2), a2.bounce(n2), a2.reflect(n2), a2.cross(b2), a2.abs(),
			a2.sign(), a2.clamp(b2, c2), a2.clampf(y, z), a2.snapped(b2), a2.snappedf(x), a2.min(b2),
			a2.minf(x), a2.max(b2), a2.maxf(x), Vector2.from_angle(x), Vector2(x, y),
			Vector2(Vector2i(int(x), int(y)))]:
		_put_result(o, v)
	var a3 := Vector3(a.x, a.y, a.z)
	var b3 := Vector3(b.x, b.y, b.z)
	var c3 := Vector3(c.x, c.y, c.z)
	var d3 := Vector3(d.x, d.y, d.z)
	for v: Variant in [a3.angle_to(b3), a3.signed_angle_to(b3, n3), a3.direction_to(b3),
			a3.distance_to(b3), a3.distance_squared_to(b3), a3.length(), a3.length_squared(),
			a3.limit_length(x), a3.normalized(), a3.is_normalized(), a3.is_equal_approx(b3),
			a3.is_zero_approx(), a3.is_finite(), a3.inverse(), a3.clamp(b3, c3), a3.clampf(y, z),
			a3.snapped(b3), a3.snappedf(x), a3.rotated(n3, x), a3.lerp(b3, w), a3.slerp(b3, w),
			a3.cubic_interpolate(b3, c3, d3, w), a3.cubic_interpolate_in_time(b3, c3, d3, w, x, y, z),
			a3.bezier_interpolate(b3, c3, d3, w), a3.bezier_derivative(b3, c3, d3, w),
			a3.move_toward(b3, x), a3.dot(b3), a3.cross(b3), a3.outer(b3), a3.abs(), a3.floor(),
			a3.ceil(), a3.round(), a3.posmod(x), a3.posmodv(b3), a3.project(b3), a3.slide(n3),
			a3.bounce(n3), a3.reflect(n3), a3.sign(), a3.octahedron_encode(), a3.min(b3), a3.minf(x),
			a3.max(b3), a3.maxf(x), Vector3.octahedron_decode(a2), a3.min_axis_index(),
			a3.max_axis_index(), Vector3(x, y, z), Vector3(Vector3i(int(x), int(y), int(z)))]:
		_put_result(o, v)
	for v: Variant in [a.min_axis_index(), a.max_axis_index(), a.length(), a.length_squared(), a.abs(),
			a.sign(), a.floor(), a.ceil(), a.round(), a.lerp(b, w), a.cubic_interpolate(b, c, d, w),
			a.cubic_interpolate_in_time(b, c, d, w, x, y, z), a.posmod(x), a.posmodv(b), a.snapped(b),
			a.snappedf(x), a.clamp(b, c), a.clampf(y, z), a.normalized(), a.is_normalized(),
			a.direction_to(b), a.distance_to(b), a.distance_squared_to(b), a.dot(b), a.inverse(),
			a.is_equal_approx(b), a.is_zero_approx(), a.is_finite(), a.min(b), a.minf(x), a.max(b),
			a.maxf(x), Vector4(w, x, y, z), Vector4(Vector4i(int(w), int(x), int(y), int(z)))]:
		_put_result(o, v)
	return o


# One Bag.replaced_vectors call against _vector_results, compared bit for bit, so signed zeros
# count, except that any NaN matches any NaN: which NaN an operation keeps depends on the order the
# compiler puts its operands in. Returns 1 on a mismatch.
func _check_vector_case(b2: Bag, a: Vector4, b: Vector4, c: Vector4, d: Vector4, n2: Vector2, n3: Vector3, w: float, x: float, y: float, z: float) -> int:
	var want := _vector_results(a, b, c, d, n2, n3, w, x, y, z)
	var got: PackedFloat32Array = b2.replaced_vectors(a, b, c, d, n2, n3, w, x, y, z)
	var got_bits := got.to_byte_array().to_int32_array()
	var want_bits := want.to_byte_array().to_int32_array()
	if got_bits == want_bits:
		return 0
	var at := 0
	while at < mini(got.size(), want.size()) and (got_bits[at] == want_bits[at] or (is_nan(got[at]) and is_nan(want[at]))):
		at += 1
	if at == got.size() and at == want.size():
		return 0
	print("FAIL: Bag.replaced_vectors(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) differs at %d of %d: %s, not %s" % [a, b, c, d, n2, n3, w, x, y, z, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


# The vector procs that replace engine methods, on edge cases (zeros, signed zeros, halves, units,
# infinities and NaNs, zero times and steps, normals that are not normalized) and then on seeded
# random vectors, some with integer and half components so floor, round and snapped meet ties.
func _check_replaced_vectors(b2: Bag) -> int:
	var failures := 0
	var inf := INF
	# GDScript pools equal constants, so a literal -0.0 becomes +0.0; build it at run time.
	var neg_zero := -float(Time.get_ticks_msec() * 0)
	var edges: Array[Vector4] = [Vector4.ZERO, Vector4(neg_zero, 0, neg_zero, 0), Vector4(1, 0, 0, 0),
		Vector4(0, 1, 0, 0), Vector4(0.5, -0.5, 2.5, -2.5), Vector4(1.5, -1.5, 3, -3),
		Vector4(inf, 1, 2, 3), Vector4(1, -inf, 2, 3), Vector4(NAN, 0, 0, 0), Vector4(3, 4, 0, 0),
		Vector4(-3, 4, -12, 0.25), Vector4(1e-6, -1e-6, 1e-7, 0), Vector4(1e20, 1e20, -1e20, 1e20)]
	var normals2: Array[Vector2] = [Vector2(1, 0), Vector2(0.6, 0.8), Vector2(2, 0), Vector2.ZERO, Vector2(1.0002, 0)]
	var normals3: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0.6, 0, -0.8), Vector3(1, 1, 0), Vector3.ZERO, Vector3(0, 0, 1.0002)]
	var scalars: Array = [[0.5, 1.0, -1.0, 2.0], [0.0, 0.0, 0.0, 0.0], [1.0, 0.5, 0.0, 1.0],
		[-0.25, 2.5, 1.0, 1.0], [1.5, -3.0, 2.0, -2.0], [0.0, 0.25, -0.5, 0.75]]
	for i: int in edges.size():
		for j: int in [0, 3, 5, 9]:
			var a := edges[i]
			var b := edges[(i + j) % edges.size()]
			var s: Array = scalars[(i + j) % scalars.size()]
			failures += _check_vector_case(b2, a, b, edges[(i + 2) % edges.size()], edges[(i + 7) % edges.size()],
				normals2[(i + j) % normals2.size()], normals3[(i + j) % normals3.size()], s[0], s[1], s[2], s[3])
	# 5.35 / 0.1 and -4.05 / 0.3 land on a tie only when snapped divides in double.
	failures += _check_vector_case(b2, Vector4(5.35, -4.05, 5.35, -4.05), Vector4(0.1, 0.3, 0.1, 0.3),
		edges[2], edges[3], normals2[0], normals3[0], 0.5, 0.1, 0.0, 1.0)
	# A delta equal to the length must return the target exactly, not v + vd / l * delta.
	failures += _check_vector_case(b2, Vector4.ZERO, Vector4(1, 1, 0, 0), edges[2], edges[3],
		normals2[0], normals3[0], 0.5, Vector2(1, 1).length(), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	for round: int in 2000:
		var v: Array[Vector4] = []
		for k: int in 4:
			var e := Vector4()
			for m: int in 4:
				match rng.randi_range(0, 5):
					0: e[m] = float(rng.randi_range(-4, 4))
					1: e[m] = rng.randi_range(-8, 8) * 0.5
					_: e[m] = rng.randf_range(-10, 10)
			v.append(e)
		var n2 := Vector2.from_angle(rng.randf_range(-PI, PI))
		var n3 := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		if round % 4 == 0:
			v[1] = v[0] * rng.randf_range(-2, 2)
		failures += _check_vector_case(b2, v[0], v[1], v[2], v[3], n2, n3, rng.randf_range(-0.5, 1.5),
			rng.randf_range(-6, 6), rng.randf_range(-3, 1), rng.randf_range(0, 4))
	return failures


# Appends `v` to `out` as integers: a vector by component, a float as its bits, an int as itself.
func _put_int_result(out: PackedInt64Array, v: Variant) -> void:
	match typeof(v):
		TYPE_VECTOR2I:
			out.append_array([v.x, v.y])
		TYPE_VECTOR3I:
			out.append_array([v.x, v.y, v.z])
		TYPE_VECTOR4I:
			out.append_array([v.x, v.y, v.z, v.w])
		TYPE_FLOAT:
			out.append(PackedFloat64Array([v]).to_byte_array().decode_s64(0))
		_:
			out.append(int(v))


# The engine's Vector2i, Vector3i and Vector4i methods in the order Bag.replaced_vectorsi calls
# the Odin procs.
func _vectori_results(a: Vector4i, b: Vector4i, c: Vector4i, x: int, y: int, f: Vector4) -> PackedInt64Array:
	var o := PackedInt64Array()
	var a2 := Vector2i(a.x, a.y)
	var b2 := Vector2i(b.x, b.y)
	var c2 := Vector2i(c.x, c.y)
	for v: Variant in [Vector2i(), Vector2i(a2), Vector2i(Vector2(f.x, f.y)), Vector2i(x, y), a2.aspect(),
			a2.max_axis_index(), a2.min_axis_index(), a2.distance_to(b2), a2.distance_squared_to(b2),
			a2.length(), a2.length_squared(), a2.sign(), a2.abs(), a2.clamp(b2, c2), a2.clampi(x, y),
			a2.snapped(b2), a2.snappedi(x), a2.min(b2), a2.mini(x), a2.max(b2), a2.maxi(x)]:
		_put_int_result(o, v)
	var a3 := Vector3i(a.x, a.y, a.z)
	var b3 := Vector3i(b.x, b.y, b.z)
	var c3 := Vector3i(c.x, c.y, c.z)
	for v: Variant in [Vector3i(), Vector3i(a3), Vector3i(Vector3(f.x, f.y, f.z)), Vector3i(x, y, x),
			a3.max_axis_index(), a3.min_axis_index(), a3.distance_to(b3), a3.distance_squared_to(b3),
			a3.length(), a3.length_squared(), a3.sign(), a3.abs(), a3.clamp(b3, c3), a3.clampi(x, y),
			a3.snapped(b3), a3.snappedi(x), a3.min(b3), a3.mini(x), a3.max(b3), a3.maxi(x)]:
		_put_int_result(o, v)
	for v: Variant in [Vector4i(), Vector4i(a), Vector4i(f), Vector4i(x, y, y, x),
			a.max_axis_index(), a.min_axis_index(), a.distance_to(b), a.distance_squared_to(b),
			a.length(), a.length_squared(), a.sign(), a.abs(), a.clamp(b, c), a.clampi(x, y),
			a.snapped(b), a.snappedi(x), a.min(b), a.mini(x), a.max(b), a.maxi(x)]:
		_put_int_result(o, v)
	return o


func _check_vectori_case(b2: Bag, a: Vector4i, b: Vector4i, c: Vector4i, x: int, y: int, f: Vector4) -> int:
	var want := _vectori_results(a, b, c, x, y, f)
	var got: PackedInt64Array = b2.replaced_vectorsi(a, b, c, x, y, f)
	if got == want:
		return 0
	var at := 0
	while at < mini(got.size(), want.size()) and got[at] == want[at]:
		at += 1
	print("FAIL: Bag.replaced_vectorsi(%s, %s, %s, %d, %d, %s) differs at %d of %d: %s, not %s" % [a, b, c, x, y, f, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


# The int vector procs that replace engine methods, on edge cases (zero, units, the int32 limits,
# whose differences and snaps wrap, zero and negative steps, scalars past int32 that truncate,
# floats that truncate or fall out of range) and then on seeded random vectors.
func _check_replaced_vectorsi(b2: Bag) -> int:
	var failures := 0
	var top := 2147483647
	var low := -2147483648
	var edges: Array[Vector4i] = [Vector4i.ZERO, Vector4i(1, -1, 0, 2), Vector4i(2, 2, 2, 2),
		Vector4i(-7, 7, 3, -3), Vector4i(top, low, top, low), Vector4i(low, top, -1, 1),
		Vector4i(top, top, low, low), Vector4i(46341, -46341, 65536, -65536), Vector4i(0, 0, 1, 1),
		Vector4i(5, 3, 5, 3), Vector4i(-2, -4, -6, -8), Vector4i(1073741824, -1073741824, 3, 0)]
	var scalars: Array = [[0, 0], [1, -1], [2, 5], [-3, 3], [top, low], [4294967298, -4294967291],
		[3, 2], [-1, 7]]
	var floats: Array[Vector4] = [Vector4(0.5, -0.5, 1.9, -1.9), Vector4(INF, -INF, NAN, 0),
		Vector4(3e9, -3e9, 2147483520.0, -2147483648.0), Vector4(1e-30, -1e30, 7, -7.99),
		Vector4(2147483648.0, -2147483904.0, 2147483392.0, 0.5)]
	for i: int in edges.size():
		for j: int in [0, 1, 4, 7]:
			var s: Array = scalars[(i + j) % scalars.size()]
			failures += _check_vectori_case(b2, edges[i], edges[(i + j) % edges.size()],
				edges[(i + j + 3) % edges.size()], s[0], s[1], floats[(i + j) % floats.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261113
	for round: int in 2000:
		var v: Array[Vector4i] = []
		for k: int in 3:
			var e := Vector4i()
			for m: int in 4:
				match rng.randi_range(0, 4):
					0: e[m] = rng.randi_range(-2147483648, 2147483647)
					1: e[m] = [top, low, 0][rng.randi_range(0, 2)]
					_: e[m] = rng.randi_range(-9, 9)
			v.append(e)
		var f := Vector4(rng.randf_range(-20, 20), rng.randf_range(-3e9, 3e9), rng.randf_range(-1, 1), rng.randf_range(-1e5, 1e5))
		failures += _check_vectori_case(b2, v[0], v[1], v[2], rng.randi_range(-9, 9), rng.randi_range(-9, 9), f)
	return failures



# Appends `v` as Bag.replaced_colors does: a Color by the bits of each float component, a float
# as its bits, a bool or int as itself, and every NaN as one value.
func _put_color_result(out: PackedInt64Array, v: Variant) -> void:
	match typeof(v):
		TYPE_COLOR:
			for k: int in 4:
				var e: float = v[k]
				out.append(0x7fc00000 if is_nan(e) else PackedFloat32Array([e]).to_byte_array().decode_u32(0))
		TYPE_FLOAT:
			out.append(0x7ff8000000000000 if is_nan(v) else PackedFloat64Array([v]).to_byte_array().decode_s64(0))
		_:
			out.append(int(v))


# The engine's Color methods in the order Bag.replaced_colors calls the Odin procs.
func _color_results(a: Color, b: Color, c: Color, x: float, n: int) -> PackedInt64Array:
	var o := PackedInt64Array()
	for v: Variant in [Color(), Color(a), Color(a, x), Color(x, b.g, b.b), Color(x, b.g, b.b, c.a),
			a.to_argb32(), a.to_abgr32(), a.to_rgba32(), a.to_argb64(), a.to_abgr64(), a.to_rgba64(),
			a.clamp(b, c), a.inverted(), a.lerp(b, x), a.lightened(x), a.darkened(x), a.blend(b),
			a.get_luminance(), a.srgb_to_linear(), a.linear_to_srgb(), a.is_equal_approx(b),
			Color.hex(n), Color.hex64(n), Color.from_hsv(x, a.g, a.b, a.a),
			Color.from_hsv(a.r, b.g, a.b, x), Color.from_rgbe9995(n),
			Color.from_rgba8(n, n >> 40, n % 300, -n)]:
		_put_color_result(o, v)
	return o


func _check_color_case(b2: Bag, a: Color, b: Color, c: Color, x: float, n: int) -> int:
	var want := _color_results(a, b, c, x, n)
	var got: PackedInt64Array = b2.replaced_colors(a, b, c, x, n)
	if got == want:
		return 0
	var at := 0
	while at < mini(got.size(), want.size()) and got[at] == want[at]:
		at += 1
	print("FAIL: Bag.replaced_colors(%s, %s, %s, %s, %d) differs at %d of %d: %s, not %s" % [a, b, c, x, n, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


# The Color procs that replace engine methods, on edge cases (zero, white, signed zeros, values
# outside 0 to 1 and outside int32 once scaled, infinities, NaNs, the sRGB thresholds, channels a
# half step from a byte, transparent colors, and 17700158, the least float whose srgb_to_linear
# depends on the last bit of the double 1 / 1.055) and then on seeded random colors.
func _check_replaced_colors(b2: Bag) -> int:
	var failures := 0
	var nz := -float(Time.get_ticks_msec() * 0)
	var edges: Array[Color] = [Color(0, 0, 0, 0), Color(1, 1, 1, 1), Color(nz, nz, 0, nz),
		Color(0.5, 0.25, 0.75, 0.5),
		Color(0.5, 0.25, 0.75, 1), Color(-0.5, 1.5, 2, -1), Color(3e9, -3e9, 1e38, 16777216),
		Color(INF, -INF, NAN, 1), Color(0.04045, 0.0031308, 0.04044, 0.0031307),
		Color(0.5 / 255, 1.5 / 255, 254.5 / 255, 255.5 / 255), Color(0.3, 0.6, 0.9, 0),
		Color(1e-30, -1e-30, 65535.5, 300), Color(0.2, 0.9, 0.9, 1), Color(0.9, 0.2, 0.5, 0.7),
		Color(0.1, 0.1, 0.8, 0.3), Color(9.5, 0.75, 33, 2),
		Color(0.6, 17700158, 0.04, 1)]
	var xs: Array[float] = [0.0, 1.0, 0.25, -0.5, 2.5, INF, NAN, 1.0 / 6, 0.9999, 1e10, -1e-30,
		5.0 / 6, nz, 0.5, -INF, 0.75]
	var ns: Array[int] = [0, -1, 0xFF00FF80, 0x123456789abcdef0, 9223372036854775807,
		0x7fffffff, 4294967301, 0xF8000000, 0x0801FF3F, -0x7fffffffffffffff, 255, 300]
	for i: int in edges.size():
		for j: int in [0, 1, 4, 7, 11]:
			failures += _check_color_case(b2, edges[i], edges[(i + j) % edges.size()],
				edges[(i + j + 3) % edges.size()], xs[(i + j) % xs.size()], ns[(i + j) % ns.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	for round: int in 2000:
		var v: Array[Color] = []
		for k: int in 3:
			var e := Color()
			for m: int in 4:
				match rng.randi_range(0, 5):
					0: e[m] = rng.randf_range(-3, 3)
					1: e[m] = rng.randi_range(0, 255) / 255.0 + [0.0, 0.5 / 255][rng.randi_range(0, 1)]
					2: e[m] = rng.randf_range(-1e10, 1e10)
					_: e[m] = rng.randf()
			v.append(e)
		var n := (rng.randi() << 32) | rng.randi()
		failures += _check_color_case(b2, v[0], v[1], v[2], rng.randf_range(-2, 2), n)
	return failures


func _put_basis_result(out: PackedInt64Array, v: Variant) -> void:
	match typeof(v):
		TYPE_BASIS:
			for e: Vector3 in [v.x, v.y, v.z]:
				_put_basis_result(out, e)
		TYPE_TRANSFORM3D:
			_put_basis_result(out, v.basis)
			_put_basis_result(out, v.origin)
		TYPE_TRANSFORM2D:
			for e: Vector2 in [v.x, v.y, v.origin]:
				_put_basis_result(out, e)
		TYPE_VECTOR2:
			for e: float in [v.x, v.y]:
				out.append(0x7fc00000 if is_nan(e) else PackedFloat32Array([e]).to_byte_array().decode_u32(0))
		TYPE_VECTOR3:
			for e: float in [v.x, v.y, v.z]:
				out.append(0x7fc00000 if is_nan(e) else PackedFloat32Array([e]).to_byte_array().decode_u32(0))
		TYPE_QUATERNION:
			for e: float in [v.x, v.y, v.z, v.w]:
				out.append(0x7fc00000 if is_nan(e) else PackedFloat32Array([e]).to_byte_array().decode_u32(0))
		TYPE_FLOAT:
			out.append(0x7ff8000000000000 if is_nan(v) else PackedFloat64Array([v]).to_byte_array().decode_s64(0))
		_:
			out.append(int(v))


# The engine's Basis methods in the order Bag.replaced_bases calls the Odin procs.
func _basis_results(a: Basis, b: Basis, v: Vector3, w: Vector3, x: float, n: int) -> PackedInt64Array:
	var vs: Array = [Basis(), Basis(a), Basis(Quaternion(v.x, v.y, v.z, x)), Basis(v, x), Basis(w, v, w),
		a.inverse(), a.transposed(), a.orthonormalized(), a.determinant(), a.rotated(v, x),
		a.scaled(v), a.scaled_local(v), a.get_scale(), a.get_euler(n)]
	for k: int in 6:
		vs.append(a.get_euler(k))
	vs.append_array([a.tdotx(v), a.tdoty(v), a.tdotz(v), a.slerp(b, x), a.is_conformal(),
		a.is_equal_approx(b), a.is_finite(), a.is_orthonormal(), a.get_rotation_quaternion(),
		Basis.looking_at(v, w, false), Basis.looking_at(v, w, true), Basis.from_scale(v),
		Basis.from_euler(v, n)])
	for k: int in 6:
		vs.append(Basis.from_euler(v, k))
	var o := PackedInt64Array()
	for e: Variant in vs:
		_put_basis_result(o, e)
	return o


func _check_basis_case(b2: Bag, a: Basis, b: Basis, v: Vector3, w: Vector3, x: float, n: int) -> int:
	var want := _basis_results(a, b, v, w, x, n)
	var got: PackedInt64Array = b2.replaced_bases(a, b, v, w, x, n)
	if got == want:
		return 0
	var at := 0
	while at < mini(got.size(), want.size()) and got[at] == want[at]:
		at += 1
	print("FAIL: Bag.replaced_bases(%s, %s, %s, %s, %s, %d) differs at %d of %d: %s, not %s" % [a, b, v, w, x, n, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


# A random basis: a rotation, a scaled or reflected rotation, a rotation about one axis exactly,
# or arbitrary entries.
func _random_basis(rng: RandomNumberGenerator) -> Basis:
	var e := Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4))
	match rng.randi_range(0, 4):
		0:
			return Basis.from_euler(e, rng.randi_range(0, 5))
		1:
			return Basis.from_euler(e).scaled(Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
		2:
			return Basis([Vector3.RIGHT, Vector3.UP, Vector3.BACK][rng.randi_range(0, 2)], e.x)
		3:
			return Basis.from_euler(e).orthonormalized()
	return Basis(e, Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)),
		Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)))


# The Basis procs that replace engine methods, on edge cases (the identity, zero and singular
# bases, rotations about one axis that take get_euler's shortcuts, gimbal-locked and half-turn
# rotations, scaled and reflected rotations, signed zeros, huge entries, infinities and NaNs, with
# normalized, unnormalized, zero, parallel and non-finite vectors and every Euler order) and then
# on seeded random bases.
func _check_replaced_bases(b2: Bag) -> int:
	var failures := 0
	var nz := -float(Time.get_ticks_msec() * 0)
	var r := Basis.from_euler(Vector3(0.3, -1.2, 2.0))
	var edges: Array[Basis] = [Basis(), Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), r,
		Basis(Vector3(1, 2, 3), Vector3(2, 4, 6), Vector3(0, 1, 0)), Basis(Vector3.UP, 0.7),
		Basis(Vector3.RIGHT, 0.7), Basis(Vector3.BACK, 0.7), Basis.from_euler(Vector3(0, PI / 2, 0), 0),
		Basis.from_euler(Vector3(PI / 2, 0.4, 0)), Basis(Vector3(0, 0.6, 0.8), PI),
		Basis(Vector3.RIGHT, PI), r.scaled(Vector3(2, -0.5, 3)), r * Basis.from_scale(Vector3(-1, 1, 1)),
		Basis(Vector3(nz, 1, nz), Vector3(1, nz, 0), Vector3(0, 0, nz)),
		Basis(Vector3(1e30, 1, 0), Vector3(0, 1e30, 0), Vector3(0, 0, 1e30)),
		Basis(Vector3(INF, 0, 0), Vector3(0, NAN, 0), Vector3(0, 0, 1)), r.rotated(Vector3.UP, 1e-6)]
	var vs: Array[Vector3] = [Vector3.UP, Vector3(0.6, 0, 0.8), Vector3.ZERO, Vector3(1, 1, 1),
		Vector3(0, 2, 0), Vector3(INF, 0, 0), Vector3(NAN, 1, 0), Vector3(nz, nz, 1),
		Vector3(1e-30, 0, 0), Vector3(0.3, -1.2, 2.0), Vector3(0, PI / 2, 0), Vector3(-0.48, 0.6, 0.64)]
	var xs: Array[float] = [0.0, 1.0, 0.5, -0.25, PI, 2.5, INF, NAN, nz, 1e-7, 0.999]
	var ns: Array[int] = [0, 1, 2, 3, 4, 5, 6, -1, (1 << 32) + 2, 2]
	for i: int in edges.size():
		for j: int in [0, 1, 4, 7, 11]:
			failures += _check_basis_case(b2, edges[i], edges[(i + j) % edges.size()],
				vs[(i + j) % vs.size()], vs[(i + 2 * j + 1) % vs.size()], xs[(i + j) % xs.size()],
				ns[(i + j) % ns.size()])
	# Exact cases: every Euler sine entry at 1 - 0.00000025 and one ulp to either side, both signs;
	# cyclic and half-turn permutations, whose traces are 0 and -1 with tied diagonal entries, and a
	# rotation whose quaternion has equal y and z, with tied diagonal entries but no symmetry;
	# orthogonal quaternions for slerp; and bases that differ, or are not finite or orthonormal,
	# in one entry only.
	var limit := PackedByteArray([0, 0, 0, 0])
	for bits: int in [0x3f7ffffb, 0x3f7ffffc, 0x3f7ffffd]:
		limit.encode_u32(0, bits)
		for sg: float in [1.0, -1.0]:
			var e := limit.decode_float(0) * sg
			for k: int in 6:
				failures += _check_basis_case(b2, Basis(Vector3(e, e, e), Vector3(e, e, e), Vector3(e, e, e)),
					r, Vector3.UP, Vector3.BACK, 0.5, k)
	var cyc := Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
	var swap := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))
	var flip_x := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	var last := Basis(r.x, r.y, Vector3(r.z.x, r.z.y, r.z.z + 0.5))
	var inf_z := Basis(Vector3.RIGHT, Vector3.UP, Vector3(0, 0, INF))
	var skew_xz := Basis(Vector3.RIGHT, Vector3.UP, Vector3(0.6, 0, 0.8))
	var tie := Basis(Quaternion(0.3, 0.6, 0.6, sqrt(0.19)))
	for pair: Array in [[cyc, swap], [swap, cyc], [Basis(), flip_x], [flip_x, Basis()],
			[r, last], [inf_z, r], [skew_xz, r], [cyc.transposed(), swap.transposed()], [tie, cyc], [tie.transposed(), r]]:
		failures += _check_basis_case(b2, pair[0], pair[1], Vector3.UP, Vector3.BACK, 0.25, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	# Rotations whose quaternions have equal y and z, so their diagonal ties in the second and
	# third entries without the matrix being symmetric.
	for round: int in 200:
		var q := Quaternion(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0, rng.randf_range(-0.5, 0.5))
		q.z = q.y
		failures += _check_basis_case(b2, Basis(q.normalized()), r, Vector3.UP, Vector3.BACK, 0.25, 0)
	for round: int in 1500:
		var v := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		if rng.randi_range(0, 1) == 0:
			v = v.normalized()
		var w := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		failures += _check_basis_case(b2, _random_basis(rng), _random_basis(rng), v, w,
			rng.randf_range(-2, 2), rng.randi_range(0, 5))
	return failures


# The engine's Transform2D methods in the order Bag.replaced_transforms2d calls the Odin procs.
func _transform2d_results(a: Transform2D, b: Transform2D, p: Vector2, q: Vector2, x: float, y: float) -> PackedInt64Array:
	var vs: Array = [Transform2D(), Transform2D(a), Transform2D(x, p), Transform2D(x, p, y, q), Transform2D(p, q, p),
		a.inverse(), a.affine_inverse(), a.get_rotation(), a.get_origin(), a.get_scale(), a.get_skew(),
		a.orthonormalized(), a.rotated(x), a.rotated_local(x), a.scaled(p), a.scaled_local(p),
		a.translated(p), a.translated_local(p), a.determinant(), a.basis_xform(p), a.basis_xform_inv(p),
		a.interpolate_with(b, x), a.is_conformal(), a.is_equal_approx(b), a.is_finite(), a.looking_at(p)]
	var o: PackedInt64Array = PackedInt64Array()
	for e: Variant in vs:
		_put_basis_result(o, e)
	return o


# The engine's Transform3D methods in the order Bag.replaced_transforms3d calls the Odin procs.
func _transform3d_results(a: Transform3D, b: Transform3D, v: Vector3, w: Vector3, m: Projection, x: float) -> PackedInt64Array:
	var vs: Array = [Transform3D(), Transform3D(a), Transform3D(b.basis, v), Transform3D(v, w, a.origin, b.origin),
		Transform3D(m), a.inverse(), a.affine_inverse(), a.orthonormalized(), a.rotated(v, x),
		a.rotated_local(v, x), a.scaled(v), a.scaled_local(v), a.translated(v), a.translated_local(v),
		a.looking_at(v, w, false), a.looking_at(v, w, true), a.interpolate_with(b, x),
		a.is_equal_approx(b), a.is_finite()]
	var o: PackedInt64Array = PackedInt64Array()
	for e: Variant in vs:
		_put_basis_result(o, e)
	return o


func _check_transform2d_case(b2: Bag, a: Transform2D, b: Transform2D, p: Vector2, q: Vector2, x: float, y: float) -> int:
	var want: PackedInt64Array = _transform2d_results(a, b, p, q, x, y)
	var got: PackedInt64Array = b2.replaced_transforms2d(a, b, p, q, x, y)
	if got == want:
		return 0
	var at: int = 0
	while at < mini(got.size(), want.size()) and got[at] == want[at]:
		at += 1
	print("FAIL: Bag.replaced_transforms2d(%s, %s, %s, %s, %s, %s) differs at %d of %d: %s, not %s" % [a, b, p, q, x, y, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


func _check_transform3d_case(b2: Bag, a: Transform3D, b: Transform3D, v: Vector3, w: Vector3, m: Projection, x: float) -> int:
	var want: PackedInt64Array = _transform3d_results(a, b, v, w, m, x)
	var got: PackedInt64Array = b2.replaced_transforms3d(a, b, v, w, m, x)
	if got == want:
		return 0
	var at: int = 0
	while at < mini(got.size(), want.size()) and got[at] == want[at]:
		at += 1
	print("FAIL: Bag.replaced_transforms3d(%s, %s, %s, %s, %s) differs at %d of %d: %s, not %s" % [a, b, v, w, x, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


# A random Transform2D: a rotation, a rotation with scale and skew (flipped when a scale is
# negative), or arbitrary columns.
func _random_transform2d(rng: RandomNumberGenerator) -> Transform2D:
	var o: Vector2 = Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
	var kind: int = rng.randi_range(0, 2)
	if kind == 0:
		return Transform2D(rng.randf_range(-7, 7), o)
	if kind == 1:
		return Transform2D(rng.randf_range(-7, 7), Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)),
			rng.randf_range(-1.5, 1.5), o)
	return Transform2D(Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)),
		Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), o)


# The Transform2D and Transform3D procs that replace engine methods, on edge cases (the identity,
# zero and singular bases, rotations by exact angles, skewed, scaled and flipped bases, signed
# zeros, huge entries, infinities and NaNs, targets at the origin, colinear up vectors, angles a
# whole number of turns apart) and then on seeded random transforms.
func _check_replaced_transforms(b2: Bag) -> int:
	var failures: int = 0
	var nz: float = -float(Time.get_ticks_msec() * 0)
	var t: Transform2D = Transform2D(0.7, Vector2(2, -0.5), 0.3, Vector2(1, 2))
	var edges2: Array[Transform2D] = [Transform2D(), Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO), t,
		Transform2D(0.7, Vector2(1, 2)), Transform2D(Vector2(1, 2), Vector2(2, 4), Vector2(3, 0)),
		Transform2D(PI, Vector2(-1, 1), 0, Vector2.ZERO), Transform2D(PI / 2, Vector2(3, 3), 0, Vector2(0, 1)),
		Transform2D(Vector2(nz, 1), Vector2(1, nz), Vector2(nz, nz)), Transform2D(-2.0, Vector2(0, 2), 0.5, Vector2.ONE),
		Transform2D(Vector2(1e30, 0), Vector2(0, 1e30), Vector2(1e30, 1)), Transform2D(Vector2(INF, 0), Vector2(0, 1), Vector2.ZERO),
		Transform2D(Vector2(1, NAN), Vector2(0, 1), Vector2.ZERO), t.rotated(1e-6), Transform2D(0.0, Vector2(1, -1), PI / 2, Vector2.ZERO),
		Transform2D(Vector2(3, 0), Vector2(1, 2), Vector2(2, 2))]
	var ps: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(3, 4), Vector2(1, 2), Vector2(INF, 0),
		Vector2(NAN, 1), Vector2(nz, nz), Vector2(1e-30, 0), Vector2(-2, 0.5), Vector2(0, -1)])
	var xs: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 0.5, -0.25, PI, 2.5, INF, NAN, nz, 1e-7, TAU, -3 * TAU + 0.1, 0.999])
	for i: int in edges2.size():
		for j: int in [0, 1, 4, 7, 11]:
			failures += _check_transform2d_case(b2, edges2[i], edges2[(i + j) % edges2.size()],
				ps[(i + j) % ps.size()], ps[(i + 2 * j + 1) % ps.size()], xs[(i + j) % xs.size()],
				xs[(i + 3 * j + 2) % xs.size()])
	var r: Basis = Basis.from_euler(Vector3(0.3, -1.2, 2.0))
	var edges3: Array[Transform3D] = [Transform3D(), Transform3D(Basis(), Vector3(1, 2, 3)),
		Transform3D(r, Vector3(1, 2, 3)), Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ONE),
		Transform3D(Basis(Vector3(1, 2, 3), Vector3(2, 4, 6), Vector3(0, 1, 0)), Vector3(0, 0, -1)),
		Transform3D(r.scaled(Vector3(2, -0.5, 3)), Vector3(nz, 0, 0)), Transform3D(r * Basis.from_scale(Vector3(-1, 1, 1)), Vector3.UP),
		Transform3D(Basis(Vector3.UP, PI), Vector3(0, 1, 0)), Transform3D(Basis(Vector3(1e30, 1, 0), Vector3(0, 1e30, 0), Vector3(0, 0, 1e30)), Vector3.ZERO),
		Transform3D(Basis(Vector3(INF, 0, 0), Vector3(0, NAN, 0), Vector3(0, 0, 1)), Vector3.ZERO),
		Transform3D(r, Vector3(INF, 0, NAN)), Transform3D(r.rotated(Vector3.UP, 1e-6), Vector3(1, 2, 3.00001))]
	var vs: PackedVector3Array = PackedVector3Array([Vector3.UP, Vector3(0.6, 0, 0.8), Vector3.ZERO, Vector3(1, 2, 3), Vector3(0, 2, 0),
		Vector3(INF, 0, 0), Vector3(NAN, 1, 0), Vector3(nz, nz, 1), Vector3(1e-30, 0, 0), Vector3(-0.48, 0.6, 0.64)])
	var ms: Array[Projection] = [Projection(), Projection(Transform3D(r, Vector3(1, 2, 3))),
		Projection.create_perspective(70, 1.5, 0.1, 100), Projection(Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8),
		Vector4(9, 10, 11, 12), Vector4(13, NAN, INF, nz))]
	for i: int in edges3.size():
		for j: int in [0, 1, 4, 7, 11]:
			failures += _check_transform3d_case(b2, edges3[i], edges3[(i + j) % edges3.size()],
				vs[(i + j) % vs.size()], vs[(i + 2 * j + 1) % vs.size()], ms[(i + j) % ms.size()],
				xs[(i + j) % xs.size()])
	# Exact cases: targets at, or within approximate equality of, the origin; up vectors colinear
	# with the target; and transforms that differ in one entry only.
	var at: Transform3D = Transform3D(r, Vector3(1, 2, 3))
	for target: Vector3 in [Vector3(1, 2, 3), Vector3(1, 2, 3.000001), Vector3(1, 2, 4), Vector3(1, 5, 3)]:
		failures += _check_transform3d_case(b2, at, Transform3D(r, Vector3(1, 2, 3.5)), target, Vector3.UP, ms[0], 0.25)
	failures += _check_transform2d_case(b2, t, Transform2D(t.x, t.y, t.origin + Vector2(0, 0.5)), t.origin, Vector2.UP, 0.25, 0.1)
	# Columns whose normalized dot rounds just past 1 and -1 in single precision, so get_skew's
	# Math::acos clamps (the literals round to 0x3fa49248, 0x3f800001 and 0xbf7ffff9); skews of
	# exactly -PI/2 and PI/2, a whole PI apart for lerp_angle; a determinant of -0; and
	# non-finite origins.
	var sx: Vector2 = Vector2(9.0 / 7.0, 1.0)
	var clamp_hi: Transform2D = Transform2D(sx, Vector2(1.2857141, 1.0000001), Vector2.ZERO)
	var clamp_lo: Transform2D = Transform2D(sx, Vector2(-1.2857141, -0.9999996), Vector2.ZERO)
	var skew_neg: Transform2D = Transform2D(Vector2(1, 0), Vector2(1, 1e-20), Vector2.ZERO)
	var skew_pos: Transform2D = Transform2D(Vector2(1, 0), Vector2(-1, 1e-20), Vector2.ZERO)
	var pairs: Array[Array] = [[clamp_hi, clamp_lo], [clamp_lo, clamp_hi], [skew_neg, skew_pos], [skew_pos, skew_neg],
		[Transform2D(Vector2(nz, 1), Vector2(0, 1), Vector2(1, 2)), t], [Transform2D(0.5, Vector2(NAN, 1)), t],
		[Transform2D(0.5, Vector2(INF, 1)), t]]
	for pair: Array in pairs:
		failures += _check_transform2d_case(b2, pair[0], pair[1], Vector2(1, 2), Vector2(3, 4), 0.25, 0.75)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261113
	for round: int in 1500:
		var p: Vector2 = Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		var q: Vector2 = Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		failures += _check_transform2d_case(b2, _random_transform2d(rng), _random_transform2d(rng), p, q,
			rng.randf_range(-7, 7), rng.randf_range(-2, 2))
		var v: Vector3 = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		if rng.randi_range(0, 1) == 0:
			v = v.normalized()
		var w: Vector3 = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var o: Vector3 = Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))
		var m: Projection = Projection(Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf()),
			Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf()),
			Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf()),
			Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		failures += _check_transform3d_case(b2, Transform3D(_random_basis(rng), o), Transform3D(_random_basis(rng), -o),
			v, w, m, rng.randf_range(-2, 2))
	return failures


# The engine's Quaternion methods in the order Bag.replaced_quaternions calls the Odin procs.
func _quaternion_results(a: Quaternion, b: Quaternion, c: Quaternion, d: Quaternion, m: Basis, v: Vector3, w: Vector3, x: float, n: int) -> PackedInt64Array:
	var vs: Array = [Quaternion(), Quaternion(a), Quaternion(m), Quaternion(v, x), Quaternion(v, w), Quaternion(x, v.x, v.y, v.z),
		a.length(), a.length_squared(), a.normalized(), a.is_normalized(), a.is_equal_approx(b), a.is_finite(),
		a.inverse(), a.log(), a.exp(), a.angle_to(b), a.dot(b), a.slerp(b, x), a.slerpni(b, x),
		a.spherical_cubic_interpolate(b, c, d, x), a.spherical_cubic_interpolate_in_time(b, c, d, x, w.x, w.y, w.z),
		a.get_euler(n)]
	for k: int in 6:
		vs.append(a.get_euler(k))
	vs.append_array([Quaternion.from_euler(v), a.get_axis(), a.get_angle()])
	var o: PackedInt64Array = PackedInt64Array()
	for e: Variant in vs:
		_put_basis_result(o, e)
	return o


func _check_quaternion_case(b2: Bag, a: Quaternion, b: Quaternion, c: Quaternion, d: Quaternion, m: Basis, v: Vector3, w: Vector3, x: float, n: int) -> int:
	var want: PackedInt64Array = _quaternion_results(a, b, c, d, m, v, w, x, n)
	var got: PackedInt64Array = b2.replaced_quaternions(a, b, c, d, m, v, w, x, n)
	if got == want:
		return 0
	var at: int = 0
	while at < mini(got.size(), want.size()) and got[at] == want[at]:
		at += 1
	print("FAIL: Bag.replaced_quaternions(%s, %s, %s, %s, %s, %s, %s, %s, %d) differs at %d of %d: %s, not %s" % [a, b, c, d, m, v, w, x, n, at, want.size(), got.slice(at, at + 4), want.slice(at, at + 4)])
	return 1


# A float from its single-precision bits.
func _f32_bits(bits: int) -> float:
	var buf: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	buf.encode_u32(0, bits)
	return buf.decode_float(0)


# A random rotation quaternion, sometimes flipped in sign or scaled off unit length.
func _random_quaternion(rng: RandomNumberGenerator) -> Quaternion:
	var axis: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	if axis == Vector3.ZERO:
		axis = Vector3.UP
	var q: Quaternion = Quaternion(axis, rng.randf_range(-7, 7))
	var kind: int = rng.randi_range(0, 3)
	if kind == 0:
		return -q
	if kind == 1:
		return q * rng.randf_range(0.5, 1.5)
	return q


# The Quaternion procs that replace engine methods, on edge cases (the identity, zero, unnormalized,
# opposite and nearly equal quaternions, signed zeros, infinities and NaNs, parallel and opposite
# arcs) and exact limits, then on seeded random quaternions.
func _check_replaced_quaternions(b2: Bag) -> int:
	var failures: int = 0
	var nz: float = -float(Time.get_ticks_msec() * 0)
	var r: Quaternion = Quaternion.from_euler(Vector3(0.3, -1.2, 2.0))
	var edges: Array[Quaternion] = [Quaternion(), Quaternion(0, 0, 0, 0), r, -r, Quaternion(1, 1, 1, 1),
		Quaternion(0, 0, 0, -1), Quaternion(1, 0, 0, 0), Quaternion(0, 0.6, 0.8, 0), Quaternion(nz, nz, nz, 1),
		Quaternion(INF, 0, 0, 1), Quaternion(0, NAN, 0, 1), r * Quaternion(Vector3.UP, 1e-6),
		Quaternion(Vector3(0.6, 0, 0.8), PI), Quaternion(1e30, 0, 0, 1), Quaternion(0.5, 0.5, 0.5, 0.5)]
	var vs: PackedVector3Array = PackedVector3Array([Vector3.UP, Vector3(0.6, 0, 0.8), Vector3.ZERO, Vector3(1, 2, 3),
		Vector3(0, -2, 0), Vector3(INF, 0, 0), Vector3(NAN, 1, 0), Vector3(nz, nz, 1), Vector3(1e-30, 0, 0),
		Vector3(-0.48, 0.6, 0.64), Vector3(0.3, -1.2, 2.0), Vector3(0, PI / 2, 0)])
	var bases: Array[Basis] = [Basis(), Basis.from_euler(Vector3(0.3, -1.2, 2.0)), Basis(Vector3.UP, PI),
		Basis.from_scale(Vector3(2, 1, 1)), Basis(Vector3(INF, 0, 0), Vector3.UP, Vector3.BACK)]
	var xs: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 0.5, -0.25, PI, 2.5, INF, NAN, nz, 1e-7, TAU, 0.999])
	var ns: PackedInt64Array = PackedInt64Array([0, 1, 2, 3, 4, 5, 6, -1, (1 << 32) + 2, 2])
	for i: int in edges.size():
		for j: int in [0, 1, 4, 7, 11]:
			var e: int = edges.size()
			failures += _check_quaternion_case(b2, edges[i], edges[(i + j) % e], edges[(i + 2 * j + 1) % e],
				edges[(i + 3 * j + 2) % e], bases[(i + j) % bases.size()], vs[(i + j) % vs.size()],
				vs[(i + 2 * j + 1) % vs.size()], xs[(i + j) % xs.size()], ns[(i + j) % ns.size()])
	# Exact limits: get_axis's `1 - CMP_EPSILON` and exp's `CMP_EPSILON`, both compared in double,
	# with the floats either side (0x3f7fff58 and 0x3f7fff59 bracket 0.99999, 0x3727c5ac and
	# 0x3727c5ad bracket 0.00001); slerpni's 0.9999 and the shortest arc's 0.99999975 with the dot
	# a float either side; parallel and opposite arcs, opposite along each axis.
	for bits: int in [0x3f7fff58, 0x3f7fff59]:
		var w: float = _f32_bits(bits)
		for sg: float in [1.0, -1.0]:
			failures += _check_quaternion_case(b2, Quaternion(sqrt(1 - w * w), 0, 0, w * sg), r, r, r, bases[0],
				Vector3.UP, Vector3.BACK, 0.5, 0)
	for bits: int in [0x3727c5ac, 0x3727c5ad]:
		var t: float = _f32_bits(bits)
		failures += _check_quaternion_case(b2, Quaternion(t, 0, 0, 1), r, r, r, bases[0], Vector3.UP, Vector3.BACK, 0.5, 0)
		failures += _check_quaternion_case(b2, Quaternion(0, 0, -t, 0), r, r, r, bases[0], Vector3.UP, Vector3.BACK, 0.5, 0)
	for bits: int in [0x3f7ff972, 0x3f7ff973, 0x3f7ffffb, 0x3f7ffffc, 0x3f7ffffd]:
		var dw: float = _f32_bits(bits)
		var near: Quaternion = Quaternion(sqrt(1 - dw * dw), 0, 0, dw)
		failures += _check_quaternion_case(b2, Quaternion(), near, r, r, bases[0], Vector3.RIGHT,
			Vector3(dw, sqrt(1 - dw * dw), 0), 0.25, 0)
		failures += _check_quaternion_case(b2, Quaternion(), -near, r, r, bases[0], Vector3.RIGHT,
			Vector3(-dw, sqrt(1 - dw * dw), 0), 0.25, 0)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1, 1, 1), Vector3(0.6, 0, -0.8)]:
		failures += _check_quaternion_case(b2, r, r, r, r, bases[0], axis, -axis, 0.5, 0)
		failures += _check_quaternion_case(b2, r, r, r, r, bases[0], axis, axis * 3, 0.5, 0)
	# The spherical cubic's sign flips on every pairing of half and quarter turns, whose dots after
	# the basis round trip are exactly +0 or -0, and of a NaN, whose dot's sign bit is set.
	var h: float = sqrt(0.5)
	var turns: Array[Quaternion] = [Quaternion(), Quaternion(1, 0, 0, 0), Quaternion(0, 1, 0, 0), Quaternion(0, 0, 1, 0),
		Quaternion(0, 0.6, 0.8, 0), Quaternion(h, 0, 0, h), Quaternion(0, h, 0, -h), Quaternion(0, 0, -h, h),
		Quaternion(0, NAN, 0, 1)]
	for i: int in turns.size():
		for j: int in turns.size():
			for k: int in turns.size():
				for l: int in turns.size():
					failures += _check_quaternion_case(b2, turns[i], turns[j], turns[k], turns[l], bases[0],
						Vector3.UP, Vector3(0.5, -1, 2), 0.3, 0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261114
	for round: int in 1500:
		var v: Vector3 = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		if rng.randi_range(0, 1) == 0:
			v = v.normalized()
		var w: Vector3 = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		failures += _check_quaternion_case(b2, _random_quaternion(rng), _random_quaternion(rng), _random_quaternion(rng),
			_random_quaternion(rng), _random_basis(rng), v, w, rng.randf_range(-2, 2), rng.randi_range(0, 5))
	return failures


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
