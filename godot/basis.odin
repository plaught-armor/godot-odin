package godot

// Basis methods and constructors computed in place, under the names and signatures the bindings
// generated before. Each follows the engine's own code in core/math/basis.cpp, basis.h and
// quaternion.cpp of Godot 4.7-stable: single-precision operations in the same order, the same
// libm calls (sinf, cosf, atan2f, asinf, acosf), and the one double step of Quaternion::slerp, so
// results match bit for bit. The checks the engine makes under MATH_CHECKS (on in editor and
// debug builds) are made here too, with the same fallback results: a singular basis inverts to
// itself, a basis that is not a rotation gives the identity quaternion, and an axis that is not
// normalized gives the identity rotation.
// tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin.
//
// The engine stores a Basis as three rows. The generated struct names them x, y and z, but its
// fields hold rows, not the column axes GDScript calls x, y and z.

import "core:c/libc"
import "core:math"
import gde "../gdextension"

@(private) Basis_Rows :: [3]Vector3

@(private) B_IDENTITY :: Basis{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}

// `1.0f - epsilon` with get_euler's epsilon of 0.00000025, as the engine's compiler folds it in
// single precision, by bits, because Odin folds constant expressions at higher precision.
@(private) B_EULER_LIMIT :: f32(0h3f7ffffc)
// `Math::PI / 2.0f` stored in a real_t.
@(private) B_HALF_PI :: f32(math.PI / 2)

@(private) b_from_columns :: #force_inline proc "contextless" (x, y, z: Vector3) -> Basis {
	return {{x.x, y.x, z.x}, {x.y, y.y, z.y}, {x.z, y.z, z.z}}
}

@(private) b_column :: #force_inline proc "contextless" (m: Basis_Rows, i: int) -> Vector3 {
	return {m[0][i], m[1][i], m[2][i]}
}

// `a * b`: each entry the dot of a row of `a` with a column of `b`, summed as the engine's tdotx,
// tdoty and tdotz do. Zero entries still multiply, so infinities and NaNs spread as there.
@(private) b_mul :: #force_inline proc "contextless" (a, b: Basis) -> Basis {
	l, r := transmute(Basis_Rows)a, transmute(Basis_Rows)b
	o: Basis_Rows
	#unroll for i in 0 ..< 3 {
		#unroll for j in 0 ..< 3 {
			o[i][j] = r[0][j] * l[i][0] + r[1][j] * l[i][1] + r[2][j] * l[i][2]
		}
	}
	return transmute(Basis)o
}

@(private) b_determinant :: #force_inline proc "contextless" (b: Basis) -> f32 {
	m := transmute(Basis_Rows)b
	return m[0][0] * (m[1][1] * m[2][2] - m[2][1] * m[1][2]) -
		m[1][0] * (m[0][1] * m[2][2] - m[2][1] * m[0][2]) +
		m[2][0] * (m[0][1] * m[1][2] - m[1][1] * m[0][2])
}

// Basis(axis, angle), the engine's set_axis_angle. An axis that is not normalized leaves the
// identity, as the engine's constructor does once its check fails.
@(private) b_axis_angle :: #force_inline proc "contextless" (axis: Vector3, angle: f32) -> Basis {
	if !v_is_normalized(axis) {
		math_error("The axis Vector3 must be normalized.")
		return B_IDENTITY
	}
	sq := axis * axis
	cosine := libc.cosf(angle)
	sine := libc.sinf(angle)
	t := 1 - cosine
	m: Basis_Rows
	m[0].x = sq.x + cosine * (1 - sq.x)
	m[1].y = sq.y + cosine * (1 - sq.y)
	m[2].z = sq.z + cosine * (1 - sq.z)
	xyzt, zyxs := axis.x * axis.y * t, axis.z * sine
	m[0].y, m[1].x = xyzt - zyxs, xyzt + zyxs
	xyzt, zyxs = axis.x * axis.z * t, axis.y * sine
	m[0].z, m[2].x = xyzt + zyxs, xyzt - zyxs
	xyzt, zyxs = axis.y * axis.z * t, axis.x * sine
	m[1].z, m[2].y = xyzt - zyxs, xyzt + zyxs
	return transmute(Basis)m
}

