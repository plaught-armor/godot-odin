package godot

// Transform2D and Transform3D methods and constructors computed in place, under the names and
// signatures the bindings generated before. Each follows the engine's own code in
// core/math/transform_2d.cpp, transform_3d.cpp and their headers in Godot 4.7-stable:
// single-precision operations in the same order and the same libm calls (sinf, cosf, atan2f,
// acosf, fmodf), so results match bit for bit. The checks the engine makes under MATH_CHECKS (on
// in editor and debug builds) are made here too, with the same fallback results: a singular
// Transform2D's affine inverse is the copy unchanged, a singular Transform3D's keeps its basis,
// and Transform3D.looking_at at its own origin gives the identity.
// tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin.
//
// Transform2D's x, y and origin are the engine's columns[0], columns[1] and columns[2].

import "core:c/libc"
import "core:math"

@(private) T2_IDENTITY :: Transform2D{{1, 0}, {0, 1}, {0, 0}}
@(private) T3_IDENTITY :: Transform3D{B_IDENTITY, {0, 0, 0}}

// `(float)Math::TAU` and `(float)Math::PI`.
@(private) TAU_F32 :: f32(math.TAU)
@(private) PI_F32 :: f32(math.PI)

// Math::acos(float), which clamps its argument to [-1, 1] before the library call.
@(private) m_acos :: #force_inline proc "contextless" (x: f32) -> f32 {
	return PI_F32 if x < -1 else (0 if x > 1 else libc.acosf(x))
}

// Math::lerp_angle(float): the shortest signed difference by two fmodf calls, then a lerp.
@(private) m_lerp_angle :: #force_inline proc "contextless" (from, to, weight: f32) -> f32 {
	d := libc.fmodf(to - from, TAU_F32)
	return from + (libc.fmodf(2 * d, TAU_F32) - d) * weight
}

// Transform2D ------------------------------------------------------------------------------------

// basis_xform, which is also tdotx and tdoty taken together.
@(private) t2_basis_xform :: #force_inline proc "contextless" (t: Transform2D, v: Vector2) -> Vector2 {
	return {t.x.x * v.x + t.y.x * v.y, t.x.y * v.x + t.y.y * v.y}
}
@(private) t2_xform :: #force_inline proc "contextless" (t: Transform2D, v: Vector2) -> Vector2 {
	return t2_basis_xform(t, v) + t.origin
}
// `a * b`, the engine's operator*=.
@(private) t2_mul :: #force_inline proc "contextless" (a, b: Transform2D) -> Transform2D {
	return {t2_basis_xform(a, b.x), t2_basis_xform(a, b.y), t2_xform(a, b.origin)}
}
@(private) t2_determinant :: #force_inline proc "contextless" (t: Transform2D) -> f32 {
	return t.x.x * t.y.y - t.x.y * t.y.x
}
@(private) t2_get_rotation :: #force_inline proc "contextless" (t: Transform2D) -> f32 {
	return libc.atan2f(t.x.y, t.x.x)
}
// The column lengths, the second negated when the determinant is negative and zeroed (or NaN,
// for an infinite length) when it is zero or NaN, as SIGN gives 0 there.
@(private) t2_get_scale :: #force_inline proc "contextless" (t: Transform2D) -> Vector2 {
	return {m_sqrt(v_dot(t.x, t.x)), m_sign(t2_determinant(t)) * m_sqrt(v_dot(t.y, t.y))}
}
@(private) t2_from_rotation :: #force_inline proc "contextless" (rot: f32, pos: Vector2) -> Transform2D {
	sr, cr := m_sincos(rot)
	return {{cr, sr}, {-sr, cr}, pos}
}
@(private) t2_from_rotation_scale_skew :: #force_inline proc "contextless" (rot: f32, scale: Vector2, skew: f32, pos: Vector2) -> Transform2D {
	return {
		{libc.cosf(rot) * scale.x, libc.sinf(rot) * scale.x},
		{-libc.sinf(rot + skew) * scale.y, libc.cosf(rot + skew) * scale.y},
		pos,
	}
}
// affine_invert. A zero determinant fails the engine's check and leaves the copy as it was.
@(private) t2_affine_inverse :: #force_inline proc "contextless" (t: Transform2D) -> Transform2D {
	det := t2_determinant(t)
	if det == 0 {
		math_error("Condition \"det == 0\" is true.")
		return t
	}
	idet := 1 / det
	r := t
	r.x.x, r.y.y = t.y.y, t.x.x
	r.x *= Vector2{idet, -idet}
	r.y *= Vector2{-idet, idet}
	r.origin = t2_basis_xform(r, -t.origin)
	return r
}

