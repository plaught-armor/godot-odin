// Direct access to engine storage: packed arrays, Strings, Arrays, Images and files read and written
// through the pointers the interface hands out, instead of one builtin or method call per element.
package godot

import "base:intrinsics"
import "base:runtime"
import "core:c/libc"
import "core:math"
import "core:strconv"
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

packed_read_byte :: proc "contextless" (a: ^PackedByteArray) -> []u8 { if packed_layout_known { return packed_stored(u8, a) }; return packed_slice(u8, a, packed_byte_array_size(a), gde.packed_byte_array_operator_index_const) }
packed_read_int32 :: proc "contextless" (a: ^PackedInt32Array) -> []i32 { if packed_layout_known { return packed_stored(i32, a) }; return packed_slice(i32, a, packed_int32_array_size(a), gde.packed_int32_array_operator_index_const) }
packed_read_int64 :: proc "contextless" (a: ^PackedInt64Array) -> []i64 { if packed_layout_known { return packed_stored(i64, a) }; return packed_slice(i64, a, packed_int64_array_size(a), gde.packed_int64_array_operator_index_const) }
packed_read_float32 :: proc "contextless" (a: ^PackedFloat32Array) -> []f32 { if packed_layout_known { return packed_stored(f32, a) }; return packed_slice(f32, a, packed_float32_array_size(a), gde.packed_float32_array_operator_index_const) }
packed_read_float64 :: proc "contextless" (a: ^PackedFloat64Array) -> []f64 { if packed_layout_known { return packed_stored(f64, a) }; return packed_slice(f64, a, packed_float64_array_size(a), gde.packed_float64_array_operator_index_const) }
packed_read_string :: proc "contextless" (a: ^PackedStringArray) -> []String { if packed_layout_known { return packed_stored(String, a) }; return packed_slice(String, a, packed_string_array_size(a), gde.packed_string_array_operator_index_const) }
packed_read_vector2 :: proc "contextless" (a: ^PackedVector2Array) -> []Vector2 { if packed_layout_known { return packed_stored(Vector2, a) }; return packed_slice(Vector2, a, packed_vector2_array_size(a), gde.packed_vector2_array_operator_index_const) }
packed_read_vector3 :: proc "contextless" (a: ^PackedVector3Array) -> []Vector3 { if packed_layout_known { return packed_stored(Vector3, a) }; return packed_slice(Vector3, a, packed_vector3_array_size(a), gde.packed_vector3_array_operator_index_const) }
packed_read_vector4 :: proc "contextless" (a: ^PackedVector4Array) -> []Vector4 { if packed_layout_known { return packed_stored(Vector4, a) }; return packed_slice(Vector4, a, packed_vector4_array_size(a), gde.packed_vector4_array_operator_index_const) }
packed_read_color :: proc "contextless" (a: ^PackedColorArray) -> []Color { if packed_layout_known { return packed_stored(Color, a) }; return packed_slice(Color, a, packed_color_array_size(a), gde.packed_color_array_operator_index_const) }

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
	return runes_equal_text(string_read(s), text)
}

