// Vector2i, Vector3i and Vector4i methods in place of the generated builtin calls: the same names
// and signatures, computed here exactly as the engine does, so each result matches it. Components
// are int32 and wrap on overflow, as the engine's do in practice. Arguments the API passes as int64
// truncate to int32, as the engine's ptrcall does. Lengths and distances are double; aspect is
// real_t, widened to f64.
package godot

import "core:c/libc"
import "core:math"

// The engine's integer helpers (core/math/math_funcs.h and typedefs.h), kept to their exact
// expressions. abs of the lowest int32 wraps to itself.

@(private) i_abs :: #force_inline proc "contextless" (x: i32) -> i32 { return x if x > 0 else -x }
@(private) i_sign :: #force_inline proc "contextless" (x: i32) -> i32 { return 1 if x > 0 else (-1 if x < 0 else 0) }
@(private) i_min :: #force_inline proc "contextless" (a, b: i32) -> i32 { return a if a < b else b }
@(private) i_max :: #force_inline proc "contextless" (a, b: i32) -> i32 { return a if a > b else b }
@(private) i_clamp :: #force_inline proc "contextless" (x, lo, hi: i32) -> i32 { return lo if x < lo else (hi if x > hi else x) }

// A double truncated to int32 as the engine's conversion does on x86-64: toward zero, and the
// lowest int32 for NaN, infinities and anything out of range. Odin's own conversion leaves those
// cases to the backend, which saturates or wraps them. Exactly 2^31 converts to the lowest int32
// on this backend either way, so `<` and `<=` on the upper bound behave the same.
@(private) i_of_double :: #force_inline proc "contextless" (d: f64) -> i32 {
	return i32(d) if d > -2147483649 && d < 2147483648 else min(i32)
}

// Math::snapped takes doubles: both ints widen exactly, and the result truncates back to int32.
@(private) i_snapped :: #force_inline proc "contextless" (x, step: i32) -> i32 {
	if step == 0 { return x }
	return i_of_double(libc.floor(f64(x) / f64(step) + 0.5) * f64(step))
}

// Per-component and reducing forms shared by the three vector types.

@(private) vi_map :: #force_inline proc "contextless" (v: $V/[$N]i32, $f: proc "contextless" (i32) -> i32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = f(v[i]) }
	return
}

@(private) vi_map2 :: #force_inline proc "contextless" (a, b: $V/[$N]i32, $f: proc "contextless" (i32, i32) -> i32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = f(a[i], b[i]) }
	return
}

@(private) vi_map_scalar :: #force_inline proc "contextless" (v: $V/[$N]i32, s: i32, $f: proc "contextless" (i32, i32) -> i32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = f(v[i], s) }
	return
}

@(private) vi_clamp :: #force_inline proc "contextless" (v, lo, hi: $V/[$N]i32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = i_clamp(v[i], lo[i], hi[i]) }
	return
}

@(private) vi_clampi :: #force_inline proc "contextless" (v: $V/[$N]i32, lo, hi: i32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = i_clamp(v[i], lo, hi) }
	return
}

// Each square is taken in int64, and the sum runs left to right.
@(private) vi_length_squared :: #force_inline proc "contextless" (v: $V/[$N]i32) -> (s: i64) {
	s = i64(v[0]) * i64(v[0])
	#unroll for i in 1 ..< N { s += i64(v[i]) * i64(v[i]) }
	return
}

@(private) vi_length :: #force_inline proc "contextless" (v: $V/[$N]i32) -> f64 { return math.sqrt(f64(vi_length_squared(v))) }

// The difference is taken in int32 before squaring, so far-apart points wrap as in the engine.
@(private) vi_distance_squared :: #force_inline proc "contextless" (from, to: $V/[$N]i32) -> i64 { return vi_length_squared(to - from) }
@(private) vi_distance :: #force_inline proc "contextless" (from, to: $V/[$N]i32) -> f64 { return vi_length(to - from) }

// The constructors from float vectors truncate each component as i_of_double does.

// Vector2i

vector2i_new :: proc "contextless" () -> (__r: Vector2i) { return }
vector2i_new_from_vector2i :: proc "contextless" (from: Vector2i) -> (__r: Vector2i) { return from }
vector2i_new_from_vector2 :: proc "contextless" (from: Vector2) -> (__r: Vector2i) { return {i_of_double(f64(from.x)), i_of_double(f64(from.y))} }
vector2i_new_from_int_int :: proc "contextless" (x: i64, y: i64) -> (__r: Vector2i) { return {i32(x), i32(y)} }