transform2d_new :: proc "contextless" () -> (__r: Transform2D) { return T2_IDENTITY }
transform2d_new_from_transform2d :: proc "contextless" (from: Transform2D) -> (__r: Transform2D) { return from }
transform2d_new_from_float_vector2 :: proc "contextless" (rotation: f64, position: Vector2) -> (__r: Transform2D) {
	return t2_from_rotation(f32(rotation), position)
}
transform2d_new_from_float_vector2_float_vector2 :: proc "contextless" (rotation: f64, scale: Vector2, skew: f64, position: Vector2) -> (__r: Transform2D) {
	return t2_from_rotation_scale_skew(f32(rotation), scale, f32(skew), position)
}
transform2d_new_from_vector2_vector2_vector2 :: proc "contextless" (x_axis: Vector2, y_axis: Vector2, origin: Vector2) -> (__r: Transform2D) {
	return {x_axis, y_axis, origin}
}

// invert, which assumes a rotation: the basis transposed and the origin carried through it.
transform2d_inverse :: proc "contextless" (self: ^Transform2D) -> Transform2D {
	t := self^
	r := t
	r.x.y, r.y.x = t.y.x, t.x.y
	r.origin = t2_basis_xform(r, -t.origin)
	return r
}
transform2d_affine_inverse :: proc "contextless" (self: ^Transform2D) -> Transform2D { return t2_affine_inverse(self^) }
transform2d_get_rotation :: proc "contextless" (self: ^Transform2D) -> f64 { return f64(t2_get_rotation(self^)) }
transform2d_get_origin :: proc "contextless" (self: ^Transform2D) -> Vector2 { return self.origin }
transform2d_get_scale :: proc "contextless" (self: ^Transform2D) -> Vector2 { return t2_get_scale(self^) }
transform2d_get_skew :: proc "contextless" (self: ^Transform2D) -> f64 {
	t := self^
	x := v_normalized(t.x, V2_NOT_FINITE)
	y := m_sign(t2_determinant(t)) * v_normalized(t.y, V2_NOT_FINITE)
	return f64(m_acos(v_dot(x, y)) - B_HALF_PI)
}
// Gram-Schmidt on the two basis columns, each normalized as Vector2::normalize does.
transform2d_orthonormalized :: proc "contextless" (self: ^Transform2D) -> Transform2D {
	t := self^
	x := v_normalized(t.x, V2_NOT_FINITE)
	y := v_normalized(t.y - x * v_dot(x, t.y), V2_NOT_FINITE)
	return {x, y, t.origin}
}
transform2d_rotated :: proc "contextless" (self: ^Transform2D, angle: f64) -> Transform2D {
	return t2_mul(t2_from_rotation(f32(angle), {}), self^)
}
transform2d_rotated_local :: proc "contextless" (self: ^Transform2D, angle: f64) -> Transform2D {
	return t2_mul(self^, t2_from_rotation(f32(angle), {}))
}
// scale: each basis row scaled, then the origin.
transform2d_scaled :: proc "contextless" (self: ^Transform2D, scale: Vector2) -> Transform2D {
	t := self^
	return {t.x * scale, t.y * scale, t.origin * scale}
}
transform2d_scaled_local :: proc "contextless" (self: ^Transform2D, scale: Vector2) -> Transform2D {
	t := self^
	return {t.x * scale.x, t.y * scale.y, t.origin}
}
transform2d_translated :: proc "contextless" (self: ^Transform2D, offset: Vector2) -> Transform2D {
	t := self^
	return {t.x, t.y, t.origin + offset}
}
transform2d_translated_local :: proc "contextless" (self: ^Transform2D, offset: Vector2) -> Transform2D {
	t := self^
	return {t.x, t.y, t.origin + t2_basis_xform(t, offset)}
}
transform2d_determinant :: proc "contextless" (self: ^Transform2D) -> f64 { return f64(t2_determinant(self^)) }
transform2d_basis_xform :: proc "contextless" (self: ^Transform2D, v: Vector2) -> Vector2 { return t2_basis_xform(self^, v) }
transform2d_basis_xform_inv :: proc "contextless" (self: ^Transform2D, v: Vector2) -> Vector2 {
	return {v_dot(self.x, v), v_dot(self.y, v)}
}
// Rotation and skew lerped as angles, scale and origin lerped per component, then rebuilt.
transform2d_interpolate_with :: proc "contextless" (self: ^Transform2D, xform: Transform2D, weight: f64) -> Transform2D {
	a, b, w := self^, xform, f32(weight)
	rot := m_lerp_angle(t2_get_rotation(a), t2_get_rotation(b), w)
	scale := v_lerp(t2_get_scale(a), t2_get_scale(b), w)
	skew := m_lerp_angle(f32(transform2d_get_skew(&a)), f32(transform2d_get_skew(&b)), w)
	return t2_from_rotation_scale_skew(rot, scale, skew, v_lerp(a.origin, b.origin, w))
}
transform2d_is_conformal :: proc "contextless" (self: ^Transform2D) -> bool {
	t := self^
	return (m_is_equal_approx(t.x.x, t.y.y) && m_is_equal_approx(t.x.y, -t.y.x)) ||
		(m_is_equal_approx(t.x.x, -t.y.y) && m_is_equal_approx(t.x.y, t.y.x))
}
transform2d_is_equal_approx :: proc "contextless" (self: ^Transform2D, xform: Transform2D) -> bool {
	m, o := transmute([6]f32)self^, transmute([6]f32)xform
	#unroll for i in 0 ..< 6 { if !m_is_equal_approx(m[i], o[i]) { return false } }
	return true
}
transform2d_is_finite :: proc "contextless" (self: ^Transform2D) -> bool {
	return v_is_finite(self.x) && v_is_finite(self.y) && v_is_finite(self.origin)
}
// The rotation of this transform, turned toward the target as seen through the affine inverse,
// then set as set_rotation does: the scale read first, the basis columns renormalized after.
transform2d_looking_at :: proc "contextless" (self: ^Transform2D, target: Vector2) -> Transform2D {
	t := self^
	r := t2_from_rotation(t2_get_rotation(t), t.origin)
	tp := t2_xform(t2_affine_inverse(t), target) * t2_get_scale(t)
	rot := t2_get_rotation(r) + libc.atan2f(tp.y, tp.x)
	scale := t2_get_scale(r)
	sr, cr := m_sincos(rot)
	r.x = v_normalized(Vector2{cr, sr}, V2_NOT_FINITE) * scale.x
	r.y = v_normalized(Vector2{-sr, cr}, V2_NOT_FINITE) * scale.y
	return r
}

