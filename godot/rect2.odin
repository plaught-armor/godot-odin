package godot

// Rect2 and Rect2i methods and constructors computed in place, under the names and signatures the
// bindings generated before. Each follows the engine's own code in core/math/rect2.h, rect2.cpp,
// rect2i.h and rect2i.cpp of Godot 4.7-stable: single-precision operations in the same order and
// the same comparisons, so Rect2 results match bit for bit, NaN included, and Rect2i results wrap
// on 32-bit overflow as the engine's int arithmetic does on x86-64. The errors the engine prints
// under MATH_CHECKS (on in editor and debug builds) for a negative size are printed here too.
// Integer arguments arrive as 64-bit values and keep only their low 32 bits, as the engine's
// int and uint32_t parameters do. tools/odin_bindgen.py leaves these names out of
// godot/gen_builtins.odin.

@(private) RECT2_NEGATIVE :: "Rect2 size is negative, this is not supported. Use Rect2.abs() to get a Rect2 with a positive size."
@(private) RECT2I_NEGATIVE :: "Rect2i size is negative, this is not supported. Use Rect2i.abs() to get a Rect2i with a positive size."

@(private) rect2_check_size :: #force_inline proc "contextless" (s: Vector2) {
	if s.x < 0 || s.y < 0 { math_error(RECT2_NEGATIVE) }
}

// The two-rect methods check both sizes and print once.
@(private) rect2_check_sizes :: #force_inline proc "contextless" (s, t: Vector2) {
	if s.x < 0 || s.y < 0 || t.x < 0 || t.y < 0 { math_error(RECT2_NEGATIVE) }
}

@(private) rect2i_check_size :: #force_inline proc "contextless" (s: Vector2i) {
	if s.x < 0 || s.y < 0 { math_error(RECT2I_NEGATIVE) }
}

@(private) rect2i_check_sizes :: #force_inline proc "contextless" (s, t: Vector2i) {
	if s.x < 0 || s.y < 0 || t.x < 0 || t.y < 0 { math_error(RECT2I_NEGATIVE) }
}

// A float to int32 conversion as x86-64's cvttss2si does it: toward zero, and INT32_MIN for NaN or
// a value outside the int32 range, where Odin's own conversion is undefined.
@(private) f32_to_i32 :: #force_inline proc "contextless" (x: f32) -> i32 {
	if !(x >= -2147483648 && x < 2147483648) { return min(i32) }
	return i32(x)
}

@(private) rect2_grow_by :: #force_inline proc "contextless" (r: Rect2, left, top, right, bottom: f32) -> Rect2 {
	return {{r.position.x - left, r.position.y - top}, {r.size.x + (left + right), r.size.y + (top + bottom)}}
}

@(private) rect2i_grow_by :: #force_inline proc "contextless" (r: Rect2i, left, top, right, bottom: i32) -> Rect2i {
	return {{r.position.x - left, r.position.y - top}, {r.size.x + (left + right), r.size.y + (top + bottom)}}
}

// Rect2::intersects: without borders, rects that only touch do not intersect.
@(private) rect2_intersects_of :: #force_inline proc "contextless" (a, b: Rect2, include_borders: bool) -> bool {
	rect2_check_sizes(a.size, b.size)
	a_end, b_end := a.position + a.size, b.position + b.size
	if include_borders {
		return !(a.position.x > b_end.x || a_end.x < b.position.x || a.position.y > b_end.y || a_end.y < b.position.y)
	}
	return !(a.position.x >= b_end.x || a_end.x <= b.position.x || a.position.y >= b_end.y || a_end.y <= b.position.y)
}

@(private) rect2i_intersects_of :: #force_inline proc "contextless" (a, b: Rect2i) -> bool {
	rect2i_check_sizes(a.size, b.size)
	a_end, b_end := a.position + a.size, b.position + b.size
	return !(a.position.x >= b_end.x || a_end.x <= b.position.x || a.position.y >= b_end.y || a_end.y <= b.position.y)
}

rect2_new :: proc "contextless" () -> (__r: Rect2) { return }
rect2_new_from_rect2 :: proc "contextless" (from: Rect2) -> (__r: Rect2) { return from }
rect2_new_from_rect2i :: proc "contextless" (from: Rect2i) -> (__r: Rect2) {
	return {{f32(from.position.x), f32(from.position.y)}, {f32(from.size.x), f32(from.size.y)}}
}
rect2_new_from_vector2_vector2 :: proc "contextless" (position: Vector2, size: Vector2) -> (__r: Rect2) { return {position, size} }
rect2_new_from_float_float_float_float :: proc "contextless" (x: f64, y: f64, width: f64, height: f64) -> (__r: Rect2) {
	return {{f32(x), f32(y)}, {f32(width), f32(height)}}
}