vector2i_aspect :: proc "contextless" (self: ^Vector2i) -> f64 { return f64(f32(self.x) / f32(self.y)) }
vector2i_max_axis_index :: proc "contextless" (self: ^Vector2i) -> i64 { return 1 if self.x < self.y else 0 }
vector2i_min_axis_index :: proc "contextless" (self: ^Vector2i) -> i64 { return 0 if self.x < self.y else 1 }
vector2i_distance_to :: proc "contextless" (self: ^Vector2i, to: Vector2i) -> f64 { return vi_distance(self^, to) }
vector2i_distance_squared_to :: proc "contextless" (self: ^Vector2i, to: Vector2i) -> i64 { return vi_distance_squared(self^, to) }
vector2i_length :: proc "contextless" (self: ^Vector2i) -> f64 { return vi_length(self^) }
vector2i_length_squared :: proc "contextless" (self: ^Vector2i) -> i64 { return vi_length_squared(self^) }
vector2i_sign :: proc "contextless" (self: ^Vector2i) -> Vector2i { return vi_map(self^, i_sign) }
vector2i_abs :: proc "contextless" (self: ^Vector2i) -> Vector2i { return vi_map(self^, i_abs) }
vector2i_clamp :: proc "contextless" (self: ^Vector2i, min: Vector2i, max: Vector2i) -> Vector2i { return vi_clamp(self^, min, max) }
vector2i_clampi :: proc "contextless" (self: ^Vector2i, min: i64, max: i64) -> Vector2i { return vi_clampi(self^, i32(min), i32(max)) }
vector2i_snapped :: proc "contextless" (self: ^Vector2i, step: Vector2i) -> Vector2i { return vi_map2(self^, step, i_snapped) }
vector2i_snappedi :: proc "contextless" (self: ^Vector2i, step: i64) -> Vector2i { return vi_map_scalar(self^, i32(step), i_snapped) }
vector2i_min :: proc "contextless" (self: ^Vector2i, with: Vector2i) -> Vector2i { return vi_map2(self^, with, i_min) }
vector2i_mini :: proc "contextless" (self: ^Vector2i, with: i64) -> Vector2i { return vi_map_scalar(self^, i32(with), i_min) }
vector2i_max :: proc "contextless" (self: ^Vector2i, with: Vector2i) -> Vector2i { return vi_map2(self^, with, i_max) }
vector2i_maxi :: proc "contextless" (self: ^Vector2i, with: i64) -> Vector2i { return vi_map_scalar(self^, i32(with), i_max) }

// Vector3i

vector3i_new :: proc "contextless" () -> (__r: Vector3i) { return }
vector3i_new_from_vector3i :: proc "contextless" (from: Vector3i) -> (__r: Vector3i) { return from }
vector3i_new_from_vector3 :: proc "contextless" (from: Vector3) -> (__r: Vector3i) { return {i_of_double(f64(from.x)), i_of_double(f64(from.y)), i_of_double(f64(from.z))} }
vector3i_new_from_int_int_int :: proc "contextless" (x: i64, y: i64, z: i64) -> (__r: Vector3i) { return {i32(x), i32(y), i32(z)} }

vector3i_min_axis_index :: proc "contextless" (self: ^Vector3i) -> i64 {
	x, y, z := self.x, self.y, self.z
	return (0 if x < z else 2) if x < y else (1 if y < z else 2)
}

vector3i_max_axis_index :: proc "contextless" (self: ^Vector3i) -> i64 {
	x, y, z := self.x, self.y, self.z
	return (2 if y < z else 1) if x < y else (2 if x < z else 0)
}

