// Vector2, Vector3 and Vector4 methods in place of the generated builtin calls: the same names and
// signatures, computed here in single precision exactly as the engine's real_t math does, so each
// result matches the engine's bit for bit. Arguments the API passes as double narrow to f32 first,
// as the engine's ptrcall does, and real_t results widen back to f64. Trigonometry and the libm
// rounding calls go through the same C library the engine calls.
package godot

import "base:intrinsics"
import "core:c/libc"
import "core:math"
import gde "../gdextension"

// The engine's real_t helpers (core/math/math_funcs.h and typedefs.h), kept to their exact
// expressions: their NaN and signed-zero cases differ from Odin's builtins.

@(private) CMP_EPSILON :: f32(0.00001)
@(private) UNIT_EPSILON :: f32(0.001)

@(private) m_abs :: #force_inline proc "contextless" (x: f32) -> f32 { return 0 if x == 0 else (-x if x < 0 else x) }
@(private) m_sign :: #force_inline proc "contextless" (x: f32) -> f32 { return 1 if x > 0 else (-1 if x < 0 else 0) }
@(private) m_min :: #force_inline proc "contextless" (a, b: f32) -> f32 { return a if a < b else b }
@(private) m_max :: #force_inline proc "contextless" (a, b: f32) -> f32 { return a if a > b else b }
@(private) m_clamp :: #force_inline proc "contextless" (x, lo, hi: f32) -> f32 { return lo if x < lo else (hi if x > hi else x) }
@(private) m_sqrt :: #force_inline proc "contextless" (x: f32) -> f32 { return intrinsics.sqrt(x) }
// sinf and cosf of one angle from a single call. glibc's sincosf returns the same bits as its sinf
// and cosf for every input (checked over all 2^32), and the engine's own build already pairs them.
when ODIN_OS == .Linux {
	foreign import libm "system:m"
	@(default_calling_convention = "c")
	foreign libm { sincosf :: proc(x: f32, sine, cosine: ^f32) --- }
	@(private) m_sincos :: #force_inline proc "contextless" (x: f32) -> (sine, cosine: f32) {
		sincosf(x, &sine, &cosine)
		return
	}
} else {
	@(private) m_sincos :: #force_inline proc "contextless" (x: f32) -> (sine, cosine: f32) {
		return libc.sinf(x), libc.cosf(x)
	}
}
@(private) m_lerp :: #force_inline proc "contextless" (from, to, weight: f32) -> f32 { return from + (to - from) * weight }
// Neither an infinity nor a NaN: those alone have every exponent bit set. One test, no branch.
@(private) m_is_finite :: #force_inline proc "contextless" (x: f32) -> bool { return transmute(u32)x & 0x7f800000 != 0x7f800000 }
@(private) m_is_zero_approx :: #force_inline proc "contextless" (x: f32) -> bool { return m_abs(x) < CMP_EPSILON }

@(private) m_is_equal_approx :: #force_inline proc "contextless" (a, b: f32) -> bool {
	if a == b { return true }
	tolerance := CMP_EPSILON * m_abs(a)
	if tolerance < CMP_EPSILON { tolerance = CMP_EPSILON }
	return m_abs(a - b) < tolerance
}

@(private) m_fposmod :: #force_inline proc "contextless" (x, y: f32) -> f32 {
	value := libc.fmodf(x, y)
	if (value < 0 && y > 0) || (value > 0 && y < 0) { value += y }
	return value + 0
}

// Math::snapped takes doubles: the f32 operands widen, and the result narrows back.
@(private) m_snapped :: #force_inline proc "contextless" (x, step: f32) -> f32 {
	if step == 0 { return x }
	return f32(libc.floor(f64(x) / f64(step) + 0.5) * f64(step))
}

@(private) m_cubic :: #force_inline proc "contextless" (from, to, pre, post, w: f32) -> f32 {
	return 0.5 * ((from * 2) + (-pre + to) * w + (2 * pre - 5 * from + 4 * to - post) * (w * w) + (-pre + 3 * from - 3 * to + post) * (w * w * w))
}

@(private) m_cubic_in_time :: #force_inline proc "contextless" (from, to, pre, post, w, to_t, pre_t, post_t: f32) -> f32 {
	t := m_lerp(0, to_t, w)
	a1 := m_lerp(pre, from, 0 if pre_t == 0 else (t - pre_t) / -pre_t)
	a2 := m_lerp(from, to, 0.5 if to_t == 0 else t / to_t)
	a3 := m_lerp(to, post, 1 if post_t - to_t == 0 else (t - to_t) / (post_t - to_t))
	b1 := m_lerp(a1, a2, 0 if to_t - pre_t == 0 else (t - pre_t) / (to_t - pre_t))
	b2 := m_lerp(a2, a3, 1 if post_t == 0 else t / post_t)
	return m_lerp(b1, b2, 0.5 if to_t == 0 else t / to_t)
}

