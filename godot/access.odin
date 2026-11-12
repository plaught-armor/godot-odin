// Direct access to engine storage: packed arrays, Strings, Arrays, Images and files read and written
// through the pointers the interface hands out, instead of one builtin or method call per element.
package godot

import "base:intrinsics"
import "base:runtime"
import "core:unicode/utf8"
import gde "../gdextension"

// The elements of packed array `a` as a slice over its storage, for reading in place. It stays valid
// until `a` is written, resized or destroyed. Do not write through it: the storage may be shared
// with copies of `a`. Use `packed_write` for that.
packed_read :: proc {
	packed_read_byte, packed_read_int32, packed_read_int64, packed_read_float32, packed_read_float64,
	packed_read_string, packed_read_vector2, packed_read_vector3, packed_read_vector4, packed_read_color,
}

// The elements of packed array `a` as a writable slice. The first call on a shared array gives `a`
// storage of its own, as any write does; the slice stays valid until `a` is copied, resized or
// destroyed. `a` must be an array you own, not a borrowed parameter.
packed_write :: proc {
	packed_write_byte, packed_write_int32, packed_write_int64, packed_write_float32, packed_write_float64,
	packed_write_string, packed_write_vector2, packed_write_vector3, packed_write_vector4, packed_write_color,
}

packed_read_byte :: proc "contextless" (a: ^PackedByteArray) -> []u8 { return packed_slice(u8, a, packed_byte_array_size(a), gde.packed_byte_array_operator_index_const) }
packed_read_int32 :: proc "contextless" (a: ^PackedInt32Array) -> []i32 { return packed_slice(i32, a, packed_int32_array_size(a), gde.packed_int32_array_operator_index_const) }
packed_read_int64 :: proc "contextless" (a: ^PackedInt64Array) -> []i64 { return packed_slice(i64, a, packed_int64_array_size(a), gde.packed_int64_array_operator_index_const) }
packed_read_float32 :: proc "contextless" (a: ^PackedFloat32Array) -> []f32 { return packed_slice(f32, a, packed_float32_array_size(a), gde.packed_float32_array_operator_index_const) }
packed_read_float64 :: proc "contextless" (a: ^PackedFloat64Array) -> []f64 { return packed_slice(f64, a, packed_float64_array_size(a), gde.packed_float64_array_operator_index_const) }
packed_read_string :: proc "contextless" (a: ^PackedStringArray) -> []String { return packed_slice(String, a, packed_string_array_size(a), gde.packed_string_array_operator_index_const) }
packed_read_vector2 :: proc "contextless" (a: ^PackedVector2Array) -> []Vector2 { return packed_slice(Vector2, a, packed_vector2_array_size(a), gde.packed_vector2_array_operator_index_const) }
packed_read_vector3 :: proc "contextless" (a: ^PackedVector3Array) -> []Vector3 { return packed_slice(Vector3, a, packed_vector3_array_size(a), gde.packed_vector3_array_operator_index_const) }
packed_read_vector4 :: proc "contextless" (a: ^PackedVector4Array) -> []Vector4 { return packed_slice(Vector4, a, packed_vector4_array_size(a), gde.packed_vector4_array_operator_index_const) }
packed_read_color :: proc "contextless" (a: ^PackedColorArray) -> []Color { return packed_slice(Color, a, packed_color_array_size(a), gde.packed_color_array_operator_index_const) }

packed_write_byte :: proc "contextless" (a: ^PackedByteArray) -> []u8 { return packed_slice(u8, a, packed_byte_array_size(a), gde.packed_byte_array_operator_index) }
packed_write_int32 :: proc "contextless" (a: ^PackedInt32Array) -> []i32 { return packed_slice(i32, a, packed_int32_array_size(a), gde.packed_int32_array_operator_index) }
packed_write_int64 :: proc "contextless" (a: ^PackedInt64Array) -> []i64 { return packed_slice(i64, a, packed_int64_array_size(a), gde.packed_int64_array_operator_index) }
packed_write_float32 :: proc "contextless" (a: ^PackedFloat32Array) -> []f32 { return packed_slice(f32, a, packed_float32_array_size(a), gde.packed_float32_array_operator_index) }
packed_write_float64 :: proc "contextless" (a: ^PackedFloat64Array) -> []f64 { return packed_slice(f64, a, packed_float64_array_size(a), gde.packed_float64_array_operator_index) }
packed_write_string :: proc "contextless" (a: ^PackedStringArray) -> []String { return packed_slice(String, a, packed_string_array_size(a), gde.packed_string_array_operator_index) }
packed_write_vector2 :: proc "contextless" (a: ^PackedVector2Array) -> []Vector2 { return packed_slice(Vector2, a, packed_vector2_array_size(a), gde.packed_vector2_array_operator_index) }
packed_write_vector3 :: proc "contextless" (a: ^PackedVector3Array) -> []Vector3 { return packed_slice(Vector3, a, packed_vector3_array_size(a), gde.packed_vector3_array_operator_index) }
packed_write_vector4 :: proc "contextless" (a: ^PackedVector4Array) -> []Vector4 { return packed_slice(Vector4, a, packed_vector4_array_size(a), gde.packed_vector4_array_operator_index) }
packed_write_color :: proc "contextless" (a: ^PackedColorArray) -> []Color { return packed_slice(Color, a, packed_color_array_size(a), gde.packed_color_array_operator_index) }

// `n` elements of `E` from the first one `at` finds in `a`. An empty array gives nil without asking
// `at`, which reports an error for index 0 of an empty array.
@(private)
packed_slice :: #force_inline proc "contextless" ($E: typeid, a: rawptr, n: i64, at: proc "c" (rawptr, gde.Int) -> $R) -> []E {
	if n <= 0 { return nil }
	return ([^]E)(rawptr(at(a, 0)))[:n]
}

// A new packed array holding a copy of `xs`, which the caller destroys or returns. A String element
// is copied as a new reference; the others are copied as bytes.
packed_of :: proc {
	packed_of_byte, packed_of_int32, packed_of_int64, packed_of_float32, packed_of_float64,
	packed_of_string, packed_of_vector2, packed_of_vector3, packed_of_vector4, packed_of_color,
}

