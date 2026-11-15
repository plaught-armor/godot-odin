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
	for &s, i in packed_write_string(&out) { s = string_copy(&xs[i]) }
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

// `string_read` of a String passed by value, read from the value itself. Taking the parameter's
// address instead costs a stall of about 7 ns once the proc is inlined: the compiler then holds the
// String's eight opaque bytes apart, stores them one at a time and loads them back as one pointer.
@(private)
string_chars :: #force_inline proc "contextless" (s: String) -> []rune {
	if string_layout_known {
		p := transmute([^]rune)s
		if p == nil { return nil }
		n := (^i64)(uintptr(p) - STRING_SIZE_OFFSET)^ - 1
		if n <= 0 { return nil }
		return p[:n]
	}
	s := s
	return string_read(&s)
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
	return count_in(string_read(self), rune_needle_of(string_chars(what), false), from, to, false)
}

// `string_count` ignoring case: the engine's `countn`.
string_countn :: proc "contextless" (self: ^String, what: String, from: i64, to: i64) -> i64 {
	return count_in(string_read(self), rune_needle_of(string_chars(what), true), from, to, true)
}

// How many parts `delimiter` cuts `self` into: the engine's `get_slice_count`. One more than the
// places `delimiter` is found, not overlapping, and 0 when either String is empty.
string_get_slice_count :: proc "contextless" (self: ^String, delimiter: String) -> i64 {
	chars, d := string_read(self), string_chars(delimiter)
	if len(chars) == 0 || len(d) == 0 { return 0 }
	return count_in(chars, rune_needle_of(d, false), 0, 0, false) + 1
}

// Whether the characters of `self` appear in `text` in the same order, with any others between
// them: the engine's `is_subsequence_of`. An empty `self` gives true.
string_is_subsequence_of :: proc "contextless" (self: ^String, text: String) -> bool {
	return runes_subsequence(string_read(self), string_chars(text), false)
}

// `string_is_subsequence_of` ignoring case: the engine's `is_subsequence_ofn`.
string_is_subsequence_ofn :: proc "contextless" (self: ^String, text: String) -> bool {
	return runes_subsequence(string_read(self), string_chars(text), true)
}

// Whether `self` fits the pattern `expr`, where `*` stands for any characters and `?` for one
// character other than a full stop: the engine's `match`. False when either String is empty.
string_match :: proc "contextless" (self: ^String, expr: String) -> bool {
	return runes_wildcard(string_chars(expr), string_read(self), false)
}

// `string_match` ignoring case: the engine's `matchn`.
string_matchn :: proc "contextless" (self: ^String, expr: String) -> bool {
	return runes_wildcard(string_chars(expr), string_read(self), true)
}

// Whether the characters of `part` appear in `whole` in order, compared lowered when `NOCASE`. The
// engine walks both to their terminator, so a zero character ends either one there: `part` counts
// as found once the characters before its zero are, unless the zero comes first, and `whole` is
// searched only up to its zero.
@(private)
runes_subsequence :: #force_inline proc "contextless" (part, whole: []rune, $NOCASE: bool) -> bool {
	if len(part) == 0 { return true }
	if len(part) > len(whole) { return false }
	at := 0
	#no_bounds_check for c in whole {
		want := part[at]
		if want == 0 || c == 0 { return false }
		when NOCASE {
			if rune_lower(want) != rune_lower(c) { continue }
		} else {
			if want != c { continue }
		}
		at += 1
		if at == len(part) || part[at] == 0 { return true }
	}
	return false
}

// Whether `text` fits `pattern`, compared raised when `NOCASE`; false when either is empty. The
// engine tries every length for each `*` by calling itself. This remembers only the last `*` and
// how much of `text` it has taken, and on a mismatch gives it one character more: an earlier `*`
// never needs to take more, since the last one can take any characters at all. A zero character
// ends `pattern` or `text`, as the engine's terminator does. Both must be the characters of a
// String, which that terminator follows: it is read as the character one past the end, and
// neither index moves past it.
@(private)
runes_wildcard :: proc "contextless" (pattern, text: []rune, $NOCASE: bool) -> bool {
	if len(pattern) == 0 || len(text) == 0 { return false }
	p, t := 0, 0
	star, taken := -1, 0
	// `taken` only grows and stays within `text`, and between two growths `p` only grows and stays
	// within `pattern`, so the rounds below cover every step.
	#no_bounds_check for _ in 0 ..< (len(pattern) + 2) * (len(text) + 2) {
		pc, tc := pattern[p], text[t]
		if pc == '*' {
			star, taken = p, t
			p += 1
			continue
		}
		if pc == 0 && tc == 0 { return true }
		// A zero `tc` is the end of `text` and fits nothing; a zero `pc` equals no other character.
		fits: bool
		when NOCASE {
			fits = tc != '.' if pc == '?' else rune_upper(tc) == rune_upper(pc)
		} else {
			fits = tc != '.' if pc == '?' else tc == pc
		}
		if fits && tc != 0 {
			p += 1
			t += 1
			continue
		}
		if star < 0 || text[taken] == 0 { return false }
		taken += 1
		p, t = star + 1, taken
	}
	return false
}

// Whether `self` starts with `text`: the engine's `begins_with`. Empty `text` gives true.
string_begins_with :: proc "contextless" (self: ^String, text: String) -> bool {
	chars, t := string_read(self), string_chars(text)
	return len(t) <= len(chars) && runes_equal(raw_data(chars), raw_data(t), len(t))
}

// Whether `self` ends with `text`: the engine's `ends_with`. Empty `text` gives true.
string_ends_with :: proc "contextless" (self: ^String, text: String) -> bool {
	chars, t := string_read(self), string_chars(text)
	return len(t) <= len(chars) && runes_equal(raw_data(chars[len(chars) - len(t):]), raw_data(t), len(t))
}

// What an empty String's characters start at: the terminator alone.
@(private)
rune_end: rune

// Where the characters of a String start, which its terminator follows, so a walk that stops at
// a zero character needs no length. `chars` is the whole of a String's characters.
@(private)
runes_terminated :: #force_inline proc "contextless" (chars: []rune) -> [^]rune {
	return raw_data(chars) if len(chars) > 0 else ([^]rune)(&rune_end)
}

@(private)
rune_is_digit :: #force_inline proc "contextless" (c: rune) -> bool {
	return c >= '0' && c <= '9'
}

