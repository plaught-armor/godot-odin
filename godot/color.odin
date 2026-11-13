package godot

// Color methods and constructors computed in place, under the names and signatures the bindings
// generated before. Each follows the engine's own code in core/math/color.cpp and color.h of
// Godot 4.7-stable: single-precision operations in the same order, the same libm calls (powf,
// fmodf, floorf), roundf's rounding done inline, and the same mixed double steps, so results match bit for bit.
// The String methods read and build Strings in place and print the engine's errors for an
// invalid code or name; `from_ok_hsl` follows thirdparty/misc/ok_color.h with the engine's own
// cbrtf. tools/odin_bindgen.py leaves these names out of godot/gen_builtins.odin.

import "base:intrinsics"
import "core:c/libc"
import gde "../gdextension"

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

// One digit of a color code as the engine's `_parse_col4` reads it: through a `char`, so only the
// low byte of the character counts, and -1 for anything that is not a hex digit.
@(private) html_digit :: #force_inline proc "contextless" (c: rune) -> i32 {
	b := u8(c)
	switch b {
	case '0' ..= '9': return i32(b - '0')
	case 'a' ..= 'f': return i32(b - 'a') + 10
	case 'A' ..= 'F': return i32(b - 'A') + 10
	}
	return -1
}

// `_parse_col8`: two digits, so a valid first digit before an invalid one still counts as a value.
@(private) html_pair :: #force_inline proc "contextless" (d: []rune, i: int) -> f32 {
	return f32(html_digit(d[i]) * 16 + html_digit(d[i + 1])) / 255.0
}