// `string_equal_text` on characters already read, such as a part from `split_next`.
runes_equal_text :: proc "contextless" (chars: []rune, text: string) -> bool {
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

// The String procs below replace the generated bindings of the engine's methods of the same name
// (tools/odin_bindgen.py REPLACED, logged in docs/replaced.md): same signature and answers, read in
// place from both Strings with no engine call.

// Where `what` first appears in `self` at or after character `from`, in characters, or -1: the
// engine's `find`. A negative `from` counts back from the last place `what` fits, and an empty
// `what` gives -1.
string_find :: proc "contextless" (self: ^String, what: String, from: i64) -> i64 {
	return find_string(self, what, from, false)
}

// `string_find` ignoring case: the engine's `findn`.
string_findn :: proc "contextless" (self: ^String, what: String, from: i64) -> i64 {
	return find_string(self, what, from, true)
}

// Where `what` last appears in `self` at or before character `from`, or -1: the engine's `rfind`,
// `from` read as in `string_find`.
string_rfind :: proc "contextless" (self: ^String, what: String, from: i64) -> i64 {
	return rfind_string(self, what, from, false)
}

// `string_rfind` ignoring case: the engine's `rfindn`.
string_rfindn :: proc "contextless" (self: ^String, what: String, from: i64) -> i64 {
	return rfind_string(self, what, from, true)
}

// Whether `what` appears in `self`: the engine's `contains`. Empty `what` gives false.
string_contains :: proc "contextless" (self: ^String, what: String) -> bool {
	return find_string(self, what, 0, false) >= 0
}

// `string_contains` ignoring case: the engine's `containsn`.
string_containsn :: proc "contextless" (self: ^String, what: String) -> bool {
	return find_string(self, what, 0, true) >= 0
}

// How many times `what` appears in `self` between characters `from` and `to`, not overlapping:
// the engine's `count`, with `to` read as in `string_count_text`.
string_count :: proc "contextless" (self: ^String, what: String, from: i64, to: i64) -> i64 {
	what := what
	return count_in(string_read(self), rune_needle_of(string_read(&what), false), from, to, false)
}

// `string_count` ignoring case: the engine's `countn`.
string_countn :: proc "contextless" (self: ^String, what: String, from: i64, to: i64) -> i64 {
	what := what
	return count_in(string_read(self), rune_needle_of(string_read(&what), true), from, to, true)
}

// Whether `self` starts with `text`: the engine's `begins_with`. Empty `text` gives true.
string_begins_with :: proc "contextless" (self: ^String, text: String) -> bool {
	text := text
	chars, t := string_read(self), string_read(&text)
	return len(t) <= len(chars) && runes_equal(raw_data(chars), raw_data(t), len(t))
}

// Whether `self` ends with `text`: the engine's `ends_with`. Empty `text` gives true.
string_ends_with :: proc "contextless" (self: ^String, text: String) -> bool {
	text := text
	chars, t := string_read(self), string_read(&text)
	return len(t) <= len(chars) && runes_equal(raw_data(chars[len(chars) - len(t):]), raw_data(t), len(t))
}

// The engine's `casecmp_to`: -1, 0 or 1 as `self` sorts before, with or after `to`, character by
// character by code point, a shorter String first.
string_casecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	to := to
	return compare_runes(string_read(self), string_read(&to), false)
}

// `string_casecmp_to` with both characters uppercased first: the engine's `nocasecmp_to`.
string_nocasecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	to := to
	return compare_runes(string_read(self), string_read(&to), true)
}

// A copy of `self` with every `what` replaced by `forwhat`: the engine's `replace`, made as
// `string_replace_text` makes it. The caller destroys the result.
string_replace :: proc "contextless" (self: ^String, what: String, forwhat: String) -> String {
	what, forwhat := what, forwhat
	return replace_in(self, rune_needle_of(string_read(&what), false), string_read(&forwhat), false)
}

// `string_replace` ignoring case: the engine's `replacen`.
string_replacen :: proc "contextless" (self: ^String, what: String, forwhat: String) -> String {
	what, forwhat := what, forwhat
	return replace_in(self, rune_needle_of(string_read(&what), true), string_read(&forwhat), true)
}

// The parts of `self` between each `delimiter`: the engine's `split`, made as `string_split_text`
// makes it. The caller destroys the result.
string_split :: proc "contextless" (self: ^String, delimiter: String, allow_empty: bool, maxsplit: i64) -> (out: PackedStringArray) {
	delimiter := delimiter
	return split_make(string_read(self), rune_needle_of(string_read(&delimiter), false), allow_empty, maxsplit)
}

// Walks `a` and `b` as the engine's `casecmp_to` and `nocasecmp_to` do: an empty String sorts
// first, and either ends at its first zero character, so one embedded ends the comparison there.
@(private)
compare_runes :: #force_inline proc "contextless" (a, b: []rune, $NOCASE: bool) -> i64 {
	if len(a) == 0 { return 0 if len(b) == 0 else -1 }
	if len(b) == 0 { return 1 }
	for k in 0 ..= min(len(a), len(b)) {
		x := a[k] if k < len(a) else 0
		y := b[k] if k < len(b) else 0
		if x == 0 || y == 0 { return i64(x != 0) - i64(y != 0) }
		when NOCASE { x, y = rune_upper(x), rune_upper(y) }
		if x != y { return -1 if u32(x) < u32(y) else 1 }
	}
	return 0
}

