package godot

// Projection methods and constructors computed in place, under the names and signatures the
// bindings generated before. Each follows the engine's own code in core/math/projection.cpp and
// projection.h of Godot 4.7-stable: single-precision operations in the same order, the double
// steps where the engine's literals widen an expression to double, and the same libm calls (sinf,
// cosf, atan2f, tan, atan), so results match bit for bit. The errors the engine prints when it
// refuses a frustum or a singular matrix are printed here too, and the result is then left as the
// engine leaves it. tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin.

import "core:c/libc"
import "core:math"
import "core:simd"

// Math::deg_to_rad and Math::rad_to_deg: the float overloads scale by a factor folded from
// `(float)PI`, the double ones by one folded in double.
@(private) P_DEG_TO_RAD_F :: f32(math.PI) / 180
@(private) P_RAD_TO_DEG_F :: 180 / f32(math.PI)
@(private) P_DEG_TO_RAD_D :: f64(math.PI) / 180
@(private) P_RAD_TO_DEG_D :: 180 / f64(math.PI)

// The columns as the engine's `columns[i][j]`: column i, component j.
@(private) Proj_Cols :: [4][4]f32

@(private) PROJ_IDENTITY :: Proj_Cols{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}

@(private) proj_cols :: #force_inline proc "contextless" (p: Projection) -> Proj_Cols { return transmute(Proj_Cols)p }
@(private) proj_of :: #force_inline proc "contextless" (c: Proj_Cols) -> Projection { return transmute(Projection)c }

// Projection::operator*, each entry summed from zero in k order.
@(private) proj_mul :: proc "contextless" (a, b: Proj_Cols) -> (r: Proj_Cols) {
	#unroll for j in 0 ..< 4 {
		#unroll for i in 0 ..< 4 {
			ab := f32(0)
			#unroll for k in 0 ..< 4 { ab += a[k][i] * b[j][k] }
			r[j][i] = ab
		}
	}
	return
}

// Projection::get_fovy: the half angle and everything after it in double.
@(private) proj_fovy :: proc "contextless" (fovx, aspect: f32) -> f32 {
	return f32(libc.atan(f64(aspect) * libc.tan(f64(fovx * P_DEG_TO_RAD_F) * 0.5)) * 2.0 * P_RAD_TO_DEG_D)
}

// The flip_fov step the perspective setters share: `get_fovy(fovy, 1.0 / aspect)`, the reciprocal
// taken in double.
@(private) proj_flip_fovy :: #force_inline proc "contextless" (fovy, aspect: f32) -> f32 {
	return proj_fovy(fovy, f32(1.0 / f64(aspect)))
}

@(private) proj_z_far :: #force_inline proc "contextless" (c: Proj_Cols) -> f32 { return (c[3][3] - c[3][2]) / (c[2][3] - c[2][2]) }
@(private) proj_z_near :: #force_inline proc "contextless" (c: Proj_Cols) -> f32 { return (c[3][3] + c[3][2]) / (c[2][3] + c[2][2]) }

// Projection::set_frustum: refuses an empty or inverted box with an error, leaving `c` as it was.
@(private) proj_set_frustum :: proc "contextless" (c: ^Proj_Cols, left, right, bottom, top, near, far: f32) {
	if right <= left {
		math_error("Condition \"p_right <= p_left\" is true.")
		return
	}
	if top <= bottom {
		math_error("Condition \"p_top <= p_bottom\" is true.")
		return
	}
	if far <= near {
		math_error("Condition \"p_far <= p_near\" is true.")
		return
	}
	x := 2 * near / (right - left)
	y := 2 * near / (top - bottom)
	a := (right + left) / (right - left)
	b := (top + bottom) / (top - bottom)
	cz := -(far + near) / (far - near)
	d := -2 * far * near / (far - near)
	c^ = {{x, 0, 0, 0}, {0, y, 0, 0}, {a, b, cz, -1}, {0, 0, d, 0}}
}