// Prints `prefix`, the characters and a full stop as one engine error, in the engine's UTF-8 (a
// surrogate encodes as is; a character past 0x1FFFFF, which the engine reports separately,
// prints as '?'). The text lives in an engine allocation for the one call.
@(private) color_text_error :: proc "contextless" (prefix: string, chars: []rune) {
	size := len(prefix) + 4 * len(chars) + 2
	buf := ([^]u8)(gde.mem_alloc2(uint(size), 0))
	if buf == nil { return }
	k := copy(buf[:size], prefix)
	for c in chars {
		u := u32(c)
		switch {
		case u <= 0x7f:
			buf[k] = u8(u); k += 1
		case u <= 0x7ff:
			buf[k], buf[k + 1] = u8(0xc0 | u >> 6), u8(0x80 | u & 0x3f); k += 2
		case u <= 0xffff:
			buf[k], buf[k + 1], buf[k + 2] = u8(0xe0 | u >> 12), u8(0x80 | (u >> 6) & 0x3f), u8(0x80 | u & 0x3f); k += 3
		case u <= 0x1fffff:
			buf[k], buf[k + 1] = u8(0xf0 | u >> 18), u8(0x80 | (u >> 12) & 0x3f)
			buf[k + 2], buf[k + 3] = u8(0x80 | (u >> 6) & 0x3f), u8(0x80 | u & 0x3f); k += 4
		case:
			buf[k] = '?'; k += 1
		}
	}
	buf[k], buf[k + 1] = '.', 0
	gde.print_error(cstring(buf), "", #file, #line, 1)
	gde.mem_free2(buf, 0)
}

// Color::html: three, four, six or eight digits after an optional '#'. Any other count, or a
// negative component from an invalid digit, prints the engine's error and gives Color().
@(private) html_parse :: proc "contextless" (chars: []rune) -> Color {
	if len(chars) == 0 { return {0, 0, 0, 1} }
	d := chars[1:] if chars[0] == '#' else chars
	c := Color{0, 0, 0, 1}
	switch len(d) {
	case 3, 4:
		c.r, c.g, c.b = f32(html_digit(d[0])) / 15.0, f32(html_digit(d[1])) / 15.0, f32(html_digit(d[2])) / 15.0
		if len(d) == 4 { c.a = f32(html_digit(d[3])) / 15.0 }
	case 6, 8:
		c.r, c.g, c.b = html_pair(d, 0), html_pair(d, 2), html_pair(d, 4)
		if len(d) == 8 { c.a = html_pair(d, 6) }
	case:
		color_text_error("Invalid color code: ", chars)
		return {0, 0, 0, 1}
	}
	if c.r < 0 || c.g < 0 || c.b < 0 || c.a < 0 {
		color_text_error("Invalid color code: ", chars)
		return {0, 0, 0, 1}
	}
	return c
}

// Color::html_is_valid: the digit count as html_parse wants it, and every digit a hex digit as a
// whole character, not by its low byte.
@(private) html_valid :: proc "contextless" (chars: []rune) -> bool {
	if len(chars) == 0 { return false }
	d := chars[1:] if chars[0] == '#' else chars
	switch len(d) {
	case 3, 4, 6, 8:
	case: return false
	}
	for c in d {
		if !(c >= '0' && c <= '9' || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F') { return false }
	}
	return true
}

// Color::find_named_color: the name without " -_'." and upper-cased as the engine's `to_upper`
// does, matched against the table's names without '_'. Every table name is ASCII capitals and at
// most NAMED_MAX long, so any other character or a longer name cannot match.
@(private) NAMED_MAX :: 17
@(private) named_color_index :: proc "contextless" (chars: []rune) -> int {
	buf: [NAMED_MAX]u8
	k := 0
	for c in chars {
		switch c {
		case ' ', '-', '_', '\'', '.': continue
		}
		u := rune_upper(c)
		if u < 'A' || u > 'Z' || k == NAMED_MAX { return -1 }
		buf[k] = u8(u)
		k += 1
	}
	name := string(buf[:k])
	lo, hi := 0, len(NAMED_COLORS)
	for lo < hi {
		mid := (lo + hi) / 2
		if NAMED_COLORS[mid].name < name { lo = mid + 1 } else { hi = mid }
	}
	return lo if lo < len(NAMED_COLORS) && NAMED_COLORS[lo].name == name else -1
}

// `Color(String)`: a valid code, or else a name, with the engine's error and Color() for neither.
@(private) color_of_text :: proc "contextless" (chars: []rune) -> Color {
	if html_valid(chars) { return html_parse(chars) }
	i := named_color_index(chars)
	if i < 0 {
		color_text_error("Invalid color name: ", chars)
		return {0, 0, 0, 1}
	}
	return color_hex(i64(NAMED_COLORS[i].hex))
}

color_new_from_string :: proc "contextless" (code: String) -> (__r: Color) {
	return color_of_text(string_chars(code))
}
color_new_from_string_float :: proc "contextless" (code: String, alpha: f64) -> (__r: Color) {
	c := color_of_text(string_chars(code))
	c.a = f32(alpha)
	return c
}
color_html :: proc "contextless" (rgba: String) -> Color {
	return html_parse(string_chars(rgba))
}
color_html_is_valid :: proc "contextless" (color: String) -> bool {
	return html_valid(string_chars(color))
}
color_from_string :: proc "contextless" (str: String, default: Color) -> Color {
	chars := string_chars(str)
	if html_valid(chars) { return html_parse(chars) }
	i := named_color_index(chars)
	return default if i < 0 else color_hex(i64(NAMED_COLORS[i].hex))
}

// Color::to_html: each component rounded to a byte and clamped, in lower-case hex.
color_to_html :: proc "contextless" (self: ^Color, with_alpha: bool) -> (out: String) {
	HEX := "0123456789abcdef"
	v := [4]f32{self.r, self.g, self.b, self.a}
	text: [8]u8
	n := 8 if with_alpha else 6
	for i in 0 ..< n / 2 {
		x := clamp(c_round_i32(v[i] * 255.0), 0, 255)
		text[2 * i], text[2 * i + 1] = HEX[x >> 4], HEX[x & 0xf]
	}
	ascii_fill(&out, text[:n])
	return
}

// OkHSL, after thirdparty/misc/ok_color.h of Godot 4.7-stable, operation for operation.

// The engine's own cbrtf (FreeBSD's, as musl carries it): a bit-level first guess, then two
// Newton steps in double, rounded once to float.
@(private) ok_cbrtf :: proc "contextless" (x: f32) -> f32 {
	B1 :: 709958130
	B2 :: 642849266
	u := transmute(u32)x
	hx := u & 0x7fffffff
	if hx >= 0x7f800000 { return x + x }
	if hx < 0x00800000 {
		if hx == 0 { return x }
		u = transmute(u32)(x * 0h4b800000)
		hx = (u & 0x7fffffff) / 3 + B2
	} else {
		hx = hx / 3 + B1
	}
	t := f64(transmute(f32)(u & 0x80000000 | hx))
	xd := f64(x)
	r := t * t * t
	t = t * (xd + xd + r) / (xd + r + r)
	r = t * t * t
	t = t * (xd + xd + r) / (xd + r + r)
	return f32(t)
}

// fmin and fmax as the engine's compiler inlines them: a NaN first argument gives the second.
@(private) ok_fmin :: #force_inline proc "contextless" (x, y: f32) -> f32 {
	return y if x != x else (y if y < x else x)
}
@(private) ok_fmax :: #force_inline proc "contextless" (x, y: f32) -> f32 {
	return y if x != x else (y if y > x else x)
}