@(private)
find_string :: #force_inline proc "contextless" (self: ^String, what: String, from: i64, $NOCASE: bool) -> i64 {
	what := what
	chars := string_read(self)
	n := rune_needle_of(string_read(&what), NOCASE)
	start, last, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_forward(chars, start, last, n, NOCASE)
}

@(private)
rfind_string :: #force_inline proc "contextless" (self: ^String, what: String, from: i64, $NOCASE: bool) -> i64 {
	what := what
	chars := string_read(self)
	n := rune_needle_of(string_read(&what), NOCASE)
	start, _, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_backward(chars, start, n, NOCASE)
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
	return runes_equal_text_nocase(string_read(s), text)
}

// `string_equal_text_nocase` on characters already read, such as a part from `split_next`.
runes_equal_text_nocase :: proc "contextless" (chars: []rune, text: string) -> bool {
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
replace_in :: proc "contextless" (s: ^String, n: $N, with: $W, $NOCASE: bool) -> (out: String) {
	chars := string_read(s)
	hits := int(count_in(chars, n, 0, 0, NOCASE))
	if hits == 0 { return string_new_from_string(s^) }
	// `with` is Odin text, decoded as it is written, or characters read from a String.
	with_ascii: bool
	with_count: int
	when W == string {
		with_ascii = text_is_ascii(with)
		with_count = len(with) if with_ascii else text_rune_count(with)
	} else {
		with_count = len(with)
	}
	total := len(chars) + hits * (with_count - n.count)
	// A zeroed String is the engine's empty one: its storage pointer is null.
	if total == 0 { return }
	// The engine's resize counts the terminator, which it leaves for the caller to write.
	w := string_storage(&out, total + 1)[:total + 1]
	j, start, last := 0, 0, len(chars) - n.count
	for _ in 0 ..< hits {
		at := int(find_forward(chars, start, last, n, NOCASE))
		j += copy(w[j:], chars[start:at])
		when W == string { j += text_put(w[j:], with, with_ascii) } else { j += copy(w[j:], with) }
		start = at + n.count
	}
	j += copy(w[j:], chars[start:])
	w[total] = 0
	return
}

// The parts of a String between each place a delimiter appears, as slices over its characters, read
// one at a time with `split_next`: `split` with `allow_empty` true, but with no String or array
// made. Valid until the String is written or destroyed.
Split_Parts :: struct {
	chars:  []rune,
	needle: Needle,
	from:   int,
	done:   bool,
}

// The parts of `s` between each Odin text `delimiter`, for `split_next`. `delimiter` must stay
// unchanged while they are read.
string_split_parts :: proc "contextless" (s: ^String, delimiter: string) -> Split_Parts {
	return {chars = string_read(s), needle = needle_of(delimiter, false)}
}

// The next part, or false after the last: `for part in godot.split_next(&parts)`. An empty
// String has one empty part, an empty delimiter gives one part per character, and a delimiter at
// either end gives an empty part there. The rest of the String after the part just read is
// `parts.chars[parts.from:]`.
split_next :: #force_inline proc "contextless" (parts: ^Split_Parts) -> (part: []rune, ok: bool) {
	if parts.done { return }
	chars := parts.chars
	end := split_end(chars, parts.from, parts.needle)
	part, ok = chars[parts.from:end], true
	if end == len(chars) { parts.done = true } else { parts.from = end + parts.needle.count }
	return
}

// Where the part of `chars` starting at `from` ends, as the engine's `split` finds it: at the next
// `n`, at the end when there is none, or one character on for an empty `n`.
@(private)
split_end :: #force_inline proc "contextless" (chars: []rune, from: int, n: $N) -> int {
	if n.count == 0 { return min(from + 1, len(chars)) }
	end := int(find_forward(chars, from, len(chars) - n.count, n, false))
	return end if end >= 0 else len(chars)
}

// `chars` without the whitespace at its left and right ends, as the engine's `strip_edges` trims a
// String: any character up to 32, space, is whitespace. A slice of `chars`, so a part from
// `split_next` is trimmed with no String made.
runes_strip_edges :: proc "contextless" (chars: []rune, left := true, right := true) -> []rune {
	beg, end := 0, len(chars)
	for _ in 0 ..< len(chars) {
		if !left || beg == end || u32(chars[beg]) > 32 { break }
		beg += 1
	}
	for _ in 0 ..< len(chars) {
		if !right || end == beg || u32(chars[end - 1]) > 32 { break }
		end -= 1
	}
	return chars[beg:end]
}