packed_of_byte :: proc "contextless" (xs: []u8) -> (out: PackedByteArray) { out = packed_byte_array_new(); packed_fill(&out, xs, packed_byte_array_resize, packed_write_byte); return }
packed_of_int32 :: proc "contextless" (xs: []i32) -> (out: PackedInt32Array) { out = packed_int32_array_new(); packed_fill(&out, xs, packed_int32_array_resize, packed_write_int32); return }
packed_of_int64 :: proc "contextless" (xs: []i64) -> (out: PackedInt64Array) { out = packed_int64_array_new(); packed_fill(&out, xs, packed_int64_array_resize, packed_write_int64); return }
packed_of_float32 :: proc "contextless" (xs: []f32) -> (out: PackedFloat32Array) { out = packed_float32_array_new(); packed_fill(&out, xs, packed_float32_array_resize, packed_write_float32); return }
packed_of_float64 :: proc "contextless" (xs: []f64) -> (out: PackedFloat64Array) { out = packed_float64_array_new(); packed_fill(&out, xs, packed_float64_array_resize, packed_write_float64); return }
packed_of_vector2 :: proc "contextless" (xs: []Vector2) -> (out: PackedVector2Array) { out = packed_vector2_array_new(); packed_fill(&out, xs, packed_vector2_array_resize, packed_write_vector2); return }
packed_of_vector3 :: proc "contextless" (xs: []Vector3) -> (out: PackedVector3Array) { out = packed_vector3_array_new(); packed_fill(&out, xs, packed_vector3_array_resize, packed_write_vector3); return }
packed_of_vector4 :: proc "contextless" (xs: []Vector4) -> (out: PackedVector4Array) { out = packed_vector4_array_new(); packed_fill(&out, xs, packed_vector4_array_resize, packed_write_vector4); return }
packed_of_color :: proc "contextless" (xs: []Color) -> (out: PackedColorArray) { out = packed_color_array_new(); packed_fill(&out, xs, packed_color_array_resize, packed_write_color); return }

packed_of_string :: proc "contextless" (xs: []String) -> (out: PackedStringArray) {
	out = packed_string_array_new()
	packed_string_array_resize(&out, i64(len(xs)))
	// Each new slot is an empty String, which holds nothing to release before it is overwritten.
	for &s, i in packed_write_string(&out) { s = string_new_from_string(xs[i]) }
	return
}

// Sizes `out` to `xs` and copies `xs` into it as bytes.
@(private)
packed_fill :: #force_inline proc "contextless" (out: ^$A, xs: []$E, resize: proc "contextless" (^A, i64) -> i64, write: proc "contextless" (^A) -> []E) {
	resize(out, i64(len(xs)))
	copy(write(out), xs)
}

// The characters of `s` as a slice over its storage, read in place. It stays valid until `s` is
// written or destroyed. Do not write through it: the storage may be shared with copies of `s`.
string_read :: proc "contextless" (s: ^String) -> []rune {
	if string_layout_known {
		// Read from the storage, as `check_string_layout` proved it: no engine call.
		n := string_stored_length(s)
		if n <= 0 { return nil }
		return (^[^]rune)(s)^[:n]
	}
	n := string_length(s)
	if n <= 0 { return nil }
	return gde.string_operator_index_const(s, 0)[:n]
}

// Whether `a` and `b` hold the same characters. Copies share storage, so they answer without a
// read, and Strings of different lengths answer from their headers; only Strings of one length
// compare their characters.
string_equal :: proc "contextless" (a, b: ^String) -> bool {
	if string_layout_known {
		pa, pb := (^rawptr)(a)^, (^rawptr)(b)^
		if pa == pb { return true }
		n := string_stored_length(a)
		if n != string_stored_length(b) { return false }
		return runes_equal((^[^]rune)(a)^, (^[^]rune)(b)^, int(n))
	}
	@(static) eq: gde.PtrOperatorEvaluator
	if eq == nil { eq = gde.variant_get_ptr_operator_evaluator(.EQUAL, .STRING, .STRING) }
	r: u8
	eq(a, b, &r)
	return r != 0
}