@(private) oklab_to_linear_srgb :: proc "contextless" (L, a, b: f32) -> [3]f32 {
	l_ := L + 0.3963377774 * a + 0.2158037573 * b
	m_ := L - 0.1055613458 * a - 0.0638541728 * b
	s_ := L - 0.0894841775 * a - 1.2914855480 * b
	l := l_ * l_ * l_
	m := m_ * m_ * m_
	s := s_ * s_ * s_
	return {
		+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
	}
}

@(private) ok_max_saturation :: proc "contextless" (a, b: f32) -> f32 {
	k0, k1, k2, k3, k4, wl, wm, ws: f32
	if -1.88170328 * a - 0.80936493 * b > 1 {
		k0, k1, k2, k3, k4 = +1.19086277, +1.76576728, +0.59662641, +0.75515197, +0.56771245
		wl, wm, ws = +4.0767416621, -3.3077115913, +0.2309699292
	} else if 1.81444104 * a - 1.19445276 * b > 1 {
		k0, k1, k2, k3, k4 = +0.73956515, -0.45954404, +0.08285427, +0.12541070, +0.14503204
		wl, wm, ws = -1.2684380046, +2.6097574011, -0.3413193965
	} else {
		k0, k1, k2, k3, k4 = +1.35733652, -0.00915799, -1.15130210, -0.50559606, +0.00692167
		wl, wm, ws = -0.0041960863, -0.7034186147, +1.7076147010
	}
	S := k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b
	k_l := +0.3963377774 * a + 0.2158037573 * b
	k_m := -0.1055613458 * a - 0.0638541728 * b
	k_s := -0.0894841775 * a - 1.2914855480 * b
	l_ := 1 + S * k_l
	m_ := 1 + S * k_m
	s_ := 1 + S * k_s
	l := l_ * l_ * l_
	m := m_ * m_ * m_
	s := s_ * s_ * s_
	l_dS := 3 * k_l * l_ * l_
	m_dS := 3 * k_m * m_ * m_
	s_dS := 3 * k_s * s_ * s_
	l_dS2 := 6 * k_l * k_l * l_
	m_dS2 := 6 * k_m * k_m * m_
	s_dS2 := 6 * k_s * k_s * s_
	f := wl * l + wm * m + ws * s
	f1 := wl * l_dS + wm * m_dS + ws * s_dS
	f2 := wl * l_dS2 + wm * m_dS2 + ws * s_dS2
	return S - f * f1 / (f1 * f1 - 0.5 * f * f2)
}