// Walks `a` and `b` as the engine's natural compares do, and with FILE as its file compares do.
// Either ends at its first zero character. In order:
// - FILE only: while both start with `_` it is skipped, and where one does and the other has a
//   character left, the `_` sorts first unless the other character is `.`.
// - While either starts with `.`: the one that does sorts first, and when both do the `.` is
//   skipped and the one that ends there sorts first, `b` checked before `a`.
// - Then character by character, uppercased with NOCASE. A run of digits sorts before any other
//   character, and two runs compare as numbers: without their leading zeros the shorter is less,
//   and equal lengths compare digit by digit.
@(private)
compare_natural :: proc "contextless" (a, b: []rune, $NOCASE: bool, $FILE: bool) -> i64 {
	// Read through the terminators, as the engine does: nothing below steps past one.
	na, nb := len(a), len(b)
	a, b := runes_terminated(a), runes_terminated(b)
	i, j := 0, 0
	when FILE {
		for (a[i] == '_' && b[j] != 0) || (a[i] != 0 && b[j] == '_') {
			x, y := a[i], b[j]
			if x != '_' { return -1 if x == '.' else 1 }
			if y != '_' { return 1 if y == '.' else -1 }
			i += 1
			j += 1
		}
	}
	for a[i] == '.' || b[j] == '.' {
		if a[i] != '.' { return 1 }
		if b[j] != '.' { return -1 }
		i += 1
		j += 1
		if b[j] == 0 { return 1 }
		if a[i] == 0 { return -1 }
	}
	for {
		// Four characters at a time while they are the same in both, none a digit or a zero: the
		// steps below would only skip them one by one.
		for i + 4 <= na && j + 4 <= nb {
			x := intrinsics.unaligned_load((^#simd[4]u32)(&a[i]))
			y := intrinsics.unaligned_load((^#simd[4]u32)(&b[j]))
			stop := intrinsics.simd_bit_or(intrinsics.simd_lanes_ne(x, y), intrinsics.simd_lanes_eq(x, (#simd[4]u32)(0)))
			stop = intrinsics.simd_bit_or(stop, intrinsics.simd_lanes_lt(x - (#simd[4]u32)('0'), (#simd[4]u32)(10)))
			if intrinsics.simd_reduce_or(stop) != 0 { break }
			i += 4
			j += 4
		}
		x, y := a[i], b[j]
		// The common step first: the same character in both, not a digit and not the end.
		if x == y && x != 0 && !rune_is_digit(x) {
			i += 1
			j += 1
			continue
		}
		if x == 0 { return -1 if y != 0 else 0 }
		if y == 0 { return 1 }
		if !rune_is_digit(x) {
			if rune_is_digit(y) { return 1 }
			when NOCASE { x, y = rune_upper(x), rune_upper(y) }
			if x != y { return -1 if u32(x) < u32(y) else 1 }
			i += 1
			j += 1
			continue
		}
		if !rune_is_digit(y) { return -1 }
		// Both runs of digits: `i` and `j` go to their ends, `i0` and `j0` past their leading
		// zeros, which stop at the end of the run at the latest.
		i0, j0 := i, j
		for rune_is_digit(a[i]) { i += 1 }
		for rune_is_digit(b[j]) { j += 1 }
		for a[i0] == '0' { i0 += 1 }
		for b[j0] == '0' { j0 += 1 }
		if i - i0 != j - j0 { return -1 if i - i0 < j - j0 else 1 }
		for k in 0 ..< i - i0 {
			if a[i0 + k] != b[j0 + k] { return -1 if a[i0 + k] < b[j0 + k] else 1 }
		}
	}
}

// The engine's `naturalcasecmp_to`: -1, 0 or 1 as `self` sorts before, with or after `to`, with
// runs of digits compared as numbers and a leading `.` first.
string_naturalcasecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	return compare_natural(string_read(self), string_chars(to), false, false)
}

// `string_naturalcasecmp_to` with characters uppercased first: the engine's
// `naturalnocasecmp_to`.
string_naturalnocasecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	return compare_natural(string_read(self), string_chars(to), true, false)
}

// `string_naturalcasecmp_to` with a leading `_` before everything but `.`: the engine's
// `filecasecmp_to`.
string_filecasecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	return compare_natural(string_read(self), string_chars(to), false, true)
}

// `string_filecasecmp_to` with characters uppercased first: the engine's `filenocasecmp_to`.
string_filenocasecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	return compare_natural(string_read(self), string_chars(to), true, true)
}

// The engine's `casecmp_to`: -1, 0 or 1 as `self` sorts before, with or after `to`, character by
// character by code point, a shorter String first.
string_casecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	return compare_runes(string_read(self), string_chars(to), false)
}

// `string_casecmp_to` with both characters uppercased first: the engine's `nocasecmp_to`.
string_nocasecmp_to :: proc "contextless" (self: ^String, to: String) -> i64 {
	return compare_runes(string_read(self), string_chars(to), true)
}

// A copy of `self` with every `what` replaced by `forwhat`: the engine's `replace`, made as
// `string_replace_text` makes it. The caller destroys the result.
string_replace :: proc "contextless" (self: ^String, what: String, forwhat: String) -> String {
	return replace_in(self, rune_needle_of(string_chars(what), false), string_chars(forwhat), false)
}

// `string_replace` ignoring case: the engine's `replacen`.
string_replacen :: proc "contextless" (self: ^String, what: String, forwhat: String) -> String {
	return replace_in(self, rune_needle_of(string_chars(what), true), string_chars(forwhat), true)
}

// The parts of `self` between each `delimiter`: the engine's `split`, made as `string_split_text`
// makes it. The caller destroys the result.
string_split :: proc "contextless" (self: ^String, delimiter: String, allow_empty: bool, maxsplit: i64) -> (out: PackedStringArray) {
	return split_make(string_read(self), rune_needle_of(string_chars(delimiter), false), allow_empty, maxsplit)
}

// The `len` characters of `self` from character `from`, or the rest when `len` is -1: the engine's
// `substr`. Empty when `from` is outside `self` or no characters are asked for, and a count past
// the end stops there. Both are 32-bit ints in the engine, so they wrap here as they do there;
// their sum is taken in 64 bits, where the engine's overflows. The caller destroys the result.
string_substr :: proc "contextless" (self: ^String, from: i64, len: i64) -> String {
	return substr_of(self, from, len)
}

// `string_substr`, whose `len` parameter hides the builtin this needs.
@(private)
substr_of :: #force_inline proc "contextless" (self: ^String, from, count: i64) -> String {
	chars := string_read(self)
	length := i64(len(chars))
	from, n := i64(i32(from)), i64(i32(count))
	if n == -1 { n = length - from }
	if from < 0 || from >= length || n <= 0 { return {} }
	return slice_of(self, chars, from, min(n, length - from))
}

// The first `length` characters of `self`, or all but the last `-length` when negative: the
// engine's `left`, `length` wrapped to 32 bits as there. The caller destroys the result.
string_left :: proc "contextless" (self: ^String, length: i64) -> String {
	chars := string_read(self)
	n := i64(i32(length))
	if n < 0 { n += i64(len(chars)) }
	if n <= 0 { return {} }
	return slice_of(self, chars, 0, min(n, i64(len(chars))))
}

// The last `length` characters of `self`, or all but the first `-length` when negative: the
// engine's `right`, `length` wrapped to 32 bits as there. The caller destroys the result.
string_right :: proc "contextless" (self: ^String, length: i64) -> String {
	chars := string_read(self)
	n := i64(i32(length))
	if n < 0 { n += i64(len(chars)) }
	if n <= 0 { return {} }
	n = min(n, i64(len(chars)))
	return slice_of(self, chars, i64(len(chars)) - n, n)
}

// `self` with every character raised as the engine's case table raises it: the engine's
// `to_upper`. The result has its own storage unless `self` is empty. The engine stops at a zero
// character inside the String and leaves what follows unset; here the rest is raised too. The
// caller destroys the result.
string_to_upper :: proc "contextless" (self: ^String) -> (out: String) {
	chars := string_read(self)
	if len(chars) == 0 { return }
	w := string_storage(&out, len(chars) + 1)
	#no_bounds_check for c, i in chars { w[i] = rune_upper(c) }
	w[len(chars)] = 0
	return
}

// `string_to_upper` lowering: the engine's `to_lower`.
string_to_lower :: proc "contextless" (self: ^String) -> (out: String) {
	chars := string_read(self)
	if len(chars) == 0 { return }
	w := string_storage(&out, len(chars) + 1)
	#no_bounds_check for c, i in chars { w[i] = rune_lower(c) }
	w[len(chars)] = 0
	return
}

// Part `slice` of `self` split on `delimiter`, counted from 0: the engine's `get_slice`. Empty when
// either String is empty, when `slice` is negative, a 32-bit int as in the engine, or when there
// are fewer parts; all of `self` when `delimiter` is not in it, whatever `slice` is. The caller
// destroys the result.
string_get_slice :: proc "contextless" (self: ^String, delimiter: String, slice: i64) -> String {
	chars, d := string_read(self), string_chars(delimiter)
	slice := i64(i32(slice))
	if len(chars) == 0 || len(d) == 0 || slice < 0 { return {} }
	pos := find_string(self, delimiter, 0, false)
	if pos == -1 { return string_copy(self) }
	from := i64(0)
	// Each round passes a delimiter of at least one character, so there are at most as many
	// rounds as characters, and one more for the last part.
	for i in 0 ..= i64(len(chars)) {
		if i == slice { return substr_of(self, from, pos - from) }
		if pos == i64(len(chars)) { break }
		from = pos + i64(len(d))
		pos = find_string(self, delimiter, from, false)
		if pos == -1 { pos = i64(len(chars)) }
	}
	return {}
}

// `self` without `prefix` at its start when it begins with it, else a copy: the engine's
// `trim_prefix`. The caller destroys the result.
string_trim_prefix :: proc "contextless" (self: ^String, prefix: String) -> String {
	if !string_begins_with(self, prefix) { return string_copy(self) }
	return substr_of(self, i64(len(string_chars(prefix))), -1)
}

// `self` without `suffix` at its end when it ends with it, else a copy: the engine's
// `trim_suffix`. The caller destroys the result.
string_trim_suffix :: proc "contextless" (self: ^String, suffix: String) -> String {
	if !string_ends_with(self, suffix) { return string_copy(self) }
	return substr_of(self, 0, i64(len(string_read(self)) - len(string_chars(suffix))))
}

// `self` without the whitespace at its `left` and `right` ends, as `runes_strip_edges` trims it:
// the engine's `strip_edges`. A copy that shares the storage when nothing is trimmed. The caller
// destroys the result.
string_strip_edges :: proc "contextless" (self: ^String, left: bool, right: bool) -> String {
	chars := string_read(self)
	kept := runes_strip_edges(chars, left, right)
	if len(kept) == len(chars) { return string_copy(self) }
	return string_of_runes(kept)
}

// The case conventions the engine's `capitalize`, `to_camel_case`, `to_pascal_case`,
// `to_snake_case` and `to_kebab_case` write.
@(private)
Recase :: enum {
	SNAKE,      // lower case words joined by `_`
	KEBAB,      // lower case words joined by `-`
	CAPITALIZE, // words with an upper case first character, joined by a space
	CAMEL,      // the same joined by nothing, the first word all lower case
	PASCAL,     // the same joined by nothing
}

// What the engine asks of a character to find where a word ends.
@(private)
Letter :: enum u8 { OTHER, UPPER, LOWER, DIGIT }

// The class of `c`: an upper or lower case letter of the engine's tables, or an ASCII digit.
@(private)
letter_of :: proc "contextless" (c: rune) -> Letter {
	switch c {
	case 'A' ..= 'Z': return .UPPER
	case 'a' ..= 'z': return .LOWER
	case '0' ..= '9': return .DIGIT
	}
	if u32(c) < 0x80 { return .OTHER }
	if ranges_has(letter_upper, c) { return .UPPER }
	if ranges_has(letter_lower, c) { return .LOWER }
	return .OTHER
}

// Whether `c` lies between words: the engine's whitespace, underscore and hyphens, which it turns
// into a space before it splits.
@(private)
rune_is_gap :: proc "contextless" (c: rune) -> bool {
	switch c {
	case ' ', '_', '-', 0x09 ..= 0x0D, 0x85, 0xA0, 0x1680, 0x2000 ..= 0x200B, 0x2010, 0x2011,
	     0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
		return true
	}
	return false
}

// Writes `c` to `out` at `n^` when it fits, and counts it either way.
@(private)
put_rune :: #force_inline proc "contextless" (out: []rune, n: ^int, c: rune) {
	if n^ < len(out) { out[n^] = c }
	n^ += 1
}

// Writes `text` in the case convention `KIND` to `out`, as much as fits, and returns how many
// characters that takes, so a call with an empty `out` only counts. As the engine's
// `_separate_compound_words`, a word ends before an upper case letter after a lower case one
// (aA), before an upper case letter after an upper case one or a digit when a lower case one
// follows (AAa, 2Aa), before a lower case letter after a digit when a lower case one follows
// (2aa), before a digit after a letter (A2, a2), and at each gap. For the three conventions of
// words the engine drops empty words, and `text` must have its edges trimmed by `runes_trim_gaps`.
@(private)
runes_recase :: proc "contextless" (text: []rune, out: []rune, $KIND: Recase) -> int {
	n := 0
	prev := Letter.OTHER
	curr := letter_of(text[0]) if len(text) > 0 else Letter.OTHER
	starts := true // The next character written is the first of a word.
	for c, i in text {
		next := letter_of(text[i + 1]) if i + 1 < len(text) else Letter.OTHER
		split := (prev == .LOWER && curr == .UPPER) ||
			((prev == .UPPER || prev == .DIGIT) && curr == .UPPER && next == .LOWER) ||
			(prev == .DIGIT && curr == .LOWER && next == .LOWER) ||
			((prev == .UPPER || prev == .LOWER) && curr == .DIGIT)
		prev, curr = curr, next
		when KIND == .SNAKE || KIND == .KEBAB {
			JOIN :: '_' when KIND == .SNAKE else '-'
			if split { put_rune(out, &n, JOIN) }
			put_rune(out, &n, JOIN if rune_is_gap(c) else rune_lower(c))
		} else {
			if rune_is_gap(c) {
				starts = true
				continue
			}
			lowered := rune_lower(c)
			if split || starts {
				// The engine changes the case of the first character of a word it has
				// already lowered.
				when KIND == .CAMEL {
					lowered = rune_lower(lowered) if n == 0 else rune_upper(lowered)
				} else {
					lowered = rune_upper(lowered)
				}
				when KIND == .CAPITALIZE {
					if n > 0 { put_rune(out, &n, ' ') }
				}
				starts = false
			}
			put_rune(out, &n, lowered)
		}
	}
	return n
}

// `chars` without the gaps and the characters up to the space at its ends: what the engine's
// `strip_edges` cuts from words once their gaps are spaces.
@(private)
runes_trim_gaps :: proc "contextless" (chars: []rune) -> []rune {
	beg, end := 0, len(chars)
	for _ in 0 ..< len(chars) {
		if beg == end || (u32(chars[beg]) > 32 && !rune_is_gap(chars[beg])) { break }
		beg += 1
	}
	for _ in 0 ..< len(chars) {
		if end == beg || (u32(chars[end - 1]) > 32 && !rune_is_gap(chars[end - 1])) { break }
		end -= 1
	}
	return chars[beg:end]
}

// The longest text `string_recased` writes in one pass, into a buffer on the stack.
@(private)
RECASE_SHORT :: 128

// A String of `self` in the case convention `KIND`, in storage of its own. A text of up to
// RECASE_SHORT characters is written once into a buffer of twice that, which holds a join before
// every character, and copied; a longer one is counted first and then written into the storage.
@(private)
string_recased :: #force_inline proc "contextless" (self: ^String, $KIND: Recase) -> (out: String) {
	text := string_read(self)
	when KIND != .SNAKE && KIND != .KEBAB { text = runes_trim_gaps(text) }
	if len(text) <= RECASE_SHORT {
		buf: [RECASE_SHORT * 2]rune = ---
		n := runes_recase(text, buf[:], KIND)
		if n == 0 { return }
		w := string_storage(&out, n + 1)
		copy(w[:n], buf[:n])
		w[n] = 0
		return
	}
	n := runes_recase(text, nil, KIND)
	if n == 0 { return }
	w := string_storage(&out, n + 1)
	runes_recase(text, w[:n], KIND)
	w[n] = 0
	return
}

// `self` as words with an upper case first character, joined by a space: the engine's
// `capitalize`. The caller destroys the result.
string_capitalize :: proc "contextless" (self: ^String) -> String { return string_recased(self, .CAPITALIZE) }

// `self` as camelCase: the engine's `to_camel_case`. The caller destroys the result.
string_to_camel_case :: proc "contextless" (self: ^String) -> String { return string_recased(self, .CAMEL) }

// `self` as PascalCase: the engine's `to_pascal_case`. The caller destroys the result.
string_to_pascal_case :: proc "contextless" (self: ^String) -> String { return string_recased(self, .PASCAL) }

// `self` as snake_case: the engine's `to_snake_case`. The caller destroys the result.
string_to_snake_case :: proc "contextless" (self: ^String) -> String { return string_recased(self, .SNAKE) }

// `self` as kebab-case: the engine's `to_kebab_case`. The caller destroys the result.
string_to_kebab_case :: proc "contextless" (self: ^String) -> String { return string_recased(self, .KEBAB) }

// Where `c` first is in `chars` at or after `from`, or -1: the engine's `find_char` for a `from`
// that is not negative.
@(private)
runes_index :: proc "contextless" (chars: []rune, c: rune, from: int) -> int {
	for i in from ..< len(chars) {
		if chars[i] == c { return i }
	}
	return -1
}

// Where the last `/` or `\` is in `chars`, or -1.
@(private)
runes_last_separator :: proc "contextless" (chars: []rune) -> int {
	#reverse for c, i in chars {
		if c == '/' || c == '\\' { return i }
	}
	return -1
}

// Where the full stop that starts the extension is in `chars`: the last one, when no `/` or `\`
// follows it. -1 when there is none.
@(private)
runes_extension_dot :: proc "contextless" (chars: []rune) -> int {
	#reverse for c, i in chars {
		if c == '.' { return i }
		if c == '/' || c == '\\' { break }
	}
	return -1
}