// Transform3D ------------------------------------------------------------------------------------

// Basis::xform: each row dotted with the vector.
@(private) t3_basis_xform :: #force_inline proc "contextless" (b: Basis, v: Vector3) -> Vector3 {
	return {v_dot(b.x, v), v_dot(b.y, v), v_dot(b.z, v)}
}

transform3d_new :: proc "contextless" () -> (__r: Transform3D) { return T3_IDENTITY }
transform3d_new_from_transform3d :: proc "contextless" (from: Transform3D) -> (__r: Transform3D) { return from }
transform3d_new_from_basis_vector3 :: proc "contextless" (basis: Basis, origin: Vector3) -> (__r: Transform3D) {
	return {basis, origin}
}
transform3d_new_from_vector3_vector3_vector3_vector3 :: proc "contextless" (x_axis: Vector3, y_axis: Vector3, z_axis: Vector3, origin: Vector3) -> (__r: Transform3D) {
	return {b_from_columns(x_axis, y_axis, z_axis), origin}
}
// The upper 3x4 of the projection: its first three columns as the basis columns and its last as
// the origin.
transform3d_new_from_projection :: proc "contextless" (from: Projection) -> (__r: Transform3D) {
	return {b_from_columns(from.x.xyz, from.y.xyz, from.z.xyz), from.w.xyz}
}