// Projection::set_orthogonal on the identity it starts from.
@(private) proj_orthogonal :: proc "contextless" (left, right, bottom, top, znear, zfar: f32) -> Projection {
	c := PROJ_IDENTITY
	c[0][0] = f32(2.0 / f64(right - left))
	c[3][0] = -((right + left) / (right - left))
	c[1][1] = f32(2.0 / f64(top - bottom))
	c[3][1] = -((top + bottom) / (top - bottom))
	c[2][2] = f32(-2.0 / f64(zfar - znear))
	c[3][2] = -((zfar + znear) / (zfar - znear))
	c[3][3] = 1
	return proj_of(c)
}

projection_new :: proc "contextless" () -> (__r: Projection) { return proj_of(PROJ_IDENTITY) }
projection_new_from_projection :: proc "contextless" (from: Projection) -> (__r: Projection) { return from }

// Projection(const Transform3D &): the basis's columns over the origin, with a 0 0 0 1 bottom row.
projection_new_from_transform3d :: proc "contextless" (from: Transform3D) -> (__r: Projection) {
	b, o := from.basis, from.origin
	return {{b.x.x, b.y.x, b.z.x, 0}, {b.x.y, b.y.y, b.z.y, 0}, {b.x.z, b.y.z, b.z.z, 0}, {o.x, o.y, o.z, 1}}
}

projection_new_from_vector4_vector4_vector4_vector4 :: proc "contextless" (x_axis: Vector4, y_axis: Vector4, z_axis: Vector4, w_axis: Vector4) -> (__r: Projection) {
	return {x_axis, y_axis, z_axis, w_axis}
}

// Projection::set_depth_correction with its reverse_z and remap_z defaults on.
projection_create_depth_correction :: proc "contextless" (flip_y: bool) -> Projection {
	return {{1, 0, 0, 0}, {0, -1 if flip_y else 1, 0, 0}, {0, 0, -0.5, 0}, {0, 0, 0.5, 1}}
}

projection_create_light_atlas_rect :: proc "contextless" (rect: Rect2) -> Projection {
	return {{rect.size.x, 0, 0, 0}, {0, rect.size.y, 0, 0}, {0, 0, 1, 0}, {rect.position.x, rect.position.y, 0, 1}}
}

// Projection::set_perspective: the identity when the depth range, the half angle's sine or the
// aspect is zero.
projection_create_perspective :: proc "contextless" (fovy: f64, aspect: f64, z_near: f64, z_far: f64, flip_fov: bool) -> Projection {
	fov, a, n, f := f32(fovy), f32(aspect), f32(z_near), f32(z_far)
	if flip_fov { fov = proj_flip_fovy(fov, a) }
	radians := f32(f64(fov) / 2.0 * P_DEG_TO_RAD_D)
	delta_z := f - n
	sine, cosine := m_sincos(radians)
	c := PROJ_IDENTITY
	if delta_z == 0 || sine == 0 || a == 0 { return proj_of(c) }
	cotangent := cosine / sine
	c[0][0] = cotangent / a
	c[1][1] = cotangent
	c[2][2] = -(f + n) / delta_z
	c[2][3] = -1
	c[3][2] = -2 * n * f / delta_z
	c[3][3] = 0
	return proj_of(c)
}