// The first `n` characters of `self`, which has them: empty for none, a copy that shares the
// storage for all.
@(private)
head_of :: #force_inline proc "contextless" (self: ^String, chars: []rune, n: int) -> String {
	if n == 0 { return {} }
	return slice_of(self, chars, 0, i64(n))
}

// The characters of `self` from `from`, which is at most its length: empty for none, a copy that
// shares the storage for all.
@(private)
tail_of :: #force_inline proc "contextless" (self: ^String, chars: []rune, from: int) -> String {
	if from == len(chars) { return {} }
	return slice_of(self, chars, i64(from), i64(len(chars) - from))
}

// What follows the last full stop of the file name in path `self`, or empty when it has none:
// the engine's `get_extension`. The caller destroys the result.
string_get_extension :: proc "contextless" (self: ^String) -> String {
	chars := string_read(self)
	dot := runes_extension_dot(chars)
	if dot == -1 { return {} }
	return tail_of(self, chars, dot + 1)
}

// Path `self` without its extension and the full stop before it, or a copy when it has none: the
// engine's `get_basename`. The caller destroys the result.
string_get_basename :: proc "contextless" (self: ^String) -> String {
	chars := string_read(self)
	dot := runes_extension_dot(chars)
	if dot == -1 { return string_copy(self) }
	return head_of(self, chars, dot)
}