// Whether the `n` characters at `a` and `b` match, four at a time: inlined, as a short String's
// compare costs less than a call to a general one.
@(private)
runes_equal :: #force_inline proc "contextless" (a, b: [^]rune, n: int) -> bool {
	i := 0
	for ; i + 4 <= n; i += 4 {
		x := intrinsics.unaligned_load((^#simd[4]u32)(&a[i]))
		y := intrinsics.unaligned_load((^#simd[4]u32)(&b[i]))
		if intrinsics.simd_reduce_or(intrinsics.simd_lanes_ne(x, y)) != 0 { return false }
	}
	for ; i < n; i += 1 {
		if a[i] != b[i] { return false }
	}
	return true
}

// Whether `s` holds the characters of Odin text `text`, compared in place: no String is made.
// Every character takes one to four bytes of UTF-8, so a length outside that range answers at once.
// Invalid UTF-8 in `text` reads as U+FFFD, as it does when made into a String.
string_equal_text :: proc "contextless" (s: ^String, text: string) -> bool {
	chars := string_read(s)
	if len(chars) > len(text) || len(chars) * 4 < len(text) { return false }
	// One byte per character: only ASCII text can match.
	if len(chars) == len(text) { return ascii_matches(chars, text) }
	n, ok := text_prefix_of(chars, text)
	return ok && n == len(chars)
}

// Whether `s` starts with the characters of Odin text `text`, compared in place: no String is made.
// Invalid UTF-8 in `text` reads as U+FFFD.
string_begins_with_text :: proc "contextless" (s: ^String, text: string) -> bool {
	chars := string_read(s)
	if text_is_ascii(text) { return len(text) <= len(chars) && ascii_matches(chars[:len(text)], text) }
	_, ok := text_prefix_of(chars, text)
	return ok
}

// Whether `s` ends with the characters of Odin text `text`, compared in place: no String is made.
// Invalid UTF-8 in `text` reads as U+FFFD.
string_ends_with_text :: proc "contextless" (s: ^String, text: string) -> bool {
	chars := string_read(s)
	if text_is_ascii(text) {
		return len(text) <= len(chars) && ascii_matches(chars[len(chars) - len(text):], text)
	}
	k := text_rune_count(text)
	if k > len(chars) { return false }
	_, ok := text_prefix_of(chars[len(chars) - k:], text)
	return ok
}

// `string_begins_with_text` ignoring case. The engine has no such method; this lowers each
// character as `findn` does, so it is `s.to_lower().begins_with(text.to_lower())` with no String
// made.
string_begins_with_text_nocase :: proc "contextless" (s: ^String, text: string) -> bool {
	chars := string_read(s)
	ascii := text_is_ascii(text)
	k := len(text) if ascii else text_rune_count(text)
	return k <= len(chars) && window_nocase(chars[:k], text, ascii)
}

// `string_ends_with_text` ignoring case, lowering as `string_begins_with_text_nocase` does.
string_ends_with_text_nocase :: proc "contextless" (s: ^String, text: string) -> bool {
	chars := string_read(s)
	ascii := text_is_ascii(text)
	k := len(text) if ascii else text_rune_count(text)
	return k <= len(chars) && window_nocase(chars[len(chars) - k:], text, ascii)
}

// Whether `window`, as many characters as `text` holds, is `text` with each character lowered
// through the engine's case table. `ascii` says `text` is all ASCII.
@(private)
window_nocase :: #force_inline proc "contextless" (window: []rune, text: string, ascii: bool) -> bool {
	if ascii {
		if equal, plain := ascii_nocase_matches(window, text); plain { return equal }
	}
	_, ok := fold_prefix_of(window, text, false)
	return ok
}

// Where Odin text `text` first appears in `s` at or after character `from`, in characters, or -1:
// the engine's `find`, compared in place with no String made. As there, a negative `from` counts
// back from the last place `text` fits, -1 being that place, and empty text gives -1. Finds each
// place `text`'s first character appears, and compares the rest there.
string_find_text :: proc "contextless" (s: ^String, text: string, from: i64 = 0) -> i64 {
	chars := string_read(s)
	n := needle_of(text, false)
	start, last, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_forward(chars, start, last, n, false)
}

// Where Odin text `text` last appears in `s` at or before character `from`, in characters, or -1:
// the engine's `rfind`, compared in place. `from` reads as in `string_find_text`, so the default
// -1 searches from the last place `text` fits, and a `from` past that place gives -1.
string_rfind_text :: proc "contextless" (s: ^String, text: string, from: i64 = -1) -> i64 {
	chars := string_read(s)
	n := needle_of(text, false)
	start, _, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_backward(chars, start, n, false)
}

// `string_find_text` ignoring case: the engine's `findn`, which lowers each character of both
// through the engine's Unicode case table before comparing.
string_findn_text :: proc "contextless" (s: ^String, text: string, from: i64 = 0) -> i64 {
	chars := string_read(s)
	n := needle_of(text, true)
	start, last, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_forward(chars, start, last, n, true)
}

// `string_rfind_text` ignoring case: the engine's `rfindn`.
string_rfindn_text :: proc "contextless" (s: ^String, text: string, from: i64 = -1) -> i64 {
	chars := string_read(s)
	n := needle_of(text, true)
	start, _, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_backward(chars, start, n, true)
}

// Whether Odin text `text` appears in `s` ignoring case: the engine's `containsn`.
string_containsn_text :: proc "contextless" (s: ^String, text: string) -> bool {
	return string_findn_text(s, text) >= 0
}

// Whether `s` holds Odin text `text` ignoring case: the engine's `nocasecmp_to(text) == 0`, which
// raises each character of both through the engine's Unicode case table before comparing. All
// ASCII on both sides compares with no branch per character.
string_equal_text_nocase :: proc "contextless" (s: ^String, text: string) -> bool {
	chars := string_read(s)
	if len(chars) > len(text) || len(chars) * 4 < len(text) { return false }
	if len(chars) == len(text) {
		if equal, plain := ascii_nocase_matches(chars, text); plain { return equal }
	}
	n, ok := fold_prefix_of(chars, text, true)
	return ok && n == len(chars)
}

// How many times Odin text `text` appears in `s` between characters `from` and `to`, not
// overlapping: the engine's `count`, compared in place. As there, `to` 0 means the end, a `to` past
// the end stops there, and empty text, a negative bound or `from` at or past `to` gives 0.
string_count_text :: proc "contextless" (s: ^String, text: string, from: i64 = 0, to: i64 = 0) -> i64 {
	return count_in(string_read(s), needle_of(text, false), from, to, false)
}

// `string_count_text` ignoring case: the engine's `countn`.
string_countn_text :: proc "contextless" (s: ^String, text: string, from: i64 = 0, to: i64 = 0) -> i64 {
	return count_in(string_read(s), needle_of(text, true), from, to, true)
}

// A copy of `s` with every `what` replaced by `forwhat`, both Odin text, left to right and not
// overlapping: the engine's `replace`. Matches are found in place and the result is written once
// into a String made at its final length. Empty `what`, or none found, gives a copy sharing `s`'s
// storage. The caller destroys the result.
string_replace_text :: proc "contextless" (s: ^String, what, forwhat: string) -> String {
	return replace_in(s, needle_of(what, false), forwhat, false)
}

// `string_replace_text` ignoring case: the engine's `replacen`.
string_replacen_text :: proc "contextless" (s: ^String, what, forwhat: string) -> String {
	return replace_in(s, needle_of(what, true), forwhat, true)
}

// Counts the matches first, so the result is sized once, then finds them again to fill it: the
// same search from the same places, so it meets the same `hits` matches.
@(private)
replace_in :: proc "contextless" (s: ^String, n: Needle, with: string, $NOCASE: bool) -> (out: String) {
	chars := string_read(s)
	hits := int(count_in(chars, n, 0, 0, NOCASE))
	if hits == 0 { return string_new_from_string(s^) }
	with_ascii := text_is_ascii(with)
	with_count := len(with) if with_ascii else text_rune_count(with)
	total := len(chars) + hits * (with_count - n.count)
	// A zeroed String is the engine's empty one: its storage pointer is null.
	if total == 0 { return }
	// The engine's resize counts the terminator, which it leaves for the caller to write.
	gde.string_resize(&out, gde.Int(total + 1))
	w := gde.string_operator_index(&out, 0)[:total + 1]
	j, start, last := 0, 0, len(chars) - n.count
	for _ in 0 ..< hits {
		at := int(find_forward(chars, start, last, n, NOCASE))
		j += copy(w[j:], chars[start:at])
		j += text_put(w[j:], with, with_ascii)
		start = at + n.count
	}
	j += copy(w[j:], chars[start:])
	w[total] = 0
	return
}

// The parts of `s` between each Odin text `delimiter`: the engine's `split`. Empty `delimiter` gives
// one part per character; `allow_empty` false drops empty parts; a positive `maxsplit` stops after
// that many parts and adds the rest of `s` as one more. The parts are counted first so the array is
// sized once, then each is made straight from its characters, with no String made for `delimiter`.
// The caller destroys the result.
string_split_text :: proc "contextless" (s: ^String, delimiter: string, allow_empty := true, maxsplit: i64 = 0) -> (out: PackedStringArray) {
	chars := string_read(s)
	n := needle_of(delimiter, false)
	out = packed_string_array_new()
	k := split_in(chars, n, allow_empty, maxsplit, nil)
	if k == 0 { return }
	packed_string_array_resize(&out, i64(k))
	split_in(chars, n, allow_empty, maxsplit, packed_write_string(&out))
	return
}

// Walks the parts of `chars` as the engine's `split` does and returns how many there are. With
// `out`, it also makes part `k` in `out[k]`, which must hold an empty String: the array's slots
// after a resize. Each round moves `from` on by at least one, so `len(chars) + 1` rounds cover it.
@(private)
split_in :: proc "contextless" (chars: []rune, n: Needle, allow_empty: bool, maxsplit: i64, out: []String) -> (k: int) {
	if len(chars) == 0 { return 1 if allow_empty else 0 }
	from, last := 0, len(chars) - n.count
	for _ in 0 ..= len(chars) {
		end := from + 1 if n.count == 0 else int(find_forward(chars, from, last, n, false))
		if end < 0 { end = len(chars) }
		if allow_empty || end > from {
			if maxsplit > 0 && i64(k) == maxsplit {
				part_put(out, k, chars[from:])
				k += 1
				break
			}
			part_put(out, k, chars[from:end])
			k += 1
		}
		if end == len(chars) { break }
		from = end + n.count
	}
	return
}

// Makes `out[k]` hold `part`, when there is an `out`. An empty part leaves the slot's empty String.
// The characters come from a String, so they are copied as they are, without the check a String
// made from outside characters gets: one resize and a copy.
@(private)
part_put :: #force_inline proc "contextless" (out: []String, k: int, part: []rune) {
	if out == nil || len(part) == 0 { return }
	string_fill(&out[k], part)
}

// Sizes the empty String `s` to `chars` and copies them in, with the terminator the engine's resize
// leaves for the caller. `s` must be a String you own with no other references.
@(private)
string_fill :: #force_inline proc "contextless" (s: ^String, chars: []rune) {
	gde.string_resize(s, gde.Int(len(chars) + 1))
	w := (^[^]rune)(s)^ if string_layout_known else gde.string_operator_index(s, 0)
	copy(w[:len(chars)], chars)
	w[len(chars)] = 0
}