// Basis(quaternion), the engine's set_quaternion. It makes no check: a quaternion that is not
// normalized still scales by 2 / length_squared.
@(private) b_from_quaternion :: #force_inline proc "contextless" (q: Quaternion) -> Basis {
	s := 2 / v_dot(q, q)
	xs, ys, zs := q.x * s, q.y * s, q.z * s
	wx, wy, wz := q.w * xs, q.w * ys, q.w * zs
	xx, xy, xz := q.x * xs, q.x * ys, q.x * zs
	yy, yz, zz := q.y * ys, q.y * zs, q.z * zs
	return {{1 - (yy + zz), xy - wz, xz + wy}, {xy + wz, 1 - (xx + zz), yz - wx}, {xz - wy, yz + wx, 1 - (xx + yy)}}
}

@(private) b_is_conformal :: #force_inline proc "contextless" (b: Basis) -> bool {
	m := transmute(Basis_Rows)b
	x, y, z := b_column(m, 0), b_column(m, 1), b_column(m, 2)
	x_len_sq := v_dot(x, x)
	return m_is_equal_approx(x_len_sq, v_dot(y, y)) && m_is_equal_approx(x_len_sq, v_dot(z, z)) &&
		m_is_zero_approx(v_dot(x, y)) && m_is_zero_approx(v_dot(x, z)) && m_is_zero_approx(v_dot(y, z))
}

// Gram-Schmidt on the columns, each normalized as Vector3::normalize does (a non-finite column
// warns and becomes zero).
@(private) b_orthonormalized :: #force_inline proc "contextless" (b: Basis) -> Basis {
	m := transmute(Basis_Rows)b
	x := v_normalized(b_column(m, 0), V3_NOT_FINITE)
	y := b_column(m, 1)
	z := b_column(m, 2)
	y = v_normalized(y - x * v_dot(x, y), V3_NOT_FINITE)
	z = v_normalized(z - x * v_dot(x, z) - y * v_dot(y, z), V3_NOT_FINITE)
	return b_from_columns(x, y, z)
}

// Basis::get_quaternion. Under MATH_CHECKS the engine refuses a basis that is not a rotation
// (conformal, with a determinant within UNIT_EPSILON of 1) and gives the identity quaternion.
@(private) b_get_quaternion :: #force_inline proc "contextless" (b: Basis) -> Quaternion {
	det := b_determinant(b)
	if !(b_is_conformal(b) && (det == 1 || m_abs(det - 1) < UNIT_EPSILON)) {
		math_error("Basis must be normalized in order to be casted to a Quaternion. Use get_rotation_quaternion() or call orthonormalized() if the Basis contains linearly independent vectors.")
		return {0, 0, 0, 1}
	}
	m := transmute(Basis_Rows)b
	trace := m[0][0] + m[1][1] + m[2][2]
	t: [4]f32
	if trace > 0 {
		s := m_sqrt(trace + 1)
		t[3] = s * 0.5
		s = 0.5 / s
		t[0] = (m[2][1] - m[1][2]) * s
		t[1] = (m[0][2] - m[2][0]) * s
		t[2] = (m[1][0] - m[0][1]) * s
	} else {
		i := (2 if m[1][1] < m[2][2] else 1) if m[0][0] < m[1][1] else (2 if m[0][0] < m[2][2] else 0)
		j := (i + 1) % 3
		k := (i + 2) % 3
		s := m_sqrt(m[i][i] - m[j][j] - m[k][k] + 1)
		t[i] = s * 0.5
		s = 0.5 / s
		t[3] = (m[k][j] - m[j][k]) * s
		t[j] = (m[j][i] + m[i][j]) * s
		t[k] = (m[k][i] + m[i][k]) * s
	}
	return Quaternion(t)
}