// What follows the last `/` or `\` of path `self`, or a copy when it has neither: the engine's
// `get_file`. The caller destroys the result.
string_get_file :: proc "contextless" (self: ^String) -> String {
	chars := string_read(self)
	return tail_of(self, chars, runes_last_separator(chars) + 1)
}

// Path `self` up to its last `/` or `\`: the engine's `get_base_dir`. The start that is a URL
// scheme (`res://`), a drive (`C:/`), a network share (`//server/share/`) or the root `/` is
// kept whole, and the last separator is looked for after it. The caller destroys the result.
string_get_base_dir :: proc "contextless" (self: ^String) -> String {
	chars := string_read(self)
	base := 0
	colon, width := string_find_text(self, "://"), 3
	if colon == -1 { colon, width = string_find_text(self, ":/"), 2 }
	if colon == -1 { colon = string_find_text(self, ":\\") }
	if colon != -1 {
		base = int(colon) + width
	} else if runes_is_share(chars) {
		// The engine looks for the separator after the server's name from
		// character 2, and for the one after the share's name from the character after that
		// separator, which is character 0 when there is none.
		server := runes_index(chars, '/', 2)
		if server == -1 { server = runes_index(chars, '\\', 2) }
		share := runes_index(chars, '/', server + 1)
		if share == -1 { share = runes_index(chars, '\\', server + 1) }
		if share != -1 { base = share + 1 }
	}
	if base == 0 && len(chars) > 0 && chars[0] == '/' { base = 1 }
	return head_of(self, chars, base + max(runes_last_separator(chars[base:]), 0))
}

// Whether path `chars` starts with `//` or `\\\\`, as a network share does: the engine's
// `is_network_share_path`.
@(private)
runes_is_share :: #force_inline proc "contextless" (chars: []rune) -> bool {
	return len(chars) >= 2 && chars[0] == chars[1] && (chars[0] == '/' || chars[0] == '\\')
}

@(private)
rune_is_separator :: #force_inline proc "contextless" (c: rune) -> bool {
	return c == '/' || c == '\\'
}

