package godot

import "base:intrinsics"

// Correctly rounded single-precision sine and cosine: for every f32 input the result is the f32
// nearest the exact value (checked against MPFR over all 2^32 inputs, round-to-nearest mode).
// The method is CORE-MATH's sincosf (Alexei Sibidanov and Paul Zimmermann, MIT): reduce the angle
// to q + z sixteenths of pi with |z| <= 1/2, read sin and cos of q*pi/16 from a table, and extend
// by two short polynomials in z, all in double precision.

// sin(k*pi/16) for k = 0..31. The cosine of the same angle is the entry eight places on.
@(private, rodata) TRIG_TABLE := [32]f64 {
	0h0000000000000000, 0h3FC8F8B83C69A60B, 0h3FD87DE2A6AEA963, 0h3FE1C73B39AE68C8,
	0h3FE6A09E667F3BCD, 0h3FEA9B66290EA1A3, 0h3FED906BCF328D46, 0h3FEF6297CFF75CB0,
	0h3FF0000000000000, 0h3FEF6297CFF75CB0, 0h3FED906BCF328D46, 0h3FEA9B66290EA1A3,
	0h3FE6A09E667F3BCD, 0h3FE1C73B39AE68C8, 0h3FD87DE2A6AEA963, 0h3FC8F8B83C69A60B,
	0h0000000000000000, 0hBFC8F8B83C69A60B, 0hBFD87DE2A6AEA963, 0hBFE1C73B39AE68C8,
	0hBFE6A09E667F3BCD, 0hBFEA9B66290EA1A3, 0hBFED906BCF328D46, 0hBFEF6297CFF75CB0,
	0hBFF0000000000000, 0hBFEF6297CFF75CB0, 0hBFED906BCF328D46, 0hBFEA9B66290EA1A3,
	0hBFE6A09E667F3BCD, 0hBFE1C73B39AE68C8, 0hBFD87DE2A6AEA963, 0hBFC8F8B83C69A60B,
}

// sin(z*pi/16) = z * (S0 + S1 z^2 + S2 z^4 + S3 z^6); 1 - cos(z*pi/16) = z^2 * (C0 + ... + C3 z^6).
@(private) TRIG_S0 :: f64(0h3FC921FB54442D17)
@(private) TRIG_S1 :: f64(0hBF54ABBCE6256A39)
@(private) TRIG_S2 :: f64(0h3EC466BC5A518C16)
@(private) TRIG_S3 :: f64(0hBE232BDC61074FF6)
@(private) TRIG_C0 :: f64(0h3F93BD3CC9BE45DC)
@(private) TRIG_C1 :: f64(0hBF103C1F081B0833)
@(private) TRIG_C2 :: f64(0h3E755D3C6FC9AC1F)
@(private) TRIG_C3 :: f64(0hBDCE1D3FF281B40D)

// 16/pi in two parts: the head has 28 bits, so its product with an f32 is exact in f64.
@(private) TRIG_16_PI_HI :: f64(0h40145F306E000000)
@(private) TRIG_16_PI_LO :: f64(0hBE2B1BBEAD603D8B)
// Adding then subtracting 1.5 * 2^52 rounds an f64 to the nearest integer, ties to even, and
// leaves that integer in the low bits of the sum.
@(private) TRIG_ROUND :: f64(0h4338000000000000)

// sin and cos from the reduced angle (q + z) * pi/16.
@(private) m_sincos_kernel :: #force_inline proc "contextless" (q: u32, z: f64) -> (sine, cosine: f32) {
	z2 := z * z
	z4 := z2 * z2
	s0 := TRIG_TABLE[q & 31]
	c0 := TRIG_TABLE[(q + 8) & 31]
	ps := (TRIG_S0 + z2 * TRIG_S1) + z4 * (TRIG_S2 + z2 * TRIG_S3)
	pc := (TRIG_C0 + z2 * TRIG_C1) + z4 * (TRIG_C2 + z2 * TRIG_C3)
	// The products with the table values start beside the polynomials rather than after them.
	zs, zc := z * s0, z * c0
	z2s, z2c := z2 * s0, z2 * c0
	return f32(s0 + (ps * zc - pc * z2s)), f32(c0 - (ps * zs + pc * z2c))
}