@(private) q_is_normalized :: #force_inline proc "contextless" (q: Quaternion) -> bool {
	d := v_dot(q, q)
	return d == 1 || m_abs(d - 1) < UNIT_EPSILON
}

// Quaternion::slerp. Its first scale takes `(1.0 - weight) * omega` in double and divides in
// double before storing to float; the second stays in float. The cosine is never negative once
// the sign is flipped and below 1 in the slerp branch, so Math::acos's clamping never applies.
@(private) q_slerp :: proc "contextless" (from, to: Quaternion, weight: f32) -> Quaternion {
	if !q_is_normalized(from) || !q_is_normalized(to) {
		math_error("The quaternions to slerp must be normalized.")
		return {0, 0, 0, 1}
	}
	cosom := v_dot(from, to)
	to1 := to
	if cosom < 0 {
		cosom = -cosom
		to1 = -to
	}
	scale0, scale1: f32
	if 1 - cosom > CMP_EPSILON {
		omega := libc.acosf(cosom)
		sinom := libc.sinf(omega)
		scale0 = f32(libc.sin((1.0 - f64(weight)) * f64(omega)) / f64(sinom))
		scale1 = libc.sinf(weight * omega) / sinom
	} else {
		scale0 = 1 - weight
		scale1 = weight
	}
	return from * scale0 + to1 * scale1
}

basis_new :: proc "contextless" () -> (__r: Basis) { return B_IDENTITY }
basis_new_from_basis :: proc "contextless" (from: Basis) -> (__r: Basis) { return from }
basis_new_from_quaternion :: proc "contextless" (from: Quaternion) -> (__r: Basis) { return b_from_quaternion(from) }
basis_new_from_vector3_float :: proc "contextless" (axis: Vector3, angle: f64) -> (__r: Basis) {
	return b_axis_angle(axis, f32(angle))
}
basis_new_from_vector3_vector3_vector3 :: proc "contextless" (x_axis: Vector3, y_axis: Vector3, z_axis: Vector3) -> (__r: Basis) {
	return b_from_columns(x_axis, y_axis, z_axis)
}

// Basis::invert by cofactors. A zero determinant fails the engine's check and leaves the copy as it was.
@(private) b_inverse :: #force_inline proc "contextless" (b: Basis) -> Basis {
	m := transmute(Basis_Rows)b
	cofac :: #force_inline proc "contextless" (m: Basis_Rows, r1, c1, r2, c2: int) -> f32 {
		return m[r1][c1] * m[r2][c2] - m[r1][c2] * m[r2][c1]
	}
	co0, co1, co2 := cofac(m, 1, 1, 2, 2), cofac(m, 1, 2, 2, 0), cofac(m, 1, 0, 2, 1)
	det := m[0][0] * co0 + m[0][1] * co1 + m[0][2] * co2
	if det == 0 {
		math_error("Condition \"det == 0\" is true.")
		return b
	}
	s := 1 / det
	return {
		{co0 * s, cofac(m, 0, 2, 2, 1) * s, cofac(m, 0, 1, 1, 2) * s},
		{co1 * s, cofac(m, 0, 0, 2, 2) * s, cofac(m, 0, 2, 1, 0) * s},
		{co2 * s, cofac(m, 0, 1, 2, 0) * s, cofac(m, 0, 0, 1, 1) * s},
	}
}
basis_inverse :: proc "contextless" (self: ^Basis) -> Basis { return b_inverse(self^) }
basis_transposed :: proc "contextless" (self: ^Basis) -> Basis {
	m := transmute(Basis_Rows)self^
	return b_from_columns(m[0], m[1], m[2])
}
basis_orthonormalized :: proc "contextless" (self: ^Basis) -> Basis { return b_orthonormalized(self^) }
basis_determinant :: proc "contextless" (self: ^Basis) -> f64 { return f64(b_determinant(self^)) }
basis_rotated :: proc "contextless" (self: ^Basis, axis: Vector3, angle: f64) -> Basis {
	return b_mul(b_axis_angle(axis, f32(angle)), self^)
}
basis_scaled :: proc "contextless" (self: ^Basis, scale: Vector3) -> Basis {
	return {self.x * scale.x, self.y * scale.y, self.z * scale.z}
}
basis_scaled_local :: proc "contextless" (self: ^Basis, scale: Vector3) -> Basis {
	return {self.x * scale, self.y * scale, self.z * scale}
}
// The column lengths, all negated when the determinant is negative and all zero (or NaN, for an
// infinite length) when it is zero or NaN, as SIGN gives 0 there.
basis_get_scale :: proc "contextless" (self: ^Basis) -> Vector3 {
	m := transmute(Basis_Rows)self^
	x, y, z := b_column(m, 0), b_column(m, 1), b_column(m, 2)
	return Vector3{m_sqrt(v_dot(x, x)), m_sqrt(v_dot(y, y)), m_sqrt(v_dot(z, z))} * m_sign(b_determinant(self^))
}