// How many characters at the start of path `self` the engine's `simplify_path` keeps as they are,
// by its order of tests: a scheme of ASCII letters and digits with its `://`; the two separators
// of a network share; one leading separator; a drive, which is everything up to a `:/` or, when
// there is no `:/`, a `:\`, and counts only when that is before the first `/`.
@(private)
runes_path_drive :: proc "contextless" (self: ^String, chars: []rune) -> int {
	if scheme := int(string_find_text(self, "://")); scheme > 0 {
		plain := true
		for c in chars[:scheme] {
			if !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || rune_is_digit(c)) { plain = false }
		}
		if plain { return scheme + 3 }
	}
	if runes_is_share(chars) { return 2 }
	if len(chars) > 0 && rune_is_separator(chars[0]) { return 1 }
	colon := string_find_text(self, ":/")
	if colon == -1 { colon = string_find_text(self, ":\\") }
	if colon != -1 && int(colon) < runes_index(chars, '/', 0) { return int(colon) + 2 }
	return 0
}

// Writes path `self`, whose characters are `chars`, to `out` as the engine's `simplify_path`
// leaves it and returns how many characters that is, never more than `chars` has. The start
// `runes_path_drive` counts is copied. The names after it, which are the runs between
// separators, are written with one `/` between them, but:
// - `.` is left out;
// - `..` takes back the name written before it, unless that is `..` too;
// - `..` with no name before it is left out of an absolute path that is not under `res://`.
@(private)
runes_simplify_path :: proc "contextless" (self: ^String, chars: []rune, out: []rune) -> int {
	drive := runes_path_drive(self, chars)
	copy(out[:drive], chars[:drive])
	absolute := runes_is_absolute_path(chars) && !string_begins_with_text(self, "res://")
	n := drive
	for i := drive; i < len(chars); {
		if rune_is_separator(chars[i]) {
			i += 1
			continue
		}
		start := i
		for i < len(chars) && !rune_is_separator(chars[i]) { i += 1 }
		name := chars[start:i]
		if len(name) == 1 && name[0] == '.' { continue }
		if len(name) == 2 && name[0] == '.' && name[1] == '.' {
			if n == drive {
				if absolute { continue }
			} else {
				// The name written last starts after the last `/` written, or at `drive`.
				last := n
				for last > drive && out[last - 1] != '/' { last -= 1 }
				if !(n - last == 2 && out[last] == '.' && out[last + 1] == '.') {
					n = max(last - 1, drive)
					continue
				}
			}
		}
		if n > drive {
			out[n] = '/'
			n += 1
		}
		copy(out[n:], name)
		n += len(name)
	}
	return n
}

// The longest path `string_simplify_path` works out on the stack.
@(private)
PATH_SHORT :: 256

// Path `self` without `.` names, doubled separators and the `..` names that a name before them
// cancels, its separators after the start as `/`: the engine's `simplify_path`. A path that is
// simple already comes back as a copy that shares the storage. The caller destroys the result.
string_simplify_path :: proc "contextless" (self: ^String) -> String {
	chars := string_read(self)
	if len(chars) <= PATH_SHORT {
		buf: [PATH_SHORT]rune = ---
		n := runes_simplify_path(self, chars, buf[:])
		if n == len(chars) && runes_equal(raw_data(chars), raw_data(buf[:]), n) { return string_copy(self) }
		return string_of_runes(buf[:n])
	}
	// A longer path is worked out in a String of its length, which is then copied to size.
	whole: String
	defer destroy[.STRING](&whole)
	w := string_storage(&whole, len(chars) + 1)[:len(chars) + 1]
	n := runes_simplify_path(self, chars, w[:len(chars)])
	w[n] = 0
	return string_of_runes(w[:n])
}

// Path `self` with `path` after it and one `/` between them, unless `self` ends with one or `path`
// starts with one; a copy of `path` when `self` is empty: the engine's `path_join`. The caller
// destroys the result.
string_path_join :: proc "contextless" (self: ^String, path: String) -> (out: String) {
	path := path
	a, b := string_read(self), string_chars(path)
	if len(a) == 0 { return string_copy(&path) }
	slash := int(a[len(a) - 1] != '/' && (len(b) == 0 || b[0] != '/'))
	if len(b) == 0 && slash == 0 { return string_copy(self) }
	n := len(a) + slash + len(b)
	w := string_storage(&out, n + 1)
	copy(w[:len(a)], a)
	if slash == 1 { w[len(a)] = '/' }
	copy(w[len(a) + slash:n], b)
	w[n] = 0
	return
}

// `self` `count` times over: the engine's `repeat`. A negative `count` prints the engine's error
// and gives an empty String. The caller destroys the result.
string_repeat :: proc "contextless" (self: ^String, count: i64) -> (out: String) {
	count := i64(i32(count))
	if count < 0 {
		math_error("Parameter count should be a positive number.")
		return
	}
	a := string_read(self)
	if count == 0 { return }
	if count == 1 || len(a) == 0 { return string_copy(self) }
	n := len(a) * int(count)
	w := string_storage(&out, n + 1)
	copy(w[:len(a)], a)
	// Each round copies what is written so far, so the written part doubles.
	for done := len(a); done < n; {
		step := min(done, n - done)
		copy(w[done:][:step], w[:step])
		done += step
	}
	w[n] = 0
	return
}

// `self` with its characters in the opposite order: the engine's `reverse`. The caller destroys
// the result.
string_reverse :: proc "contextless" (self: ^String) -> (out: String) {
	a := string_read(self)
	n := len(a)
	if n <= 1 { return string_copy(self) }
	w := string_storage(&out, n + 1)
	for i in 0 ..< n { w[i] = a[n - 1 - i] }
	w[n] = 0
	return
}

// `self` with `what` put in before character `position`, or at the end when `position` is past
// it; a copy of `self` when `what` is empty or `position` is negative: the engine's `insert`. The
// caller destroys the result.
string_insert :: proc "contextless" (self: ^String, position: i64, what: String) -> (out: String) {
	a, b := string_read(self), string_chars(what)
	position := i64(i32(position))
	if len(b) == 0 || position < 0 { return string_copy(self) }
	at := int(min(position, i64(len(a))))
	n := len(a) + len(b)
	w := string_storage(&out, n + 1)
	copy(w[:at], a[:at])
	copy(w[at:][:len(b)], b)
	copy(w[at + len(b):n], a[at:])
	w[n] = 0
	return
}

// `self` without the `chars` characters from `position` on: the engine's `erase`. A negative
// `position` or `chars` prints the engine's error and gives an empty String. The caller destroys
// the result.
string_erase :: proc "contextless" (self: ^String, position: i64, chars: i64) -> (out: String) {
	position, chars := i64(i32(position)), i64(i32(chars))
	if position < 0 {
		erase_error("Invalid starting position for `String.erase()`: ", position, ". Starting position must be positive or zero.")
		return
	}
	if chars < 0 {
		erase_error("Invalid character count for `String.erase()`: ", chars, ". Character count must be positive or zero.")
		return
	}
	a := string_read(self)
	head := int(min(position, i64(len(a))))
	// The engine adds the two as 32-bit integers, and keeps nothing after a sum that is negative
	// or past the end.
	from := i64(i32(position + chars))
	tail := int(from) if from >= 0 && from < i64(len(a)) else len(a)
	n := head + len(a) - tail
	if n == len(a) { return string_copy(self) }
	if n == 0 { return }
	w := string_storage(&out, n + 1)
	copy(w[:head], a[:head])
	copy(w[head:n], a[tail:])
	w[n] = 0
	return
}