// The integer `chars` spell, read as the engine's `to_int` reads a String: up to the first '.',
// taking every ASCII digit and skipping anything else, with each '-' before the first nonzero digit
// flipping the sign. A value past the 64-bit range gives the nearest end of it, where the engine
// also prints an error.
runes_to_int :: proc "contextless" (chars: []rune) -> i64 {
	integer: u64
	// The engine counts digits in a byte, which wraps after 255 and skips the range check again
	// for the next 19 digits; counting the same way gives the same value then.
	digits: u8
	positive := true
	for c in chars {
		if c == '.' { break }
		if c >= '0' && c <= '9' {
			if digits > 18 {
				top := u64(max(i64) / 10)
				// The engine lets a negative value end in '8'; that is `min(i64)`, which the clamp gives.
				if integer > top || (integer == top && c > '7') {
					return max(i64) if positive else min(i64)
				}
			}
			integer = integer * 10 + u64(c - '0')
			digits += 1
		} else if integer == 0 && c == '-' {
			positive = !positive
		}
	}
	return i64(integer) if positive else i64(0 - integer)
}

// The powers 10^(2^k) `runes_to_float` scales by, one per exponent bit up to 511.
@(private, rodata)
FLOAT_POWERS := [9]f64{1e1, 1e2, 1e4, 1e8, 1e16, 1e32, 1e64, 1e128, 1e256}

// The number `chars` spell, read as the engine's `to_float` reads a String, to the same bits: space,
// tab and newline skipped at the front, a sign, digits with at most one '.', and an exponent, with
// reading stopping at the first character that does not fit. As there, mantissa digits past 18
// are dropped, an exponent past 511 is taken as 511 (the engine also prints a warning), a lone
// sign gives zero with that sign, and an 'e' with no digits after it leaves the mantissa unscaled
// by its '.': "1.5e" reads 15.
runes_to_float :: proc "contextless" (chars: []rune) -> f64 #no_bounds_check {
	n := len(chars)
	p := 0
	for ; p < n && (chars[p] == ' ' || chars[p] == '\t' || chars[p] == '\n'); p += 1 {}
	negative := p < n && chars[p] == '-'
	if p < n && (chars[p] == '-' || chars[p] == '+') { p += 1 }
	// The mantissa in one pass: its first 18 digits, how many digits, and how many before the '.'.
	mant: u64
	digits, dec_pt := 0, -1
	for ; p < n; p += 1 {
		c := chars[p]
		if c >= '0' && c <= '9' {
			if digits < 18 { mant = 10 * mant + u64(c - '0') }
			digits += 1
			continue
		}
		if c != '.' || dec_pt >= 0 { break }
		dec_pt = digits
	}
	if dec_pt < 0 { dec_pt = digits }
	if digits == 0 { return -0.0 if negative else 0.0 }
	frac_exp := dec_pt - min(digits, 18)
	// The engine sums two nine-digit halves as doubles; the high half times 1e9 is exact there, so
	// that sum rounds once, as this conversion does.
	fraction := f64(mant)
	// The exponent.
	exp := 0
	if p < n && (chars[p] == 'E' || chars[p] == 'e') {
		q := p + 1
		exp_negative := q < n && chars[q] == '-'
		if q < n && (chars[q] == '-' || chars[q] == '+') { q += 1 }
		if q >= n || chars[q] < '0' || chars[q] > '9' { return -fraction if negative else fraction }
		for ; q < n && chars[q] >= '0' && chars[q] <= '9'; q += 1 {
			// The engine's exponent is a 32-bit int: past it, it wraps there too.
			exp = int(i32(exp) * 10 + i32(chars[q] - '0'))
		}
		if exp_negative { exp = -exp }
	}
	exp = int(i32(frac_exp + exp))
	scale_down := exp < 0
	exp = min(abs(exp), 511)
	scale := 1.0
	for power in FLOAT_POWERS {
		if exp == 0 { break }
		if exp & 1 != 0 { scale *= power }
		exp >>= 1
	}
	fraction = fraction / scale if scale_down else fraction * scale
	return -fraction if negative else fraction
}