// find_cusp: the cusp's lightness and chroma, as [L, C].
@(private) ok_find_cusp :: proc "contextless" (a, b: f32) -> [2]f32 {
	S_cusp := ok_max_saturation(a, b)
	rgb := oklab_to_linear_srgb(1, S_cusp * a, S_cusp * b)
	L_cusp := ok_cbrtf(1 / ok_fmax(ok_fmax(rgb.r, rgb.g), rgb.b))
	return {L_cusp, L_cusp * S_cusp}
}

// One Halley step's correction for one channel, with weights w: the step when it heads forward,
// FLT_MAX otherwise.
@(private) ok_halley :: #force_inline proc "contextless" (w, v, vdt, vdt2: [3]f32) -> f32 {
	x := w[0] * v[0] + w[1] * v[1] + w[2] * v[2] - 1
	x1 := w[0] * vdt[0] + w[1] * vdt[1] + w[2] * vdt[2]
	x2 := w[0] * vdt2[0] + w[1] * vdt2[1] + w[2] * vdt2[2]
	u := x1 / (x1 * x1 - 0.5 * x * x2)
	return -x * u if u >= 0 else f32(0h7f7fffff)
}

@(private) ok_gamut_intersection :: proc "contextless" (a, b, L1, C1, L0: f32, cusp: [2]f32) -> f32 {
	if (L1 - L0) * cusp[1] - (cusp[0] - L0) * C1 <= 0 {
		return cusp[1] * L0 / (C1 * cusp[0] + cusp[1] * (L0 - L1))
	}
	t := cusp[1] * (L0 - 1) / (C1 * (cusp[0] - 1) + cusp[1] * (L0 - L1))
	dL := L1 - L0
	dC := C1
	k := [3]f32{+0.3963377774 * a + 0.2158037573 * b, -0.1055613458 * a - 0.0638541728 * b, -0.0894841775 * a - 1.2914855480 * b}
	l_dt := dL + dC * k[0]
	m_dt := dL + dC * k[1]
	s_dt := dL + dC * k[2]
	L := L0 * (1 - t) + t * L1
	C := t * C1
	l_ := L + C * k[0]
	m_ := L + C * k[1]
	s_ := L + C * k[2]
	v := [3]f32{l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_}
	vdt := [3]f32{3 * l_dt * l_ * l_, 3 * m_dt * m_ * m_, 3 * s_dt * s_ * s_}
	vdt2 := [3]f32{6 * l_dt * l_dt * l_, 6 * m_dt * m_dt * m_, 6 * s_dt * s_dt * s_}
	t_r := ok_halley({4.0767416621, -3.3077115913, 0.2309699292}, v, vdt, vdt2)
	t_g := ok_halley({-1.2684380046, 2.6097574011, -0.3413193965}, v, vdt, vdt2)
	t_b := ok_halley({-0.0041960863, -0.7034186147, 1.7076147010}, v, vdt, vdt2)
	return t + ok_fmin(t_r, ok_fmin(t_g, t_b))
}

// get_ST_mid: the polynomial approximation of the cusp's S and T.
@(private) ok_st_mid :: proc "contextless" (a_, b_: f32) -> [2]f32 {
	S := 0.11516993 + 1 / (+7.44778970 + 4.15901240 * b_ + a_ * (-2.19557347 + 1.75198401 * b_ + a_ * (-2.13704948 - 10.02301043 * b_ + a_ * (-4.24894561 + 5.38770819 * b_ + 4.69891013 * a_))))
	T := 0.11239642 + 1 / (+1.61320320 - 0.68124379 * b_ + a_ * (+0.40370612 + 0.90148123 * b_ + a_ * (-0.27087943 + 0.61223990 * b_ + a_ * (+0.00299215 - 0.45399568 * b_ - 0.14661872 * a_))))
	return {S, T}
}