// Logs the engine's error for a negative `value` given to `erase`.
@(private)
erase_error :: proc "contextless" (before: string, value: i64, after: string) {
	buf: [128]u8
	k := copy(buf[:], before)
	k += decimal_into(buf[k:], value)
	k += copy(buf[k:len(buf) - 1], after)
	buf[k] = 0
	gde.print_error(cstring(&buf[0]), "", #file, #line, 1)
}

// `self` with each `key` character replaced by `with`: the engine's `replace_char`, which takes
// the low 32 bits of each. A copy of `self` when it has no `key`; a `with` of 0 prints the
// engine's error and gives a copy too. The caller destroys the result.
string_replace_char :: proc "contextless" (self: ^String, key: i64, with: i64) -> (out: String) {
	k, v := rune(u32(key)), rune(u32(with))
	if v == 0 {
		math_error("`with` must not be the NUL character.")
		return string_copy(self)
	}
	a := string_read(self)
	first := -1 if k == 0 else runes_index(a, k, 0)
	if first < 0 { return string_copy(self) }
	w := string_storage(&out, len(a) + 1)
	copy(w[:first], a[:first])
	for i in first ..< len(a) { w[i] = v if a[i] == k else a[i] }
	w[len(a)] = 0
	return
}

// `self` without its `what` characters: the engine's `remove_char`, which takes the low 32 bits
// of `what`. A copy of `self` when it has none. The caller destroys the result.
string_remove_char :: proc "contextless" (self: ^String, what: i64) -> (out: String) {
	k := rune(u32(what))
	a := string_read(self)
	first := -1 if k == 0 else runes_index(a, k, 0)
	if first < 0 { return string_copy(self) }
	hits := 0
	for c in a[first:] { hits += int(c == k) }
	n := len(a) - hits
	if n == 0 { return }
	w := string_storage(&out, n + 1)
	copy(w[:first], a[:first])
	// Every character is written at `j`, which only moves past the ones kept; `j` stays within
	// `n`, where the terminator goes last.
	j := first
	for c in a[first + 1:] {
		w[j] = c
		j += int(c != k)
	}
	w[n] = 0
	return
}

// Whether `c` is one of `set`.
runes_has :: proc "contextless" (set: []rune, c: rune) -> bool {
	for s in set {
		if s == c { return true }
	}
	return false
}

// `self` without the run of characters of `chars` at its start: the engine's `lstrip`. A copy
// that shares the storage when nothing is cut. The caller destroys the result.
string_lstrip :: proc "contextless" (self: ^String, chars: String) -> String {
	text, set := string_read(self), string_chars(chars)
	beg := 0
	for c in text {
		if !runes_has(set, c) { break }
		beg += 1
	}
	return slice_of(self, text, i64(beg), i64(len(text) - beg))
}

// `self` without the run of characters of `chars` at its end: the engine's `rstrip`. A copy that
// shares the storage when nothing is cut. The caller destroys the result.
string_rstrip :: proc "contextless" (self: ^String, chars: String) -> String {
	text, set := string_read(self), string_chars(chars)
	end := len(text)
	#reverse for c in text {
		if !runes_has(set, c) { break }
		end -= 1
	}
	return slice_of(self, text, 0, i64(end))
}

// A String of the `n` characters of `chars` from `from`, which lie inside it, `n` at least 1.
// All of `chars`, the characters of `self`, is a copy that shares its storage, as the engine
// returns.
@(private)
slice_of :: #force_inline proc "contextless" (self: ^String, chars: []rune, from, n: i64) -> String {
	if n == i64(len(chars)) { return string_copy(self) }
	return string_of_runes(chars[from:][:n])
}

// Walks `a` and `b` as the engine's `casecmp_to` and `nocasecmp_to` do: an empty String sorts
// first, and either ends at its first zero character, so one embedded ends the comparison there.
@(private)
compare_runes :: #force_inline proc "contextless" (a, b: []rune, $NOCASE: bool) -> i64 {
	if len(a) == 0 { return 0 if len(b) == 0 else -1 }
	if len(b) == 0 { return 1 }
	k := 0
	when !NOCASE {
		// Skip the equal start four characters at a time, stopping before a zero character, which
		// ends the walk: the loop below then decides from the first four that differ or hold one.
		pa, pb := raw_data(a), raw_data(b)
		for m := min(len(a), len(b)); k + 4 <= m; k += 4 {
			x := intrinsics.unaligned_load((^#simd[4]u32)(&pa[k]))
			y := intrinsics.unaligned_load((^#simd[4]u32)(&pb[k]))
			stop := intrinsics.simd_bit_or(intrinsics.simd_lanes_ne(x, y), intrinsics.simd_lanes_eq(x, (#simd[4]u32)(0)))
			if intrinsics.simd_reduce_or(stop) != 0 { break }
		}
	}
	for ; k <= min(len(a), len(b)); k += 1 {
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
	chars := string_read(self)
	n := rune_needle_of(string_chars(what), NOCASE)
	start, last, ok := find_start(len(chars), n, from)
	if !ok { return -1 }
	return find_forward(chars, start, last, n, NOCASE)
}

@(private)
rfind_string :: #force_inline proc "contextless" (self: ^String, what: String, from: i64, $NOCASE: bool) -> i64 {
	chars := string_read(self)
	n := rune_needle_of(string_chars(what), NOCASE)
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
	if hits == 0 { return string_copy(s) }
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
	v, _ := runes_parse_int(chars)
	return v
}

// `runes_to_int`, and whether the value passed the 64-bit range, where the engine prints an error.
@(private)
runes_parse_int :: proc "contextless" (chars: []rune) -> (value: i64, overflow: bool) {
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
					return max(i64) if positive else min(i64), true
				}
			}
			integer = integer * 10 + u64(c - '0')
			digits += 1
		} else if integer == 0 && c == '-' {
			positive = !positive
		}
	}
	return i64(integer) if positive else i64(0 - integer), false
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
runes_to_float :: proc "contextless" (chars: []rune) -> f64 {
	v, _ := runes_parse_float(chars)
	return v
}

// `runes_to_float`, and whether the exponent passed 511, where the engine prints a warning.
@(private)
runes_parse_float :: proc "contextless" (chars: []rune) -> (value: f64, clipped: bool) #no_bounds_check {
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
	if digits == 0 { return -0.0 if negative else 0.0, false }
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
		if q >= n || chars[q] < '0' || chars[q] > '9' { return -fraction if negative else fraction, false }
		for ; q < n && chars[q] >= '0' && chars[q] <= '9'; q += 1 {
			// The engine's exponent is a 32-bit int: past it, it wraps there too.
			exp = int(i32(exp) * 10 + i32(chars[q] - '0'))
		}
		if exp_negative { exp = -exp }
	}
	exp = int(i32(frac_exp + exp))
	scale_down := exp < 0
	clipped = abs(exp) > 511
	exp = min(abs(exp), 511)
	scale := 1.0
	for power in FLOAT_POWERS {
		if exp == 0 { break }
		if exp & 1 != 0 { scale *= power }
		exp >>= 1
	}
	fraction = fraction / scale if scale_down else fraction * scale
	return -fraction if negative else fraction, clipped
}

// Whether `chars` spell an integer as the engine's `is_valid_int` reads a String: ASCII digits only,
// after a '+' or '-' when there is more than it.
runes_is_valid_int :: proc "contextless" (chars: []rune) -> bool {
	if len(chars) == 0 { return false }
	from := 1 if len(chars) > 1 && (chars[0] == '+' || chars[0] == '-') else 0
	for c in chars[from:] {
		if c < '0' || c > '9' { return false }
	}
	return true
}

// Whether `chars` are a path the engine's `is_absolute_path` calls absolute: one starting with '/'
// or '\\', or, when longer than one character, holding ":/" or ":\\" anywhere.
runes_is_absolute_path :: proc "contextless" (chars: []rune) -> bool {
	if len(chars) == 0 { return false }
	if chars[0] == '/' || chars[0] == '\\' { return true }
	for i in 1 ..< len(chars) {
		if chars[i - 1] == ':' && (chars[i] == '/' || chars[i] == '\\') { return true }
	}
	return false
}

// Whether `chars` spell an identifier as the engine's `is_valid_ascii_identifier` reads a String:
// ASCII letters, digits and '_', not starting with a digit, and not empty.
runes_is_valid_ascii_identifier :: proc "contextless" (chars: []rune) -> bool {
	if len(chars) == 0 || (chars[0] >= '0' && chars[0] <= '9') { return false }
	for c in chars {
		letter := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
		if !letter && (c < '0' || c > '9') && c != '_' { return false }
	}
	return true
}

// The value of hexadecimal digit `c` in either case, or -1.
@(private)
hex_digit :: #force_inline proc "contextless" (c: rune) -> i64 {
	if d := u32(c) - '0'; d <= 9 { return i64(d) }
	// Setting bit 5 turns an upper-case ASCII letter into its lower-case one.
	if d := (u32(c) | 0x20) - 'a'; d <= 5 { return i64(d) + 10 }
	return -1
}