// A String holding `chars`, which the caller destroys. They are copied as they are, without the
// check a String made from outside characters gets, so they should come from a String: a part
// from `split_next` or `runes_strip_edges`.
string_of_runes :: proc "contextless" (chars: []rune) -> (out: String) {
	// A zeroed String is the engine's empty one.
	if len(chars) > 0 { string_fill(&out, chars) }
	return
}

// `number` written in `base`, 2 to 36, as the engine's `String.num_int64` writes it: a '-' when
// negative, then digits, with letters past 9 that are lowercase unless `capitalize_hex`. Written
// straight into the String, with no text for the engine to read back. The caller destroys it.
string_of_int :: proc "contextless" (number: i64, base: i64 = 10, capitalize_hex := false) -> (out: String) {
	runtime.assert_contextless(base >= 2 && base <= 36, "godot_odin: string_of_int takes a base from 2 to 36")
	buf: [65]rune
	// The magnitude as unsigned, so the most negative number has one too.
	m := u64(number) if number >= 0 else 0 - u64(number)
	at := len(buf)
	if base == 10 {
		// A constant base, so each division is a multiply.
		for _ in 0 ..< 20 {
			at -= 1
			buf[at] = '0' + rune(m % 10)
			m /= 10
			if m == 0 { break }
		}
	} else {
		b := u64(base)
		letter: rune = 'A' if capitalize_hex else 'a'
		for _ in 0 ..< 64 {
			d := rune(m % b)
			at -= 1
			buf[at] = '0' + d if d < 10 else letter + d - 10
			m /= b
			if m == 0 { break }
		}
	}
	if number < 0 {
		at -= 1
		buf[at] = '-'
	}
	string_fill(&out, buf[at:])
	return
}

// `number` written as the engine's `String.num` writes it: "nan", "inf" or "-inf", else rounded to
// `decimals` places as C's "%.*f" rounds, with trailing zeros dropped down to one after the '.'. A
// negative `decimals` asks for the engine's default, 14 places less the number's power of ten when
// it is past 10, and the engine's format reads a default below zero as six places. Places past 32
// are taken as 32. The caller destroys the result.
string_of_float :: proc(number: f64, decimals: i64 = -1) -> (out: String) {
	buf: [400]byte
	ascii_fill(&out, float_text(buf[:], number, decimals))
	return
}

// `number` written as the engine's `String.num_real` writes it, which `str` and printing use for a
// float: a whole number in the 64-bit range as `string_of_int` writes it, with ".0" after when
// `trailing`, and any other number as `string_of_float` with its default places. The caller
// destroys the result.
string_of_real :: proc(number: f64, trailing := true) -> (out: String) {
	buf: [400]byte
	text: []byte
	// The engine checks whether the number survives a trip through a 64-bit int; that conversion
	// gives the most negative int for a number out of range, here as there.
	if whole := i64(number); !math.is_nan(number) && !math.is_inf(number) && number == f64(whole) {
		digits := string_of_int(whole)
		if !trailing { return digits }
		defer destroy[.STRING](&digits)
		chars := string_read(&digits)
		for c, k in chars { buf[k] = u8(c) }
		copy(buf[len(chars):], ".0")
		text = buf[:len(chars) + 2]
	} else {
		text = float_text(buf[:], number, -1)
	}
	ascii_fill(&out, text)
	return
}

// The text of the engine's `String.num` for `number`, written in `buf`, which holds 400 bytes: the
// most a double takes at 32 places.
@(private)
float_text :: proc(buf: []byte, number: f64, decimals: i64) -> []byte {
	if math.is_nan(number) { return transmute([]byte)string("nan") }
	if math.is_inf(number) { return transmute([]byte)string("-inf" if number < 0 else "inf") }
	places := decimals
	if places < 0 {
		places = 14
		// The engine's own log10, from the C library, so the powers of ten fall where they fall there.
		if a := abs(number); a > 10 { places -= i64(math.floor(libc.log10(a))) }
	}
	places = min(places, 32)
	// The engine's format reads a negative place count as no place count: "%lf", six places.
	if places < 0 { places = 6 }
	text, fits := fixed_text(buf, number, int(places))
	if !fits {
		// Odin's fixed-point writer rounds the exact value half to even, as C's printf does.
		text = strconv.generic_ftoa(buf, number, 'f', int(places), 64)
		if text[0] == '+' { text = text[1:] }
	}
	// Trailing zeros go, down to one after the '.', which stops the walk; with no places there is
	// no '.' and nothing to walk.
	end := len(text)
	for _ in 0 ..< places {
		if text[end - 1] != '0' { break }
		end -= 1
	}
	if text[end - 1] == '.' { end += 1 }
	return text[:end]
}

