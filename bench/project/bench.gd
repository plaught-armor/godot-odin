extends SceneTree

# Prints nanoseconds per call for each binding path, best of ROUNDS runs of N calls.
#   godot --headless --path bench/project -s bench.gd

const N: int = 1_000_000
const ROUNDS: int = 5


# The GDScript side of the `_process` comparison.
class GdTicker extends Node:
	var ticks: int = 0

	func _process(_delta: float) -> void:
		ticks += 1


func _initialize() -> void:
	var b: Bench = Bench.new()
	var u: Variant = b
	_report("GDScript -> Odin, typed, 1 arg", func() -> float: return _typed(b))
	_report("GDScript -> Odin, typed, 3 args", func() -> float: return _typed3(b))
	_report("GDScript -> Odin, untyped, 1 arg", func() -> float: return _untyped(u))
	_report("GDScript -> Odin, untyped, 3 args", func() -> float: return _untyped3(u))
	_report("GDScript loop only (baseline)", func() -> float: return _empty())
	var c: Curve = Curve.new()
	var cu: Variant = c
	_report("GDScript -> engine, typed, 1 arg", func() -> float: return _native(c))
	_report("GDScript -> engine, untyped, 1 arg", func() -> float: return _native_untyped(cu))
	_report("Odin -> engine ptrcall", func() -> float: return b.engine_call_ns(N))
	_report("Odin construct + release", func() -> float: return b.construct_ns(N))
	var xs := PackedInt64Array()
	xs.resize(1000)
	_report("Odin sum PackedInt64Array, get(), per element", func() -> float: return b.packed_get_ns(xs, N / 1000))
	_report("Odin sum PackedInt64Array, packed_read, per element", func() -> float: return b.packed_read_ns(xs, N / 1000))
	_report("Odin build PackedInt64Array, set(), per element", func() -> float: return b.packed_build_ns(false, N / 1000))
	_report("Odin build PackedInt64Array, packed_of, per element", func() -> float: return b.packed_build_ns(true, N / 1000))
	var text := "the quick brown fox jumps over the lazy dog, ".repeat(20)
	_report("Odin scan String, unicode_at(), per char", func() -> float: return b.string_scan_ns(text, false, N / 1000))
	_report("Odin scan String, string_read, per char", func() -> float: return b.string_scan_ns(text, true, N / 1000))
	var words: Array = []
	for i in 1000:
		words.append("word %d" % i)
	_report("Odin read Array of Strings, get(), per element", func() -> float: return b.array_read_ns(words, false, N / 1000))
	_report("Odin read Array of Strings, array_at, per element", func() -> float: return b.array_read_ns(words, true, N / 1000))
	_report("Odin build Array of ints, push_back(), per element", func() -> float: return b.array_build_ns(false, false, N / 1000))
	_report("Odin build Array of ints, array_of, per element", func() -> float: return b.array_build_ns(false, true, N / 1000))
	_report("Odin build Array[int], push_back(), per element", func() -> float: return b.array_build_ns(true, false, N / 1000))
	_report("Odin build Array[int], array_typed_of, per element", func() -> float: return b.array_build_ns(true, true, N / 1000))
	_report("Odin build Dictionary of ints, set(), per entry", func() -> float: return b.dict_build_ns(false, N / 1000))
	_report("Odin build Dictionary of ints, dict_of, per entry", func() -> float: return b.dict_build_ns(true, N / 1000))
	_report("Odin Dictionary get, dictionary_get", func() -> float: return b.dict_get_ns(0, N / 1000))
	_report("Odin Dictionary get, dict_get", func() -> float: return b.dict_get_ns(1, N / 1000))
	_report("Odin Dictionary get, dict_get_into", func() -> float: return b.dict_get_ns(2, N / 1000))
	_report("Odin set Array of ints, set(), per element", func() -> float: return b.array_write_ns(false, false, N / 1000))
	_report("Odin set Array of ints, array_write, per element", func() -> float: return b.array_write_ns(false, true, N / 1000))
	_report("Odin set Array[int], set(), per element", func() -> float: return b.array_write_ns(true, false, N / 1000))
	_report("Odin set Array[int], array_write_typed, per element", func() -> float: return b.array_write_ns(true, true, N / 1000))
	_report("Odin name_of + destroy, short identifier", func() -> float: return b.ident_ns(0, N))
	_report("Odin path_of + destroy, short path", func() -> float: return b.ident_ns(1, N))
	_report("Odin string_of + destroy, short identifier", func() -> float: return b.ident_ns(2, N))
	_report("Odin utf8, short identifier", func() -> float: return b.ident_ns(3, N))
	_report("Odin intern, short identifier", func() -> float: return b.ident_ns(4, N))
	_report("Odin intern_path, short path", func() -> float: return b.ident_ns(5, N))
	_report("Odin intern_text, short identifier", func() -> float: return b.ident_ns(6, N))
	_report("Odin temp_text in an engine-call scope", func() -> float: return b.ident_ns(7, N))
	_report("Odin string_length, short String", func() -> float: return b.ident_ns(8, N))
	_report("engine String ==, short equal Strings", func() -> float: return b.ident_ns(9, N))
	_report("Odin string_equal, short equal Strings", func() -> float: return b.ident_ns(10, N))
	_report("engine String ==, String and its copy", func() -> float: return b.ident_ns(12, N))
	_report("Odin string_equal, String and its copy", func() -> float: return b.ident_ns(13, N))
	_report("engine string_of + String == + destroy, short text", func() -> float: return b.ident_ns(14, N))
	_report("Odin string_equal_text, short equal text", func() -> float: return b.ident_ns(11, N))
	_report("Odin string_begins_with, cached String prefix", func() -> float: return b.ident_ns(15, N))
	_report("Odin string_begins_with_text, Odin text prefix", func() -> float: return b.ident_ns(16, N))
	_report("Odin string_ends_with_text, Odin text suffix", func() -> float: return b.ident_ns(17, N))
	_report("engine String == over 8 names, match last", func() -> float: return b.ident_ns(18, N))
	_report("Odin string_equal_text over 8 names, match last", func() -> float: return b.ident_ns(19, N))
	_report("Odin string_which over 8 names, match last", func() -> float: return b.ident_ns(20, N))
	_report("Engine String.find call, cached String in a sentence", func() -> float: return b.ident_ns(47, N))
	_report("Odin string_find, cached String in a sentence", func() -> float: return b.ident_ns(21, N))
	_report("Odin string_find_text, Odin text in a sentence", func() -> float: return b.ident_ns(22, N))
	_report("Odin same_name on intern of 8 names, match last", func() -> float: return b.ident_ns(23, N))
	_report("Odin name_which over 8 names, match last", func() -> float: return b.ident_ns(24, N))
	_report("Engine String.rfind call, cached String in a sentence", func() -> float: return b.ident_ns(48, N))
	_report("Odin string_rfind, cached String in a sentence", func() -> float: return b.ident_ns(25, N))
	_report("Odin string_rfind_text, Odin text in a sentence", func() -> float: return b.ident_ns(26, N))
	_report("Engine String.findn call, cached String in a sentence", func() -> float: return b.ident_ns(49, N))
	_report("Odin string_findn, cached String in a sentence", func() -> float: return b.ident_ns(27, N))
	_report("Odin string_findn_text, Odin text in a sentence", func() -> float: return b.ident_ns(28, N))
	_report("Engine String.nocasecmp_to call, cached String", func() -> float: return b.ident_ns(50, N))
	_report("Odin string_nocasecmp_to, cached String", func() -> float: return b.ident_ns(29, N))
	_report("Odin string_equal_text_nocase, Odin text", func() -> float: return b.ident_ns(30, N))
	_report("Odin string_count_text, Odin text in a sentence", func() -> float: return b.ident_ns(32, N))
	_report("Odin string_begins_with_text_nocase, Odin text", func() -> float: return b.ident_ns(33, N))
	_report("Engine String.replace call, cached Strings in a sentence", func() -> float: return b.ident_ns(51, N))
	_report("Odin string_replace, cached Strings in a sentence", func() -> float: return b.ident_ns(34, N))
	_report("Odin string_replace_text, Odin text in a sentence", func() -> float: return b.ident_ns(35, N))
	_report("Engine String.rfindn call, cached String in a sentence", func() -> float: return b.string_ns(0, N))
	_report("Odin string_rfindn, cached String in a sentence", func() -> float: return b.string_ns(1, N))
	_report("Engine String.contains call, cached String in a sentence", func() -> float: return b.string_ns(2, N))
	_report("Odin string_contains, cached String in a sentence", func() -> float: return b.string_ns(3, N))
	_report("Engine String.containsn call, cached String in a sentence", func() -> float: return b.string_ns(4, N))
	_report("Odin string_containsn, cached String in a sentence", func() -> float: return b.string_ns(5, N))
	_report("Engine String.count call, cached String in a sentence", func() -> float: return b.string_ns(6, N))
	_report("Odin string_count, cached String in a sentence", func() -> float: return b.string_ns(7, N))
	_report("Engine String.countn call, cached String in a sentence", func() -> float: return b.string_ns(8, N))
	_report("Odin string_countn, cached String in a sentence", func() -> float: return b.string_ns(9, N))
	_report("Engine String.begins_with call, cached String on a sentence", func() -> float: return b.string_ns(10, N))
	_report("Odin string_begins_with, cached String on a sentence", func() -> float: return b.string_ns(11, N))
	_report("Engine String.ends_with call, cached String on a sentence", func() -> float: return b.string_ns(12, N))
	_report("Odin string_ends_with, cached String on a sentence", func() -> float: return b.string_ns(13, N))
	_report("Engine String.casecmp_to call, equal Strings", func() -> float: return b.string_ns(14, N))
	_report("Odin string_casecmp_to, equal Strings", func() -> float: return b.string_ns(15, N))
	_report("Engine String.replacen call, cached Strings in a sentence", func() -> float: return b.string_ns(16, N))
	_report("Odin string_replacen, cached Strings in a sentence", func() -> float: return b.string_ns(17, N))
	_report("Engine String.substr call, 5 characters of a sentence", func() -> float: return b.string_ns(18, N))
	_report("Odin string_substr, 5 characters of a sentence", func() -> float: return b.string_ns(19, N))
	_report("Engine String.left call, 9 characters of a sentence", func() -> float: return b.string_ns(20, N))
	_report("Odin string_left, 9 characters of a sentence", func() -> float: return b.string_ns(21, N))
	_report("Engine String.right call, 8 characters of a sentence", func() -> float: return b.string_ns(22, N))
	_report("Odin string_right, 8 characters of a sentence", func() -> float: return b.string_ns(23, N))
	_report("Engine String.to_upper call, cached String of a sentence", func() -> float: return b.string_ns(24, N))
	_report("Odin string_to_upper, cached String of a sentence", func() -> float: return b.string_ns(25, N))
	_report("Engine String.to_lower call, cached String of a sentence", func() -> float: return b.string_ns(26, N))
	_report("Odin string_to_lower, cached String of a sentence", func() -> float: return b.string_ns(27, N))
	_report("Engine String.get_slice call, part 3 of a sentence split on spaces", func() -> float: return b.string_ns(28, N))
	_report("Odin string_get_slice, part 3 of a sentence split on spaces", func() -> float: return b.string_ns(29, N))
	_report("Engine String.trim_prefix call, two words off a sentence", func() -> float: return b.string_ns(30, N))
	_report("Odin string_trim_prefix, two words off a sentence", func() -> float: return b.string_ns(31, N))
	_report("Engine String.trim_suffix call, two words off a sentence", func() -> float: return b.string_ns(32, N))
	_report("Odin string_trim_suffix, two words off a sentence", func() -> float: return b.string_ns(33, N))
	_report("Engine String.strip_edges call, four characters off a sentence", func() -> float: return b.string_ns(34, N))
	_report("Odin string_strip_edges, four characters off a sentence", func() -> float: return b.string_ns(35, N))
	_report("Engine String.lstrip call, four characters off a sentence, a set of four", func() -> float: return b.string_ns(36, N))
	_report("Odin string_lstrip, four characters off a sentence, a set of four", func() -> float: return b.string_ns(37, N))
	_report("Engine String.rstrip call, four characters off a sentence, a set of four", func() -> float: return b.string_ns(38, N))
	_report("Odin string_rstrip, four characters off a sentence, a set of four", func() -> float: return b.string_ns(39, N))
	_report("Engine String.capitalize call, cached String of a sentence", func() -> float: return b.string_ns(40, N))
	_report("Odin string_capitalize, cached String of a sentence", func() -> float: return b.string_ns(41, N))
	_report("Engine String.to_camel_case call, cached String of a sentence", func() -> float: return b.string_ns(42, N))
	_report("Odin string_to_camel_case, cached String of a sentence", func() -> float: return b.string_ns(43, N))
	_report("Engine String.to_pascal_case call, cached String of a sentence", func() -> float: return b.string_ns(44, N))
	_report("Odin string_to_pascal_case, cached String of a sentence", func() -> float: return b.string_ns(45, N))
	_report("Engine String.to_snake_case call, cached String of a sentence", func() -> float: return b.string_ns(46, N))
	_report("Odin string_to_snake_case, cached String of a sentence", func() -> float: return b.string_ns(47, N))
	_report("Engine String.to_kebab_case call, cached String of a sentence", func() -> float: return b.string_ns(48, N))
	_report("Odin string_to_kebab_case, cached String of a sentence", func() -> float: return b.string_ns(49, N))
	_report("Engine String.get_extension call, a scene path", func() -> float: return b.string_ns(50, N))
	_report("Odin string_get_extension, a scene path", func() -> float: return b.string_ns(51, N))
	_report("Engine String.get_basename call, a scene path", func() -> float: return b.string_ns(52, N))
	_report("Odin string_get_basename, a scene path", func() -> float: return b.string_ns(53, N))
	_report("Engine String.get_file call, a scene path", func() -> float: return b.string_ns(54, N))
	_report("Odin string_get_file, a scene path", func() -> float: return b.string_ns(55, N))
	_report("Engine String.get_base_dir call, a scene path", func() -> float: return b.string_ns(56, N))
	_report("Odin string_get_base_dir, a scene path", func() -> float: return b.string_ns(57, N))
	_report("Engine String.naturalcasecmp_to call, two numbered file names", func() -> float: return b.string_ns(58, N))
	_report("Odin string_naturalcasecmp_to, two numbered file names", func() -> float: return b.string_ns(59, N))
	_report("Engine String.naturalnocasecmp_to call, two numbered file names", func() -> float: return b.string_ns(60, N))
	_report("Odin string_naturalnocasecmp_to, two numbered file names", func() -> float: return b.string_ns(61, N))
	_report("Engine String.filecasecmp_to call, two numbered file names", func() -> float: return b.string_ns(62, N))
	_report("Odin string_filecasecmp_to, two numbered file names", func() -> float: return b.string_ns(63, N))
	_report("Engine String.filenocasecmp_to call, two numbered file names", func() -> float: return b.string_ns(64, N))
	_report("Odin string_filenocasecmp_to, two numbered file names", func() -> float: return b.string_ns(65, N))
	_report("Engine String.path_join call, a folder and a file name", func() -> float: return b.string_ns(66, N))
	_report("Odin string_path_join, a folder and a file name", func() -> float: return b.string_ns(67, N))
	_report("Engine String.split call, cached String on a sentence", func() -> float: return b.ident_ns(52, N))
	_report("Engine StringName.length call", func() -> float: return b.ident_ns(53, N))
	_report("Odin string_name_length", func() -> float: return b.ident_ns(54, N))
	_report("Engine StringName.hash call", func() -> float: return b.ident_ns(55, N))
	_report("Odin string_name_hash", func() -> float: return b.ident_ns(56, N))
	_report("Engine StringName.find call, cached String in a sentence", func() -> float: return b.ident_ns(57, N))
	_report("Odin string_name_find, cached String in a sentence", func() -> float: return b.ident_ns(58, N))
	_report("Odin string_split, cached String on a sentence", func() -> float: return b.ident_ns(36, N))
	_report("Odin string_split_text, Odin text on a sentence", func() -> float: return b.ident_ns(37, N))
	_report("Odin string_split_parts, each part read in place", func() -> float: return b.ident_ns(38, N))
	_report("Engine String.to_int call, cached String", func() -> float: return b.ident_ns(59, N))
	_report("Odin string_to_int, cached String", func() -> float: return b.ident_ns(39, N))
	_report("Odin runes_to_int, the String read in place", func() -> float: return b.ident_ns(40, N))
	_report("Engine String.to_float call, cached String", func() -> float: return b.ident_ns(60, N))
	_report("Odin string_to_float, cached String", func() -> float: return b.ident_ns(41, N))
	_report("Odin runes_to_float, the String read in place", func() -> float: return b.ident_ns(42, N))
	_report("Engine String.is_valid_float call, cached String", func() -> float: return b.ident_ns(61, N))
	_report("Odin string_is_valid_float, cached String", func() -> float: return b.ident_ns(62, N))
	_report("Engine NodePath.get_name_count call", func() -> float: return b.ident_ns(63, N))
	_report("Odin node_path_get_name_count", func() -> float: return b.ident_ns(64, N))
	_report("Engine NodePath.hash call", func() -> float: return b.ident_ns(65, N))
	_report("Odin node_path_hash", func() -> float: return b.ident_ns(66, N))
	_report("Engine NodePath.get_name call", func() -> float: return b.ident_ns(67, N))
	_report("Odin node_path_get_name", func() -> float: return b.ident_ns(68, N))
	_report("Engine Array.get call, a StringName element", func() -> float: return b.ident_ns(69, N))
	_report("Odin array_get, a StringName element", func() -> float: return b.ident_ns(70, N))
	_report("Engine StringName copy constructor", func() -> float: return b.ident_ns(71, N))
	_report("Odin name_copy", func() -> float: return b.ident_ns(72, N))
	_report("Engine Array.get call, a String element", func() -> float: return b.ident_ns(73, N))
	_report("Odin array_get, a String element", func() -> float: return b.ident_ns(74, N))
	_report("Engine String copy constructor", func() -> float: return b.ident_ns(75, N))
	_report("Odin string_copy", func() -> float: return b.ident_ns(76, N))
	_report("Engine STRING_NAME Variant constructor", func() -> float: return b.ident_ns(77, N))
	_report("Odin variant of a StringName", func() -> float: return b.ident_ns(78, N))
	_report("Engine STRING Variant constructor", func() -> float: return b.ident_ns(79, N))
	_report("Odin variant of a String", func() -> float: return b.ident_ns(80, N))
	_report("Odin string to Variant, as before", func() -> float: return b.ident_ns(81, N))
	_report("Odin variant of an Odin string", func() -> float: return b.ident_ns(82, N))
	_report("Engine PackedByteArray.decode_u32 call", func() -> float: return b.ident_ns(83, N))
	_report("Odin packed_byte_array_decode_u32", func() -> float: return b.ident_ns(84, N))
	_report("Engine PackedByteArray.decode_half call", func() -> float: return b.ident_ns(85, N))
	_report("Odin packed_byte_array_decode_half", func() -> float: return b.ident_ns(86, N))
	_report("Engine String.unicode_at call", func() -> float: return b.ident_ns(87, N))
	_report("Odin string_unicode_at", func() -> float: return b.ident_ns(88, N))
	_report("Engine String.hex_to_int call", func() -> float: return b.ident_ns(89, N))
	_report("Odin string_hex_to_int", func() -> float: return b.ident_ns(90, N))
	_report("Engine String.hash call", func() -> float: return b.ident_ns(91, N))
	_report("Odin string_hash", func() -> float: return b.ident_ns(92, N))
	_report("Engine String.is_valid_filename call", func() -> float: return b.ident_ns(93, N))
	_report("Odin string_is_valid_filename", func() -> float: return b.ident_ns(94, N))
	_report("Engine Array.is_typed call", func() -> float: return b.ident_ns(95, N))
	_report("Odin array_is_typed", func() -> float: return b.ident_ns(96, N))
	_report("Engine String.is_valid_html_color call", func() -> float: return b.ident_ns(97, N))
	_report("Odin string_is_valid_html_color", func() -> float: return b.ident_ns(98, N))
	_report("Engine String.is_valid_ip_address call", func() -> float: return b.ident_ns(99, N))
	_report("Odin string_is_valid_ip_address", func() -> float: return b.ident_ns(100, N))
	_report("Engine Array.is_same_typed call", func() -> float: return b.ident_ns(101, N))
	_report("Odin array_is_same_typed", func() -> float: return b.ident_ns(102, N))
	_report("Engine Dictionary.is_same_typed call", func() -> float: return b.ident_ns(103, N))
	_report("Odin dictionary_is_same_typed", func() -> float: return b.ident_ns(104, N))
	_report("Engine Callable.is_null call", func() -> float: return b.ident_ns(105, N))
	_report("Odin callable_is_null", func() -> float: return b.ident_ns(106, N))
	_report("Engine Callable.get_object_id call", func() -> float: return b.ident_ns(107, N))
	_report("Odin callable_get_object_id", func() -> float: return b.ident_ns(108, N))
	_report("Engine Signal.is_null call", func() -> float: return b.ident_ns(109, N))
	_report("Odin signal_is_null", func() -> float: return b.ident_ns(110, N))
	_report("Engine PackedInt64Array.set call", func() -> float: return b.ident_ns(111, N))
	_report("Odin packed_int64_array_set", func() -> float: return b.ident_ns(112, N))
	_report("Engine PackedVector3Array.set call", func() -> float: return b.ident_ns(113, N))
	_report("Odin packed_vector3_array_set", func() -> float: return b.ident_ns(114, N))
	_report("Engine PackedByteArray.encode_u32 call", func() -> float: return b.ident_ns(115, N))
	_report("Odin packed_byte_array_encode_u32", func() -> float: return b.ident_ns(116, N))
	_report("Engine PackedByteArray.encode_half call", func() -> float: return b.ident_ns(117, N))
	_report("Odin packed_byte_array_encode_half", func() -> float: return b.ident_ns(118, N))
	_report("Engine PackedByteArray.bswap32 call", func() -> float: return b.ident_ns(119, N))
	_report("Odin packed_byte_array_bswap32", func() -> float: return b.ident_ns(120, N))
	_report("Engine PackedByteArray.bswap16_long call", func() -> float: return b.ident_ns(121, N / 100))
	_report("Odin packed_byte_array_bswap16_long", func() -> float: return b.ident_ns(122, N / 100))
	_report("Engine String.get_slice_count call", func() -> float: return b.ident_ns(123, N))
	_report("Odin string_get_slice_count", func() -> float: return b.ident_ns(124, N))
	_report("Engine String.match call", func() -> float: return b.ident_ns(125, N))
	_report("Odin string_match", func() -> float: return b.ident_ns(126, N))
	_report("Engine String.matchn call", func() -> float: return b.ident_ns(127, N))
	_report("Odin string_matchn", func() -> float: return b.ident_ns(128, N))
	_report("Engine String.is_subsequence_of call", func() -> float: return b.ident_ns(129, N))
	_report("Odin string_is_subsequence_of", func() -> float: return b.ident_ns(130, N))
	_report("Engine String.is_subsequence_ofn call", func() -> float: return b.ident_ns(131, N))
	_report("Odin string_is_subsequence_ofn", func() -> float: return b.ident_ns(132, N))
	_report("Engine PackedInt64Array.fill call", func() -> float: return b.ident_ns(133, N))
	_report("Odin packed_int64_array_fill", func() -> float: return b.ident_ns(134, N))
	_report("Engine PackedInt64Array.reverse call", func() -> float: return b.ident_ns(135, N))
	_report("Odin packed_int64_array_reverse", func() -> float: return b.ident_ns(136, N))
	_report("Engine PackedByteArray.fill call", func() -> float: return b.ident_ns(137, N))
	_report("Odin packed_byte_array_fill", func() -> float: return b.ident_ns(138, N))
	_report("Generated string_num_int64, made and destroyed", func() -> float: return b.ident_ns(43, N))
	_report("Odin string_of_int, made and destroyed", func() -> float: return b.ident_ns(44, N))
	_report("Generated string_num, made and destroyed", func() -> float: return b.ident_ns(45, N))
	_report("Odin string_of_float, made and destroyed", func() -> float: return b.ident_ns(46, N))
	_report("Engine Vector3.length call", func() -> float: return b.vector_ns(0, N))
	_report("Odin vector3_length", func() -> float: return b.vector_ns(1, N))
	_report("Engine Vector3.normalized call", func() -> float: return b.vector_ns(2, N))
	_report("Odin vector3_normalized", func() -> float: return b.vector_ns(3, N))
	_report("Engine Vector3.dot call", func() -> float: return b.vector_ns(4, N))
	_report("Odin vector3_dot", func() -> float: return b.vector_ns(5, N))
	_report("Engine Vector3.lerp call", func() -> float: return b.vector_ns(6, N))
	_report("Odin vector3_lerp", func() -> float: return b.vector_ns(7, N))
	_report("Engine Vector3i.length call", func() -> float: return b.vectori_ns(0, N))
	_report("Odin vector3i_length", func() -> float: return b.vectori_ns(1, N))
	_report("Engine Vector3i.distance_squared_to call", func() -> float: return b.vectori_ns(2, N))
	_report("Odin vector3i_distance_squared_to", func() -> float: return b.vectori_ns(3, N))
	_report("Engine Vector3i.snapped call", func() -> float: return b.vectori_ns(4, N))
	_report("Odin vector3i_snapped", func() -> float: return b.vectori_ns(5, N))
	_report("Engine Color.to_rgba32 call", func() -> float: return b.color_ns(0, N))
	_report("Odin color_to_rgba32", func() -> float: return b.color_ns(1, N))
	_report("Engine Color.lerp call", func() -> float: return b.color_ns(2, N))
	_report("Odin color_lerp", func() -> float: return b.color_ns(3, N))
	_report("Engine Color.linear_to_srgb call", func() -> float: return b.color_ns(4, N))
	_report("Odin color_linear_to_srgb", func() -> float: return b.color_ns(5, N))
	_report("Engine Color.from_hsv call", func() -> float: return b.color_ns(6, N))
	_report("Odin color_from_hsv", func() -> float: return b.color_ns(7, N))
	_report("Engine Color.to_html call", func() -> float: return b.color_ns(8, N))
	_report("Odin color_to_html", func() -> float: return b.color_ns(9, N))
	_report("Engine Color.from_string call", func() -> float: return b.color_ns(10, N))
	_report("Odin color_from_string", func() -> float: return b.color_ns(11, N))
	_report("Engine Color.from_ok_hsl call", func() -> float: return b.color_ns(12, N))
	_report("Odin color_from_ok_hsl", func() -> float: return b.color_ns(13, N))
	_report("Engine Basis.inverse call", func() -> float: return b.basis_ns(0, N))
	_report("Odin basis_inverse", func() -> float: return b.basis_ns(1, N))
	_report("Engine Basis.rotated call", func() -> float: return b.basis_ns(2, N))
	_report("Odin basis_rotated", func() -> float: return b.basis_ns(3, N))
	_report("Engine Basis.get_euler call", func() -> float: return b.basis_ns(4, N))
	_report("Odin basis_get_euler", func() -> float: return b.basis_ns(5, N))
	_report("Engine Basis.slerp call", func() -> float: return b.basis_ns(6, N))
	_report("Odin basis_slerp", func() -> float: return b.basis_ns(7, N))
	_report("Engine Transform2D.affine_inverse call", func() -> float: return b.transform_ns(0, N))
	_report("Odin transform2d_affine_inverse", func() -> float: return b.transform_ns(1, N))
	_report("Engine Transform2D.interpolate_with call", func() -> float: return b.transform_ns(2, N))
	_report("Odin transform2d_interpolate_with", func() -> float: return b.transform_ns(3, N))
	_report("Engine Transform3D.affine_inverse call", func() -> float: return b.transform_ns(4, N))
	_report("Odin transform3d_affine_inverse", func() -> float: return b.transform_ns(5, N))
	_report("Engine Transform3D.interpolate_with call", func() -> float: return b.transform_ns(6, N))
	_report("Odin transform3d_interpolate_with", func() -> float: return b.transform_ns(7, N))
	_report("Engine Quaternion.slerp call", func() -> float: return b.quaternion_ns(0, N))
	_report("Odin quaternion_slerp", func() -> float: return b.quaternion_ns(1, N))
	_report("Engine Quaternion.spherical_cubic_interpolate call", func() -> float: return b.quaternion_ns(2, N))
	_report("Odin quaternion_spherical_cubic_interpolate", func() -> float: return b.quaternion_ns(3, N))
	_report("Engine Quaternion.get_euler call", func() -> float: return b.quaternion_ns(4, N))
	_report("Odin quaternion_get_euler", func() -> float: return b.quaternion_ns(5, N))
	_report("Engine Quaternion.inverse call", func() -> float: return b.quaternion_ns(6, N))
	_report("Odin quaternion_inverse", func() -> float: return b.quaternion_ns(7, N))
	_report("Engine Quaternion.log call", func() -> float: return b.quaternion_ns(8, N))
	_report("Odin quaternion_log", func() -> float: return b.quaternion_ns(9, N))
	_report("Engine Quaternion.exp call", func() -> float: return b.quaternion_ns(10, N))
	_report("Odin quaternion_exp", func() -> float: return b.quaternion_ns(11, N))
	_report("Engine Quaternion.spherical_cubic_interpolate_in_time call", func() -> float: return b.quaternion_ns(12, N))
	_report("Odin quaternion_spherical_cubic_interpolate_in_time", func() -> float: return b.quaternion_ns(13, N))
	_report("Engine Plane.normalized call", func() -> float: return b.plane_ns(0, N))
	_report("Odin plane_normalized", func() -> float: return b.plane_ns(1, N))
	_report("Engine Plane.distance_to call", func() -> float: return b.plane_ns(2, N))
	_report("Odin plane_distance_to", func() -> float: return b.plane_ns(3, N))
	_report("Engine Plane.intersect_3 call", func() -> float: return b.plane_ns(4, N))
	_report("Odin plane_intersect_3", func() -> float: return b.plane_ns(5, N))
	_report("Engine Plane.intersects_ray call", func() -> float: return b.plane_ns(6, N))
	_report("Odin plane_intersects_ray", func() -> float: return b.plane_ns(7, N))
	_report("Engine AABB.merge call", func() -> float: return b.aabb_ns(0, N))
	_report("Odin aabb_merge", func() -> float: return b.aabb_ns(1, N))
	_report("Engine AABB.intersects call", func() -> float: return b.aabb_ns(2, N))
	_report("Odin aabb_intersects", func() -> float: return b.aabb_ns(3, N))
	_report("Engine AABB.intersects_plane call", func() -> float: return b.aabb_ns(4, N))
	_report("Odin aabb_intersects_plane", func() -> float: return b.aabb_ns(5, N))
	_report("Engine AABB.intersects_ray call", func() -> float: return b.aabb_ns(6, N))
	_report("Odin aabb_intersects_ray", func() -> float: return b.aabb_ns(7, N))
	_report("Engine Rect2.has_point call", func() -> float: return b.rect2_ns(0, N))
	_report("Odin rect2_has_point", func() -> float: return b.rect2_ns(1, N))
	_report("Engine Rect2.intersection call", func() -> float: return b.rect2_ns(2, N))
	_report("Odin rect2_intersection", func() -> float: return b.rect2_ns(3, N))
	_report("Engine Rect2.merge call", func() -> float: return b.rect2_ns(4, N))
	_report("Odin rect2_merge", func() -> float: return b.rect2_ns(5, N))
	_report("Engine Rect2i.intersection call", func() -> float: return b.rect2_ns(6, N))
	_report("Odin rect2i_intersection", func() -> float: return b.rect2_ns(7, N))
	_report("Engine Projection.inverse call", func() -> float: return b.projection_ns(0, N))
	_report("Odin projection_inverse", func() -> float: return b.projection_ns(1, N))
	_report("Engine Projection.determinant call", func() -> float: return b.projection_ns(2, N))
	_report("Odin projection_determinant", func() -> float: return b.projection_ns(3, N))
	_report("Engine Projection.get_projection_plane call", func() -> float: return b.projection_ns(4, N))
	_report("Odin projection_get_projection_plane", func() -> float: return b.projection_ns(5, N))
	_report("Engine Projection.create_perspective call", func() -> float: return b.projection_ns(6, N))
	_report("Odin projection_create_perspective", func() -> float: return b.projection_ns(7, N))
	_report("Engine PackedInt64Array.size call", func() -> float: return b.packed_ns(0, N))
	_report("Odin packed_int64_array_size", func() -> float: return b.packed_ns(1, N))
	_report("Engine PackedInt64Array.get call", func() -> float: return b.packed_ns(2, N))
	_report("Odin packed_int64_array_get", func() -> float: return b.packed_ns(3, N))
	_report("Engine PackedInt64Array.find call", func() -> float: return b.packed_ns(4, N))
	_report("Odin packed_int64_array_find", func() -> float: return b.packed_ns(5, N))
	_report("Engine PackedStringArray.find call", func() -> float: return b.packed_ns(6, N))
	_report("Odin packed_string_array_find", func() -> float: return b.packed_ns(7, N))
	_report("Engine Array.size call", func() -> float: return b.array_ns(0, N))
	_report("Odin array_size", func() -> float: return b.array_ns(1, N))
	_report("Engine Array.get call", func() -> float: return b.array_ns(2, N))
	_report("Odin array_get", func() -> float: return b.array_ns(3, N))
	_report("Engine Array.find call on ints", func() -> float: return b.array_ns(4, N))
	_report("Odin array_find on ints", func() -> float: return b.array_ns(5, N))
	_report("Engine Array.find call on Strings", func() -> float: return b.array_ns(6, N))
	_report("Odin array_find on Strings", func() -> float: return b.array_ns(7, N))
	_report("Engine Array.set call", func() -> float: return b.array_ns(8, N))
	_report("Odin array_set", func() -> float: return b.array_ns(9, N))
	_report("Engine Array.set call, a String then an int", func() -> float: return b.array_ns(10, N))
	_report("Odin array_set, a String then an int", func() -> float: return b.array_ns(11, N))
	_report("Engine Array.set call, a StringName then an int", func() -> float: return b.array_ns(12, N))
	_report("Odin array_set, a StringName then an int", func() -> float: return b.array_ns(13, N))
	_report("Engine Array.fill call", func() -> float: return b.array_ns(14, N / 10))
	_report("Odin array_fill", func() -> float: return b.array_ns(15, N / 10))
	_report("Engine Array.fill call, a String last", func() -> float: return b.array_ns(16, N / 10))
	_report("Odin array_fill, a String last", func() -> float: return b.array_ns(17, N / 10))
	_report("Engine Array.reverse call", func() -> float: return b.array_ns(18, N / 10))
	_report("Odin array_reverse", func() -> float: return b.array_ns(19, N / 10))
	_report("Engine Dictionary.size call", func() -> float: return b.dict_ns(0, N))
	_report("Odin dictionary_size", func() -> float: return b.dict_ns(1, N))
	_report("Engine Dictionary.has call on ints", func() -> float: return b.dict_ns(2, N))
	_report("Odin dictionary_has on ints", func() -> float: return b.dict_ns(3, N))
	_report("Engine Dictionary.get call on ints", func() -> float: return b.dict_ns(4, N))
	_report("Odin dictionary_get on ints", func() -> float: return b.dict_ns(5, N))
	_report("Engine Dictionary.has call on Strings", func() -> float: return b.dict_ns(6, N))
	_report("Odin dictionary_has on Strings", func() -> float: return b.dict_ns(7, N))
	_report("Engine Dictionary.keys call, 64 ints", func() -> float: return b.dict_ns(8, N / 10))
	_report("Odin dictionary_keys, 64 ints", func() -> float: return b.dict_ns(9, N / 10))
	_report("Engine Dictionary.values call, 64 ints", func() -> float: return b.dict_ns(10, N / 10))
	_report("Odin dictionary_values, 64 ints", func() -> float: return b.dict_ns(11, N / 10))
	_report("Engine Dictionary.find_key call, 41st of 64", func() -> float: return b.dict_ns(12, N))
	_report("Odin dictionary_find_key, 41st of 64", func() -> float: return b.dict_ns(13, N))
	_report("Engine Dictionary.set call", func() -> float: return b.dict_ns(14, N))
	_report("Odin dictionary_set", func() -> float: return b.dict_ns(15, N))
	_report("Engine Dictionary.get_or_add call", func() -> float: return b.dict_ns(16, N))
	_report("Odin dictionary_get_or_add", func() -> float: return b.dict_ns(17, N))
	_report("GDScript -> Odin, typed, String param", func() -> float: return _string_param(b, false))
	_report("GDScript -> Odin, typed, string param", func() -> float: return _string_param(b, true))
	var table: Dictionary = {}
	for i in 1000:
		table["key %d" % i] = i
	_report("Odin sum Dictionary values, keys() + get(), per entry", func() -> float: return b.dict_iter_ns(table, false, N / 1000))
	_report("Odin sum Dictionary values, dict_items, per entry", func() -> float: return b.dict_iter_ns(table, true, N / 1000))
	_report("Odin fill Image, set_pixel(), per pixel", func() -> float: return b.image_fill_ns(false, N / 4096))
	_report("Odin fill Image, image_write, per pixel", func() -> float: return b.image_fill_ns(true, N / 4096))
	var data := PackedByteArray()
	data.resize(1 << 20)
	var fw: FileAccess = FileAccess.open("user://bench_read.bin", FileAccess.WRITE)
	fw.store_buffer(data)
	fw.close()
	_report("Odin read file, get_buffer(), per 4 KiB", func() -> float: return b.file_read_ns("user://bench_read.bin", false, N / 100000))
	_report("Odin read file, file_read, per 4 KiB", func() -> float: return b.file_read_ns("user://bench_read.bin", true, N / 100000))
	_report("Odin run_task + wait_task, per task", func() -> float: return b.task_ns(N / 1000))
	_report("GDScript add_task + wait, per task (Callable)", func() -> float: return _gd_tasks())
	_report("Odin run_group of 1024 + wait, per call", func() -> float: return b.group_item_ns(N / 10000))
	_report("GDScript add_group_task of 1024 + wait, per call", func() -> float: return _gd_groups())
	var bump: Callable = func(x: int) -> int: return x + 1
	_report("Odin -> Callable.call (GDScript lambda)", func() -> float: return b.callable_call_ns(bump, N))
	_report("GDScript -> Callable.call (same lambda)", func() -> float: return _callable_calls(bump))
	_report("Odin emit, 1 arg, no connections", func() -> float: return b.emit_ns(N))
	_report("GDScript emit (same signal)", func() -> float: return _emits(b))
	_report("GDScript -> Odin field get, typed", func() -> float: return _field_get(b))
	_report("GDScript -> Odin field set, typed", func() -> float: return _field_set(b))
	var timer: Timer = Timer.new()
	_report("GDScript -> engine property get, typed", func() -> float: return _prop_get(timer))
	_report("GDScript -> engine property set, typed", func() -> float: return _prop_set(timer))
	timer.free()
	_report("GDScript Bench.new() + release", func() -> float: return _new_bench())
	_report("GDScript RefCounted.new() + release", func() -> float: return _new_refcounted())
	_report("GDScript -> Callable.call (Odin proc)", func() -> float: return _callable_calls(b.odin_callable()))
	_report("GDScript -> Callable.call (Odin proc, no args)", func() -> float: return _plain_callable_calls(b.odin_callable_plain()))
	_report("GDScript -> Callable.call (GDScript lambda, no args)", func() -> float: return _plain_callable_calls(func() -> void: pass))
	var plain: Node = Node.new()
	var odin: Node = BenchTicker.new()
	var gd: Node = GdTicker.new()
	_report("Node._process, no override (baseline)", func() -> float: return _process_calls(plain))
	_report("Node._process, Odin override", func() -> float: return _process_calls(odin))
	_report("Node._process, GDScript override", func() -> float: return _process_calls(gd))
	# Every other replaced method, from tools/bench_gen.py.
	for i in b.replaced_count():
		_report("Engine %s call" % b.replaced_label(i, true), func() -> float: return b.replaced_ns(i, true, N))
		_report("Odin %s" % b.replaced_label(i, false), func() -> float: return b.replaced_ns(i, false, N))
	plain.free()
	odin.free()
	gd.free()
	quit(0)