rect2_get_center :: proc "contextless" (self: ^Rect2) -> Vector2 { return self.position + self.size * 0.5 }
rect2_get_area :: proc "contextless" (self: ^Rect2) -> f64 { return f64(self.size.x * self.size.y) }
rect2_has_area :: proc "contextless" (self: ^Rect2) -> bool { return self.size.x > 0 && self.size.y > 0 }

// A NaN coordinate fails every comparison, so such a point counts as inside, as in the engine.
rect2_has_point :: proc "contextless" (self: ^Rect2, point: Vector2) -> bool {
	r := self^
	rect2_check_size(r.size)
	end := r.position + r.size
	return !(point.x < r.position.x || point.y < r.position.y || point.x >= end.x || point.y >= end.y)
}

rect2_is_equal_approx :: proc "contextless" (self: ^Rect2, rect: Rect2) -> bool {
	p, s := self.position, self.size
	return m_is_equal_approx(p.x, rect.position.x) && m_is_equal_approx(p.y, rect.position.y) &&
		m_is_equal_approx(s.x, rect.size.x) && m_is_equal_approx(s.y, rect.size.y)
}
rect2_is_finite :: proc "contextless" (self: ^Rect2) -> bool { return v_is_finite(self.position) && v_is_finite(self.size) }

rect2_intersects :: proc "contextless" (self: ^Rect2, b: Rect2, include_borders: bool) -> bool {
	return rect2_intersects_of(self^, b, include_borders)
}

rect2_encloses :: proc "contextless" (self: ^Rect2, b: Rect2) -> bool {
	r := self^
	rect2_check_sizes(r.size, b.size)
	r_end, b_end := r.position + r.size, b.position + b.size
	return b.position.x >= r.position.x && b.position.y >= r.position.y && b_end.x <= r_end.x && b_end.y <= r_end.y
}

// Rect2::intersection: the zero rect when the two do not intersect, borders excluded.
rect2_intersection :: proc "contextless" (self: ^Rect2, b: Rect2) -> Rect2 {
	r := self^
	if !rect2_intersects_of(r, b, false) { return {} }
	lo := v_map2(b.position, r.position, m_max)
	return {lo, v_map2(b.position + b.size, r.position + r.size, m_min) - lo}
}

rect2_merge :: proc "contextless" (self: ^Rect2, b: Rect2) -> Rect2 {
	r := self^
	rect2_check_sizes(r.size, b.size)
	lo := v_map2(b.position, r.position, m_min)
	return {lo, v_map2(b.position + b.size, r.position + r.size, m_max) - lo}
}

rect2_expand :: proc "contextless" (self: ^Rect2, to: Vector2) -> Rect2 {
	r := self^
	rect2_check_size(r.size)
	lo := v_map2(to, r.position, m_min)
	return {lo, v_map2(to, r.position + r.size, m_max) - lo}
}

rect2_get_support :: proc "contextless" (self: ^Rect2, direction: Vector2) -> Vector2 {
	p := self.position
	if direction.x > 0 { p.x += self.size.x }
	if direction.y > 0 { p.y += self.size.y }
	return p
}

rect2_grow :: proc "contextless" (self: ^Rect2, amount: f64) -> Rect2 {
	a := f32(amount)
	return {self.position - a, self.size + a * 2}
}

// Rect2::grow_side_bind: a side outside 0 to 3 grows nothing.
rect2_grow_side :: proc "contextless" (self: ^Rect2, side: i64, amount: f64) -> Rect2 {
	s, a := Side(u32(side)), f32(amount)
	return rect2_grow_by(self^, a if s == .SIDE_LEFT else 0, a if s == .SIDE_TOP else 0, a if s == .SIDE_RIGHT else 0, a if s == .SIDE_BOTTOM else 0)
}

rect2_grow_individual :: proc "contextless" (self: ^Rect2, left: f64, top: f64, right: f64, bottom: f64) -> Rect2 {
	return rect2_grow_by(self^, f32(left), f32(top), f32(right), f32(bottom))
}

rect2_abs :: proc "contextless" (self: ^Rect2) -> Rect2 {
	return {self.position + v_minf(self.size, 0), v_map(self.size, m_abs)}
}