// The powers of ten up to 10^22, the most places `fixed_text` takes: 10^22 times a 53-bit mantissa
// fits 128 bits.
@(private, rodata)
FIXED_TENS := [23]u128{
	1, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16,
	1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
}

// The finite `number` written with `places` places in `buf`, rounded as C's "%.*f" rounds: the
// exact binary value, half to even. The value times 10^places is worked in 128-bit integers, so
// this returns false for a number too big for that, or more than 22 places, and writes nothing.
@(private)
fixed_text :: proc "contextless" (buf: []byte, number: f64, places: int) -> ([]byte, bool) {
	if places > 22 { return nil, false }
	bits := transmute(u64)number
	mant := bits & (1 << 52 - 1)
	biased := int(bits >> 52 & 0x7FF)
	if biased != 0 { mant |= 1 << 52 } else { biased = 1 }
	// number = mant * 2^shift, and scaled = mant * 10^places, below 2^127.
	shift := biased - 1075
	scaled := u128(mant) * FIXED_TENS[places]
	q: u128
	switch {
	case shift >= 0:
		if mant != 0 && shift >= int(intrinsics.count_leading_zeros(scaled)) { return nil, false }
		q = scaled << uint(shift)
	case shift > -128:
		s := uint(-shift)
		q = scaled >> s
		r := scaled & (u128(1) << s - 1)
		half := u128(1) << (s - 1)
		if r > half || (r == half && q & 1 == 1) { q += 1 }
	// Below 2^-128 of scaled, which is below 2^127: under one half, so zero.
	}
	// The digits of q, last first, in 64-bit halves so each digit is a 64-bit division: the low 19
	// digits, all of them when there are more, then the rest, then zeros up to places + 1 so there
	// is a leading 0. q is below 2^127, so the rest is below 2^64.
	lo, hi := u64(q), u64(0)
	if q >> 64 != 0 {
		lo = u64(q % 1e19)
		hi = u64(q / 1e19)
	}
	digits: [40]byte
	n := 0
	for _ in 0 ..< 20 {
		digits[n] = '0' + u8(lo % 10)
		n += 1
		lo /= 10
		if lo == 0 && (hi == 0 || n == 19) { break }
	}
	for _ in 0 ..< 20 {
		if hi == 0 { break }
		digits[n] = '0' + u8(hi % 10)
		n += 1
		hi /= 10
	}
	for n <= places {
		digits[n] = '0'
		n += 1
	}
	k := 0
	if bits >> 63 != 0 {
		buf[0] = '-'
		k = 1
	}
	for i := n - 1; i >= 0; i -= 1 {
		if i == places - 1 {
			buf[k] = '.'
			k += 1
		}
		buf[k] = digits[i]
		k += 1
	}
	return buf[:k], true
}

// Sizes the empty String `s` to the ASCII `text` and writes it in, with the terminator.
@(private)
ascii_fill :: proc "contextless" (s: ^String, text: []byte) {
	w := string_storage(s, len(text) + 1)
	for c, k in text { w[k] = rune(c) }
	w[len(text)] = 0
}

// The parts of `s` between each Odin text `delimiter`: the engine's `split`. Empty `delimiter` gives
// one part per character; `allow_empty` false drops empty parts; a positive `maxsplit` stops after
// that many parts and adds the rest of `s` as one more. The parts are counted first so the array is
// sized once, then each is made straight from its characters, with no String made for `delimiter`.
// The caller destroys the result.
string_split_text :: proc "contextless" (s: ^String, delimiter: string, allow_empty := true, maxsplit: i64 = 0) -> PackedStringArray {
	return split_make(string_read(s), needle_of(delimiter, false), allow_empty, maxsplit)
}

// How many parts `split_make` keeps the bounds of while counting, so it need not search again.
@(private)
SPLIT_BOUNDS :: 64