vector3i_distance_to :: proc "contextless" (self: ^Vector3i, to: Vector3i) -> f64 { return vi_distance(self^, to) }
vector3i_distance_squared_to :: proc "contextless" (self: ^Vector3i, to: Vector3i) -> i64 { return vi_distance_squared(self^, to) }
vector3i_length :: proc "contextless" (self: ^Vector3i) -> f64 { return vi_length(self^) }
vector3i_length_squared :: proc "contextless" (self: ^Vector3i) -> i64 { return vi_length_squared(self^) }
vector3i_sign :: proc "contextless" (self: ^Vector3i) -> Vector3i { return vi_map(self^, i_sign) }
vector3i_abs :: proc "contextless" (self: ^Vector3i) -> Vector3i { return vi_map(self^, i_abs) }
vector3i_clamp :: proc "contextless" (self: ^Vector3i, min: Vector3i, max: Vector3i) -> Vector3i { return vi_clamp(self^, min, max) }
vector3i_clampi :: proc "contextless" (self: ^Vector3i, min: i64, max: i64) -> Vector3i { return vi_clampi(self^, i32(min), i32(max)) }
vector3i_snapped :: proc "contextless" (self: ^Vector3i, step: Vector3i) -> Vector3i { return vi_map2(self^, step, i_snapped) }
vector3i_snappedi :: proc "contextless" (self: ^Vector3i, step: i64) -> Vector3i { return vi_map_scalar(self^, i32(step), i_snapped) }
vector3i_min :: proc "contextless" (self: ^Vector3i, with: Vector3i) -> Vector3i { return vi_map2(self^, with, i_min) }
vector3i_mini :: proc "contextless" (self: ^Vector3i, with: i64) -> Vector3i { return vi_map_scalar(self^, i32(with), i_min) }
vector3i_max :: proc "contextless" (self: ^Vector3i, with: Vector3i) -> Vector3i { return vi_map2(self^, with, i_max) }
vector3i_maxi :: proc "contextless" (self: ^Vector3i, with: i64) -> Vector3i { return vi_map_scalar(self^, i32(with), i_max) }

// Vector4i

vector4i_new :: proc "contextless" () -> (__r: Vector4i) { return }
vector4i_new_from_vector4i :: proc "contextless" (from: Vector4i) -> (__r: Vector4i) { return from }
vector4i_new_from_vector4 :: proc "contextless" (from: Vector4) -> (__r: Vector4i) { return {i_of_double(f64(from.x)), i_of_double(f64(from.y)), i_of_double(f64(from.z)), i_of_double(f64(from.w))} }
vector4i_new_from_int_int_int_int :: proc "contextless" (x: i64, y: i64, z: i64, w: i64) -> (__r: Vector4i) { return {i32(x), i32(y), i32(z), i32(w)} }

// The engine scans for the minimum with <=, so the last of equal components wins, and for the
// maximum with >, so the first wins.
vector4i_min_axis_index :: proc "contextless" (self: ^Vector4i) -> (index: i64) {
	low := self.x
	#unroll for i in 1 ..< 4 {
		if self[i] <= low { index, low = i64(i), self[i] }
	}
	return
}

vector4i_max_axis_index :: proc "contextless" (self: ^Vector4i) -> (index: i64) {
	high := self.x
	#unroll for i in 1 ..< 4 {
		if self[i] > high { index, high = i64(i), self[i] }
	}
	return
}

vector4i_length :: proc "contextless" (self: ^Vector4i) -> f64 { return vi_length(self^) }
vector4i_length_squared :: proc "contextless" (self: ^Vector4i) -> i64 { return vi_length_squared(self^) }
vector4i_sign :: proc "contextless" (self: ^Vector4i) -> Vector4i { return vi_map(self^, i_sign) }
vector4i_abs :: proc "contextless" (self: ^Vector4i) -> Vector4i { return vi_map(self^, i_abs) }
vector4i_clamp :: proc "contextless" (self: ^Vector4i, min: Vector4i, max: Vector4i) -> Vector4i { return vi_clamp(self^, min, max) }
vector4i_clampi :: proc "contextless" (self: ^Vector4i, min: i64, max: i64) -> Vector4i { return vi_clampi(self^, i32(min), i32(max)) }
vector4i_snapped :: proc "contextless" (self: ^Vector4i, step: Vector4i) -> Vector4i { return vi_map2(self^, step, i_snapped) }
vector4i_snappedi :: proc "contextless" (self: ^Vector4i, step: i64) -> Vector4i { return vi_map_scalar(self^, i32(step), i_snapped) }
vector4i_min :: proc "contextless" (self: ^Vector4i, with: Vector4i) -> Vector4i { return vi_map2(self^, with, i_min) }
vector4i_mini :: proc "contextless" (self: ^Vector4i, with: i64) -> Vector4i { return vi_map_scalar(self^, i32(with), i_min) }
vector4i_max :: proc "contextless" (self: ^Vector4i, with: Vector4i) -> Vector4i { return vi_map2(self^, with, i_max) }
vector4i_maxi :: proc "contextless" (self: ^Vector4i, with: i64) -> Vector4i { return vi_map_scalar(self^, i32(with), i_max) }
vector4i_distance_to :: proc "contextless" (self: ^Vector4i, to: Vector4i) -> f64 { return vi_distance(self^, to) }
vector4i_distance_squared_to :: proc "contextless" (self: ^Vector4i, to: Vector4i) -> i64 { return vi_distance_squared(self^, to) }