basis_tdotx :: proc "contextless" (self: ^Basis, with: Vector3) -> f64 {
	return f64(self.x.x * with.x + self.y.x * with.y + self.z.x * with.z)
}
basis_tdoty :: proc "contextless" (self: ^Basis, with: Vector3) -> f64 {
	return f64(self.x.y * with.x + self.y.y * with.y + self.z.y * with.z)
}
basis_tdotz :: proc "contextless" (self: ^Basis, with: Vector3) -> f64 {
	return f64(self.x.z * with.x + self.y.z * with.y + self.z.z * with.z)
}

// Basis::slerp: the rotations slerped as quaternions, each row then scaled by the lerp of the
// two rows' lengths.
basis_slerp :: proc "contextless" (self: ^Basis, to: Basis, weight: f64) -> Basis {
	w := f32(weight)
	b := transmute(Basis_Rows)b_from_quaternion(q_slerp(b_get_quaternion(self^), b_get_quaternion(to), w))
	m, t := transmute(Basis_Rows)self^, transmute(Basis_Rows)to
	#unroll for i in 0 ..< 3 {
		b[i] *= m_lerp(m_sqrt(v_dot(m[i], m[i])), m_sqrt(v_dot(t[i], t[i])), w)
	}
	return transmute(Basis)b
}

basis_is_conformal :: proc "contextless" (self: ^Basis) -> bool { return b_is_conformal(self^) }
basis_is_equal_approx :: proc "contextless" (self: ^Basis, b: Basis) -> bool {
	m, o := transmute([9]f32)self^, transmute([9]f32)b
	#unroll for i in 0 ..< 9 { if !m_is_equal_approx(m[i], o[i]) { return false } }
	return true
}
basis_is_finite :: proc "contextless" (self: ^Basis) -> bool {
	return v_is_finite(self.x) && v_is_finite(self.y) && v_is_finite(self.z)
}
basis_is_orthonormal :: proc "contextless" (self: ^Basis) -> bool {
	m := transmute(Basis_Rows)self^
	x, y, z := b_column(m, 0), b_column(m, 1), b_column(m, 2)
	return m_is_equal_approx(v_dot(x, x), 1) && m_is_equal_approx(v_dot(y, y), 1) && m_is_equal_approx(v_dot(z, z), 1) &&
		m_is_zero_approx(v_dot(x, y)) && m_is_zero_approx(v_dot(x, z)) && m_is_zero_approx(v_dot(y, z))
}

basis_get_rotation_quaternion :: proc "contextless" (self: ^Basis) -> Quaternion { return b_rotation_quaternion(self^) }
// The orthonormalized basis, negated when it reflects, as a quaternion. Inlined so a caller that
// takes two, as Transform3D.interpolate_with does, can run their sqrt and divide chains together.
@(private) b_rotation_quaternion :: #force_inline proc "contextless" (b: Basis) -> Quaternion {
	m := b_orthonormalized(b)
	if b_determinant(m) < 0 {
		m = {m.x * -1, m.y * -1, m.z * -1}
	}
	return b_get_quaternion(m)
}