@(private) m_bezier :: #force_inline proc "contextless" (start, c1, c2, end, t: f32) -> f32 {
	omt := 1 - t
	omt2 := omt * omt
	omt3 := omt2 * omt
	t2 := t * t
	t3 := t2 * t
	return start * omt3 + c1 * omt2 * t * 3 + c2 * omt * t2 * 3 + end * t3
}

@(private) m_bezier_derivative :: #force_inline proc "contextless" (start, c1, c2, end, t: f32) -> f32 {
	omt := 1 - t
	omt2 := omt * omt
	t2 := t * t
	return (c1 - start) * 3 * omt2 + (c2 - c1) * 6 * omt * t + (end - c2) * 3 * t2
}

// Logs the engine's error for a math precondition its debug builds check.
@(private) math_error :: proc "contextless" (message: cstring) {
	gde.print_error(message, "", #file, #line, 1)
}

// Per-component and reducing forms shared by the three vector types. Sums run left to right, as
// the engine writes them.

@(private) v_dot :: #force_inline proc "contextless" (a, b: $V/[$N]f32) -> (s: f32) {
	s = a[0] * b[0]
	#unroll for i in 1 ..< N { s += a[i] * b[i] }
	return
}

@(private) v_map :: #force_inline proc "contextless" (v: $V/[$N]f32, $f: proc "contextless" (f32) -> f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = f(v[i]) }
	return
}

@(private) v_map2 :: #force_inline proc "contextless" (a, b: $V/[$N]f32, $f: proc "contextless" (f32, f32) -> f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = f(a[i], b[i]) }
	return
}

@(private) v_all :: #force_inline proc "contextless" (v: $V/[$N]f32, $f: proc "contextless" (f32) -> bool) -> bool {
	// Every component tested and the answers combined, so no branch separates them.
	ok := true
	#unroll for i in 0 ..< N { ok &= f(v[i]) }
	return ok
}

@(private) v_is_finite :: #force_inline proc "contextless" (v: $V/[$N]f32) -> bool { return v_all(v, m_is_finite) }

@(private) v_is_normalized :: #force_inline proc "contextless" (v: $V/[$N]f32) -> bool {
	d := v_dot(v, v)
	return d == 1 || m_abs(d - 1) < UNIT_EPSILON
}

@(private) v_normalized :: #force_inline proc "contextless" (v: $V/[$N]f32, $MESSAGE: cstring) -> V {
	// An infinite or NaN component makes the squared length infinite or NaN, so a finite, non-zero
	// one settles both of the engine's checks at once. A sum of squares is never negative, so its
	// bits, less one, fall under infinity's exactly when it is neither zero, infinite nor NaN.
	l := v_dot(v, v)
	if transmute(u32)l - 1 < 0x7f800000 - 1 { return v / m_sqrt(l) }
	if !v_is_finite(v) {
		gde.print_warning(MESSAGE, "", #file, #line, 1)
		return {}
	}
	if l == 0 { return {} }
	return v / m_sqrt(l)
}

@(private) v_limit_length :: #force_inline proc "contextless" (v: $V/[$N]f32, length: f32) -> V {
	l := m_sqrt(v_dot(v, v))
	if l > 0 && length < l { return v / l * length }
	return v
}

@(private) v_move_toward :: #force_inline proc "contextless" (v, to: $V/[$N]f32, delta: f32) -> V {
	vd := to - v
	l := m_sqrt(v_dot(vd, vd))
	return to if l <= delta || l < CMP_EPSILON else v + vd / l * delta
}

@(private) v_lerp :: #force_inline proc "contextless" (a, b: $V/[$N]f32, w: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_lerp(a[i], b[i], w) }
	return
}

@(private) v_posmod :: #force_inline proc "contextless" (v: $V/[$N]f32, m: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_fposmod(v[i], m) }
	return
}

@(private) v_snapped :: #force_inline proc "contextless" (v: $V/[$N]f32, step: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_snapped(v[i], step) }
	return
}

@(private) v_clamp :: #force_inline proc "contextless" (v, lo, hi: $V/[$N]f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_clamp(v[i], lo[i], hi[i]) }
	return
}

@(private) v_clampf :: #force_inline proc "contextless" (v: $V/[$N]f32, lo, hi: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_clamp(v[i], lo, hi) }
	return
}

@(private) v_minf :: #force_inline proc "contextless" (v: $V/[$N]f32, s: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_min(v[i], s) }
	return
}

@(private) v_maxf :: #force_inline proc "contextless" (v: $V/[$N]f32, s: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_max(v[i], s) }
	return
}