transform3d_inverse :: proc "contextless" (self: ^Transform3D) -> Transform3D {
	b := basis_transposed(&self.basis)
	return {b, t3_basis_xform(b, -self.origin)}
}
// affine_invert. A singular basis fails Basis::invert's check and stays as it was; the origin is
// still carried through it.
transform3d_affine_inverse :: proc "contextless" (self: ^Transform3D) -> Transform3D {
	b := b_inverse(self.basis)
	return {b, t3_basis_xform(b, -self.origin)}
}
transform3d_orthonormalized :: proc "contextless" (self: ^Transform3D) -> Transform3D {
	return {b_orthonormalized(self.basis), self.origin}
}
transform3d_rotated :: proc "contextless" (self: ^Transform3D, axis: Vector3, angle: f64) -> Transform3D {
	p := b_axis_angle(axis, f32(angle))
	return {b_mul(p, self.basis), t3_basis_xform(p, self.origin)}
}
transform3d_rotated_local :: proc "contextless" (self: ^Transform3D, axis: Vector3, angle: f64) -> Transform3D {
	return {b_mul(self.basis, b_axis_angle(axis, f32(angle))), self.origin}
}
transform3d_scaled :: proc "contextless" (self: ^Transform3D, scale: Vector3) -> Transform3D {
	return {basis_scaled(&self.basis, scale), self.origin * scale}
}
transform3d_scaled_local :: proc "contextless" (self: ^Transform3D, scale: Vector3) -> Transform3D {
	return {basis_scaled_local(&self.basis, scale), self.origin}
}
transform3d_translated :: proc "contextless" (self: ^Transform3D, offset: Vector3) -> Transform3D {
	return {self.basis, self.origin + offset}
}
transform3d_translated_local :: proc "contextless" (self: ^Transform3D, offset: Vector3) -> Transform3D {
	return {self.basis, self.origin + t3_basis_xform(self.basis, offset)}
}
transform3d_looking_at :: proc "contextless" (self: ^Transform3D, target: Vector3, up: Vector3, use_model_front: bool) -> Transform3D {
	o := self.origin
	if m_is_equal_approx(o.x, target.x) && m_is_equal_approx(o.y, target.y) && m_is_equal_approx(o.z, target.z) {
		math_error("The transform's origin and target can't be equal.")
		return T3_IDENTITY
	}
	return {basis_looking_at(target - o, up, use_model_front), o}
}
// Rotation slerped as quaternions and normalized, scale and origin lerped per component; the
// basis rebuilt as set_quaternion_scale does, Basis(rotation) times the scale diagonal.
transform3d_interpolate_with :: proc "contextless" (self: ^Transform3D, xform: Transform3D, weight: f64) -> Transform3D {
	a, b, w := self^, xform, f32(weight)
	q := q_slerp(b_rotation_quaternion(a.basis), b_rotation_quaternion(b.basis), w)
	q = q * (1 / m_sqrt(v_dot(q, q)))
	s := v_lerp(basis_get_scale(&a.basis), basis_get_scale(&b.basis), w)
	return {b_mul(b_from_quaternion(q), basis_from_scale(s)), v_lerp(a.origin, b.origin, w)}
}
transform3d_is_equal_approx :: proc "contextless" (self: ^Transform3D, xform: Transform3D) -> bool {
	m, o := transmute([12]f32)self^, transmute([12]f32)xform
	#unroll for i in 0 ..< 12 { if !m_is_equal_approx(m[i], o[i]) { return false } }
	return true
}
transform3d_is_finite :: proc "contextless" (self: ^Transform3D) -> bool {
	return basis_is_finite(&self.basis) && v_is_finite(self.origin)
}