// Writes the characters of `text` to the front of `dst`, decoded as `text_rune_count` counts them,
// and returns how many. `dst` must hold them.
@(private)
text_put :: #force_inline proc "contextless" (dst: []rune, text: string, ascii: bool) -> int {
	if ascii {
		for b, k in transmute([]u8)text { dst[k] = rune(b) }
		return len(text)
	}
	i, k := 0, 0
	for _ in 0 ..< len(text) {
		if i >= len(text) { break }
		r, w := utf8.decode_rune_in_string(text[i:])
		dst[k] = r
		i += w
		k += 1
	}
	return k
}

@(private)
count_in :: #force_inline proc "contextless" (chars: []rune, n: Needle, from, to: i64, $NOCASE: bool) -> (count: i64) {
	if n.count == 0 || from < 0 || to < 0 { return 0 }
	end := i64(len(chars)) if to == 0 else min(to, i64(len(chars)))
	if from >= end { return 0 }
	part := chars[from:end]
	last := len(part) - n.count
	start := 0
	// Each match moves `start` on by at least one, so `len(part) + 1` rounds cover it.
	for _ in 0 ..= len(part) {
		if start > last { break }
		at := find_forward(part, start, last, n, NOCASE)
		if at < 0 { break }
		count += 1
		start = int(at) + n.count
	}
	return
}