// The eye-shifted Projection::set_perspective: a frustum shifted by the eye, times a translation
// by half the intraocular distance. Eye 1 is the left, 2 the right, any other mono.
projection_create_perspective_hmd :: proc "contextless" (fovy: f64, aspect: f64, z_near: f64, z_far: f64, flip_fov: bool, eye: i64, intraocular_dist: f64, convergence_dist: f64) -> Projection {
	fov, a, n, f := f32(fovy), f32(aspect), f32(z_near), f32(z_far)
	iod, conv := f32(intraocular_dist), f32(convergence_dist)
	if flip_fov { fov = proj_flip_fovy(fov, a) }
	ymax := f32(f64(n) * libc.tan(f64(fov) / 2.0 * P_DEG_TO_RAD_D))
	xmax := ymax * a
	shift := f32(f64(iod) / 2.0 * f64(n) / f64(conv))
	left, right, translation: f32
	switch i32(eye) {
	case 1:
		left, right, translation = -xmax + shift, xmax + shift, f32(f64(iod) / 2.0)
	case 2:
		left, right, translation = -xmax - shift, xmax - shift, f32(f64(-iod) / 2.0)
	case:
		left, right, translation = -xmax, xmax, 0
	}
	c := PROJ_IDENTITY
	proj_set_frustum(&c, left, right, -ymax, ymax, n, f)
	cm := PROJ_IDENTITY
	cm[3][0] = translation
	return proj_of(proj_mul(c, cm))
}

// Projection::set_for_hmd: the identity for any eye but 1 (left) and 2 (right).
projection_create_for_hmd :: proc "contextless" (eye: i64, aspect: f64, intraocular_dist: f64, display_width: f64, display_to_lens: f64, oversample: f64, z_near: f64, z_far: f64) -> Projection {
	a, iod, width, to_lens := f32(aspect), f32(intraocular_dist), f32(display_width), f32(display_to_lens)
	over, n, f := f32(oversample), f32(z_near), f32(z_far)
	f1 := f32(f64(iod) * 0.5 / f64(to_lens))
	f2 := f32(f64(width - iod) * 0.5 / f64(to_lens))
	f3 := f32(f64(width) / 4.0 / f64(to_lens))
	add := f32(f64(f1 + f2) * (f64(over) - 1.0) / 2.0)
	f1 += add
	f2 += add
	f3 *= over
	f3 /= a
	c := PROJ_IDENTITY
	switch i32(eye) {
	case 1: proj_set_frustum(&c, -f2 * n, f1 * n, -f3 * n, f3 * n, n, f)
	case 2: proj_set_frustum(&c, -f1 * n, f2 * n, -f3 * n, f3 * n, n, f)
	}
	return proj_of(c)
}

projection_create_orthogonal :: proc "contextless" (left: f64, right: f64, bottom: f64, top: f64, z_near: f64, z_far: f64) -> Projection {
	return proj_orthogonal(f32(left), f32(right), f32(bottom), f32(top), f32(z_near), f32(z_far))
}

projection_create_orthogonal_aspect :: proc "contextless" (size: f64, aspect: f64, z_near: f64, z_far: f64, flip_fov: bool) -> Projection {
	s, a := f32(size), f32(aspect)
	if !flip_fov { s *= a }
	return proj_orthogonal(-s / 2, +s / 2, -s / a / 2, +s / a / 2, f32(z_near), f32(z_far))
}

projection_create_frustum :: proc "contextless" (left: f64, right: f64, bottom: f64, top: f64, z_near: f64, z_far: f64) -> Projection {
	c := PROJ_IDENTITY
	proj_set_frustum(&c, f32(left), f32(right), f32(bottom), f32(top), f32(z_near), f32(z_far))
	return proj_of(c)
}

projection_create_frustum_aspect :: proc "contextless" (size: f64, aspect: f64, offset: Vector2, z_near: f64, z_far: f64, flip_fov: bool) -> Projection {
	s, a := f32(size), f32(aspect)
	if !flip_fov { s *= a }
	c := PROJ_IDENTITY
	proj_set_frustum(&c, -s / 2 + offset.x, +s / 2 + offset.x, -s / a / 2 + offset.y, +s / a / 2 + offset.y, f32(z_near), f32(z_far))
	return proj_of(c)
}

// Projection::scale_translate_to_fit: maps the box onto the -1 to 1 cube.
projection_create_fit_aabb :: proc "contextless" (aabb: AABB) -> Projection {
	lo := aabb.position
	hi := aabb.position + aabb.size
	c: Proj_Cols
	#unroll for i in 0 ..< 3 {
		c[i][i] = 2 / (hi[i] - lo[i])
		c[3][i] = -(hi[i] + lo[i]) / (hi[i] - lo[i])
	}
	c[3][3] = 1
	return proj_of(c)
}

