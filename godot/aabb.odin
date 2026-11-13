package godot

// AABB methods and constructors computed in place, under the names and signatures the bindings
// generated before. Each follows the engine's own code in core/math/aabb.cpp and aabb.h of Godot
// 4.7-stable: single-precision operations in the same order and the same single-precision
// comparisons, so results match bit for bit, NaN included. The errors the engine prints under
// MATH_CHECKS (on in editor and debug builds) for a negative size are printed here too. The
// segment and ray tests return a Variant holding the Vector3 found, or a nil Variant when there is
// none, as the engine's binds do. tools/odin_bindgen.py leaves these names out of
// godot/gen_builtins.odin.

@(private) AABB_NEGATIVE :: "AABB size is negative, this is not supported. Use AABB.abs() to get an AABB with a positive size."

// The error get_endpoint's ERR_FAIL_V prints for an index outside 0 to 7.
@(private) AABB_BAD_ENDPOINT :: "Method/function failed. Returning: Vector3()"

@(private) aabb_check_size :: #force_inline proc "contextless" (s: Vector3) {
	if s.x < 0 || s.y < 0 || s.z < 0 { math_error(AABB_NEGATIVE) }
}

// The two-box methods check both sizes and print once.
@(private) aabb_check_sizes :: #force_inline proc "contextless" (s, t: Vector3) {
	if s.x < 0 || s.y < 0 || s.z < 0 || t.x < 0 || t.y < 0 || t.z < 0 { math_error(AABB_NEGATIVE) }
}

// Corner `i` in the engine's order: bit 2 adds size.x, bit 1 size.y, bit 0 size.z.
@(private) aabb_corner :: #force_inline proc "contextless" (a: AABB, i: int) -> Vector3 {
	p := a.position
	if i & 4 != 0 { p.x += a.size.x }
	if i & 2 != 0 { p.y += a.size.y }
	if i & 1 != 0 { p.z += a.size.z }
	return p
}

// The longest and shortest axes: strict comparisons from x on, so the first of equal sizes wins.
@(private) aabb_longest :: #force_inline proc "contextless" (s: Vector3) -> (axis: int) {
	if s.y > s[axis] { axis = 1 }
	if s.z > s[axis] { axis = 2 }
	return
}

@(private) aabb_shortest :: #force_inline proc "contextless" (s: Vector3) -> (axis: int) {
	if s.y < s[axis] { axis = 1 }
	if s.z < s[axis] { axis = 2 }
	return
}

@(private) aabb_unit :: #force_inline proc "contextless" (axis: int) -> (v: Vector3) {
	v[axis] = 1
	return
}

aabb_new :: proc "contextless" () -> (__r: AABB) { return }
aabb_new_from_aabb :: proc "contextless" (from: AABB) -> (__r: AABB) { return from }
aabb_new_from_vector3_vector3 :: proc "contextless" (position: Vector3, size: Vector3) -> (__r: AABB) { return {position, size} }

aabb_abs :: proc "contextless" (self: ^AABB) -> AABB {
	return {self.position + v_minf(self.size, 0), v_map(self.size, m_abs)}
}
aabb_get_center :: proc "contextless" (self: ^AABB) -> Vector3 { return self.position + self.size * 0.5 }
aabb_get_volume :: proc "contextless" (self: ^AABB) -> f64 { s := self.size; return f64(s.x * s.y * s.z) }
aabb_has_volume :: proc "contextless" (self: ^AABB) -> bool { s := self.size; return s.x > 0 && s.y > 0 && s.z > 0 }
aabb_has_surface :: proc "contextless" (self: ^AABB) -> bool { s := self.size; return s.x > 0 || s.y > 0 || s.z > 0 }

aabb_has_point :: proc "contextless" (self: ^AABB, point: Vector3) -> bool {
	a := self^
	aabb_check_size(a.size)
	end := a.position + a.size
	return !(point.x < a.position.x || point.y < a.position.y || point.z < a.position.z || point.x > end.x || point.y > end.y || point.z > end.z)
}

aabb_is_equal_approx :: proc "contextless" (self: ^AABB, aabb: AABB) -> bool {
	p, s := self.position, self.size
	return m_is_equal_approx(p.x, aabb.position.x) && m_is_equal_approx(p.y, aabb.position.y) && m_is_equal_approx(p.z, aabb.position.z) &&
		m_is_equal_approx(s.x, aabb.size.x) && m_is_equal_approx(s.y, aabb.size.y) && m_is_equal_approx(s.z, aabb.size.z)
}
aabb_is_finite :: proc "contextless" (self: ^AABB) -> bool { return v_is_finite(self.position) && v_is_finite(self.size) }

aabb_intersects :: proc "contextless" (self: ^AABB, with: AABB) -> bool {
	a := self^
	aabb_check_sizes(a.size, with.size)
	a_end, w_end := a.position + a.size, with.position + with.size
	#unroll for i in 0 ..< 3 {
		if a.position[i] >= w_end[i] || a_end[i] <= with.position[i] { return false }
	}
	return true
}

aabb_encloses :: proc "contextless" (self: ^AABB, with: AABB) -> bool {
	a := self^
	aabb_check_sizes(a.size, with.size)
	a_end, w_end := a.position + a.size, with.position + with.size
	return a.position.x <= with.position.x && a_end.x >= w_end.x && a.position.y <= with.position.y && a_end.y >= w_end.y &&
		a.position.z <= with.position.z && a_end.z >= w_end.z
}

