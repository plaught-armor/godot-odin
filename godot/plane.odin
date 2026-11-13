package godot

// Plane methods and constructors computed in place, under the names and signatures the bindings
// generated before. Each follows the engine's own code in core/math/plane.cpp and plane.h of Godot
// 4.7-stable: single-precision operations in the same order and the same single-precision
// comparisons, so results match bit for bit. The warnings the engine prints under MATH_CHECKS (on
// in editor and debug builds) are printed here too. The three intersection methods return a
// Variant holding the Vector3 found, or a nil Variant when there is none, as the engine's binds
// do. tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin.

import gde "../gdextension"

@(private) PLANE_NOT_FINITE :: "Plane cannot be normalized, the distance and the normal should be finite."

// `1.0f + (real_t)CMP_EPSILON`, the segment test's upper bound, folded in single precision.
@(private) PLANE_SEGMENT_END :: f32(1.00001)

@(private) plane_is_finite_of :: #force_inline proc "contextless" (p: Plane) -> bool {
	return v_is_finite(p.normal) && m_is_finite(p.d)
}

@(private) plane_distance :: #force_inline proc "contextless" (p: Plane, point: Vector3) -> f32 {
	return v_dot(p.normal, point) - p.d
}

// The Variant the engine's binds return: a Vector3 when `found`, else nil. A Vector3 needs no
// construction, so it is written in place in the layout `check_borrow_layout` proves: the type
// tag in the first 4 bytes, the value at byte 8, the rest zero. A zeroed Variant is nil.
@(private) plane_hit :: #force_inline proc "contextless" (found: bool, v: Vector3) -> (out: Variant) {
	if found {
		(^u32)(&out._opaque[0])^ = u32(gde.VariantType.VECTOR3)
		(^Vector3)(&out._opaque[8])^ = v
	}
	return
}

plane_new :: proc "contextless" () -> (__r: Plane) { return }
plane_new_from_plane :: proc "contextless" (from: Plane) -> (__r: Plane) { return from }
plane_new_from_vector3 :: proc "contextless" (normal: Vector3) -> (__r: Plane) { return {normal, 0} }
plane_new_from_vector3_float :: proc "contextless" (normal: Vector3, d: f64) -> (__r: Plane) { return {normal, f32(d)} }
plane_new_from_vector3_vector3 :: proc "contextless" (normal: Vector3, point: Vector3) -> (__r: Plane) {
	return {normal, v_dot(normal, point)}
}

// The clockwise three-point constructor: its normal goes through Vector3::normalize, which warns
// and gives zero for a non-finite vector.
plane_new_from_vector3_vector3_vector3 :: proc "contextless" (point1: Vector3, point2: Vector3, point3: Vector3) -> (__r: Plane) {
	n := v_normalized(v3_cross(point1 - point3, point1 - point2), V3_NOT_FINITE)
	return {n, v_dot(n, point1)}
}

plane_new_from_float_float_float_float :: proc "contextless" (a: f64, b: f64, c: f64, d: f64) -> (__r: Plane) {
	return {{f32(a), f32(b), f32(c)}, f32(d)}
}

// Plane::normalize: it warns on a non-finite plane but goes on, divides by the normal's length
// rather than multiplying by its reciprocal, and gives the zero plane for a zero normal.
plane_normalized :: proc "contextless" (self: ^Plane) -> Plane {
	p := self^
	if !plane_is_finite_of(p) { gde.print_warning(PLANE_NOT_FINITE, "", #file, #line, 1) }
	l := m_sqrt(v_dot(p.normal, p.normal))
	if l == 0 { return {} }
	return {p.normal / l, p.d / l}
}

plane_get_center :: proc "contextless" (self: ^Plane) -> Vector3 { return self.normal * self.d }
plane_is_equal_approx :: proc "contextless" (self: ^Plane, to_plane: Plane) -> bool {
	n, m := self.normal, to_plane.normal
	return m_is_equal_approx(n.x, m.x) && m_is_equal_approx(n.y, m.y) && m_is_equal_approx(n.z, m.z) && m_is_equal_approx(self.d, to_plane.d)
}
plane_is_finite :: proc "contextless" (self: ^Plane) -> bool { return plane_is_finite_of(self^) }
plane_is_point_over :: proc "contextless" (self: ^Plane, point: Vector3) -> bool { return v_dot(self.normal, point) > self.d }
plane_distance_to :: proc "contextless" (self: ^Plane, point: Vector3) -> f64 { return f64(plane_distance(self^, point)) }
plane_has_point :: proc "contextless" (self: ^Plane, point: Vector3, tolerance: f64) -> bool {
	return m_abs(plane_distance(self^, point)) <= f32(tolerance)
}
plane_project :: proc "contextless" (self: ^Plane, point: Vector3) -> Vector3 {
	return point - self.normal * plane_distance(self^, point)
}

// Plane::intersect_3: the point the three planes share, none when their normals' triple product is
// zero to within CMP_EPSILON.
plane_intersect_3 :: proc "contextless" (self: ^Plane, b: Plane, c: Plane) -> Variant {
	n0, n1, n2 := self.normal, b.normal, c.normal
	n01 := v3_cross(n0, n1)
	denom := v_dot(n01, n2)
	if m_is_zero_approx(denom) { return {} }
	return plane_hit(true, (v3_cross(n1, n2) * self.d + v3_cross(n2, n0) * b.d + n01 * c.d) / denom)
}

// Plane::intersects_ray: none when the ray runs parallel to the plane or starts more than
// CMP_EPSILON past it.
plane_intersects_ray :: proc "contextless" (self: ^Plane, from: Vector3, dir: Vector3) -> Variant {
	den := v_dot(self.normal, dir)
	if m_is_zero_approx(den) { return {} }
	dist := plane_distance(self^, from) / den
	return plane_hit(!(dist > CMP_EPSILON), from + dir * -dist)
}

// Plane::intersects_segment, with `begin - end` as the segment: none when it runs parallel to the
// plane or the crossing lies outside it by more than CMP_EPSILON.
plane_intersects_segment :: proc "contextless" (self: ^Plane, from: Vector3, to: Vector3) -> Variant {
	segment := from - to
	den := v_dot(self.normal, segment)
	if m_is_zero_approx(den) { return {} }
	dist := plane_distance(self^, from) / den
	return plane_hit(!(dist < -CMP_EPSILON || dist > PLANE_SEGMENT_END), from + segment * -dist)
}