// get_Cs: the chroma at saturation 0, the middle and the gamut's edge, as [C_0, C_mid, C_max].
@(private) ok_cs :: proc "contextless" (L, a_, b_: f32) -> [3]f32 {
	cusp := ok_find_cusp(a_, b_)
	C_max := ok_gamut_intersection(a_, b_, L, 1, L, cusp)
	S_max, T_max := cusp[1] / cusp[0], cusp[1] / (1 - cusp[0])
	k := C_max / ok_fmin(L * S_max, (1 - L) * T_max)
	mid := ok_st_mid(a_, b_)
	C_a := L * mid[0]
	C_b := (1 - L) * mid[1]
	C_mid := 0.9 * k * intrinsics.sqrt(intrinsics.sqrt(1 / (1 / (C_a * C_a * C_a * C_a) + 1 / (C_b * C_b * C_b * C_b))))
	C_a0 := L * 0.4
	C_b0 := (1 - L) * 0.8
	return {intrinsics.sqrt(1 / (1 / (C_a0 * C_a0) + 1 / (C_b0 * C_b0))), C_mid, C_max}
}

@(private) ok_srgb_transfer :: #force_inline proc "contextless" (a: f32) -> f32 {
	return 12.92 * a if 0.0031308 >= a else 1.055 * libc.powf(a, 0.4166666666666667) - 0.055
}