@(private) v_cubic :: #force_inline proc "contextless" (a, b, pre, post: $V/[$N]f32, w: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_cubic(a[i], b[i], pre[i], post[i], w) }
	return
}

@(private) v_cubic_in_time :: #force_inline proc "contextless" (a, b, pre, post: $V/[$N]f32, w, b_t, pre_t, post_t: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_cubic_in_time(a[i], b[i], pre[i], post[i], w, b_t, pre_t, post_t) }
	return
}

@(private) v_bezier :: #force_inline proc "contextless" (a, c1, c2, end: $V/[$N]f32, t: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_bezier(a[i], c1[i], c2[i], end[i], t) }
	return
}

@(private) v_bezier_derivative :: #force_inline proc "contextless" (a, c1, c2, end: $V/[$N]f32, t: f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = m_bezier_derivative(a[i], c1[i], c2[i], end[i], t) }
	return
}

@(private) v_project :: #force_inline proc "contextless" (v, to: $V/[$N]f32) -> V { return to * (v_dot(v, to) / v_dot(to, to)) }

@(private) v_slide :: #force_inline proc "contextless" (v, n: $V/[$N]f32, $MESSAGE: cstring) -> V {
	if !v_is_normalized(n) { math_error(MESSAGE); return {} }
	return v - n * v_dot(v, n)
}

@(private) v_reflect :: #force_inline proc "contextless" (v, n: $V/[$N]f32, $MESSAGE: cstring) -> V {
	if !v_is_normalized(n) { math_error(MESSAGE); return {} }
	return 2 * n * v_dot(v, n) - v
}

@(private) v_inverse :: #force_inline proc "contextless" (v: $V/[$N]f32) -> (out: V) {
	#unroll for i in 0 ..< N { out[i] = 1 / v[i] }
	return
}

@(private) m_floor :: #force_inline proc "contextless" (x: f32) -> f32 { return libc.floorf(x) }
// ceilf and roundf through floorf, which compiles to one instruction where they stay libm calls.
// Both equal libm's on every f32 bit pattern, NaN payloads and signs included.
@(private) m_ceil :: #force_inline proc "contextless" (x: f32) -> f32 { return -libc.floorf(-x) }
@(private) m_round :: #force_inline proc "contextless" (x: f32) -> f32 {
	// 0.49999997 is the f32 just under one half, so a value just under a half does not round up.
	whole := libc.floorf(abs(x) + 0.49999997)
	return transmute(f32)(transmute(u32)whole & 0x7fffffff | transmute(u32)x & 0x80000000)
}

// Vector2 ----------------------------------------------------------------------------------------