// The first place from `start` up to `last` where `n` appears in `chars`, or -1. Four places per
// step while none of them can hold `n`'s first character, then one at a time through a step that
// can. Every round moves `i` on, so `len(chars) + 1` rounds cover it.
@(private)
find_forward :: #force_inline proc "contextless" (chars: []rune, start, last: int, n: Needle, $NOCASE: bool) -> i64 {
	i := start
	for _ in 0 ..= len(chars) {
		if i > last { break }
		if i + 3 <= last {
			v := intrinsics.unaligned_load((^#simd[4]u32)(&chars[i]))
			if !may_hold_first(v, n, NOCASE) {
				i += 4
				continue
			}
		}
		if needle_at(chars, i, n, NOCASE) { return i64(i) }
		i += 1
	}
	return -1
}

// As `find_forward`, walking down from `start` to 0: four places ending at `i` per step.
@(private)
find_backward :: #force_inline proc "contextless" (chars: []rune, start: int, n: Needle, $NOCASE: bool) -> i64 {
	i := start
	for _ in 0 ..= len(chars) {
		if i < 0 { break }
		if i >= 3 {
			v := intrinsics.unaligned_load((^#simd[4]u32)(&chars[i - 3]))
			if !may_hold_first(v, n, NOCASE) {
				i -= 4
				continue
			}
		}
		if needle_at(chars, i, n, NOCASE) { return i64(i) }
		i -= 1
	}
	return -1
}

// Whether any of four characters may be `n`'s first. Ignoring case, an ASCII letter matches with
// bit 5 set, and any non-ASCII character may lower to it.
@(private)
may_hold_first :: #force_inline proc "contextless" (v: #simd[4]u32, n: Needle, $NOCASE: bool) -> bool {
	f := u32(n.first)
	firsts := #simd[4]u32{f, f, f, f}
	when NOCASE {
		m := n.fold_bit
		hit := intrinsics.simd_lanes_eq(intrinsics.simd_bit_or(v, #simd[4]u32{m, m, m, m}), firsts)
		wide := intrinsics.simd_lanes_ge(v, #simd[4]u32{0x80, 0x80, 0x80, 0x80})
		return intrinsics.simd_reduce_or(intrinsics.simd_bit_or(hit, wide)) != 0
	} else {
		return intrinsics.simd_reduce_or(intrinsics.simd_lanes_eq(v, firsts)) != 0
	}
}

// Text searched for by the find procs, with its length in characters and its first character,
// lowered when the search ignores case. `fold_bit` is 0x20 when that character is an ASCII letter.
@(private)
Needle :: struct {
	text:     string,
	ascii:    bool,
	count:    int,
	first:    rune,
	fold_bit: u32,
}

@(private)
needle_of :: #force_inline proc "contextless" (text: string, $NOCASE: bool) -> (n: Needle) {
	n.text = text
	if len(text) == 0 { return }
	n.ascii = text_is_ascii(text)
	if n.ascii {
		n.count, n.first = len(text), rune(text[0])
	} else {
		n.count = text_rune_count(text)
		n.first, _ = utf8.decode_rune_in_string(text)
	}
	when NOCASE {
		n.first = rune_lower(n.first)
		if n.first >= 'a' && n.first <= 'z' { n.fold_bit = 0x20 }
	}
	return
}

// The first place a search from `from` looks, and the last place `n` fits in `length` characters,
// by the engine's rules; not `ok` when `from` is out of range or `n` is empty.
@(private)
find_start :: #force_inline proc "contextless" (length: int, n: Needle, from: i64) -> (start, last: int, ok: bool) {
	if n.count == 0 { return }
	l := i64(length - n.count)
	f := from if from >= 0 else l + from + 1
	if f < 0 || f > l { return }
	return int(f), int(l), true
}

// Whether `n` appears at character `i` of `chars`, which it fits in.
@(private)
needle_at :: #force_inline proc "contextless" (chars: []rune, i: int, n: Needle, $NOCASE: bool) -> bool {
	window := chars[i:][:n.count]
	when NOCASE {
		if rune_lower(chars[i]) != n.first { return false }
		return window_nocase(window, n.text, n.ascii)
	} else {
		if chars[i] != n.first { return false }
		if n.ascii { return ascii_matches(window, n.text) }
		_, ok := text_prefix_of(window, n.text)
		return ok
	}
}

// Whether Odin text `text` appears in `s`, compared in place: `string_find_text` from the start.
string_contains_text :: proc "contextless" (s: ^String, text: string) -> bool {
	return string_find_text(s, text) >= 0
}

// A fixed set of names to match a String against, as `string_which` does. Each name has a key, its
// length in characters with its first and last characters, so a lookup compares one integer per
// name, and the characters of only the names whose key matches: names sharing a prefix, as
// "player_jump" and "player_walk" do, still differ in their last character.
Text_Set :: struct($N: int) {
	keys:  [N]u64,
	ascii: [N]bool,
	names: [N]string,
}

// The set of `names`, for `string_which`. Build it once and keep it: it holds `names` themselves,
// so they must outlive it (literals do).
text_set :: proc "contextless" (names: [$N]string) -> (set: Text_Set(N)) {
	set.names = names
	for name, i in names {
		first, last: rune
		if len(name) > 0 {
			first, _ = utf8.decode_rune_in_string(name)
			last, _ = utf8.decode_last_rune_in_string(name)
		}
		set.keys[i] = text_key(text_rune_count(name), first, last)
		set.ascii[i] = text_is_ascii(name)
	}
	return
}

// The index in `set` of the name `s` holds, the first one when names repeat; -1 when none.
string_which :: proc "contextless" (s: ^String, set: ^Text_Set($N)) -> int {
	chars := string_read(s)
	first, last: rune
	if len(chars) > 0 { first, last = chars[0], chars[len(chars) - 1] }
	key := text_key(len(chars), first, last)
	for k, i in set.keys {
		if k != key { continue }
		// The key matched, so an ASCII name is as long in bytes as `s` is in characters.
		if set.ascii[i] {
			if ascii_matches(chars, set.names[i]) { return i }
		} else if _, ok := text_prefix_of(chars, set.names[i]); ok {
			return i
		}
	}
	return -1
}

// A fixed set of StringNames to match a name against, as `name_which` does. The set holds its own
// reference to each name, released by `name_set_destroy`.
Name_Set :: struct($N: int) {
	names: [N]StringName,
}

// The set of `names`, for `name_which`; `name_set_destroy` releases it. About 31 ns a name to build.
name_set :: proc "contextless" (names: [$N]string) -> (set: Name_Set(N)) {
	for name, i in names { set.names[i] = name_of(name) }
	return
}

// Releases the names `set` holds.
name_set_destroy :: proc "contextless" (set: ^Name_Set($N)) {
	for &name in set.names { destroy[.STRING_NAME](&name) }
}

// The index in `set` of `name`, the first one when names repeat; -1 when none. Names are interned,
// so each compare is one integer.
name_which :: proc "contextless" (name: StringName, set: ^Name_Set($N)) -> int {
	for &n, i in set.names {
		if same_name(n, name) { return i }
	}
	return -1
}

// A name's key in a `Text_Set`: its length in characters, 22 bits of it, and its first and last
// characters, 21 bits each. Names with one key still compare in full.
@(private)
text_key :: #force_inline proc "contextless" (count: int, first, last: rune) -> u64 {
	return (u64(count) & (1 << 22 - 1)) << 42 | u64(u32(first)) << 21 | u64(u32(last))
}

// Whether every byte of `text` is ASCII: one pass with no branch per byte.
@(private)
text_is_ascii :: #force_inline proc "contextless" (text: string) -> bool {
	acc: u8
	for b in transmute([]u8)text { acc |= b }
	return acc < 0x80
}

// Whether `chars` are the bytes of `text`, one character per byte, all ASCII. A character past
// ASCII fails, so a lone invalid byte cannot match the character it encodes. No branch per
// character: `chars` is as long as `text`.
@(private)
ascii_matches :: #force_inline proc "contextless" (chars: []rune, text: string) -> bool {
	diff: rune
	for c, k in chars { diff |= (c ~ rune(text[k])) | (c & ~rune(0x7F)) }
	return diff == 0
}

// Whether `chars` starts with the characters of `text`, and how many of `chars` they cover. ASCII
// bytes compare as they are; the rest decode, an invalid byte as U+FFFD.
@(private)
text_prefix_of :: proc "contextless" (chars: []rune, text: string) -> (count: int, ok: bool) {
	i := 0
	for _ in 0 ..< len(text) {
		if i >= len(text) { break }
		if count >= len(chars) { return count, false }
		r, w := rune(text[i]), 1
		if text[i] >= 0x80 { r, w = utf8.decode_rune_in_string(text[i:]) }
		if chars[count] != r { return count, false }
		i += w
		count += 1
	}
	return count, true
}

// The characters in `text`, counted as `text_prefix_of` decodes them.
@(private)
text_rune_count :: proc "contextless" (text: string) -> (n: int) {
	i := 0
	for _ in 0 ..< len(text) {
		if i >= len(text) { break }
		w := 1
		if text[i] >= 0x80 { _, w = utf8.decode_rune_in_string(text[i:]) }
		i += w
		n += 1
	}
	return
}