// The array of the parts of `chars` between each `n`, for `string_split` and `string_split_text`.
// The parts are counted first so the array is sized once. Up to `SPLIT_BOUNDS` parts are made from
// the bounds kept while counting; more are found again by a second walk.
@(private)
split_make :: proc "contextless" (chars: []rune, n: $N, allow_empty: bool, maxsplit: i64) -> (out: PackedStringArray) {
	out = packed_string_array_new()
	bounds: [SPLIT_BOUNDS][2]int = ---
	k := split_in(chars, n, allow_empty, maxsplit, bounds[:], nil)
	if k == 0 { return }
	packed_string_array_resize(&out, i64(k))
	slots := packed_write_string(&out)
	if k > SPLIT_BOUNDS {
		split_in(chars, n, allow_empty, maxsplit, nil, slots)
		return
	}
	for b, i in bounds[:k] { part_put(slots, i, chars[b[0]:b[1]]) }
	return
}

// Walks the parts of `chars` as the engine's `split` does and returns how many there are. The
// bounds of the first `len(bounds)` parts go in `bounds`. With `out`, it also makes part `k` in
// `out[k]`, which must hold an empty String: the array's slots after a resize. There are at most
// `len(chars) + 1` parts, so as many rounds cover them.
@(private)
split_in :: proc "contextless" (chars: []rune, n: $N, allow_empty: bool, maxsplit: i64, bounds: [][2]int, out: []String) -> (k: int) {
	// The engine's `maxsplit` is a 32-bit int: keep the low 32 bits, sign-extended.
	maxsplit := i64(i32(maxsplit))
	from := 0
	for _ in 0 ..= len(chars) {
		end := split_end(chars, from, n)
		if allow_empty || end > from {
			// Past `maxsplit` parts, the rest of `chars` is the last, and the walk ends after it.
			last := maxsplit > 0 && i64(k) == maxsplit
			if last { end = len(chars) }
			if k < len(bounds) { bounds[k] = {from, end} }
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
	w := string_storage(s, len(chars) + 1)
	copy(w[:len(chars)], chars)
	w[len(chars)] = 0
}

// Gives the empty String `s` storage for `n` characters, the terminator counted, and returns it.
// With `string_layout_known` it allocates and fills the header itself, the reference count 1 and
// the capacity and size the engine's `resize` from empty would set, sparing the engine's resize
// path; the engine frees such storage as its own. Otherwise it asks the engine to resize.
@(private)
string_storage :: #force_inline proc "contextless" (s: ^String, n: int) -> [^]rune {
	if !string_layout_known {
		gde.string_resize(s, gde.Int(n))
		return gde.string_operator_index(s, 0)
	}
	capacity := max(2, n)
	base := ([^]i64)(gde.mem_alloc2(uint(STRING_DATA_OFFSET + capacity * size_of(rune)), gde.Bool(0)))
	base[0], base[1], base[2] = 1, i64(capacity), i64(n)
	data := rawptr(&base[STRING_DATA_OFFSET / size_of(i64)])
	(^rawptr)(s)^ = data
	return ([^]rune)(data)
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
count_in :: #force_inline proc "contextless" (chars: []rune, n: $N, from, to: i64, $NOCASE: bool) -> (count: i64) {
	// The engine's bounds are 32-bit ints: wrap them as it does.
	from, to := i64(i32(from)), i64(i32(to))
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
find_forward :: #force_inline proc "contextless" (chars: []rune, start, last: int, n: $N, $NOCASE: bool) -> i64 {
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
find_backward :: #force_inline proc "contextless" (chars: []rune, start: int, n: $N, $NOCASE: bool) -> i64 {
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
may_hold_first :: #force_inline proc "contextless" (v: #simd[4]u32, n: $N, $NOCASE: bool) -> bool {
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

// A String searched for by `string_find`, read in place, with its length and first character.
@(private)
Rune_Needle :: struct {
	chars:    []rune,
	count:    int,
	first:    rune,
	fold_bit: u32,
}

@(private)
rune_needle_of :: #force_inline proc "contextless" (chars: []rune, $NOCASE: bool) -> (n: Rune_Needle) {
	n.chars, n.count = chars, len(chars)
	if n.count == 0 { return }
	n.first = chars[0]
	when NOCASE {
		n.first = rune_lower(n.first)
		if n.first >= 'a' && n.first <= 'z' { n.fold_bit = 0x20 }
	}
	return
}

// Whether `n` appears at character `i` of `chars`, which it fits in. Ignoring case, each character
// of both lowers as the engine's `findn` lowers it.
@(private)
rune_needle_at :: #force_inline proc "contextless" (chars: []rune, i: int, n: Rune_Needle, $NOCASE: bool) -> bool {
	when NOCASE {
		if rune_lower(chars[i]) != n.first { return false }
		for k in 1 ..< n.count {
			if rune_lower(chars[i + k]) != rune_lower(n.chars[k]) { return false }
		}
		return true
	} else {
		if chars[i] != n.first { return false }
		return runes_equal(raw_data(chars[i:]), raw_data(n.chars), n.count)
	}
}