// Below pi/4 two polynomials in double precision are enough: no reduction and no table. They are
// the kernels of fdlibm's `sin` and `cos`, minimax fits accurate to 2^-58 on this range, which
// take six coefficients where the Taylor series would take eight.
// sin x = x + x^3 * (S1 + S2 x^2 + ... + S6 x^10), cos x = 1 - x^2/2 + x^4 * (C1 + ... + C6 x^10).
// Both have the same shape, so one two-lane vector carries the sine in lane 0 and the cosine in
// lane 1; left as scalar code the pair runs twice the operations.
@(private) m_sincos_small :: #force_inline proc "contextless" (x: f32) -> (sine, cosine: f32) {
	V :: #simd[2]f64
	a := f64(x)
	a2 := a * a
	a4 := a2 * a2
	lo := (V{-1.66666666666666324348e-01, 4.16666666666666019037e-02} + V(a2) * V{8.33333333332248946124e-03, -1.38888888888741095749e-03}) +
		V(a4) * (V{-1.98412698298579493134e-04, 2.48015872894767294178e-05} + V(a2) * V{2.75573137070700676789e-06, -2.75573143513906633035e-07})
	hi := V{-2.50507602534068634195e-08, 2.08757232129817482790e-09} + V(a2) * V{1.58969099521155010221e-10, -1.13596475577881948265e-11}
	r := V{a, 1 + a2 * -0.5} + V{a * a2, a4} * (lo + V(a4 * a4) * hi)
	return f32(intrinsics.simd_extract(r, 0)), f32(intrinsics.simd_extract(r, 1))
}

m_sincos :: #force_inline proc "contextless" (x: f32) -> (sine, cosine: f32) {
	ax := transmute(u32)x << 1
	// 2^-12 <= |x| < pi/4.
	if ax - 0x73000000 < 0x7e921fb6 - 0x73000000 { return m_sincos_small(x) }
	// Outside 2^-12 <= |x| <= 2^26 (zero, infinities and NaN included) the rare path answers.
	if ax < 0x73000000 || ax > 0x99000000 || ax == TRIG_HARD_SIN { return m_sincos_edge(x) }
	hi := TRIG_16_PI_HI * f64(x)
	sum := hi + TRIG_ROUND
	z := (hi - (sum - TRIG_ROUND)) + TRIG_16_PI_LO * f64(x)
	return m_sincos_kernel(u32(transmute(u64)sum), z)
}

m_sin :: #force_inline proc "contextless" (x: f32) -> f32 { sine, _ := m_sincos(x); return sine }
@(private) m_cos :: #force_inline proc "contextless" (x: f32) -> f32 { _, cosine := m_sincos(x); return cosine }

// |x| = 0x1.33333p+13, the one input in the common range whose sine lies too close to the midpoint
// of two floats for the f64 result to round correctly. Its bits are shifted left one, sign dropped.
@(private) TRIG_HARD_SIN :: 0x8c333330

// The rare inputs: tiny angles, where the Taylor terms in single precision already round
// correctly, and angles past 2^26, which need more bits of 16/pi than an f64 holds.
@(private) m_sincos_edge :: #force_no_inline proc "contextless" (x: f32) -> (sine, cosine: f32) {
	u := transmute(u32)x
	ax := u << 1
	if ax < 0x66000000 { return x, 1 } // |x| < 2^-25
	if ax < 0x73000000 { return (-0.16666667 * x) * (x * x) + x, (-0.5 * x) * x + 1 }
	if ax >= 0xff000000 { return x - x, x - x } // infinity or NaN
	if ax == TRIG_HARD_SIN { return transmute(f32)(0xbeb1fa5d ~ u & 0x80000000), transmute(f32)u32(0xbf70090b) }
	// 16/pi to 256 bits, least significant word first, times the 24-bit mantissa.
	m := u128(u & 0x007fffff | 0x00800000)
	p0 := m * 0xfe5163abdebbc562
	p1 := m * 0xdb6295993c439041 + p0 >> 64
	p2 := m * 0xfc2757d1f534ddc0 + p1 >> 64
	p3 := m * 0xa2f9836e4e441529 + p2 >> 64
	p3h, p3l, p2l, p1l := u64(p3 >> 64), u64(p3), u64(p2), u64(p1)
	// The binary point sits `s` bits into p3h:p3l, 5 <= s <= 104: integer part above, fraction below.
	s := (u >> 23 & 0xff) - 147
	q: u32
	frac: i64
	if s < 64 {
		q = u32(p3h << s | p3l >> (64 - s))
		frac = i64(p3l << s | p2l >> (64 - s))
	} else if s == 64 {
		q = u32(p3l)
		frac = i64(p2l)
	} else {
		q = u32(p3l << (s - 64) | p2l >> (128 - s))
		frac = i64(p2l << (s - 64) | p1l >> (128 - s))
	}
	// A fraction of a half or more reads as negative: round the integer part up to match.
	if frac < 0 { q += 1 }
	z := f64(frac) * 0h3BF0000000000000 // 2^-64
	if i32(u) < 0 {
		q = -q
		z = -z
	}
	sine, cosine = m_sincos_kernel(q, z)
	// Three large inputs whose cosine lies too close to a midpoint, as above.
	switch ax {
	case 0xb2455500: cosine = transmute(f32)u32(0x3f08aebf) // |x| = 0x1.4555p+51
	case 0xbe3170f0: cosine = transmute(f32)u32(0x3f7f14bb) // |x| = 0x1.3170fp+63
	case 0xc22b9622: cosine = transmute(f32)u32(0x3f78142f) // |x| = 0x1.2b9622p+67
	}
	return
}
