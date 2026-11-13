package godot

// Quaternion methods and constructors computed in place, under the names and signatures the
// bindings generated before. Each follows the engine's own code in core/math/quaternion.cpp and
// quaternion.h of Godot 4.7-stable: single-precision operations in the same order, the same libm
// calls (sinf, cosf, acosf), the double comparisons the engine's `CMP_EPSILON` literal makes, and
// the double step of slerp, so results match bit for bit. The checks the engine makes under
// MATH_CHECKS (on in editor and debug builds) are made here too, with the same fallback results:
// the identity quaternion for a quaternion that must be normalized and is not, and the zero
// vector from get_euler. tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin.
//
// Godot 4.8 changed Quaternion::log and the blend that ends the two spherical cubic interpolations.
// `q_blend_log`, set once at load from the engine's version, picks that code on 4.8 or later.

import "core:c/libc"
import gde "../gdextension"

@(private) Q_IDENTITY :: Quaternion{0, 0, 0, 1}

// `1 - CMP_EPSILON` as the engine's compiler folds it, in double, by bits, because Odin folds
// constant expressions at higher precision.
@(private) Q_AXIS_LIMIT :: f64(0h3fefffeb074a771d)

// The shortest-arc constructor's `ALMOST_ONE` in single precision.
@(private) Q_ALMOST_ONE :: f32(0.99999975)

// `(real_t)Math::PI`.
@(private) Q_PI :: f32(3.1415926535897932384626433833)

// True on Godot 4.8 or later, whose Quaternion::log doubles x, y and z near the identity and whose
// spherical cubic interpolations end in Quaternion::blend_log. False on 4.7, where log has no such
// case and they end in a slerp. Written once at load by check_quaternion_version.
@(private) q_blend_log: bool

// Sets `q_blend_log` from the engine's version. Called once at load.
@(private) check_quaternion_version :: proc "contextless" () {
	v: gde.GodotVersion2
	gde.get_godot_version2(&v)
	q_blend_log = v.major > 4 || (v.major == 4 && v.minor >= 8)
}

@(private) Q_NOT_NORMALIZED :: "The quaternion must be normalized."

// Quaternion::operator*, the Hamilton product, each sum left to right as the engine writes it.
@(private) q_mul :: #force_inline proc "contextless" (a, b: Quaternion) -> Quaternion {
	return {
		a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
		a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
		a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
		a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
	}
}

// `q / length()`: the engine's operator/ multiplies by the reciprocal.
@(private) q_normalized :: #force_inline proc "contextless" (q: Quaternion) -> Quaternion {
	return q * (1 / m_sqrt(v_dot(q, q)))
}

@(private) q_inverse :: #force_inline proc "contextless" (q: Quaternion) -> Quaternion {
	if !q_is_normalized(q) {
		math_error(Q_NOT_NORMALIZED)
		return Q_IDENTITY
	}
	return {-q.x, -q.y, -q.z, q.w}
}

// Quaternion::get_axis. Its limit compares in double, as `1 - CMP_EPSILON` is a double expression.
@(private) q_get_axis :: #force_inline proc "contextless" (q: Quaternion) -> Vector3 {
	if f64(m_abs(q.w)) > Q_AXIS_LIMIT { return q.xyz }
	r := 1 / m_sqrt(1 - q.w * q.w)
	return {q.x * r, q.y * r, q.z * r}
}

@(private) q_get_angle :: #force_inline proc "contextless" (q: Quaternion) -> f32 { return 2 * m_acos(q.w) }

// Quaternion::log. From 4.8 a quaternion within `1 - CMP_EPSILON` of the identity, where the axis
// is not defined, gives twice its x, y and z; the limit is the double one get_axis compares with.
@(private) q_log :: #force_inline proc "contextless" (q: Quaternion) -> Quaternion {
	if q_blend_log && f64(m_abs(q.w)) > Q_AXIS_LIMIT { return {q.x * 2, q.y * 2, q.z * 2, 0} }
	v := q_get_axis(q) * q_get_angle(q)
	return {v.x, v.y, v.z, 0}
}

// Quaternion(axis, angle). A zero length cannot pass the normalized check, but the engine still
// tests for it.
@(private) q_from_axis_angle :: #force_inline proc "contextless" (axis: Vector3, angle: f32) -> Quaternion {
	if !v_is_normalized(axis) {
		math_error("The axis Vector3 must be normalized.")
		return Q_IDENTITY
	}
	d := m_sqrt(v_dot(axis, axis))
	if d == 0 { return {} }
	s := libc.sinf(angle * 0.5) / d
	return {axis.x * s, axis.y * s, axis.z * s, libc.cosf(angle * 0.5)}
}