vector2_new :: proc "contextless" () -> (__r: Vector2) { return }
vector2_new_from_vector2 :: proc "contextless" (from: Vector2) -> (__r: Vector2) { return from }
vector2_new_from_vector2i :: proc "contextless" (from: Vector2i) -> (__r: Vector2) { return {f32(from.x), f32(from.y)} }
vector2_new_from_float_float :: proc "contextless" (x: f64, y: f64) -> (__r: Vector2) { return {f32(x), f32(y)} }
vector2_angle :: proc "contextless" (self: ^Vector2) -> f64 { return f64(libc.atan2f(self.y, self.x)) }
vector2_angle_to :: proc "contextless" (self: ^Vector2, to: Vector2) -> f64 { return f64(v2_angle_to(self^, to)) }
vector2_angle_to_point :: proc "contextless" (self: ^Vector2, to: Vector2) -> f64 { d := to - self^; return f64(libc.atan2f(d.y, d.x)) }
vector2_direction_to :: proc "contextless" (self: ^Vector2, to: Vector2) -> Vector2 { return v_normalized(to - self^, V2_NOT_FINITE) }
vector2_distance_to :: proc "contextless" (self: ^Vector2, to: Vector2) -> f64 { d := self^ - to; return f64(m_sqrt(v_dot(d, d))) }
vector2_distance_squared_to :: proc "contextless" (self: ^Vector2, to: Vector2) -> f64 { d := self^ - to; return f64(v_dot(d, d)) }
vector2_length :: proc "contextless" (self: ^Vector2) -> f64 { return f64(m_sqrt(v_dot(self^, self^))) }
vector2_length_squared :: proc "contextless" (self: ^Vector2) -> f64 { return f64(v_dot(self^, self^)) }
vector2_limit_length :: proc "contextless" (self: ^Vector2, length: f64) -> Vector2 { return v_limit_length(self^, f32(length)) }
vector2_normalized :: proc "contextless" (self: ^Vector2) -> Vector2 { return v_normalized(self^, V2_NOT_FINITE) }
vector2_is_normalized :: proc "contextless" (self: ^Vector2) -> bool { return v_is_normalized(self^) }
vector2_is_equal_approx :: proc "contextless" (self: ^Vector2, to: Vector2) -> bool { return m_is_equal_approx(self.x, to.x) && m_is_equal_approx(self.y, to.y) }
vector2_is_zero_approx :: proc "contextless" (self: ^Vector2) -> bool { return v_all(self^, m_is_zero_approx) }
vector2_is_finite :: proc "contextless" (self: ^Vector2) -> bool { return v_is_finite(self^) }
vector2_posmod :: proc "contextless" (self: ^Vector2, mod: f64) -> Vector2 { return v_posmod(self^, f32(mod)) }
vector2_posmodv :: proc "contextless" (self: ^Vector2, modv: Vector2) -> Vector2 { return v_map2(self^, modv, m_fposmod) }
vector2_project :: proc "contextless" (self: ^Vector2, b: Vector2) -> Vector2 { return v_project(self^, b) }
vector2_lerp :: proc "contextless" (self: ^Vector2, to: Vector2, weight: f64) -> Vector2 { return v_lerp(self^, to, f32(weight)) }
vector2_slerp :: proc "contextless" (self: ^Vector2, to: Vector2, weight: f64) -> Vector2 {
	v, w := self^, f32(weight)
	start_sq, end_sq := v_dot(v, v), v_dot(to, to)
	if start_sq == 0 || end_sq == 0 { return v_lerp(v, to, w) }
	start := m_sqrt(start_sq)
	result := m_lerp(start, m_sqrt(end_sq), w)
	return v2_rotated(v, v2_angle_to(v, to) * w) * (result / start)
}
vector2_cubic_interpolate :: proc "contextless" (self: ^Vector2, b: Vector2, pre_a: Vector2, post_b: Vector2, weight: f64) -> Vector2 {
	return v_cubic(self^, b, pre_a, post_b, f32(weight))
}
vector2_cubic_interpolate_in_time :: proc "contextless" (self: ^Vector2, b: Vector2, pre_a: Vector2, post_b: Vector2, weight: f64, b_t: f64, pre_a_t: f64, post_b_t: f64) -> Vector2 {
	return v_cubic_in_time(self^, b, pre_a, post_b, f32(weight), f32(b_t), f32(pre_a_t), f32(post_b_t))
}
vector2_bezier_interpolate :: proc "contextless" (self: ^Vector2, control_1: Vector2, control_2: Vector2, end: Vector2, t: f64) -> Vector2 {
	return v_bezier(self^, control_1, control_2, end, f32(t))
}
vector2_bezier_derivative :: proc "contextless" (self: ^Vector2, control_1: Vector2, control_2: Vector2, end: Vector2, t: f64) -> Vector2 {
	return v_bezier_derivative(self^, control_1, control_2, end, f32(t))
}
vector2_max_axis_index :: proc "contextless" (self: ^Vector2) -> i64 { return 1 if self.x < self.y else 0 }
vector2_min_axis_index :: proc "contextless" (self: ^Vector2) -> i64 { return 0 if self.x < self.y else 1 }
vector2_move_toward :: proc "contextless" (self: ^Vector2, to: Vector2, delta: f64) -> Vector2 { return v_move_toward(self^, to, f32(delta)) }
vector2_rotated :: proc "contextless" (self: ^Vector2, angle: f64) -> Vector2 { return v2_rotated(self^, f32(angle)) }
vector2_orthogonal :: proc "contextless" (self: ^Vector2) -> Vector2 { return {self.y, -self.x} }
vector2_floor :: proc "contextless" (self: ^Vector2) -> Vector2 { return v_map(self^, m_floor) }
vector2_ceil :: proc "contextless" (self: ^Vector2) -> Vector2 { return v_map(self^, m_ceil) }
vector2_round :: proc "contextless" (self: ^Vector2) -> Vector2 { return v_map(self^, m_round) }
vector2_aspect :: proc "contextless" (self: ^Vector2) -> f64 { return f64(self.x / self.y) }
vector2_dot :: proc "contextless" (self: ^Vector2, with: Vector2) -> f64 { return f64(v_dot(self^, with)) }
vector2_slide :: proc "contextless" (self: ^Vector2, n: Vector2) -> Vector2 { return v_slide(self^, n, V2_NOT_NORMAL) }
vector2_bounce :: proc "contextless" (self: ^Vector2, n: Vector2) -> Vector2 { return -v_reflect(self^, n, V2_NOT_NORMAL) }
vector2_reflect :: proc "contextless" (self: ^Vector2, line: Vector2) -> Vector2 { return v_reflect(self^, line, V2_NOT_NORMAL) }
vector2_cross :: proc "contextless" (self: ^Vector2, with: Vector2) -> f64 { return f64(v2_cross(self^, with)) }
vector2_abs :: proc "contextless" (self: ^Vector2) -> Vector2 { return v_map(self^, m_abs) }
vector2_sign :: proc "contextless" (self: ^Vector2) -> Vector2 { return v_map(self^, m_sign) }
vector2_clamp :: proc "contextless" (self: ^Vector2, min: Vector2, max: Vector2) -> Vector2 { return v_clamp(self^, min, max) }
vector2_clampf :: proc "contextless" (self: ^Vector2, min: f64, max: f64) -> Vector2 { return v_clampf(self^, f32(min), f32(max)) }
vector2_snapped :: proc "contextless" (self: ^Vector2, step: Vector2) -> Vector2 { return v_map2(self^, step, m_snapped) }
vector2_snappedf :: proc "contextless" (self: ^Vector2, step: f64) -> Vector2 { return v_snapped(self^, f32(step)) }
vector2_min :: proc "contextless" (self: ^Vector2, with: Vector2) -> Vector2 { return v_map2(self^, with, m_min) }
vector2_minf :: proc "contextless" (self: ^Vector2, with: f64) -> Vector2 { return v_minf(self^, f32(with)) }
vector2_max :: proc "contextless" (self: ^Vector2, with: Vector2) -> Vector2 { return v_map2(self^, with, m_max) }
vector2_maxf :: proc "contextless" (self: ^Vector2, with: f64) -> Vector2 { return v_maxf(self^, f32(with)) }
vector2_from_angle :: proc "contextless" (angle: f64) -> Vector2 { s, c := m_sincos(f32(angle)); return {c, s} }