projection_determinant :: proc "contextless" (self: ^Projection) -> f64 {
	c := proj_cols(self^)
	return f64(det_expr(c))
}

@(private) det_expr :: #force_inline proc "contextless" (c: Proj_Cols) -> f32 {
	return c[0][3] * c[1][2] * c[2][1] * c[3][0] - c[0][2] * c[1][3] * c[2][1] * c[3][0] -
		c[0][3] * c[1][1] * c[2][2] * c[3][0] + c[0][1] * c[1][3] * c[2][2] * c[3][0] +
		c[0][2] * c[1][1] * c[2][3] * c[3][0] - c[0][1] * c[1][2] * c[2][3] * c[3][0] -
		c[0][3] * c[1][2] * c[2][0] * c[3][1] + c[0][2] * c[1][3] * c[2][0] * c[3][1] +
		c[0][3] * c[1][0] * c[2][2] * c[3][1] - c[0][0] * c[1][3] * c[2][2] * c[3][1] -
		c[0][2] * c[1][0] * c[2][3] * c[3][1] + c[0][0] * c[1][2] * c[2][3] * c[3][1] +
		c[0][3] * c[1][1] * c[2][0] * c[3][2] - c[0][1] * c[1][3] * c[2][0] * c[3][2] -
		c[0][3] * c[1][0] * c[2][1] * c[3][2] + c[0][0] * c[1][3] * c[2][1] * c[3][2] +
		c[0][1] * c[1][0] * c[2][3] * c[3][2] - c[0][0] * c[1][1] * c[2][3] * c[3][2] -
		c[0][2] * c[1][1] * c[2][0] * c[3][3] + c[0][1] * c[1][2] * c[2][0] * c[3][3] +
		c[0][2] * c[1][0] * c[2][1] * c[3][3] - c[0][0] * c[1][2] * c[2][1] * c[3][3] -
		c[0][1] * c[1][0] * c[2][2] * c[3][3] + c[0][0] * c[1][1] * c[2][2] * c[3][3]
}

// Projection::adjust_perspective_znear on a copy.
projection_perspective_znear_adjusted :: proc "contextless" (self: ^Projection, new_znear: f64) -> Projection {
	c := proj_cols(self^)
	zfar := proj_z_far(c)
	znear := f32(new_znear)
	delta_z := zfar - znear
	c[2][2] = -(zfar + znear) / delta_z
	c[3][2] = -2 * znear * zfar / delta_z
	return proj_of(c)
}

// Projection::get_projection_plane: each plane is the w row plus or minus the x, y or z row, its
// normal negated and normalized. The zero plane for an index outside the Planes enum, whose value
// the engine takes as a C int.
projection_get_projection_plane :: proc "contextless" (self: ^Projection, plane: i64) -> Plane {
	c := proj_cols(self^)
	switch Projection_Planes(i32(plane)) {
	case .PLANE_NEAR: return proj_side_plane(c, 2, true)
	case .PLANE_FAR: return proj_side_plane(c, 2, false)
	case .PLANE_LEFT: return proj_side_plane(c, 0, true)
	case .PLANE_TOP: return proj_side_plane(c, 1, false)
	case .PLANE_RIGHT: return proj_side_plane(c, 0, false)
	case .PLANE_BOTTOM: return proj_side_plane(c, 1, true)
	}
	return {}
}

@(private) proj_side_plane :: #force_inline proc "contextless" (c: Proj_Cols, row: int, add: bool) -> Plane {
	n: Vector3
	d: f32
	if add {
		n = {c[0][3] + c[0][row], c[1][3] + c[1][row], c[2][3] + c[2][row]}
		d = c[3][3] + c[3][row]
	} else {
		n = {c[0][3] - c[0][row], c[1][3] - c[1][row], c[2][3] - c[2][row]}
		d = c[3][3] - c[3][row]
	}
	p := Plane{-n, d}
	return plane_normalized(&p)
}

