package demos

import "../../godot"
import "core:math"

// A heightmap mesh from fractal Perlin noise: `build` fills the vertex, normal, colour and index
// arrays an ArrayMesh surface takes. Below 0 is water, drawn flat.
Terrain :: struct {
	vertices:   godot.PackedVector3Array,
	normals:    godot.PackedVector3Array,
	colors:     godot.PackedColorArray,
	indices:    godot.PackedInt32Array,

	heights:    []f64 `godot:"-"`,
	perm:       [512]i32 `godot:"-"`,
	// The size `indices` was built for; they depend on nothing else.
	index_size: int `godot:"-"`,
}

// The mesh spans this many units on each side.
EXTENT :: 100.0

// Height bands, as a fraction of the height scale, and the colour of each. A vertex takes the
// first band whose top is above it.
@(rodata)
BAND_TOP := [6]f64{-0.15, 0, 0.05, 0.35, 0.6, math.INF_F64}
@(rodata)
BAND_COLOR := [6]godot.Color{
	{0.05, 0.15, 0.40, 1}, {0.10, 0.35, 0.60, 1}, {0.76, 0.70, 0.50, 1},
	{0.25, 0.50, 0.20, 1}, {0.45, 0.40, 0.35, 1}, {0.95, 0.95, 0.97, 1},
}

// Perlin's gradients, cut to eight directions.
DIAG :: 0.7071067811865476
@(rodata)
GRAD_X := [8]f64{1, -1, 0, 0, DIAG, -DIAG, DIAG, -DIAG}
@(rodata)
GRAD_Y := [8]f64{0, 0, 1, -1, DIAG, DIAG, -DIAG, -DIAG}

register_terrain :: proc() {
	c := godot.class(Terrain, "TerrainOdin", "RefCounted", terrain_notification)
	godot.fields(c)
	godot.method(c, "build", terrain_build, {"size", "octaves", "frequency", "height", "seed"})
}

terrain_notification :: proc(self: ^Terrain, what: i64) {
	if what == PREDELETE {
		delete(self.heights)
		self.heights = nil
	}
}

// Fills the mesh arrays for a `size` by `size` grid of vertices: `octaves` layers of noise, the
// first at `frequency` cycles across the mesh, scaled to `height` units, permuted by `seed` (not 0).
terrain_build :: proc(self: ^Terrain, size, octaves: i64, frequency, height: f64, seed: i64) {
	assert(size >= 2 && size <= 1024 && octaves >= 1 && octaves <= 12 && frequency > 0 && seed != 0)
	n := int(size)
	terrain_permute(self, u32(seed))
	if len(self.heights) != n * n {
		delete(self.heights)
		self.heights = make([]f64, n * n)
	}
	terrain_heights(self, n, int(octaves), frequency, height)
	terrain_surface(self, n, height)
	if self.index_size != n { terrain_indices(self, n) }
}

@(private = "file")
terrain_permute :: proc(self: ^Terrain, seed: u32) {
	rng := seed
	for i in 0 ..< 256 { self.perm[i] = i32(i) }
	for i := 255; i > 0; i -= 1 {
		j := int(next_random(&rng) % u32(i + 1))
		self.perm[i], self.perm[j] = self.perm[j], self.perm[i]
	}
	for i in 0 ..< 256 { self.perm[256 + i] = self.perm[i] }
}

@(private = "file")
terrain_heights :: proc(self: ^Terrain, n, octaves: int, frequency, height: f64) #no_bounds_check {
	for j in 0 ..< n {
		for i in 0 ..< n {
			x := f64(i) / f64(n - 1) * frequency
			z := f64(j) / f64(n - 1) * frequency
			total, amp, f, norm := 0.0, 1.0, 1.0, 0.0
			for _ in 0 ..< octaves {
				total += perlin(&self.perm, x * f, z * f) * amp
				norm += amp
				amp *= 0.5
				f *= 2
			}
			self.heights[j * n + i] = total / norm * height
		}
	}
}

// Perlin noise at (`x`, `y`), both at least 0.
@(private = "file")
perlin :: #force_inline proc "contextless" (p: ^[512]i32, x, y: f64) -> f64 #no_bounds_check {
	fx, fy := math.floor(x), math.floor(y)
	xi, yi := int(fx) & 255, int(fy) & 255
	xf, yf := x - fx, y - fy
	u := xf * xf * xf * (xf * (xf * 6 - 15) + 10)
	v := yf * yf * yf * (yf * (yf * 6 - 15) + 10)
	a := int(p[xi]) + yi
	b := int(p[xi + 1]) + yi
	n00 := gradient(p[a], xf, yf)
	n10 := gradient(p[b], xf - 1, yf)
	n01 := gradient(p[a + 1], xf, yf - 1)
	n11 := gradient(p[b + 1], xf - 1, yf - 1)
	x1 := n00 + u * (n10 - n00)
	x2 := n01 + u * (n11 - n01)
	return x1 + v * (x2 - x1)
}

@(private = "file")
gradient :: #force_inline proc "contextless" (h: i32, x, y: f64) -> f64 #no_bounds_check {
	return GRAD_X[h & 7] * x + GRAD_Y[h & 7] * y
}

// Vertices with water flattened to 0, normals from the neighbours' heights, colours by band.
@(private = "file")
terrain_surface :: proc(self: ^Terrain, n: int, height: f64) #no_bounds_check {
	verts := vectors_of(&self.vertices, n * n)
	norms := vectors_of(&self.normals, n * n)
	cols := colors_of(&self.colors, n * n)
	spacing := EXTENT / f64(n - 1)
	mid := f64(n - 1) * 0.5
	for j in 0 ..< n {
		for i in 0 ..< n {
			k := j * n + i
			h := self.heights[k]
			verts[k] = {f32((f64(i) - mid) * spacing), f32(max(h, 0)), f32((f64(j) - mid) * spacing)}
			nx := max(self.heights[j * n + max(i - 1, 0)], 0) - max(self.heights[j * n + min(i + 1, n - 1)], 0)
			nz := max(self.heights[max(j - 1, 0) * n + i], 0) - max(self.heights[min(j + 1, n - 1) * n + i], 0)
			ny := 2 * spacing
			l := math.sqrt(nx * nx + ny * ny + nz * nz)
			norms[k] = {f32(nx / l), f32(ny / l), f32(nz / l)}
			t := h / height if height > 0 else 0
			band := 0
			for t >= BAND_TOP[band] { band += 1 }
			cols[k] = BAND_COLOR[band]
		}
	}
}

// Two triangles per grid square.
@(private = "file")
terrain_indices :: proc(self: ^Terrain, n: int) #no_bounds_check {
	idx := ints_of(&self.indices, (n - 1) * (n - 1) * 6)
	o := 0
	for j in 0 ..< n - 1 {
		for i in 0 ..< n - 1 {
			a := i32(j * n + i)
			c := a + i32(n)
			idx[o + 0], idx[o + 1], idx[o + 2] = a, a + 1, c
			idx[o + 3], idx[o + 4], idx[o + 5] = a + 1, c + 1, c
			o += 6
		}
	}
	self.index_size = n
}