// Quaternion::exp. `theta < CMP_EPSILON` compares in double.
@(private) q_exp :: #force_inline proc "contextless" (q: Quaternion) -> Quaternion {
	v := Vector3(q.xyz)
	theta := m_sqrt(v_dot(v, v))
	v = v_normalized(v, V3_NOT_FINITE)
	if f64(theta) < 0.00001 || !v_is_normalized(v) { return Q_IDENTITY }
	return q_from_axis_angle(v, theta)
}

@(private) q_signbit :: #force_inline proc "contextless" (x: f32) -> bool { return transmute(u32)x >> 31 != 0 }

// The log of `q` taken in the space of `base`, `(base.inverse() * q).log()`.
@(private) q_log_in :: #force_inline proc "contextless" (base, q: Quaternion) -> Quaternion {
	return q_log(q_mul(q_inverse(base), q))
}

// The x, y and z of the cubic through four logs, by Math::cubic_interpolate or its _in_time form.
@(private) q_cubic :: #force_inline proc "contextless" (from, to, pre, post: Quaternion, w, b_t, pre_t, post_t: f32, $IN_TIME: bool) -> (ln: Quaternion) {
	#unroll for i in 0 ..< 3 {
		when IN_TIME {
			ln[i] = m_cubic_in_time(from[i], to[i], pre[i], post[i], w, b_t, pre_t, post_t)
		} else {
			ln[i] = m_cubic(from[i], to[i], pre[i], post[i], w)
		}
	}
	return
}

// Quaternion::blend_log of 4.8: blends the cubic `from_ln`, taken in the space of `from_q`, with
// the cubic `to_ln`, taken in the space of the end quaternion, without leaving the exponential map.
// `to_in_from_ln` is the log of the end quaternion in the space of `from_q`; `to_ln` moves into
// that space by the engine's approximation of the inverse right Jacobian. `theta >= CMP_EPSILON`
// compares in double, and `c` takes its two steps in double, each narrowed back as the engine's
// real_t assignment does.
@(private) q_blend :: proc "contextless" (from_q, from_ln, to_ln, to_in_from_ln: Quaternion, w: f32) -> Quaternion {
	from, to, rel := Vector3(from_ln.xyz), Vector3(to_ln.xyz), Vector3(to_in_from_ln.xyz)
	theta := m_sqrt(v_dot(rel, rel))
	cross := v3_cross(rel, to)
	to += rel + cross * 0.5
	if f64(theta) >= 0.00001 {
		c := f32(1 / f64(theta * theta))
		if !m_is_equal_approx(theta, Q_PI) {
			sine, cosine := m_sincos(theta)
			c = f32(f64(c) - (1 + f64(cosine)) / (2 * f64(theta) * f64(sine)))
		}
		to += v3_cross(rel, cross) * c
	}
	blended := v_lerp(from, to, w)
	return q_mul(from_q, q_exp({blended.x, blended.y, blended.z, 0}))
}

// Quaternion::spherical_cubic_interpolate and its _in_time form, which differ only in the
// per-component cubic. Each quaternion is first replaced by the rotation of its own basis, which
// aligns flip phases, then flipped to the shortest path; the blend of the two exponential maps
// is a slerp on 4.7 and `q_blend` from 4.8.
@(private) q_spherical_cubic :: proc "contextless" (from, b, pre_a, post_b: Quaternion, w, b_t, pre_t, post_t: f32, $IN_TIME: bool) -> Quaternion {
	if !q_is_normalized(from) {
		math_error("The start quaternion must be normalized.")
		return Q_IDENTITY
	}
	if !q_is_normalized(b) {
		math_error("The end quaternion must be normalized.")
		return Q_IDENTITY
	}
	from_q := b_rotation_quaternion(b_from_quaternion(from))
	pre_q := b_rotation_quaternion(b_from_quaternion(pre_a))
	to_q := b_rotation_quaternion(b_from_quaternion(b))
	post_q := b_rotation_quaternion(b_from_quaternion(post_b))

	if q_signbit(v_dot(from_q, pre_q)) { pre_q = -pre_q }
	flip2 := q_signbit(v_dot(from_q, to_q))
	if flip2 { to_q = -to_q }
	flip3 := v_dot(to_q, post_q) <= 0 if flip2 else q_signbit(v_dot(to_q, post_q))
	if flip3 { post_q = -post_q }

	ln_to := q_log_in(from_q, to_q)
	ln_pre := q_log_in(from_q, pre_q)
	ln_post := q_log_in(from_q, post_q)
	from_ln := q_cubic({}, ln_to, ln_pre, ln_post, w, b_t, pre_t, post_t, IN_TIME)

	ln_from := q_log_in(to_q, from_q)
	ln_pre = q_log_in(to_q, pre_q)
	ln_post = q_log_in(to_q, post_q)
	to_ln := q_cubic(ln_from, {}, ln_pre, ln_post, w, b_t, pre_t, post_t, IN_TIME)

	if q_blend_log { return q_blend(from_q, from_ln, to_ln, ln_to, w) }
	return q_slerp(q_mul(from_q, q_exp(from_ln)), q_mul(to_q, q_exp(to_ln)), w)
}