basis_looking_at :: proc "contextless" (target: Vector3, up: Vector3, use_model_front: bool) -> Basis {
	if v_all(target, m_is_zero_approx) {
		math_error("The target vector can't be zero.")
		return B_IDENTITY
	}
	if v_all(up, m_is_zero_approx) {
		math_error("The up vector can't be zero.")
		return B_IDENTITY
	}
	v_z := v_normalized(target, V3_NOT_FINITE)
	if !use_model_front { v_z = -v_z }
	v_x := v3_cross(up, v_z)
	if v_all(v_x, m_is_zero_approx) {
		gde.print_warning("Target and up vectors are colinear. This is not advised as it may cause unwanted rotation around local Z axis.", "", #file, #line, 1)
		// Vector3::get_any_perpendicular, whose own zero check `up` has passed above.
		least_x := m_abs(up.x) <= m_abs(up.y) && m_abs(up.x) <= m_abs(up.z)
		v_x = v_normalized(v3_cross(up, Vector3{1, 0, 0} if least_x else Vector3{0, 1, 0}), V3_NOT_FINITE)
	}
	v_x = v_normalized(v_x, V3_NOT_FINITE)
	return b_from_columns(v_x, v3_cross(v_z, v_x), v_z)
}
basis_from_scale :: proc "contextless" (scale: Vector3) -> Basis {
	return {{scale.x, 0, 0}, {0, scale.y, 0}, {0, 0, scale.z}}
}

// Basis::from_euler: one rotation per axis, multiplied in the order's sequence. The engine takes
// the order as a 32-bit enum, so only the low 32 bits of `order` count; any other value fails its
// check and leaves the identity.
basis_from_euler :: proc "contextless" (euler: Vector3, order: i64) -> Basis {
	c, s := libc.cosf(euler.x), libc.sinf(euler.x)
	xm := Basis{{1, 0, 0}, {0, c, -s}, {0, s, c}}
	c, s = libc.cosf(euler.y), libc.sinf(euler.y)
	ym := Basis{{c, 0, s}, {0, 1, 0}, {-s, 0, c}}
	c, s = libc.cosf(euler.z), libc.sinf(euler.z)
	zm := Basis{{c, -s, 0}, {s, c, 0}, {0, 0, 1}}
	switch i32(order) {
	case 0: return b_mul(xm, b_mul(ym, zm))
	case 1: return b_mul(b_mul(xm, zm), ym)
	case 2: return b_mul(b_mul(ym, xm), zm)
	case 3: return b_mul(b_mul(ym, zm), xm)
	case 4: return b_mul(b_mul(zm, xm), ym)
	case 5: return b_mul(b_mul(zm, ym), xm)
	}
	math_error("Invalid Euler order parameter.")
	return B_IDENTITY
}

// Basis::get_euler, one proc per order. Each tests its sine entry against 1 - 0.00000025 to
// either side, so a NaN falls to the last case, as there. XYZ and YXZ take a shortcut on an exact
// rotation about their middle axis.
basis_get_euler :: proc "contextless" (self: ^Basis, order: i64) -> Vector3 {
	m := transmute(Basis_Rows)self^
	switch i32(order) {
	case 0: return b_euler_xyz(m)
	case 1: return b_euler_xzy(m)
	case 2: return b_euler_yxz(m)
	case 3: return b_euler_yzx(m)
	case 4: return b_euler_zxy(m)
	case 5: return b_euler_zyx(m)
	}
	math_error("Invalid parameter for get_euler(order)")
	return {}
}

@(private) b_euler_xyz :: #force_inline proc "contextless" (m: Basis_Rows) -> Vector3 {
	sy := m[0][2]
	if sy < B_EULER_LIMIT {
		if sy > -B_EULER_LIMIT {
			if m[1][0] == 0 && m[0][1] == 0 && m[1][2] == 0 && m[2][1] == 0 && m[1][1] == 1 {
				return {0, libc.atan2f(m[0][2], m[0][0]), 0}
			}
			return {libc.atan2f(-m[1][2], m[2][2]), libc.asinf(sy), libc.atan2f(-m[0][1], m[0][0])}
		}
		return {libc.atan2f(m[2][1], m[1][1]), -B_HALF_PI, 0}
	}
	return {libc.atan2f(m[2][1], m[1][1]), B_HALF_PI, 0}
}
@(private) b_euler_xzy :: #force_inline proc "contextless" (m: Basis_Rows) -> Vector3 {
	sz := m[0][1]
	if sz < B_EULER_LIMIT {
		if sz > -B_EULER_LIMIT {
			return {libc.atan2f(m[2][1], m[1][1]), libc.atan2f(m[0][2], m[0][0]), libc.asinf(-sz)}
		}
		return {-libc.atan2f(m[1][2], m[2][2]), 0, B_HALF_PI}
	}
	return {-libc.atan2f(m[1][2], m[2][2]), 0, -B_HALF_PI}
}
@(private) b_euler_yxz :: #force_inline proc "contextless" (m: Basis_Rows) -> Vector3 {
	m12 := m[1][2]
	if m12 < B_EULER_LIMIT {
		if m12 > -B_EULER_LIMIT {
			if m[1][0] == 0 && m[0][1] == 0 && m[0][2] == 0 && m[2][0] == 0 && m[0][0] == 1 {
				return {libc.atan2f(-m12, m[1][1]), 0, 0}
			}
			return {libc.asinf(-m12), libc.atan2f(m[0][2], m[2][2]), libc.atan2f(m[1][0], m[1][1])}
		}
		return {B_HALF_PI, libc.atan2f(m[0][1], m[0][0]), 0}
	}
	return {-B_HALF_PI, -libc.atan2f(m[0][1], m[0][0]), 0}
}
@(private) b_euler_yzx :: #force_inline proc "contextless" (m: Basis_Rows) -> Vector3 {
	sz := m[1][0]
	if sz < B_EULER_LIMIT {
		if sz > -B_EULER_LIMIT {
			return {libc.atan2f(-m[1][2], m[1][1]), libc.atan2f(-m[2][0], m[0][0]), libc.asinf(sz)}
		}
		return {libc.atan2f(m[2][1], m[2][2]), 0, -B_HALF_PI}
	}
	return {libc.atan2f(m[2][1], m[2][2]), 0, B_HALF_PI}
}
@(private) b_euler_zxy :: #force_inline proc "contextless" (m: Basis_Rows) -> Vector3 {
	sx := m[2][1]
	if sx < B_EULER_LIMIT {
		if sx > -B_EULER_LIMIT {
			return {libc.asinf(sx), libc.atan2f(-m[2][0], m[2][2]), libc.atan2f(-m[0][1], m[1][1])}
		}
		return {-B_HALF_PI, libc.atan2f(m[0][2], m[0][0]), 0}
	}
	return {B_HALF_PI, libc.atan2f(m[0][2], m[0][0]), 0}
}
@(private) b_euler_zyx :: #force_inline proc "contextless" (m: Basis_Rows) -> Vector3 {
	sy := m[2][0]
	if sy < B_EULER_LIMIT {
		if sy > -B_EULER_LIMIT {
			return {libc.atan2f(m[2][1], m[2][2]), libc.asinf(-sy), libc.atan2f(m[1][0], m[0][0])}
		}
		return {0, B_HALF_PI, -libc.atan2f(m[0][1], m[1][1])}
	}
	return {0, -B_HALF_PI, -libc.atan2f(m[0][1], m[1][1])}
}