@(private) V2_NOT_FINITE :: "Vector2 cannot be normalized, the elements must be finite. Making (0, 0) as a fallback."
@(private) V2_NOT_NORMAL :: "The normal Vector2 must be normalized."

@(private) v2_cross :: #force_inline proc "contextless" (a, b: Vector2) -> f32 { return a.x * b.y - a.y * b.x }
@(private) v2_angle_to :: #force_inline proc "contextless" (a, b: Vector2) -> f32 { return libc.atan2f(v2_cross(a, b), v_dot(a, b)) }
@(private) v2_rotated :: #force_inline proc "contextless" (v: Vector2, by: f32) -> Vector2 {
	sine, cosi := m_sincos(by)
	return {v.x * cosi - v.y * sine, v.x * sine + v.y * cosi}
}

// Vector3 ----------------------------------------------------------------------------------------

vector3_new :: proc "contextless" () -> (__r: Vector3) { return }
vector3_new_from_vector3 :: proc "contextless" (from: Vector3) -> (__r: Vector3) { return from }
vector3_new_from_vector3i :: proc "contextless" (from: Vector3i) -> (__r: Vector3) { return {f32(from.x), f32(from.y), f32(from.z)} }
vector3_new_from_float_float_float :: proc "contextless" (x: f64, y: f64, z: f64) -> (__r: Vector3) { return {f32(x), f32(y), f32(z)} }
vector3_min_axis_index :: proc "contextless" (self: ^Vector3) -> i64 {
	x, y, z := self.x, self.y, self.z
	return (0 if x < z else 2) if x < y else (1 if y < z else 2)
}
vector3_max_axis_index :: proc "contextless" (self: ^Vector3) -> i64 {
	x, y, z := self.x, self.y, self.z
	return (2 if y < z else 1) if x < y else (2 if x < z else 0)
}
vector3_angle_to :: proc "contextless" (self: ^Vector3, to: Vector3) -> f64 { return f64(v3_angle_to(self^, to)) }
vector3_signed_angle_to :: proc "contextless" (self: ^Vector3, to: Vector3, axis: Vector3) -> f64 {
	c := v3_cross(self^, to)
	unsigned := libc.atan2f(m_sqrt(v_dot(c, c)), v_dot(self^, to))
	return f64(-unsigned if v_dot(c, axis) < 0 else unsigned)
}
vector3_direction_to :: proc "contextless" (self: ^Vector3, to: Vector3) -> Vector3 { return v_normalized(to - self^, V3_NOT_FINITE) }
vector3_distance_to :: proc "contextless" (self: ^Vector3, to: Vector3) -> f64 { d := to - self^; return f64(m_sqrt(v_dot(d, d))) }
vector3_distance_squared_to :: proc "contextless" (self: ^Vector3, to: Vector3) -> f64 { d := to - self^; return f64(v_dot(d, d)) }
vector3_length :: proc "contextless" (self: ^Vector3) -> f64 { return f64(m_sqrt(v_dot(self^, self^))) }
vector3_length_squared :: proc "contextless" (self: ^Vector3) -> f64 { return f64(v_dot(self^, self^)) }
vector3_limit_length :: proc "contextless" (self: ^Vector3, length: f64) -> Vector3 { return v_limit_length(self^, f32(length)) }
vector3_normalized :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_normalized(self^, V3_NOT_FINITE) }
vector3_is_normalized :: proc "contextless" (self: ^Vector3) -> bool { return v_is_normalized(self^) }
vector3_is_equal_approx :: proc "contextless" (self: ^Vector3, to: Vector3) -> bool {
	return m_is_equal_approx(self.x, to.x) && m_is_equal_approx(self.y, to.y) && m_is_equal_approx(self.z, to.z)
}
vector3_is_zero_approx :: proc "contextless" (self: ^Vector3) -> bool { return v_all(self^, m_is_zero_approx) }
vector3_is_finite :: proc "contextless" (self: ^Vector3) -> bool { return v_is_finite(self^) }
vector3_inverse :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_inverse(self^) }
vector3_clamp :: proc "contextless" (self: ^Vector3, min: Vector3, max: Vector3) -> Vector3 { return v_clamp(self^, min, max) }
vector3_clampf :: proc "contextless" (self: ^Vector3, min: f64, max: f64) -> Vector3 { return v_clampf(self^, f32(min), f32(max)) }
vector3_snapped :: proc "contextless" (self: ^Vector3, step: Vector3) -> Vector3 { return v_map2(self^, step, m_snapped) }
vector3_snappedf :: proc "contextless" (self: ^Vector3, step: f64) -> Vector3 { return v_snapped(self^, f32(step)) }
vector3_rotated :: proc "contextless" (self: ^Vector3, axis: Vector3, angle: f64) -> Vector3 { return v3_rotated(self^, axis, f32(angle)) }
vector3_lerp :: proc "contextless" (self: ^Vector3, to: Vector3, weight: f64) -> Vector3 { return v_lerp(self^, to, f32(weight)) }
vector3_slerp :: proc "contextless" (self: ^Vector3, to: Vector3, weight: f64) -> Vector3 {
	v, w := self^, f32(weight)
	start_sq, end_sq := v_dot(v, v), v_dot(to, to)
	if start_sq == 0 || end_sq == 0 { return v_lerp(v, to, w) }
	axis := v3_cross(v, to)
	axis_sq := v_dot(axis, axis)
	if axis_sq == 0 { return v_lerp(v, to, w) }
	axis /= m_sqrt(axis_sq)
	start := m_sqrt(start_sq)
	result := m_lerp(start, m_sqrt(end_sq), w)
	return v3_rotated(v, axis, v3_angle_to(v, to) * w) * (result / start)
}
vector3_cubic_interpolate :: proc "contextless" (self: ^Vector3, b: Vector3, pre_a: Vector3, post_b: Vector3, weight: f64) -> Vector3 {
	return v_cubic(self^, b, pre_a, post_b, f32(weight))
}
vector3_cubic_interpolate_in_time :: proc "contextless" (self: ^Vector3, b: Vector3, pre_a: Vector3, post_b: Vector3, weight: f64, b_t: f64, pre_a_t: f64, post_b_t: f64) -> Vector3 {
	return v_cubic_in_time(self^, b, pre_a, post_b, f32(weight), f32(b_t), f32(pre_a_t), f32(post_b_t))
}
vector3_bezier_interpolate :: proc "contextless" (self: ^Vector3, control_1: Vector3, control_2: Vector3, end: Vector3, t: f64) -> Vector3 {
	return v_bezier(self^, control_1, control_2, end, f32(t))
}
vector3_bezier_derivative :: proc "contextless" (self: ^Vector3, control_1: Vector3, control_2: Vector3, end: Vector3, t: f64) -> Vector3 {
	return v_bezier_derivative(self^, control_1, control_2, end, f32(t))
}
vector3_move_toward :: proc "contextless" (self: ^Vector3, to: Vector3, delta: f64) -> Vector3 { return v_move_toward(self^, to, f32(delta)) }
vector3_dot :: proc "contextless" (self: ^Vector3, with: Vector3) -> f64 { return f64(v_dot(self^, with)) }
vector3_cross :: proc "contextless" (self: ^Vector3, with: Vector3) -> Vector3 { return v3_cross(self^, with) }
vector3_outer :: proc "contextless" (self: ^Vector3, with: Vector3) -> Basis { return {self.x * with, self.y * with, self.z * with} }
vector3_abs :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_map(self^, m_abs) }
vector3_floor :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_map(self^, m_floor) }
vector3_ceil :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_map(self^, m_ceil) }
vector3_round :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_map(self^, m_round) }
vector3_posmod :: proc "contextless" (self: ^Vector3, mod: f64) -> Vector3 { return v_posmod(self^, f32(mod)) }
vector3_posmodv :: proc "contextless" (self: ^Vector3, modv: Vector3) -> Vector3 { return v_map2(self^, modv, m_fposmod) }
vector3_project :: proc "contextless" (self: ^Vector3, b: Vector3) -> Vector3 { return v_project(self^, b) }
vector3_slide :: proc "contextless" (self: ^Vector3, n: Vector3) -> Vector3 { return v_slide(self^, n, V3_NOT_NORMAL) }
vector3_bounce :: proc "contextless" (self: ^Vector3, n: Vector3) -> Vector3 { return -v_reflect(self^, n, V3_NOT_NORMAL) }
vector3_reflect :: proc "contextless" (self: ^Vector3, n: Vector3) -> Vector3 { return v_reflect(self^, n, V3_NOT_NORMAL) }
vector3_sign :: proc "contextless" (self: ^Vector3) -> Vector3 { return v_map(self^, m_sign) }
vector3_octahedron_encode :: proc "contextless" (self: ^Vector3) -> Vector2 {
	n := self^ / (m_abs(self.x) + m_abs(self.y) + m_abs(self.z))
	o := Vector2(n.xy)
	if n.z < 0 {
		o.x = (1 - m_abs(n.y)) * (1 if n.x >= 0 else -1)
		o.y = (1 - m_abs(n.x)) * (1 if n.y >= 0 else -1)
	}
	return o * 0.5 + 0.5
}
vector3_min :: proc "contextless" (self: ^Vector3, with: Vector3) -> Vector3 { return v_map2(self^, with, m_min) }
vector3_minf :: proc "contextless" (self: ^Vector3, with: f64) -> Vector3 { return v_minf(self^, f32(with)) }
vector3_max :: proc "contextless" (self: ^Vector3, with: Vector3) -> Vector3 { return v_map2(self^, with, m_max) }
vector3_maxf :: proc "contextless" (self: ^Vector3, with: f64) -> Vector3 { return v_maxf(self^, f32(with)) }
vector3_octahedron_decode :: proc "contextless" (uv: Vector2) -> Vector3 {
	f := uv * 2 - 1
	n := Vector3{f.x, f.y, 1 - m_abs(f.x) - m_abs(f.y)}
	t := m_clamp(-n.z, 0, 1)
	n.x += -t if n.x >= 0 else t
	n.y += -t if n.y >= 0 else t
	return v_normalized(n, V3_NOT_FINITE)
}