// The first place a search from `from` looks, and the last place `n` fits in `length` characters,
// by the engine's rules; not `ok` when `from` is out of range or `n` is empty. `from` is a 32-bit
// int in the engine, so it wraps here as it does there.
@(private)
find_start :: #force_inline proc "contextless" (length: int, n: $N, from: i64) -> (start, last: int, ok: bool) {
	if n.count == 0 { return }
	l := i64(length - n.count)
	from := i64(i32(from))
	f := from if from >= 0 else l + from + 1
	if f < 0 || f > l { return }
	return int(f), int(l), true
}

// Whether `n` appears at character `i` of `chars`, which it fits in.
@(private)
needle_at :: proc {text_needle_at, rune_needle_at}

@(private)
text_needle_at :: #force_inline proc "contextless" (chars: []rune, i: int, n: Needle, $NOCASE: bool) -> bool {
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
	if array_layout_known { return array_stored(a) }
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
// `key` is a `^Variant`, a Variant, or any value `variant` converts. One hash lookup, in place in the
// engine's hash map where `dictionary_has` would look there, else through the engine's keyed get.
// You destroy the value.
dict_get :: proc "contextless" (d: ^Dictionary, key: $K) -> (value: Variant, found: bool) {
	found = dict_get_into(d, key, &value)
	return
}

// `dict_get` writing the value to `out`, which must hold nothing to destroy: it saves copying the
// result back (bench/). False, with `out` nil, when `d` has no such key.
dict_get_into :: proc "contextless" (d: ^Dictionary, key: $K, out: ^Variant) -> bool {
	when K == ^Variant {
		k := key
	} else when K == Variant {
		kv := variant_reload(key)
		k := (^Variant)(&kv)
	} else {
		kv := variant(key)
		k := &kv
		defer gde.variant_destroy(&kv)
	}
	e, ok := dict_lookup(d, k)
	if ok {
		if e == nil { return false }
		out^ = stored_copy(&e.value)
		return true
	}
	self := borrowed(.DICTIONARY, d)
	valid: gde.Bool
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


// True when a String is the engine's copy-on-write storage as `string_read` reads it and
// `string_storage` builds it: one pointer to the characters, null when empty, after a header of
// 64-bit reference count, capacity and size, the size counting the terminator 16 bytes before them.
// `check_string_layout` decides it at load; without it `string_read` asks the engine, two calls
// more, and `string_storage` resizes through the engine.
@(private)
string_layout_known: bool

// Where the size sits before a String's characters.
@(private)
STRING_SIZE_OFFSET :: 16

// Where a String's characters sit after the start of its storage: the reference count, capacity and
// size, each 64 bits, padded to 16 bytes.
@(private)
STRING_DATA_OFFSET :: 32

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
	// The header before the characters: the reference count, the capacity, then the size.
	holds :: proc "contextless" (s: ^String, n: int, refs: i64) -> bool {
		p := (^rawptr)(s)^
		if p == nil || p != rawptr(gde.string_operator_index_const(s, 0)) { return false }
		h := ([^]i64)(uintptr(p) - STRING_DATA_OFFSET)
		return h[0] == refs && h[1] >= i64(n) + 1 && h[2] == i64(n) + 1 && uintptr(p) - STRING_SIZE_OFFSET == uintptr(&h[2])
	}
	short :: "abc"
	long :: "a longer String, past any small-size storage"
	a := string_of(short)
	b := string_new_from_string(a)
	c := string_of(long)
	string_append_rune(&c, '!')
	string_layout_known = holds(&a, len(short), 2) && holds(&b, len(short), 2) && holds(&c, len(long) + 1, 1)
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