// AABB::intersects_plane: true when some corner lies over the plane and some does not.
aabb_intersects_plane :: proc "contextless" (self: ^AABB, plane: Plane) -> bool {
	a := self^
	over, under: bool
	#unroll for i in 0 ..< 8 {
		if plane_distance(plane, aabb_corner(a, i)) > 0 { over = true } else { under = true }
	}
	return under && over
}

// AABB::intersection: the zero box when the two are apart on any axis.
aabb_intersection :: proc "contextless" (self: ^AABB, with: AABB) -> AABB {
	a := self^
	aabb_check_sizes(a.size, with.size)
	a_end, w_end := a.position + a.size, with.position + with.size
	lo, hi: Vector3
	#unroll for i in 0 ..< 3 {
		if a.position[i] > w_end[i] || a_end[i] < with.position[i] { return {} }
		lo[i] = m_max(a.position[i], with.position[i])
		hi[i] = m_min(a_end[i], w_end[i])
	}
	return {lo, hi - lo}
}

aabb_merge :: proc "contextless" (self: ^AABB, with: AABB) -> AABB {
	a := self^
	aabb_check_sizes(a.size, with.size)
	lo := v_map2(a.position, with.position, m_min)
	hi := v_map2(a.size + a.position, with.size + with.position, m_max)
	return {lo, hi - lo}
}

aabb_expand :: proc "contextless" (self: ^AABB, to_point: Vector3) -> AABB {
	a := self^
	aabb_check_size(a.size)
	lo := v_map2(to_point, a.position, m_min)
	hi := v_map2(to_point, a.position + a.size, m_max)
	return {lo, hi - lo}
}

aabb_grow :: proc "contextless" (self: ^AABB, by: f64) -> AABB {
	amount := f32(by)
	return {self.position - amount, self.size + 2 * amount}
}

aabb_get_support :: proc "contextless" (self: ^AABB, direction: Vector3) -> Vector3 {
	p := self.position
	#unroll for i in 0 ..< 3 {
		if direction[i] > 0 { p[i] += self.size[i] }
	}
	return p
}

aabb_get_longest_axis :: proc "contextless" (self: ^AABB) -> Vector3 { return aabb_unit(aabb_longest(self.size)) }
aabb_get_longest_axis_index :: proc "contextless" (self: ^AABB) -> i64 { return i64(aabb_longest(self.size)) }
aabb_get_longest_axis_size :: proc "contextless" (self: ^AABB) -> f64 { return f64(self.size[aabb_longest(self.size)]) }
aabb_get_shortest_axis :: proc "contextless" (self: ^AABB) -> Vector3 { return aabb_unit(aabb_shortest(self.size)) }
aabb_get_shortest_axis_index :: proc "contextless" (self: ^AABB) -> i64 { return i64(aabb_shortest(self.size)) }
aabb_get_shortest_axis_size :: proc "contextless" (self: ^AABB) -> f64 { return f64(self.size[aabb_shortest(self.size)]) }

// The engine takes the index as a C int, so only its low 32 bits count.
aabb_get_endpoint :: proc "contextless" (self: ^AABB, idx: i64) -> Vector3 {
	i := i32(idx)
	if i < 0 || i > 7 {
		math_error(AABB_BAD_ENDPOINT)
		return {}
	}
	return aabb_corner(self^, int(i))
}

// AABB::intersects_segment: clips the segment's 0 to 1 range against each axis's slab in turn.
aabb_intersects_segment :: proc "contextless" (self: ^AABB, from: Vector3, to: Vector3) -> Variant {
	a := self^
	aabb_check_size(a.size)
	lo, hi := f32(0), f32(1)
	#unroll for i in 0 ..< 3 {
		f, t := from[i], to[i]
		begin := a.position[i]
		end := begin + a.size[i]
		cmin, cmax: f32
		if f < t {
			if f > end || t < begin { return {} }
			length := t - f
			cmin = (begin - f) / length if f < begin else 0
			cmax = (end - f) / length if t > end else 1
		} else {
			if t > end || f < begin { return {} }
			length := t - f
			cmin = (end - f) / length if f > end else 0
			cmax = (begin - f) / length if t < begin else 1
		}
		if cmin > lo { lo = cmin }
		if cmax < hi { hi = cmax }
		if hi < lo { return {} }
	}
	return vector3_hit(true, from + (to - from) * lo)
}

// AABB::find_intersects_ray through intersects_ray_bind: the ray's origin when it starts inside,
// else the entry point, set exactly onto the face it crosses.
aabb_intersects_ray :: proc "contextless" (self: ^AABB, from: Vector3, dir: Vector3) -> Variant {
	a := self^
	aabb_check_size(a.size)
	end := a.position + a.size
	tmin, tmax := f32(-1e20), f32(1e20)
	axis := 0
	#unroll for i in 0 ..< 3 {
		if dir[i] == 0 {
			if from[i] < a.position[i] || from[i] > end[i] { return {} }
		} else {
			t1 := (a.position[i] - from[i]) / dir[i]
			t2 := (end[i] - from[i]) / dir[i]
			if t1 > t2 { t1, t2 = t2, t1 }
			if t1 >= tmin {
				tmin = t1
				axis = i
			}
			if t2 < tmax {
				if t2 < 0 { return {} }
				tmax = t2
			}
			if tmin > tmax { return {} }
		}
	}
	if tmin < 0 { return vector3_hit(true, from) }
	p := from + dir * tmin
	p[axis] = a.position[axis] if dir[axis] >= 0 else end[axis]
	return vector3_hit(true, p)
}