@(private) V3_NOT_FINITE :: "Vector3 cannot be normalized, the elements must be finite. Making (0, 0, 0) as a fallback."
@(private) V3_NOT_NORMAL :: "The normal Vector3 must be normalized."

@(private) v3_cross :: #force_inline proc "contextless" (a, b: Vector3) -> Vector3 {
	return {(a.y * b.z) - (a.z * b.y), (a.z * b.x) - (a.x * b.z), (a.x * b.y) - (a.y * b.x)}
}
@(private) v3_angle_to :: #force_inline proc "contextless" (a, b: Vector3) -> f32 {
	c := v3_cross(a, b)
	return libc.atan2f(m_sqrt(v_dot(c, c)), v_dot(a, b))
}
// Basis(axis, angle).xform(v): the rows of godot/basis.odin's b_axis_angle, each dotted with `v`.
// An axis that is not normalized leaves the identity basis, whose rows still dot with `v`: an
// infinite or NaN component makes NaNs of the others, as 0 * inf does.
@(private) v3_rotated :: #force_inline proc "contextless" (v, axis: Vector3, angle: f32) -> Vector3 {
	if !v_is_normalized(axis) {
		math_error("The axis Vector3 must be normalized.")
		return {v_dot(B_IDENTITY.x, v), v_dot(B_IDENTITY.y, v), v_dot(B_IDENTITY.z, v)}
	}
	sine, cosine := m_sincos(angle)
	b := b_axis_sin_cos(axis, sine, cosine)
	return {v_dot(b.x, v), v_dot(b.y, v), v_dot(b.z, v)}
}

