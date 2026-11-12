class_name TerrainSim
extends RefCounted
## The heightmap mesh of TerrainOdin (demos/src/terrain.odin) in GDScript, step for step: the same
## permutation, noise and bands, so from one seed both fill the same arrays.

## The mesh spans this many units on each side.
const EXTENT: float = 100.0
const DIAG: float = 0.7071067811865476

## The arrays an ArrayMesh surface takes, filled by `build`.
var vertices: PackedVector3Array = []
var normals: PackedVector3Array = []
var colors: PackedColorArray = []
var indices: PackedInt32Array = []

var _heights: PackedFloat64Array = []
var _perm: PackedInt32Array = []
## The size `indices` was built for; they depend on nothing else.
var _index_size: int = 0
## Height bands, as a fraction of the height scale, and the colour of each. A vertex takes the
## first band whose top is above it.
var _band_top: PackedFloat64Array = [-0.15, 0.0, 0.05, 0.35, 0.6, INF]
var _band_color: PackedColorArray = [
	Color(0.05, 0.15, 0.40, 1.0),
	Color(0.10, 0.35, 0.60, 1.0),
	Color(0.76, 0.70, 0.50, 1.0),
	Color(0.25, 0.50, 0.20, 1.0),
	Color(0.45, 0.40, 0.35, 1.0),
	Color(0.95, 0.95, 0.97, 1.0),
]
## Perlin's gradients, cut to eight directions.
var _grad_x: PackedFloat64Array = [1.0, -1.0, 0.0, 0.0, DIAG, -DIAG, DIAG, -DIAG]
var _grad_y: PackedFloat64Array = [0.0, 0.0, 1.0, -1.0, DIAG, DIAG, -DIAG, -DIAG]


## Fills the mesh arrays for a `size` by `size` grid of vertices: `octaves` layers of noise, the
## first at `frequency` cycles across the mesh, scaled to `height` units, permuted by `seed` (not 0).
func build(size: int, octaves: int, frequency: float, height: float, seed: int) -> void:
	assert(size >= 2 and size <= 1024 and octaves >= 1 and octaves <= 12)
	assert(frequency > 0.0 and seed != 0)
	_permute(seed & 0xFFFFFFFF)
	_heights.resize(size * size)
	_fill_heights(size, octaves, frequency, height)
	_surface(size, height)
	if _index_size != size:
		_fill_indices(size)


func _permute(seed: int) -> void:
	var rng: int = seed
	_perm.resize(512)
	for i: int in 256:
		_perm[i] = i
	for i: int in range(255, 0, -1):
		rng ^= (rng << 13) & 0xFFFFFFFF
		rng ^= rng >> 17
		rng ^= (rng << 5) & 0xFFFFFFFF
		var j: int = rng % (i + 1)
		var held: int = _perm[i]
		_perm[i] = _perm[j]
		_perm[j] = held
	for i: int in 256:
		_perm[256 + i] = _perm[i]


func _fill_heights(n: int, octaves: int, frequency: float, height: float) -> void:
	for j: int in n:
		for i: int in n:
			var x: float = float(i) / float(n - 1) * frequency
			var z: float = float(j) / float(n - 1) * frequency
			var total: float = 0.0
			var amp: float = 1.0
			var f: float = 1.0
			var norm: float = 0.0
			for o: int in octaves:
				total += _perlin(x * f, z * f) * amp
				norm += amp
				amp *= 0.5
				f *= 2.0
			_heights[j * n + i] = total / norm * height


## Perlin noise at (`x`, `y`), both at least 0.
func _perlin(x: float, y: float) -> float:
	var fx: float = floorf(x)
	var fy: float = floorf(y)
	var xi: int = int(fx) & 255
	var yi: int = int(fy) & 255
	var xf: float = x - fx
	var yf: float = y - fy
	var u: float = xf * xf * xf * (xf * (xf * 6.0 - 15.0) + 10.0)
	var v: float = yf * yf * yf * (yf * (yf * 6.0 - 15.0) + 10.0)
	var a: int = _perm[xi] + yi
	var b: int = _perm[xi + 1] + yi
	var n00: float = _gradient(_perm[a], xf, yf)
	var n10: float = _gradient(_perm[b], xf - 1.0, yf)
	var n01: float = _gradient(_perm[a + 1], xf, yf - 1.0)
	var n11: float = _gradient(_perm[b + 1], xf - 1.0, yf - 1.0)
	var x1: float = n00 + u * (n10 - n00)
	var x2: float = n01 + u * (n11 - n01)
	return x1 + v * (x2 - x1)


func _gradient(h: int, x: float, y: float) -> float:
	return _grad_x[h & 7] * x + _grad_y[h & 7] * y


## Vertices with water flattened to 0, normals from the neighbours' heights, colours by band.
func _surface(n: int, height: float) -> void:
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	var spacing: float = EXTENT / float(n - 1)
	var mid: float = float(n - 1) * 0.5
	for j: int in n:
		for i: int in n:
			var k: int = j * n + i
			var h: float = _heights[k]
			vertices[k] = Vector3(
				(float(i) - mid) * spacing,
				maxf(h, 0.0),
				(float(j) - mid) * spacing,
			)
			var left: float = maxf(_heights[j * n + maxi(i - 1, 0)], 0.0)
			var right: float = maxf(_heights[j * n + mini(i + 1, n - 1)], 0.0)
			var up: float = maxf(_heights[maxi(j - 1, 0) * n + i], 0.0)
			var down: float = maxf(_heights[mini(j + 1, n - 1) * n + i], 0.0)
			var nx: float = left - right
			var nz: float = up - down
			var ny: float = 2.0 * spacing
			var l: float = sqrt(nx * nx + ny * ny + nz * nz)
			normals[k] = Vector3(nx / l, ny / l, nz / l)
			var t: float = h / height if height > 0.0 else 0.0
			var band: int = 0
			while t >= _band_top[band]:
				band += 1
			colors[k] = _band_color[band]


## Two triangles per grid square.
func _fill_indices(n: int) -> void:
	indices.resize((n - 1) * (n - 1) * 6)
	var o: int = 0
	for j: int in n - 1:
		for i: int in n - 1:
			var a: int = j * n + i
			var c: int = a + n
			indices[o] = a
			indices[o + 1] = a + 1
			indices[o + 2] = c
			indices[o + 3] = a + 1
			indices[o + 4] = c + 1
			indices[o + 5] = c
			o += 6
	_index_size = n