// Whether `chars` spell a hexadecimal number as the engine's `is_valid_hex_number` reads a String:
// a '+' or '-' when there is more than it, "0x" when `with_prefix`, then one hexadecimal digit or
// more.
runes_is_valid_hex_number :: proc "contextless" (chars: []rune, with_prefix: bool) -> bool {
	n := len(chars)
	if n == 0 { return false }
	from := 1 if n != 1 && (chars[0] == '+' || chars[0] == '-') else 0
	if with_prefix {
		if n < 3 || chars[from] != '0' || chars[from + 1] != 'x' { return false }
		from += 2
	}
	if from == n { return false }
	for c in chars[from:] {
		if hex_digit(c) < 0 { return false }
	}
	return true
}

// Whether `chars` name a file as the engine's `is_valid_filename` reads a String: not empty, no
// character of code 32 or less at either end, and none of : / \ ? * " | % < > anywhere.
runes_is_valid_filename :: proc "contextless" (chars: []rune) -> bool {
	n := len(chars)
	if n == 0 || u32(chars[0]) <= 32 || u32(chars[n - 1]) <= 32 { return false }
	for c in chars {
		switch c {
		case ':', '/', '\\', '?', '*', '"', '|', '%', '<', '>': return false
		}
	}
	return true
}

// The integer `chars` spell in base 2 (`bits` 1) or 16 (`bits` 4), as the engine's `bin_to_int` and
// `hex_to_int` read a String: a '-', then "0b" or "0x" in either case when the whole text is longer
// than two characters, then digits up to the end or the first 0 character. A character that is no
// digit makes the binary value 0. False where the engine prints an error, on a hexadecimal
// character that is no digit and on a value past the 64-bit range: the engine is called then.
runes_parse_radix :: #force_inline proc "contextless" (chars: []rune, bits: uint) -> (value: i64, ok: bool) {
	s := chars
	if len(s) == 0 { return 0, true }
	negative := s[0] == '-'
	if negative { s = s[1:] }
	mark: rune = 'b' if bits == 1 else 'x'
	if len(chars) > 2 && s[0] == '0' && (s[1] | 0x20) == mark { s = s[2:] }
	top := max(i64) >> bits
	v: i64
	for c in s {
		n := hex_digit(c)
		if u64(n) >> bits != 0 {
			if c == 0 { break }
			return 0, bits == 1
		}
		// Past `top` the engine prints an overflow error, except on the way to the most negative
		// value: a '-', `top + 1` and one more digit 0.
		if u64(v) > u64(top) && (!negative || v != top + 1 || n != 0) { return 0, false }
		v = v << bits + n
	}
	return -v if negative else v, true
}

// Whether `chars` spell a colour as the engine's `is_valid_html_color` reads a String: an optional
// '#', then 3, 4, 6 or 8 hexadecimal digits.
runes_is_valid_html_color :: proc "contextless" (chars: []rune) -> bool {
	s := chars
	if len(s) != 0 && s[0] == '#' { s = s[1:] }
	switch len(s) {
	case 3, 4, 6, 8:
	case: return false
	}
	for c in s {
		if hex_digit(c) < 0 { return false }
	}
	return true
}

// Whether `chars` are four decimal numbers of at most 255, each of one digit or more, with a '.'
// between them, as IPAddress::_parse_ipv4 of the engine accepts them.
@(private)
runes_is_ipv4 :: proc "contextless" (chars: []rune) -> bool {
	dots, next := 0, u32(0)
	parsed := false
	for c in chars {
		if c == '.' {
			if !parsed || dots == 3 { return false }
			parsed = false
			next = 0
			dots += 1
			continue
		}
		d := u32(c) - '0'
		if d > 9 { return false }
		parsed = true
		next = next * 10 + d
		if next > 255 { return false }
	}
	return parsed && dots == 3
}

// Whether `s` is an IPv6 address as IPAddress::_parse_ipv6 of the engine accepts it, followed line
// by line: groups of one to four hexadecimal digits with a ':' between them, eight of them or fewer
// around one "::", or the IPv4-mapped form, zero groups, "ffff", then an IPv4 address. `i` is where
// the current group starts and `j` the character read; a ':' ends the group.
@(private)
runes_is_ipv6 :: proc "contextless" (s: []rune) -> bool {
	n := len(s)
	group: [8]u16
	cur, shift := 0, -1
	for i := 0; i < n; i += 1 {
		for j := i; j < n; j += 1 {
			c := s[j]
			if c == ':' {
				if j + 1 == n { return false }
				if s[j + 1] == ':' {
					if shift > -1 { return false }
					shift = cur if j == 0 else cur + 1
					j += 1
				} else if i == j {
					return false
				}
				i = j
				break
			}
			if j - i > 3 { return false }
			if c == '.' {
				// The group before must be ffff, sixth unless a "::" came, and those before it zero.
				if cur < 1 || group[cur - 1] != 0xffff || (shift < 0 && cur != 6) { return false }
				for g in group[:cur - 1] {
					if g != 0 { return false }
				}
				return runes_is_ipv4(s[i:])
			}
			d := hex_digit(c)
			if d < 0 { return false }
			group[cur] = group[cur] << 4 | u16(d)
			if j + 1 == n { i = j }
		}
		cur += 1
		if cur > 8 || (cur == 8 && i + 1 != n) { return false }
	}
	return cur == 8 if shift < 0 else shift <= 7
}