// Vector3::get_any_perpendicular: the cross product with the axis of the least component,
// normalized.
@(private) v3_any_perpendicular :: #force_inline proc "contextless" (v: Vector3) -> Vector3 {
	if v_all(v, m_is_zero_approx) {
		math_error("The Vector3 must not be zero.")
		return {}
	}
	least_x := m_abs(v.x) <= m_abs(v.y) && m_abs(v.x) <= m_abs(v.z)
	return v_normalized(v3_cross(v, Vector3{1, 0, 0} if least_x else Vector3{0, 1, 0}), V3_NOT_FINITE)
}

// Quaternion(arc_from, arc_to), the shortest arc, normalized at the end with the engine's warning
// for non-finite elements. Vectors already within ALMOST_ONE of each other give the identity.
@(private) q_from_arc :: proc "contextless" (v0, v1: Vector3) -> Quaternion {
	if v_all(v0, m_is_zero_approx) || v_all(v1, m_is_zero_approx) {
		math_error("The vectors must not be zero.")
		return Q_IDENTITY
	}
	n0 := v_normalized(v0, V3_NOT_FINITE)
	n1 := v_normalized(v1, V3_NOT_FINITE)
	d := v_dot(n0, n1)
	q: Quaternion
	if m_abs(d) > Q_ALMOST_ONE {
		if d >= 0 { return Q_IDENTITY }
		axis := v3_any_perpendicular(n0)
		q = {axis.x, axis.y, axis.z, 0}
	} else {
		c := v3_cross(n0, n1)
		s := m_sqrt((1 + d) * 2)
		rs := 1 / s
		q = {c.x * rs, c.y * rs, c.z * rs, s * 0.5}
	}
	if !v_is_finite(q) {
		gde.print_warning("Quaternion cannot be normalized, the elements should be finite.", "", #file, #line, 1)
	}
	return q_normalized(q)
}

quaternion_new :: proc "contextless" () -> (__r: Quaternion) { return Q_IDENTITY }
quaternion_new_from_quaternion :: proc "contextless" (from: Quaternion) -> (__r: Quaternion) { return from }
quaternion_new_from_basis :: proc "contextless" (from: Basis) -> (__r: Quaternion) { return b_get_quaternion(from) }
quaternion_new_from_vector3_float :: proc "contextless" (axis: Vector3, angle: f64) -> (__r: Quaternion) {
	return q_from_axis_angle(axis, f32(angle))
}
quaternion_new_from_vector3_vector3 :: proc "contextless" (arc_from: Vector3, arc_to: Vector3) -> (__r: Quaternion) {
	return q_from_arc(arc_from, arc_to)
}
quaternion_new_from_float_float_float_float :: proc "contextless" (x: f64, y: f64, z: f64, w: f64) -> (__r: Quaternion) {
	return {f32(x), f32(y), f32(z), f32(w)}
}

quaternion_length :: proc "contextless" (self: ^Quaternion) -> f64 { return f64(m_sqrt(v_dot(self^, self^))) }
quaternion_length_squared :: proc "contextless" (self: ^Quaternion) -> f64 { return f64(v_dot(self^, self^)) }
quaternion_normalized :: proc "contextless" (self: ^Quaternion) -> Quaternion { return q_normalized(self^) }
quaternion_is_normalized :: proc "contextless" (self: ^Quaternion) -> bool { return q_is_normalized(self^) }
quaternion_is_equal_approx :: proc "contextless" (self: ^Quaternion, to: Quaternion) -> bool {
	q := self^
	return m_is_equal_approx(q.x, to.x) && m_is_equal_approx(q.y, to.y) && m_is_equal_approx(q.z, to.z) && m_is_equal_approx(q.w, to.w)
}
quaternion_is_finite :: proc "contextless" (self: ^Quaternion) -> bool { return v_is_finite(self^) }
quaternion_inverse :: proc "contextless" (self: ^Quaternion) -> Quaternion { return q_inverse(self^) }
quaternion_log :: proc "contextless" (self: ^Quaternion) -> Quaternion { return q_log(self^) }
quaternion_exp :: proc "contextless" (self: ^Quaternion) -> Quaternion { return q_exp(self^) }
quaternion_angle_to :: proc "contextless" (self: ^Quaternion, to: Quaternion) -> f64 {
	d := v_dot(self^, to)
	return f64(m_acos(d * d * 2 - 1))
}
quaternion_dot :: proc "contextless" (self: ^Quaternion, with: Quaternion) -> f64 { return f64(v_dot(self^, with)) }
quaternion_slerp :: proc "contextless" (self: ^Quaternion, to: Quaternion, weight: f64) -> Quaternion {
	return q_slerp(self^, to, f32(weight))
}

// Quaternion::slerpni: no sign flip, and the start unchanged once the two are within 0.9999.
quaternion_slerpni :: proc "contextless" (self: ^Quaternion, to: Quaternion, weight: f64) -> Quaternion {
	from, w := self^, f32(weight)
	if !q_is_normalized(from) || !q_is_normalized(to) {
		math_error("The quaternions to slerpni must be normalized.")
		return Q_IDENTITY
	}
	dot := v_dot(from, to)
	if m_abs(dot) > 0.9999 { return from }
	theta := m_acos(dot)
	sin_t := 1 / libc.sinf(theta)
	new_factor := libc.sinf(w * theta) * sin_t
	inv_factor := libc.sinf((1 - w) * theta) * sin_t
	return {
		inv_factor * from.x + new_factor * to.x,
		inv_factor * from.y + new_factor * to.y,
		inv_factor * from.z + new_factor * to.z,
		inv_factor * from.w + new_factor * to.w,
	}
}
quaternion_spherical_cubic_interpolate :: proc "contextless" (self: ^Quaternion, b: Quaternion, pre_a: Quaternion, post_b: Quaternion, weight: f64) -> Quaternion {
	return q_spherical_cubic(self^, b, pre_a, post_b, f32(weight), 0, 0, 0, false)
}
quaternion_spherical_cubic_interpolate_in_time :: proc "contextless" (self: ^Quaternion, b: Quaternion, pre_a: Quaternion, post_b: Quaternion, weight: f64, b_t: f64, pre_a_t: f64, post_b_t: f64) -> Quaternion {
	return q_spherical_cubic(self^, b, pre_a, post_b, f32(weight), f32(b_t), f32(pre_a_t), f32(post_b_t), true)
}

// Quaternion::get_euler: the Euler angles of its basis, after the engine's normalized check.
quaternion_get_euler :: proc "contextless" (self: ^Quaternion, order: i64) -> Vector3 {
	if !q_is_normalized(self^) {
		math_error(Q_NOT_NORMALIZED)
		return {}
	}
	b := b_from_quaternion(self^)
	return basis_get_euler(&b, order)
}

// Quaternion::from_euler, YXZ: half angles a1 about Y, a2 about X, a3 about Z.
quaternion_from_euler :: proc "contextless" (euler: Vector3) -> Quaternion {
	half_a1, half_a2, half_a3 := euler.y * 0.5, euler.x * 0.5, euler.z * 0.5
	sin_a1, cos_a1 := m_sincos(half_a1)
	sin_a2, cos_a2 := m_sincos(half_a2)
	sin_a3, cos_a3 := m_sincos(half_a3)
	return {
		sin_a1 * cos_a2 * sin_a3 + cos_a1 * sin_a2 * cos_a3,
		sin_a1 * cos_a2 * cos_a3 - cos_a1 * sin_a2 * sin_a3,
		-sin_a1 * sin_a2 * cos_a3 + cos_a1 * cos_a2 * sin_a3,
		sin_a1 * sin_a2 * sin_a3 + cos_a1 * cos_a2 * cos_a3,
	}
}
quaternion_get_axis :: proc "contextless" (self: ^Quaternion) -> Vector3 { return q_get_axis(self^) }
quaternion_get_angle :: proc "contextless" (self: ^Quaternion) -> f64 { return f64(q_get_angle(self^)) }