projection_flipped_y :: proc "contextless" (self: ^Projection) -> Projection {
	p := self^
	p.y = -p.y
	return p
}

projection_jitter_offseted :: proc "contextless" (self: ^Projection, offset: Vector2) -> Projection {
	p := self^
	p.w.x += offset.x
	p.w.y += offset.y
	return p
}

projection_get_fovy :: proc "contextless" (fovx: f64, aspect: f64) -> f64 { return f64(proj_fovy(f32(fovx), f32(aspect))) }
projection_get_z_far :: proc "contextless" (self: ^Projection) -> f64 { return f64(proj_z_far(proj_cols(self^))) }
projection_get_z_near :: proc "contextless" (self: ^Projection) -> f64 { return f64(proj_z_near(proj_cols(self^))) }
projection_get_aspect :: proc "contextless" (self: ^Projection) -> f64 { return f64(self.y.y / self.x.x) }

// Projection::get_fov: an asymmetric frustum's left and right angles are taken separately.
projection_get_fov :: proc "contextless" (self: ^Projection) -> f64 {
	skew, xx := self.z.x, self.x.x
	if skew == 0 { return f64(2 * libc.atan2f(1, xx) * P_RAD_TO_DEG_F) }
	right := libc.atan2f(skew + 1, xx)
	left := libc.atan2f(skew - 1, xx)
	return f64((right - left) * P_RAD_TO_DEG_F)
}

projection_is_orthogonal :: proc "contextless" (self: ^Projection) -> bool { return self.z.w == 0 }

projection_get_viewport_half_extents :: proc "contextless" (self: ^Projection) -> Vector2 {
	c := proj_cols(self^)
	w := -proj_z_near(c) * c[2][3] + c[3][3]
	return {w / c[0][0], w / c[1][1]}
}

projection_get_far_plane_half_extents :: proc "contextless" (self: ^Projection) -> Vector2 {
	c := proj_cols(self^)
	w := -proj_z_far(c) * c[2][3] + c[3][3]
	return {w / c[0][0], w / c[1][1]}
}

// The width in pixels over the projection plane's width, truncated to a C int as the engine's
// conversion does; the pixel width is a C int too.
projection_get_pixels_per_meter :: proc "contextless" (self: ^Projection, for_pixel_width: i64) -> i64 {
	c := proj_cols(self^)
	width := 2 * (-proj_z_near(c) * c[2][3] + c[3][3]) / c[0][0]
	return i64(f32_to_i32(f32(i32(for_pixel_width)) / width))
}

projection_get_lod_multiplier :: proc "contextless" (self: ^Projection) -> f64 { return f64(2 / self.x.x) }