rect2i_new :: proc "contextless" () -> (__r: Rect2i) { return }
rect2i_new_from_rect2i :: proc "contextless" (from: Rect2i) -> (__r: Rect2i) { return from }
rect2i_new_from_rect2 :: proc "contextless" (from: Rect2) -> (__r: Rect2i) {
	p, s := from.position, from.size
	return {{f32_to_i32(p.x), f32_to_i32(p.y)}, {f32_to_i32(s.x), f32_to_i32(s.y)}}
}
rect2i_new_from_vector2i_vector2i :: proc "contextless" (position: Vector2i, size: Vector2i) -> (__r: Rect2i) { return {position, size} }
rect2i_new_from_int_int_int_int :: proc "contextless" (x: i64, y: i64, width: i64, height: i64) -> (__r: Rect2i) {
	return {{i32(x), i32(y)}, {i32(width), i32(height)}}
}

// Integer division truncates toward zero, as C++'s does.
rect2i_get_center :: proc "contextless" (self: ^Rect2i) -> Vector2i { return self.position + self.size / 2 }
rect2i_get_area :: proc "contextless" (self: ^Rect2i) -> i64 { return i64(self.size.x * self.size.y) }
rect2i_has_area :: proc "contextless" (self: ^Rect2i) -> bool { return self.size.x > 0 && self.size.y > 0 }

rect2i_has_point :: proc "contextless" (self: ^Rect2i, point: Vector2i) -> bool {
	r := self^
	rect2i_check_size(r.size)
	end := r.position + r.size
	return !(point.x < r.position.x || point.y < r.position.y || point.x >= end.x || point.y >= end.y)
}

rect2i_intersects :: proc "contextless" (self: ^Rect2i, b: Rect2i) -> bool { return rect2i_intersects_of(self^, b) }

rect2i_encloses :: proc "contextless" (self: ^Rect2i, b: Rect2i) -> bool {
	r := self^
	rect2i_check_sizes(r.size, b.size)
	r_end, b_end := r.position + r.size, b.position + b.size
	return b.position.x >= r.position.x && b.position.y >= r.position.y && b_end.x <= r_end.x && b_end.y <= r_end.y
}

rect2i_intersection :: proc "contextless" (self: ^Rect2i, b: Rect2i) -> Rect2i {
	r := self^
	if !rect2i_intersects_of(r, b) { return {} }
	lo := Vector2i{max(b.position.x, r.position.x), max(b.position.y, r.position.y)}
	b_end, r_end := b.position + b.size, r.position + r.size
	return {lo, Vector2i{min(b_end.x, r_end.x), min(b_end.y, r_end.y)} - lo}
}

rect2i_merge :: proc "contextless" (self: ^Rect2i, b: Rect2i) -> Rect2i {
	r := self^
	rect2i_check_sizes(r.size, b.size)
	lo := Vector2i{min(b.position.x, r.position.x), min(b.position.y, r.position.y)}
	b_end, r_end := b.position + b.size, r.position + r.size
	return {lo, Vector2i{max(b_end.x, r_end.x), max(b_end.y, r_end.y)} - lo}
}

rect2i_expand :: proc "contextless" (self: ^Rect2i, to: Vector2i) -> Rect2i {
	r := self^
	rect2i_check_size(r.size)
	end := r.position + r.size
	lo := Vector2i{min(to.x, r.position.x), min(to.y, r.position.y)}
	return {lo, Vector2i{max(to.x, end.x), max(to.y, end.y)} - lo}
}

rect2i_grow :: proc "contextless" (self: ^Rect2i, amount: i64) -> Rect2i {
	a := i32(amount)
	return {self.position - a, self.size + a * 2}
}

// Rect2i::grow_side_bind: a side outside 0 to 3 grows nothing.
rect2i_grow_side :: proc "contextless" (self: ^Rect2i, side: i64, amount: i64) -> Rect2i {
	s, a := Side(u32(side)), i32(amount)
	return rect2i_grow_by(self^, a if s == .SIDE_LEFT else 0, a if s == .SIDE_TOP else 0, a if s == .SIDE_RIGHT else 0, a if s == .SIDE_BOTTOM else 0)
}

rect2i_grow_individual :: proc "contextless" (self: ^Rect2i, left: i64, top: i64, right: i64, bottom: i64) -> Rect2i {
	return rect2i_grow_by(self^, i32(left), i32(top), i32(right), i32(bottom))
}

// Math::abs of INT32_MIN wraps back to INT32_MIN, as std::abs does on x86-64.
rect2i_abs :: proc "contextless" (self: ^Rect2i) -> Rect2i {
	s := self.size
	return {self.position + Vector2i{min(s.x, 0), min(s.y, 0)}, Vector2i{s.x if s.x >= 0 else -s.x, s.y if s.y >= 0 else -s.y}}
}