func _report(label: String, run: Callable) -> void:
	var best: float = INF
	for i in ROUNDS:
		best = minf(best, run.call())
	print("%-52s %8.2f ns" % [label, best])


func _typed(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.add(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _typed3(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.add3(i, i, i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _untyped(u: Variant) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		u.add(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _untyped3(u: Variant) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		u.add3(i, i, i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


# An engine method of the same shape (one float in, one float out), for the cost the engine's
# own call machinery adds before any binding runs.
func _native(c: Curve) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		c.sample_baked(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _native_untyped(u: Variant) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		u.sample_baked(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _empty() -> float:
	var t: int = Time.get_ticks_usec()
	var s: int = 0
	for i in N:
		s += i
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


# One NOTIFICATION_PROCESS reaches `_process` through the engine's virtual call, as a frame does.
func _process_calls(n: Node) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		n.notification(Node.NOTIFICATION_PROCESS)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _callable_calls(f: Callable) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		f.call(1)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _plain_callable_calls(f: Callable) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		f.call()
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


# Queues one empty task on the pool and waits for it, N / 1000 times.
func _gd_tasks() -> float:
	var f: Callable = func() -> void: pass
	var t: int = Time.get_ticks_usec()
	for i in N / 1000:
		WorkerThreadPool.wait_for_task_completion(WorkerThreadPool.add_task(f))
	return float(Time.get_ticks_usec() - t) * 1000.0 / (N / 1000)


# Queues a 1024-call group of empty calls and waits for it, N / 10000 times.
func _gd_groups() -> float:
	var f: Callable = func(_i: int) -> void: pass
	var t: int = Time.get_ticks_usec()
	for i in N / 10000:
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(f, 1024))
	return float(Time.get_ticks_usec() - t) * 1000.0 / (N / 10000 * 1024)


func _emits(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.ping.emit(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _field_get(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	var s: float = 0.0
	for i in N:
		s += b.rate
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _field_set(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.rate = 1.5
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _prop_get(timer: Timer) -> float:
	var t: int = Time.get_ticks_usec()
	var s: float = 0.0
	for i in N:
		s += timer.wait_time
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _prop_set(timer: Timer) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		timer.wait_time = 1.5
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _new_bench() -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		var x: Bench = Bench.new()
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _new_refcounted() -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		var x: RefCounted = RefCounted.new()
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _string_param(b: Bench, odin_text: bool) -> float:
	var s: String = "player_jump"
	var sum: int = 0
	var t: int = Time.get_ticks_usec()
	if odin_text:
		for i in N:
			sum += b.text_len(s)
	else:
		for i in N:
			sum += b.string_len(s)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N