// `chars` against the ASCII text `text` of the same length, ignoring ASCII case, four characters a
// step with no branch per character. `plain` is false when `chars` holds a non-ASCII character,
// which may fold to ASCII through the engine's table (U+0130 lowers to 'i'), so `equal` is no
// answer then.
@(private)
ascii_nocase_matches :: #force_inline proc "contextless" (chars: []rune, text: string) -> (equal, plain: bool) {
	bytes := ([^]u8)(raw_data(text))
	diff4, wide4: #simd[4]u32
	k := 0
	for _ in 0 ..< len(chars) / 4 {
		v := intrinsics.unaligned_load((^#simd[4]u32)(&chars[k]))
		t := #simd[4]u32{u32(bytes[k]), u32(bytes[k + 1]), u32(bytes[k + 2]), u32(bytes[k + 3])}
		wide4 |= v
		diff4 |= ascii_lower4(v) ~ ascii_lower4(t)
		k += 4
	}
	diff := intrinsics.simd_reduce_or(diff4)
	wide := intrinsics.simd_reduce_or(wide4)
	for c, j in chars[k:] {
		u := u32(c)
		wide |= u
		diff |= ascii_lower(u) ~ ascii_lower(u32(bytes[k + j]))
	}
	return diff == 0, wide < 0x80
}

// `ascii_lower` on four characters.
@(private)
ascii_lower4 :: #force_inline proc "contextless" (v: #simd[4]u32) -> #simd[4]u32 {
	caps := intrinsics.simd_lanes_lt(v - #simd[4]u32{'A', 'A', 'A', 'A'}, #simd[4]u32{26, 26, 26, 26})
	return v | (caps & #simd[4]u32{0x20, 0x20, 0x20, 0x20})
}

// `c` with an ASCII capital lowered, and anything else as it is.
@(private)
ascii_lower :: #force_inline proc "contextless" (c: u32) -> u32 {
	return c | u32(c - 'A' < 26) << 5
}

// As `text_prefix_of`, comparing each character raised (`UPPER`) or lowered through the engine's
// case tables.
@(private)
fold_prefix_of :: proc "contextless" (chars: []rune, text: string, $UPPER: bool) -> (count: int, ok: bool) {
	i := 0
	for _ in 0 ..< len(text) {
		if i >= len(text) { break }
		if count >= len(chars) { return count, false }
		r, w := rune(text[i]), 1
		if text[i] >= 0x80 { r, w = utf8.decode_rune_in_string(text[i:]) }
		when UPPER {
			if rune_upper(chars[count]) != rune_upper(r) { return count, false }
		} else {
			if rune_lower(chars[count]) != rune_lower(r) { return count, false }
		}
		i += w
		count += 1
	}
	return count, true
}

// `c` raised as the engine's `_find_upper` does.
@(private)
rune_upper :: #force_inline proc "contextless" (c: rune) -> rune {
	if u32(c) < 0x80 { return c - 0x20 if c >= 'a' && c <= 'z' else c }
	return caps_find(CAPS_UPPER_FROM[:], CAPS_UPPER_TO[:], c)
}

// `c` lowered as the engine's `_find_lower` does.
@(private)
rune_lower :: #force_inline proc "contextless" (c: rune) -> rune {
	if u32(c) < 0x80 { return c + 0x20 if c >= 'A' && c <= 'Z' else c }
	return caps_find(CAPS_LOWER_FROM[:], CAPS_LOWER_TO[:], c)
}

// The value paired with `c` in a sorted case table, or `c` when it has none. Halving 1500 keys
// takes 11 rounds; 16 bounds it.
@(private)
caps_find :: proc "contextless" (from, to: []u32, c: rune) -> rune {
	lo, hi := 0, len(from)
	for _ in 0 ..< 16 {
		if lo >= hi { break }
		mid := (lo + hi) / 2
		if from[mid] < u32(c) { lo = mid + 1 } else { hi = mid }
	}
	if lo < len(from) && from[lo] == u32(c) { return rune(to[lo]) }
	return c
}

// Element `i` of `a`, borrowed: valid until `a` changes or is destroyed, and not to be destroyed.
// Nil when `i` is out of range.
array_at :: proc "contextless" (a: ^Array, i: i64) -> ^Variant {
	return (^Variant)(gde.array_operator_index_const(a, i))
}

// The elements of `a` as a slice over its storage, read in place: valid until `a` changes or is
// destroyed. Do not write through it or destroy its elements.
array_read :: proc "contextless" (a: ^Array) -> []Variant {
	n := array_size(a)
	if n <= 0 { return nil }
	return ([^]Variant)(gde.array_operator_index_const(a, 0))[:n]
}

// The elements of `a` as a writable slice, or nil when `a` is typed or read-only, whose checks a
// direct write would skip: use `array_write_typed` or `array_set` for those. An Array is shared, not copied on write, so
// every holder of `a` sees the writes, as with `array_set`. Each element is a Variant `a` owns:
// destroy the old one before storing a new one. Valid until `a` is resized, duplicated or destroyed.
array_write :: proc "contextless" (a: ^Array) -> []Variant {
	n := array_size(a)
	if n <= 0 || array_is_typed(a) || array_is_read_only(a) { return nil }
	return ([^]Variant)(gde.array_operator_index(a, 0))[:n]
}

// A new untyped Array holding `xs`, each element converted as `variant` does, in one resize. You
// destroy it, or return it.
array_of :: proc "contextless" (xs: []$T) -> (out: Array) {
	out = array_new()
	if len(xs) == 0 { return }
	array_resize(&out, i64(len(xs)))
	// The resize fills with nulls, which hold nothing to destroy.
	slots := ([^]Variant)(gde.array_operator_index(&out, 0))
	for x, i in xs { variant_into(&slots[i], x) }
	return
}

// A new Array typed to `T`, as GDScript's `Array[T]`, holding `xs`, in one resize as `array_of`
// builds. `T` is a builtin type or an engine class; an integer type makes `Array[int]` and a float type
// `Array[float]`. You destroy it, or return it.
array_typed_of :: proc "contextless" (xs: []$T) -> (out: Array) {
	out = array_new()
	array_type_as(&out, variant_type(T), typed_class(T))
	if len(xs) == 0 { return }
	array_resize(&out, i64(len(xs)))
	// The resize fills a typed Array with its type's default value: nothing to destroy for a
	// scalar or an object, which starts null, but a counted value for the rest.
	slots := ([^]Variant)(gde.array_operator_index(&out, 0))
	for x, i in xs {
		when !(T == bool || intrinsics.type_is_integer(T) || intrinsics.type_is_enum(T) || intrinsics.type_is_bit_set(T) || intrinsics.type_is_float(T) || intrinsics.type_base_type(T) == rawptr) {
			gde.variant_destroy(&slots[i])
		}
		variant_into(&slots[i], x)
	}
	return
}

