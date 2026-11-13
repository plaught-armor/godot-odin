package godot

// Color methods and constructors computed in place, under the names and signatures the bindings
// generated before. Each follows the engine's own code in core/math/color.cpp and color.h of
// Godot 4.7-stable: single-precision operations in the same order, the same libm calls (powf,
// fmodf, floorf), roundf's rounding done inline, and the same mixed double steps, so results match bit for bit.
// tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin. The String parsing
// and formatting methods (`to_html`, `html`, `html_is_valid`, `from_string`, the String
// constructors) and `from_ok_hsl` still call the engine.

import "core:c/libc"

// A float truncated to int32 as the engine's x86-64 build converts it: toward zero, and the
// lowest int32 for NaN, infinities and anything out of range.
@(private) c_to_i32 :: #force_inline proc "contextless" (x: f32) -> i32 {
	return i32(x) if x > -2147483648.0 && x < 2147483648.0 else min(i32)
}

// `Math::round(x)` converted to int32 as the engine's x86-64 build does: half away from zero, and
// the lowest int32 for NaN, infinities and anything out of range. Within range the fraction
// x - trunc(x) is exact, so this matches roundf without its library call.
@(private) c_round_i32 :: #force_inline proc "contextless" (x: f32) -> i32 {
	if !(x > -2147483648.0 && x < 2147483648.0) { return min(i32) }
	i := i32(x)
	d := x - f32(i)
	return i + i32(d >= 0.5) - i32(d <= -0.5)
}

// `(uint8_t)Math::round(x * 255.0f)`: the engine converts through a 32-bit integer and keeps the
// low byte, so values outside 0 to 255 wrap rather than clamp.
@(private) c_byte :: #force_inline proc "contextless" (x: f32) -> u32 {
	return u32(u8(c_round_i32(x * 255.0)))
}

// `(uint16_t)Math::round(x * 65535.0f)`, wrapping the same way as c_byte.
@(private) c_word :: #force_inline proc "contextless" (x: f32) -> u64 {
	return u64(u16(c_round_i32(x * 65535.0)))
}

// 1.0f / 12.92f, 1.0f / 2.4f and 1.0 / (1.0 + 0.055) as the engine's compiler folds them, by
// bits, because Odin folds constant expressions at higher precision.
@(private) INV_12_92 :: f32(0h3d9e8391)
@(private) INV_2_4 :: f32(0h3ed55555)
@(private) INV_1_055 :: f64(0h3fee54edcd0aeb60)

color_new :: proc "contextless" () -> (__r: Color) { return {0, 0, 0, 1} }
color_new_from_color :: proc "contextless" (from: Color) -> (__r: Color) { return from }
color_new_from_color_float :: proc "contextless" (from: Color, alpha: f64) -> (__r: Color) {
	return {from.r, from.g, from.b, f32(alpha)}
}
color_new_from_float_float_float :: proc "contextless" (r: f64, g: f64, b: f64) -> (__r: Color) {
	return {f32(r), f32(g), f32(b), 1}
}
color_new_from_float_float_float_float :: proc "contextless" (r: f64, g: f64, b: f64, a: f64) -> (__r: Color) {
	return {f32(r), f32(g), f32(b), f32(a)}
}

color_to_argb32 :: proc "contextless" (self: ^Color) -> i64 {
	return i64(c_byte(self.a) << 24 | c_byte(self.r) << 16 | c_byte(self.g) << 8 | c_byte(self.b))
}
color_to_abgr32 :: proc "contextless" (self: ^Color) -> i64 {
	return i64(c_byte(self.a) << 24 | c_byte(self.b) << 16 | c_byte(self.g) << 8 | c_byte(self.r))
}
color_to_rgba32 :: proc "contextless" (self: ^Color) -> i64 {
	return i64(c_byte(self.r) << 24 | c_byte(self.g) << 16 | c_byte(self.b) << 8 | c_byte(self.a))
}
color_to_argb64 :: proc "contextless" (self: ^Color) -> i64 {
	return transmute(i64)(c_word(self.a) << 48 | c_word(self.r) << 32 | c_word(self.g) << 16 | c_word(self.b))
}
color_to_abgr64 :: proc "contextless" (self: ^Color) -> i64 {
	return transmute(i64)(c_word(self.a) << 48 | c_word(self.b) << 32 | c_word(self.g) << 16 | c_word(self.r))
}
color_to_rgba64 :: proc "contextless" (self: ^Color) -> i64 {
	return transmute(i64)(c_word(self.r) << 48 | c_word(self.g) << 32 | c_word(self.b) << 16 | c_word(self.a))
}