// okhsl_to_srgb. (1 - mid) and the products after it stay single precision at run time, as the
// engine computes them, rather than folded at Odin's constant precision.
@(private) okhsl_to_srgb :: proc "contextless" (h, s, l: f32) -> [3]f32 {
	if l == 1 { return {1, 1, 1} }
	if l == 0 { return {0, 0, 0} }
	TWO_PI :: f32(0h40c90fdb)
	K_1 :: f32(0.206)
	K_2 :: f32(0.03)
	K_3 :: f32(0h3f95df31)
	a_ := libc.cosf(TWO_PI * h)
	b_ := libc.sinf(TWO_PI * h)
	L := (l * l + K_1 * l) / (K_3 * (l + K_2))
	cs := ok_cs(L, a_, b_)
	C_0, C_mid, C_max := cs[0], cs[1], cs[2]
	mid := f32(0.8)
	mid_inv := f32(1.25)
	C: f32
	if s < mid {
		t := mid_inv * s
		k_1 := mid * C_0
		k_2 := 1 - k_1 / C_mid
		C = t * k_1 / (1 - k_2 * t)
	} else {
		t := (s - mid) / (1 - mid)
		k_0 := C_mid
		k_1 := (1 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0
		k_2 := 1 - k_1 / (C_max - C_mid)
		C = k_0 + t * k_1 / (1 - k_2 * t)
	}
	rgb := oklab_to_linear_srgb(L, C * a_, C * b_)
	return {ok_srgb_transfer(rgb.r), ok_srgb_transfer(rgb.g), ok_srgb_transfer(rgb.b)}
}

// Color::from_ok_hsl: okhsl_to_srgb with the alpha, then clamped to 0 to 1 by CLAMP.
color_from_ok_hsl :: proc "contextless" (h: f64, s: f64, l: f64, alpha: f64) -> Color {
	rgb := okhsl_to_srgb(f32(h), f32(s), f32(l))
	return {m_clamp(rgb.r, 0, 1), m_clamp(rgb.g, 0, 1), m_clamp(rgb.b, 0, 1), m_clamp(f32(alpha), 0, 1)}
}

// Color::named_colors from core/math/color_names.inc, the names without '_' and sorted, for
// named_color_index's binary search.
@(private, rodata) NAMED_COLORS := [?]struct { name: string, hex: u32 }{
	{"ALICEBLUE", 0xF0F8FFFF},
	{"ANTIQUEWHITE", 0xFAEBD7FF},
	{"AQUA", 0x00FFFFFF},
	{"AQUAMARINE", 0x7FFFD4FF},
	{"AZURE", 0xF0FFFFFF},
	{"BEIGE", 0xF5F5DCFF},
	{"BISQUE", 0xFFE4C4FF},
	{"BLACK", 0x000000FF},
	{"BLANCHEDALMOND", 0xFFEBCDFF},
	{"BLUE", 0x0000FFFF},
	{"BLUEVIOLET", 0x8A2BE2FF},
	{"BROWN", 0xA52A2AFF},
	{"BURLYWOOD", 0xDEB887FF},
	{"CADETBLUE", 0x5F9EA0FF},
	{"CHARTREUSE", 0x7FFF00FF},
	{"CHOCOLATE", 0xD2691EFF},
	{"CORAL", 0xFF7F50FF},
	{"CORNFLOWERBLUE", 0x6495EDFF},
	{"CORNSILK", 0xFFF8DCFF},
	{"CRIMSON", 0xDC143CFF},
	{"CYAN", 0x00FFFFFF},
	{"DARKBLUE", 0x00008BFF},
	{"DARKCYAN", 0x008B8BFF},
	{"DARKGOLDENROD", 0xB8860BFF},
	{"DARKGRAY", 0xA9A9A9FF},
	{"DARKGREEN", 0x006400FF},
	{"DARKKHAKI", 0xBDB76BFF},
	{"DARKMAGENTA", 0x8B008BFF},
	{"DARKOLIVEGREEN", 0x556B2FFF},
	{"DARKORANGE", 0xFF8C00FF},
	{"DARKORCHID", 0x9932CCFF},
	{"DARKRED", 0x8B0000FF},
	{"DARKSALMON", 0xE9967AFF},
	{"DARKSEAGREEN", 0x8FBC8FFF},
	{"DARKSLATEBLUE", 0x483D8BFF},
	{"DARKSLATEGRAY", 0x2F4F4FFF},
	{"DARKTURQUOISE", 0x00CED1FF},
	{"DARKVIOLET", 0x9400D3FF},
	{"DEEPPINK", 0xFF1493FF},
	{"DEEPSKYBLUE", 0x00BFFFFF},
	{"DIMGRAY", 0x696969FF},
	{"DODGERBLUE", 0x1E90FFFF},
	{"FIREBRICK", 0xB22222FF},
	{"FLORALWHITE", 0xFFFAF0FF},
	{"FORESTGREEN", 0x228B22FF},
	{"FUCHSIA", 0xFF00FFFF},
	{"GAINSBORO", 0xDCDCDCFF},
	{"GHOSTWHITE", 0xF8F8FFFF},
	{"GOLD", 0xFFD700FF},
	{"GOLDENROD", 0xDAA520FF},
	{"GRAY", 0xBEBEBEFF},
	{"GREEN", 0x00FF00FF},
	{"GREENYELLOW", 0xADFF2FFF},
	{"HONEYDEW", 0xF0FFF0FF},
	{"HOTPINK", 0xFF69B4FF},
	{"INDIANRED", 0xCD5C5CFF},
	{"INDIGO", 0x4B0082FF},
	{"IVORY", 0xFFFFF0FF},
	{"KHAKI", 0xF0E68CFF},
	{"LAVENDER", 0xE6E6FAFF},
	{"LAVENDERBLUSH", 0xFFF0F5FF},
	{"LAWNGREEN", 0x7CFC00FF},
	{"LEMONCHIFFON", 0xFFFACDFF},
	{"LIGHTBLUE", 0xADD8E6FF},
	{"LIGHTCORAL", 0xF08080FF},
	{"LIGHTCYAN", 0xE0FFFFFF},
	{"LIGHTGOLDENROD", 0xFAFAD2FF},
	{"LIGHTGRAY", 0xD3D3D3FF},
	{"LIGHTGREEN", 0x90EE90FF},
	{"LIGHTPINK", 0xFFB6C1FF},
	{"LIGHTSALMON", 0xFFA07AFF},
	{"LIGHTSEAGREEN", 0x20B2AAFF},
	{"LIGHTSKYBLUE", 0x87CEFAFF},
	{"LIGHTSLATEGRAY", 0x778899FF},
	{"LIGHTSTEELBLUE", 0xB0C4DEFF},
	{"LIGHTYELLOW", 0xFFFFE0FF},
	{"LIME", 0x00FF00FF},
	{"LIMEGREEN", 0x32CD32FF},
	{"LINEN", 0xFAF0E6FF},
	{"MAGENTA", 0xFF00FFFF},
	{"MAROON", 0xB03060FF},
	{"MEDIUMAQUAMARINE", 0x66CDAAFF},
	{"MEDIUMBLUE", 0x0000CDFF},
	{"MEDIUMORCHID", 0xBA55D3FF},
	{"MEDIUMPURPLE", 0x9370DBFF},
	{"MEDIUMSEAGREEN", 0x3CB371FF},
	{"MEDIUMSLATEBLUE", 0x7B68EEFF},
	{"MEDIUMSPRINGGREEN", 0x00FA9AFF},
	{"MEDIUMTURQUOISE", 0x48D1CCFF},
	{"MEDIUMVIOLETRED", 0xC71585FF},
	{"MIDNIGHTBLUE", 0x191970FF},
	{"MINTCREAM", 0xF5FFFAFF},
	{"MISTYROSE", 0xFFE4E1FF},
	{"MOCCASIN", 0xFFE4B5FF},
	{"NAVAJOWHITE", 0xFFDEADFF},
	{"NAVYBLUE", 0x000080FF},
	{"OLDLACE", 0xFDF5E6FF},
	{"OLIVE", 0x808000FF},
	{"OLIVEDRAB", 0x6B8E23FF},
	{"ORANGE", 0xFFA500FF},
	{"ORANGERED", 0xFF4500FF},
	{"ORCHID", 0xDA70D6FF},
	{"PALEGOLDENROD", 0xEEE8AAFF},
	{"PALEGREEN", 0x98FB98FF},
	{"PALETURQUOISE", 0xAFEEEEFF},
	{"PALEVIOLETRED", 0xDB7093FF},
	{"PAPAYAWHIP", 0xFFEFD5FF},
	{"PEACHPUFF", 0xFFDAB9FF},
	{"PERU", 0xCD853FFF},
	{"PINK", 0xFFC0CBFF},
	{"PLUM", 0xDDA0DDFF},
	{"POWDERBLUE", 0xB0E0E6FF},
	{"PURPLE", 0xA020F0FF},
	{"REBECCAPURPLE", 0x663399FF},
	{"RED", 0xFF0000FF},
	{"ROSYBROWN", 0xBC8F8FFF},
	{"ROYALBLUE", 0x4169E1FF},
	{"SADDLEBROWN", 0x8B4513FF},
	{"SALMON", 0xFA8072FF},
	{"SANDYBROWN", 0xF4A460FF},
	{"SEAGREEN", 0x2E8B57FF},
	{"SEASHELL", 0xFFF5EEFF},
	{"SIENNA", 0xA0522DFF},
	{"SILVER", 0xC0C0C0FF},
	{"SKYBLUE", 0x87CEEBFF},
	{"SLATEBLUE", 0x6A5ACDFF},
	{"SLATEGRAY", 0x708090FF},
	{"SNOW", 0xFFFAFAFF},
	{"SPRINGGREEN", 0x00FF7FFF},
	{"STEELBLUE", 0x4682B4FF},
	{"TAN", 0xD2B48CFF},
	{"TEAL", 0x008080FF},
	{"THISTLE", 0xD8BFD8FF},
	{"TOMATO", 0xFF6347FF},
	{"TRANSPARENT", 0xFFFFFF00},
	{"TURQUOISE", 0x40E0D0FF},
	{"VIOLET", 0xEE82EEFF},
	{"WEBGRAY", 0x808080FF},
	{"WEBGREEN", 0x008000FF},
	{"WEBMAROON", 0x800000FF},
	{"WEBPURPLE", 0x800080FF},
	{"WHEAT", 0xF5DEB3FF},
	{"WHITE", 0xFFFFFFFF},
	{"WHITESMOKE", 0xF5F5F5FF},
	{"YELLOW", 0xFFFF00FF},
	{"YELLOWGREEN", 0x9ACD32FF},
}