// The elements of `a` as a writable slice, as `array_write` gives, when `a` is typed exactly to
// `T` and writable; else nil. Store only `T` values in it, since the direct write skips the
// engine's type check: an `Array[Node]` takes `T` Node, not a subclass, and an `Array` typed to a
// script class gives nil. Destroy an element before storing a new one in its place.
array_write_typed :: proc "contextless" (a: ^Array, $T: typeid) -> []Variant {
	n := array_size(a)
	if n <= 0 || array_is_read_only(a) || !array_typed_as(a, variant_type(T), typed_class(T)) { return nil }
	return ([^]Variant)(gde.array_operator_index(a, 0))[:n]
}

// The class name an `Array[T]` carries: `T`'s own for an engine class, the registered class's for
// `^S` of a registered struct `S`, else empty. Looked up once per engine class `T`, and kept for
// the life of the process; a registered class must register before its first typed Array.
@(private)
typed_class :: proc "contextless" ($T: typeid) -> ^StringName {
	#assert(T != Variant, "godot_odin: a typed Array needs a type; use array_of for an untyped one")
	when intrinsics.type_is_pointer(T) && intrinsics.type_base_type(T) != rawptr {
		c := (^Class(intrinsics.type_elem_type(T)))(class_slot(intrinsics.type_elem_type(T))^)
		runtime.assert_contextless(c != nil, "godot_odin: a class must register before a typed Array of it")
		return &c.name
	}
	@(static) name: StringName
	@(static) known: bool
	when intrinsics.type_base_type(T) == rawptr {
		if !known {
			name_of_type(&name, type_info_of(T))
			known = true
		}
	}
	return &name
}

// `out` set to the name of the named type `info`, an engine class's.
@(private)
name_of_type :: proc "contextless" (out: ^StringName, info: ^runtime.Type_Info) {
	named := info.variant.(runtime.Type_Info_Named)
	gde.string_name_new_with_utf8_chars_and_len(out, cstring(raw_data(named.name)), gde.Int(len(named.name)))
}

// Types the empty Array `a` to Variant type `type` and class `class` (empty unless `type` is
// OBJECT), with no script.
@(private)
array_type_as :: proc "contextless" (a: ^Array, type: gde.VariantType, class: ^StringName) {
	script: Variant
	gde.array_set_typed(a, type, class, &script)
}

// Whether `a` is typed exactly to Variant type `type` and class `class`, with no script.
@(private)
array_typed_as :: proc "contextless" (a: ^Array, type: gde.VariantType, class: ^StringName) -> bool {
	if !array_is_typed(a) || array_get_typed_builtin(a) != i64(type) { return false }
	if type != .OBJECT { return true }
	got := array_get_typed_class_name(a)
	defer destroy[.STRING_NAME](&got)
	script := array_get_typed_script(a)
	defer gde.variant_destroy(&script)
	// The engine answers an Array with no script with a null Object, not a NIL Variant.
	return same_name(got, class^) && from_variant(rawptr, &script) == nil
}

// The keys and the values of `d`, as two new Arrays in matching order: `keys[i]` maps to
// `values[i]`. Read them in place with `array_read`. You destroy both.
dict_items :: proc "contextless" (d: ^Dictionary) -> (keys, values: Array) {
	return dictionary_keys(d), dictionary_values(d)
}

// The value `key` maps to in `d`, and true; or a nil Variant and false when `d` has no such key.
// `key` is a `^Variant`, a Variant, or any value `variant` converts. One hash lookup through the
// engine's keyed get. You destroy the value.
dict_get :: proc "contextless" (d: ^Dictionary, key: $K) -> (value: Variant, found: bool) {
	found = dict_get_into(d, key, &value)
	return
}

// `dict_get` writing the value to `out`, which must hold nothing to destroy: it saves copying the
// result back, about 6 ns of the 27 a `dict_get` takes (bench/). False, with `out` nil, when `d`
// has no such key.
dict_get_into :: proc "contextless" (d: ^Dictionary, key: $K, out: ^Variant) -> bool {
	self := borrowed(.DICTIONARY, d)
	valid: gde.Bool
	when K == ^Variant {
		k := key
	} else when K == Variant {
		kv := key
		k := &kv
	} else {
		kv := variant(key)
		k := &kv
		defer gde.variant_destroy(&kv)
	}
	gde.variant_get_keyed(&self, k, out, &valid)
	return valid != 0
}

// Maps `key` to `value` in `d`, each a Variant or any value `variant` converts, through the
// engine's keyed set. False when `d` is read-only or typed and either side does not fit.
dict_set :: proc "contextless" (d: ^Dictionary, key: $K, value: $V) -> bool {
	self := borrowed(.DICTIONARY, d)
	return set_at(&self, key, value, gde.variant_set_keyed)
}

// `v[key]` for any Variant `v`, as GDScript reads it: a Dictionary's value, an Array's element, an
// Object's property, a Vector2's `"x"`. False when `v` has no such key, with a nil Variant. `key`
// is a Variant or any value `variant` converts. You destroy the value.
variant_get :: proc "contextless" (v: ^Variant, key: $K) -> (value: Variant, found: bool) {
	return get_at(v, key, gde.variant_get)
}

// `v[key] = value` for any Variant `v`, as GDScript writes it, each side a Variant or any value
// `variant` converts. False when `v` takes no such key or value. A Dictionary, Array or Object
// shares its storage, so the write reaches every holder; a Vector2 or other value type changes only
// `v`.
variant_set :: proc "contextless" (v: ^Variant, key: $K, value: $V) -> bool {
	return set_at(v, key, value, gde.variant_set)
}

// `v[key]` through `get`, the engine's generic or keyed get, with `key` converted to a Variant
// unless it is one.
@(private)
get_at :: #force_inline proc "contextless" (
	v: ^Variant,
	key: $K,
	get: proc "c" (gde.ConstVariantPtr, gde.ConstVariantPtr, gde.UninitializedVariantPtr, ^gde.Bool),
) -> (value: Variant, found: bool) {
	valid: gde.Bool
	when K == Variant {
		k := key
		get(v, &k, &value, &valid)
	} else {
		k := variant(key)
		get(v, &k, &value, &valid)
		gde.variant_destroy(&k)
	}
	return value, valid != 0
}