// Projection::invert: Gauss-Jordan elimination on the rows beside the identity, with partial
// pivoting by row swaps, adapted from Mesa. A zero pivot prints an error and leaves the matrix as
// it was. Each row is held as two four-lane values, its matrix half and its identity half, and
// swapped by value rather than through pointers, so the rows stay in registers. Every lane the
// engine computes is computed with the same operations in the same order; the extra lanes a
// whole-row step also computes are never read. The identity half skips a step where the engine
// skips it, on a zero entry.
projection_inverse :: proc "contextless" (self: ^Projection) -> Projection {
	m := proj_cols(self^)
	l0 := P_Lanes{m[0][0], m[1][0], m[2][0], m[3][0]}
	l1 := P_Lanes{m[0][1], m[1][1], m[2][1], m[3][1]}
	l2 := P_Lanes{m[0][2], m[1][2], m[2][2], m[3][2]}
	l3 := P_Lanes{m[0][3], m[1][3], m[2][3], m[3][3]}
	i0, i1, i2, i3 := P_Lanes{1, 0, 0, 0}, P_Lanes{0, 1, 0, 0}, P_Lanes{0, 0, 1, 0}, P_Lanes{0, 0, 0, 1}
	if abs(lane(l3, 0)) > abs(lane(l2, 0)) { l3, l2, i3, i2 = l2, l3, i2, i3 }
	if abs(lane(l2, 0)) > abs(lane(l1, 0)) { l2, l1, i2, i1 = l1, l2, i1, i2 }
	if abs(lane(l1, 0)) > abs(lane(l0, 0)) { l1, l0, i1, i0 = l0, l1, i0, i1 }
	if 0.0 == lane(l0, 0) {
		math_error("Condition \"0.0 == r0[0]\" is true.")
		return self^
	}
	m1 := lane(l1, 0) / lane(l0, 0)
	m2 := lane(l2, 0) / lane(l0, 0)
	m3 := lane(l3, 0) / lane(l0, 0)
	l1 -= m1 * l0
	l2 -= m2 * l0
	l3 -= m3 * l0
	i1, i2, i3 = lanes_sub_unless_zero(i1, m1, i0), lanes_sub_unless_zero(i2, m2, i0), lanes_sub_unless_zero(i3, m3, i0)
	if abs(lane(l3, 1)) > abs(lane(l2, 1)) { l3, l2, i3, i2 = l2, l3, i2, i3 }
	if abs(lane(l2, 1)) > abs(lane(l1, 1)) { l2, l1, i2, i1 = l1, l2, i1, i2 }
	if 0.0 == lane(l1, 1) {
		math_error("Condition \"0.0 == r1[1]\" is true.")
		return self^
	}
	m2 = lane(l2, 1) / lane(l1, 1)
	m3 = lane(l3, 1) / lane(l1, 1)
	l2 -= m2 * l1
	l3 -= m3 * l1
	i2, i3 = lanes_sub_unless_zero(i2, m2, i1), lanes_sub_unless_zero(i3, m3, i1)
	if abs(lane(l3, 2)) > abs(lane(l2, 2)) { l3, l2, i3, i2 = l2, l3, i2, i3 }
	if 0.0 == lane(l2, 2) {
		math_error("Condition \"0.0 == r2[2]\" is true.")
		return self^
	}
	m3 = lane(l3, 2) / lane(l2, 2)
	l3 -= m3 * l2
	i3 -= m3 * i2
	if 0.0 == lane(l3, 3) {
		math_error("Condition \"0.0 == r3[3]\" is true.")
		return self^
	}
	i3 *= 1.0 / lane(l3, 3)
	i2 = (1.0 / lane(l2, 2)) * (i2 - i3 * lane(l2, 3))
	i1 -= i3 * lane(l1, 3)
	i0 -= i3 * lane(l0, 3)
	i1 = (1.0 / lane(l1, 1)) * (i1 - i2 * lane(l1, 2))
	i0 -= i2 * lane(l0, 2)
	i0 = (1.0 / lane(l0, 0)) * (i0 - i1 * lane(l0, 1))
	// The identity halves are the inverse's rows; the result holds its columns.
	r0, r1, r2, r3 := lanes_array(i0), lanes_array(i1), lanes_array(i2), lanes_array(i3)
	return {{r0[0], r1[0], r2[0], r3[0]}, {r0[1], r1[1], r2[1], r3[1]}, {r0[2], r1[2], r2[2], r3[2]}, {r0[3], r1[3], r2[3], r3[3]}}
}

@(private) P_Lanes :: #simd[4]f32

@(private) lane :: #force_inline proc "contextless" (v: P_Lanes, $i: int) -> f32 { return simd.extract(v, i) }
@(private) lanes_array :: #force_inline proc "contextless" (v: P_Lanes) -> [4]f32 { return transmute([4]f32)v }

// `r[k] -= m * s[k]` on each lane whose `s[k]` is not zero, as the engine's identity-half steps do.
@(private) lanes_sub_unless_zero :: #force_inline proc "contextless" (r: P_Lanes, m: f32, s: P_Lanes) -> P_Lanes {
	return simd.select(simd.lanes_eq(s, 0), r, r - m * s)
}