// Whether `chars` spell an address as the engine's `is_valid_ip_address` reads a String: IPv6 when
// shorter than 40 characters with a ':', else IPv4 when shorter than 16.
runes_is_valid_ip_address :: proc "contextless" (chars: []rune) -> bool {
	if len(chars) < 40 {
		for c in chars {
			if c == ':' { return runes_is_ipv6(chars) }
		}
	}
	return len(chars) < 16 && runes_is_ipv4(chars)
}

// Whether `chars` spell a float as the engine's `is_valid_float` reads a String: after an optional
// '+' or '-', digits with at most one '.' before any exponent, then an 'e' or 'E' after a digit
// with an optional sign and digits. At least one mantissa digit; an exponent may have none.
runes_is_valid_float :: proc "contextless" (chars: []rune) -> bool {
	if len(chars) == 0 { return false }
	from := 1 if chars[0] == '+' || chars[0] == '-' else 0
	exponent, period, sign, exponent_digits, digits: bool
	for c in chars[from:] {
		switch {
		case c >= '0' && c <= '9':
			if exponent { exponent_digits = true } else { digits = true }
		case digits && !exponent && (c == 'e' || c == 'E'):
			exponent = true
		case !period && !exponent && c == '.':
			period = true
		case (c == '-' || c == '+') && exponent && !exponent_digits && !sign:
			sign = true
		case:
			return false
		}
	}
	return digits
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
		chars := string_chars(digits)
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
	return caps_find(caps_upper_from, caps_upper_to, c)
}

// `c` lowered as the engine's `_find_lower` does.
@(private)
rune_lower :: #force_inline proc "contextless" (c: rune) -> rune {
	if u32(c) < 0x80 { return c + 0x20 if c >= 'A' && c <= 'Z' else c }
	return caps_find(caps_lower_from, caps_lower_to, c)
}

// The engine's case tables from 0x80 up, keys and values apart: the ones of the running engine,
// since Godot 4.8 added the pairs of Unicode 18 to those of 4.7. Empty until `check_caps_version`
// sets them at load.
@(private) caps_upper_from, caps_upper_to, caps_lower_from, caps_lower_to: []u32

// The bounds of the engine's upper and lower case letter ranges from 0x80 up, of the running
// engine as the case tables are: each range's first character, then the one after its last.
@(private) letter_upper, letter_lower: []u32

// Whether `c` is in one of the ranges of `bounds`: whether an odd number of bounds are at or
// below it. Halving 1400 bounds takes 11 steps; 16 bounds the loop.
@(private)
ranges_has :: proc "contextless" (bounds: []u32, c: rune) -> bool {
	lo, hi := 0, len(bounds)
	for _ in 0 ..< 16 {
		if lo >= hi { break }
		mid := (lo + hi) / 2
		if bounds[mid] <= u32(c) { lo = mid + 1 } else { hi = mid }
	}
	return lo & 1 == 1
}

// Points the case tables at those of the engine's version. Called once at load.
@(private)
check_caps_version :: proc "contextless" () {
	v: gde.GodotVersion2
	gde.get_godot_version2(&v)
	if v.major > 4 || (v.major == 4 && v.minor >= 8) {
		caps_upper_from, caps_upper_to = CAPS_UPPER_FROM_48[:], CAPS_UPPER_TO_48[:]
		caps_lower_from, caps_lower_to = CAPS_LOWER_FROM_48[:], CAPS_LOWER_TO_48[:]
		letter_upper, letter_lower = LETTER_UPPER_48[:], LETTER_LOWER_48[:]
	} else {
		caps_upper_from, caps_upper_to = CAPS_UPPER_FROM[:], CAPS_UPPER_TO[:]
		caps_lower_from, caps_lower_to = CAPS_LOWER_FROM[:], CAPS_LOWER_TO[:]
		letter_upper, letter_lower = LETTER_UPPER[:], LETTER_LOWER[:]
	}
}

// The value paired with `c` in a sorted case table, or `c` when it has none. Halving 1500 keys
// takes 11 steps; 16 bounds it, counted once per eight unrolled steps as `packed_bsearch` counts
// its own, so the bound is not a branch on every step.
@(private)
caps_find :: proc "contextless" (from, to: []u32, c: rune) -> rune {
	lo, hi := 0, len(from)
	rounds: for _ in 0 ..< 2 {
		#unroll for _ in 0 ..< 8 {
			if lo >= hi { break rounds }
			mid := (lo + hi) / 2
			if from[mid] < u32(c) { lo = mid + 1 } else { hi = mid }
		}
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

// A copy of String `s`, which you destroy, made as String's copy constructor does (CowData::_ref in
// core/templates/cowdata.h of Godot 4.7-stable): one more reference on its copy-on-write storage,
// none for the empty String. `s` is a live String holding its own reference, so the count is at
// least 1 and cannot reach 0 meanwhile, which is why the constructor's conditional increment is a
// plain one here. The engine copies it before `check_string_layout` proved the layout.
string_copy :: #force_inline proc "contextless" (s: ^String) -> String {
	if !string_layout_known { return string_new_from_string(s^) }
	return string_ref(s)
}

// `string_copy` without the check that the layout is proven, for `check_string_layout` to prove and
// for callers that checked `string_layout_known` themselves.
@(private)
string_ref :: #force_inline proc "contextless" (s: ^String) -> String {
	p := (^rawptr)(s)^
	if p != nil { intrinsics.atomic_add_explicit((^u64)(uintptr(p) - STRING_DATA_OFFSET), 1, .Acq_Rel) }
	return s^
}

// Sets `string_layout_known` from Strings of known length: one shared by two references, and one
// grown by an append so its capacity differs from its size. A `string_ref` copy must add one
// reference and its destroy take it away, a STRING Variant made from a String must hold the same
// storage at `VARIANT_DATA_OFFSET` with one reference more, one built by `counted_into` must read
// the same to the engine and give its reference back when the engine destroys it, and the empty
// String must copy as empty.
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
	layout := holds(&a, len(short), 2) && holds(&b, len(short), 2) && holds(&c, len(long) + 1, 1)
	r := string_ref(&c)
	copied := layout && (^rawptr)(&r)^ == (^rawptr)(&c)^ && holds(&c, len(long) + 1, 2)
	destroy[.STRING](&r)
	copied = copied && holds(&c, len(long) + 1, 1)
	v: Variant
	from_type[.STRING](&v, &c)
	in_variant := internal[.STRING](&v) == rawptr(&v._opaque[VARIANT_DATA_OFFSET]) &&
		(^rawptr)(&v._opaque[VARIANT_DATA_OFFSET])^ == (^rawptr)(&c)^ && layout && holds(&c, len(long) + 1, 2)
	gde.variant_destroy(&v)
	// A Variant built by `counted_into` must read as the engine's, and its destroy free its reference.
	r = string_ref(&c)
	counted_into(&v, .STRING, &r)
	built := gde.variant_get_type(&v) == .STRING && (^rawptr)(internal[.STRING](&v))^ == (^rawptr)(&c)^ &&
		holds(&c, len(long) + 1, 2)
	gde.variant_destroy(&v)
	empty: String
	empty_copy := string_ref(&empty)
	string_layout_known = layout && copied && in_variant && built && holds(&c, len(long) + 1, 1) &&
		(^rawptr)(&empty_copy)^ == nil
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