// Vector4 ----------------------------------------------------------------------------------------

vector4_new :: proc "contextless" () -> (__r: Vector4) { return }
vector4_new_from_vector4 :: proc "contextless" (from: Vector4) -> (__r: Vector4) { return from }
vector4_new_from_vector4i :: proc "contextless" (from: Vector4i) -> (__r: Vector4) { return {f32(from.x), f32(from.y), f32(from.z), f32(from.w)} }
vector4_new_from_float_float_float_float :: proc "contextless" (x: f64, y: f64, z: f64, w: f64) -> (__r: Vector4) { return {f32(x), f32(y), f32(z), f32(w)} }
vector4_min_axis_index :: proc "contextless" (self: ^Vector4) -> (index: i64) {
	value := self.x
	for i in 1 ..< 4 { if self[i] <= value { index, value = i64(i), self[i] } }
	return
}
vector4_max_axis_index :: proc "contextless" (self: ^Vector4) -> (index: i64) {
	value := self.x
	for i in 1 ..< 4 { if self[i] > value { index, value = i64(i), self[i] } }
	return
}
vector4_length :: proc "contextless" (self: ^Vector4) -> f64 { return f64(m_sqrt(v_dot(self^, self^))) }
vector4_length_squared :: proc "contextless" (self: ^Vector4) -> f64 { return f64(v_dot(self^, self^)) }
vector4_abs :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_map(self^, m_abs) }
vector4_sign :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_map(self^, m_sign) }
vector4_floor :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_map(self^, m_floor) }
vector4_ceil :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_map(self^, m_ceil) }
vector4_round :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_map(self^, m_round) }
vector4_lerp :: proc "contextless" (self: ^Vector4, to: Vector4, weight: f64) -> Vector4 { return v_lerp(self^, to, f32(weight)) }
vector4_cubic_interpolate :: proc "contextless" (self: ^Vector4, b: Vector4, pre_a: Vector4, post_b: Vector4, weight: f64) -> Vector4 {
	return v_cubic(self^, b, pre_a, post_b, f32(weight))
}
vector4_cubic_interpolate_in_time :: proc "contextless" (self: ^Vector4, b: Vector4, pre_a: Vector4, post_b: Vector4, weight: f64, b_t: f64, pre_a_t: f64, post_b_t: f64) -> Vector4 {
	return v_cubic_in_time(self^, b, pre_a, post_b, f32(weight), f32(b_t), f32(pre_a_t), f32(post_b_t))
}
vector4_posmod :: proc "contextless" (self: ^Vector4, mod: f64) -> Vector4 { return v_posmod(self^, f32(mod)) }
vector4_posmodv :: proc "contextless" (self: ^Vector4, modv: Vector4) -> Vector4 { return v_map2(self^, modv, m_fposmod) }
vector4_snapped :: proc "contextless" (self: ^Vector4, step: Vector4) -> Vector4 { return v_map2(self^, step, m_snapped) }
vector4_snappedf :: proc "contextless" (self: ^Vector4, step: f64) -> Vector4 { return v_snapped(self^, f32(step)) }
vector4_clamp :: proc "contextless" (self: ^Vector4, min: Vector4, max: Vector4) -> Vector4 { return v_clamp(self^, min, max) }
vector4_clampf :: proc "contextless" (self: ^Vector4, min: f64, max: f64) -> Vector4 { return v_clampf(self^, f32(min), f32(max)) }
vector4_normalized :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_normalized(self^, V4_NOT_FINITE) }
vector4_is_normalized :: proc "contextless" (self: ^Vector4) -> bool { return v_is_normalized(self^) }
vector4_direction_to :: proc "contextless" (self: ^Vector4, to: Vector4) -> Vector4 { return v_normalized(to - self^, V4_NOT_FINITE) }
vector4_distance_to :: proc "contextless" (self: ^Vector4, to: Vector4) -> f64 { d := to - self^; return f64(m_sqrt(v_dot(d, d))) }
vector4_distance_squared_to :: proc "contextless" (self: ^Vector4, to: Vector4) -> f64 { d := to - self^; return f64(v_dot(d, d)) }
vector4_dot :: proc "contextless" (self: ^Vector4, with: Vector4) -> f64 { return f64(v_dot(self^, with)) }
vector4_inverse :: proc "contextless" (self: ^Vector4) -> Vector4 { return v_inverse(self^) }
vector4_is_equal_approx :: proc "contextless" (self: ^Vector4, to: Vector4) -> bool {
	return m_is_equal_approx(self.x, to.x) && m_is_equal_approx(self.y, to.y) && m_is_equal_approx(self.z, to.z) && m_is_equal_approx(self.w, to.w)
}
vector4_is_zero_approx :: proc "contextless" (self: ^Vector4) -> bool { return v_all(self^, m_is_zero_approx) }
vector4_is_finite :: proc "contextless" (self: ^Vector4) -> bool { return v_is_finite(self^) }
vector4_min :: proc "contextless" (self: ^Vector4, with: Vector4) -> Vector4 { return v_map2(self^, with, m_min) }
vector4_minf :: proc "contextless" (self: ^Vector4, with: f64) -> Vector4 { return v_minf(self^, f32(with)) }
vector4_max :: proc "contextless" (self: ^Vector4, with: Vector4) -> Vector4 { return v_map2(self^, with, m_max) }
vector4_maxf :: proc "contextless" (self: ^Vector4, with: f64) -> Vector4 { return v_maxf(self^, f32(with)) }

@(private) V4_NOT_FINITE :: "Vector4 cannot be normalized, the elements must be finite. Making (0, 0, 0, 0) as a fallback."