color_clamp :: proc "contextless" (self: ^Color, min: Color, max: Color) -> Color {
	c := self^
	return {m_clamp(c.r, min.r, max.r), m_clamp(c.g, min.g, max.g), m_clamp(c.b, min.b, max.b), m_clamp(c.a, min.a, max.a)}
}
color_inverted :: proc "contextless" (self: ^Color) -> Color {
	c := self^
	return {1 - c.r, 1 - c.g, 1 - c.b, c.a}
}
color_lerp :: proc "contextless" (self: ^Color, to: Color, weight: f64) -> Color {
	c, w := self^, f32(weight)
	return {m_lerp(c.r, to.r, w), m_lerp(c.g, to.g, w), m_lerp(c.b, to.b, w), m_lerp(c.a, to.a, w)}
}
color_lightened :: proc "contextless" (self: ^Color, amount: f64) -> Color {
	c, t := self^, f32(amount)
	return {c.r + (1 - c.r) * t, c.g + (1 - c.g) * t, c.b + (1 - c.b) * t, c.a}
}
color_darkened :: proc "contextless" (self: ^Color, amount: f64) -> Color {
	c, k := self^, 1 - f32(amount)
	return {c.r * k, c.g * k, c.b * k, c.a}
}
color_blend :: proc "contextless" (self: ^Color, over: Color) -> Color {
	c := self^
	sa := 1 - over.a
	a := c.a * sa + over.a
	if a == 0 { return {0, 0, 0, 0} }
	return {
		(c.r * c.a * sa + over.r * over.a) / a,
		(c.g * c.a * sa + over.g * over.a) / a,
		(c.b * c.a * sa + over.b * over.a) / a,
		a,
	}
}
color_get_luminance :: proc "contextless" (self: ^Color) -> f64 {
	return f64(0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b)
}

// The engine's ternary mixes a float branch with a double branch only in linear_to_srgb; in
// srgb_to_linear both branches are float.
@(private) c_srgb_to_linear :: #force_inline proc "contextless" (x: f32) -> f32 {
	return x * INV_12_92 if x < 0.04045 else libc.powf(f32((f64(x) + 0.055) * INV_1_055), 2.4)
}
@(private) c_linear_to_srgb :: #force_inline proc "contextless" (x: f32) -> f32 {
	return f32(f64(12.92 * x) if x < 0.0031308 else (1.0 + 0.055) * f64(libc.powf(x, INV_2_4)) - 0.055)
}
color_srgb_to_linear :: proc "contextless" (self: ^Color) -> Color {
	c := self^
	return {c_srgb_to_linear(c.r), c_srgb_to_linear(c.g), c_srgb_to_linear(c.b), c.a}
}
color_linear_to_srgb :: proc "contextless" (self: ^Color) -> Color {
	c := self^
	return {c_linear_to_srgb(c.r), c_linear_to_srgb(c.g), c_linear_to_srgb(c.b), c.a}
}
color_is_equal_approx :: proc "contextless" (self: ^Color, to: Color) -> bool {
	c := self^
	return m_is_equal_approx(c.r, to.r) && m_is_equal_approx(c.g, to.g) && m_is_equal_approx(c.b, to.b) && m_is_equal_approx(c.a, to.a)
}

color_hex :: proc "contextless" (hex: i64) -> Color {
	h := u32(hex)
	return {f32(h >> 24) / 255.0, f32((h >> 16) & 0xFF) / 255.0, f32((h >> 8) & 0xFF) / 255.0, f32(h & 0xFF) / 255.0}
}
color_hex64 :: proc "contextless" (hex: i64) -> Color {
	h := u64(hex)
	return {f32(h >> 48) / 65535.0, f32((h >> 32) & 0xFFFF) / 65535.0, f32((h >> 16) & 0xFFFF) / 65535.0, f32(h & 0xFFFF) / 65535.0}
}

// Color::set_hsv: the hue scaled to sextants, wrapped by fmodf, and its floor picking the
// dominant channel; a NaN or negative sextant falls to the engine's default case.
color_from_hsv :: proc "contextless" (h: f64, s: f64, v: f64, alpha: f64) -> Color {
	hf, sf, vf := f32(h), f32(s), f32(v)
	if sf == 0 { return {vf, vf, vf, f32(alpha)} }
	hf = libc.fmodf(hf * 6.0, 6)
	i := c_to_i32(libc.floorf(hf))
	f := hf - f32(i)
	p := vf * (1 - sf)
	q := vf * (1 - sf * f)
	t := vf * (1 - sf * (1 - f))
	switch i {
	case 0: return {vf, t, p, f32(alpha)}
	case 1: return {q, vf, p, f32(alpha)}
	case 2: return {p, vf, t, f32(alpha)}
	case 3: return {p, q, vf, f32(alpha)}
	case 4: return {t, p, vf, f32(alpha)}
	}
	return {vf, p, q, f32(alpha)}
}
color_from_rgbe9995 :: proc "contextless" (rgbe: i64) -> Color {
	e := u32(rgbe)
	m := libc.powf(2.0, f32(e >> 27) - 15.0 - 9.0)
	return {f32(e & 0x1ff) * m, f32((e >> 9) & 0x1ff) * m, f32((e >> 18) & 0x1ff) * m, 1}
}
color_from_rgba8 :: proc "contextless" (r8: i64, g8: i64, b8: i64, a8: i64) -> Color {
	return {f32(r8) / 255.0, f32(g8) / 255.0, f32(b8) / 255.0, f32(a8) / 255.0}
}