// `v[key] = value` through `set`, the engine's generic or keyed set, with each side converted to a
// Variant unless it is one.
@(private)
set_at :: #force_inline proc "contextless" (
	v: ^Variant,
	key: $K,
	value: $V,
	set: proc "c" (gde.VariantPtr, gde.ConstVariantPtr, gde.ConstVariantPtr, ^gde.Bool),
) -> bool {
	valid: gde.Bool
	when K == Variant { k := key } else { k := variant(key) }
	when V == Variant { x := value } else { x := variant(value) }
	set(v, &k, &x, &valid)
	when K != Variant { gde.variant_destroy(&k) }
	when V != Variant { gde.variant_destroy(&x) }
	return valid != 0
}

// A new untyped Dictionary mapping `keys[i]` to `values[i]`, each converted as `variant` does. A
// repeated key keeps its last value. `keys` and `values` have the same length. You destroy it, or
// return it.
dict_of :: proc "contextless" (keys: []$K, values: []$V) -> (out: Dictionary) {
	out = dictionary_new()
	dict_fill(&out, keys, values)
	return
}

// A new Dictionary typed to `K` and `V`, as GDScript's `Dictionary[K, V]`, built as `dict_of`
// builds. Each side is a builtin type, an engine class, or `Variant` for an untyped side.
dict_typed_of :: proc "contextless" (keys: []$K, values: []$V) -> (out: Dictionary) {
	out = dictionary_new()
	// An untyped side, `Variant`, has no class: the empty name.
	script: Variant
	when K == Variant { key_none: StringName; key_class := &key_none } else { key_class := typed_class(K) }
	when V == Variant { value_none: StringName; value_class := &value_none } else { value_class := typed_class(V) }
	gde.dictionary_set_typed(&out, variant_type(K), key_class, &script, variant_type(V), value_class, &script)
	dict_fill(&out, keys, values)
	return
}

// Adds `keys[i]` mapped to `values[i]` to `d`, writing each value in place: the engine's index
// inserts a null for a new key and returns the existing value for a repeated one.
@(private)
dict_fill :: proc "contextless" (d: ^Dictionary, keys: []$K, values: []$V) {
	if len(keys) != len(values) { fail("godot_odin: dict_of needs as many values as keys", "dict_of") }
	for key, i in keys {
		k := variant(key)
		slot := (^Variant)(gde.dictionary_operator_index(d, &k))
		gde.variant_destroy(&k)
		gde.variant_destroy(slot)
		variant_into(slot, values[i])
	}
}


// True when a String is the engine's copy-on-write storage as `string_read` reads it: one pointer
// to the characters, null when empty, with the 64-bit size counting the terminator 16 bytes before
// them (the capacity sits between). `check_string_layout` decides it at load; without it
// `string_read` asks the engine, two calls more.
@(private)
string_layout_known: bool

// Where the size sits before a String's characters.
@(private)
STRING_SIZE_OFFSET :: 16

// The length of `s` in characters, read from its storage's header. Only when `string_layout_known`;
// the generated `string_length` and `string_is_empty` use it then, and ask the engine otherwise.
string_stored_length :: #force_inline proc "contextless" (s: ^String) -> i64 {
	p := (^rawptr)(s)^
	if p == nil { return 0 }
	return (^i64)(uintptr(p) - STRING_SIZE_OFFSET)^ - 1
}

// Sets `string_layout_known` from Strings of known length: one shared by two references, and one
// grown by an append so its capacity differs from its size.
check_string_layout :: proc "contextless" () {
	holds :: proc "contextless" (s: ^String, n: int) -> bool {
		p := (^rawptr)(s)^
		return p != nil && p == rawptr(gde.string_operator_index_const(s, 0)) && (^i64)(uintptr(p) - STRING_SIZE_OFFSET)^ == i64(n) + 1
	}
	short :: "abc"
	long :: "a longer String, past any small-size storage"
	a := string_of(short)
	b := string_new_from_string(a)
	c := string_of(long)
	string_append_rune(&c, '!')
	string_layout_known = holds(&a, len(short)) && holds(&b, len(short)) && holds(&c, len(long) + 1)
	destroy[.STRING](&c)
	destroy[.STRING](&b)
	destroy[.STRING](&a)
}

// The characters of `s` as a writable slice. A shared String gets storage of its own first, as any
// write does; the slice stays valid until `s` is copied, resized or destroyed. `s` must be a String
// you own, not a borrowed parameter.
string_write :: proc "contextless" (s: ^String) -> []rune {
	n := string_length(s)
	if n <= 0 { return nil }
	return gde.string_operator_index(s, 0)[:n]
}

// Appends to `s` in place, growing its storage rather than building a new String: Odin UTF-8 text,
// another String, or one character. `s` must be a String you own.
string_append :: proc {string_append_text, string_append_string, string_append_rune}

string_append_text :: proc "contextless" (s: ^String, text: string) {
	// Parsed by the engine, as `string_of` is, so malformed bytes become what any other String
	// made from them holds.
	if len(text) == 0 { return }
	t := string_of(text)
	defer destroy[.STRING](&t)
	gde.string_operator_plus_eq_string(s, &t)
}

string_append_string :: proc "contextless" (s: ^String, b: String) {
	b := b
	gde.string_operator_plus_eq_string(s, &b)
}

string_append_rune :: proc "contextless" (s: ^String, r: rune) {
	gde.string_operator_plus_eq_char(s, r)
}

// The pixel bytes of `img`, read in place, laid out as its format (`image_get_format`) says. Valid
// until `img` is changed or freed. Do not write through it: the storage may be shared with copies.
image_read :: proc "contextless" (img: Image) -> []u8 {
	n := image_get_data_size(img)
	if n <= 0 { return nil }
	return gde.image_ptr(gde.ObjectPtr(img))[:n]
}

// The pixel bytes of `img` as a writable slice. Shared storage is copied first, as any write does.
// Valid until `img` is resized, converted or freed. A texture made from `img` does not see the
// writes until it is updated from it.
image_write :: proc "contextless" (img: Image) -> []u8 {
	n := image_get_data_size(img)
	if n <= 0 { return nil }
	return gde.image_ptrw(gde.ObjectPtr(img))[:n]
}

// Reads the next bytes of `f` into `dst`, up to its length, and returns how many it read: fewer at
// the end of the file.
file_read :: proc "contextless" (f: FileAccess, dst: []u8) -> int {
	if len(dst) == 0 { return 0 }
	return int(gde.file_access_get_buffer(gde.ConstObjectPtr(f), raw_data(dst), u64(len(dst))))
}

// Writes `src` to `f` at its position. `file_access_get_error` reports a failed write.
file_write :: proc "contextless" (f: FileAccess, src: []u8) {
	if len(src) == 0 { return }
	gde.file_access_store_buffer(gde.ObjectPtr(f), raw_data(src), u64(len(src)))
}
