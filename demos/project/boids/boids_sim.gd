class_name BoidsSim
extends RefCounted
## The flock of BoidsOdin (demos/src/boids.odin) in GDScript, step for step: the same grid, the
## same rules in the same order, so from one seed both write the same buffer.

const POINTER_RADIUS: float = 120.0

## How far a boid sees its neighbours (px).
var radius: float = 24.0
## Neighbours closer than this push the boid away (px).
var personal: float = 10.0
## Weights of the three rules.
var separation: float = 600.0
var alignment: float = 1.2
var cohesion: float = 0.9
## Speed limits (px/s).
var min_speed: float = 60.0
var max_speed: float = 160.0
## One 2D MultiMesh transform per boid, written by `step`.
var buffer: PackedFloat32Array = []

var _count: int = 0
var _width: float = 0.0
var _height: float = 0.0
var _cols: int = 0
var _rows: int = 0
var _px: PackedFloat64Array = []
var _py: PackedFloat64Array = []
var _vx: PackedFloat64Array = []
var _vy: PackedFloat64Array = []
var _nvx: PackedFloat64Array = []
var _nvy: PackedFloat64Array = []
## Boids sorted by cell: cell c's boids are _items[_start[c]] up to _items[_start[c + 1]].
var _start: PackedInt32Array = []
var _cursor: PackedInt32Array = []
var _items: PackedInt32Array = []
var _cell_of: PackedInt32Array = []
var _pointer_x: float = 0.0
var _pointer_y: float = 0.0
var _pointer: float = 0.0
var _rng: int = 1


## Scatters `count` boids over a `width` by `height` field (px) from `seed`, which must not be 0.
func setup(count: int, width: float, height: float, seed: int) -> void:
	assert(count >= 0 and seed != 0 and width >= 3.0 * radius and height >= 3.0 * radius)
	_count = count
	_width = width
	_height = height
	_cols = int(width / radius)
	_rows = int(height / radius)
	for a: PackedFloat64Array in [_px, _py, _vx, _vy, _nvx, _nvy]:
		a.clear()
	_px.resize(count)
	_py.resize(count)
	_vx.resize(count)
	_vy.resize(count)
	_nvx.resize(count)
	_nvy.resize(count)
	_start.resize(_cols * _rows + 1)
	_cursor.resize(_cols * _rows)
	_items.resize(count)
	_cell_of.resize(count)
	_rng = seed & 0xFFFFFFFF
	for i: int in count:
		_px[i] = _unit() * width
		_py[i] = _unit() * height
		_vx[i] = (_unit() * 2.0 - 1.0) * max_speed
		_vy[i] = (_unit() * 2.0 - 1.0) * max_speed
	_pointer = 0.0
	_write()


## Pushes boids near (`x`, `y`) away with `strength` from the next step on; 0 stops it.
func set_pointer(x: float, y: float, strength: float) -> void:
	_pointer_x = x
	_pointer_y = y
	_pointer = strength


## Advances the flock `delta` seconds and writes `buffer`.
func step(delta: float) -> void:
	_bin()
	for i: int in _count:
		_steer(i, delta)
	_move(delta)
	_write()


## xorshift32, as demos.odin's next_random, then scaled to [0, 1).
func _unit() -> float:
	var x: int = _rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_rng = x
	return float(x) / 4294967296.0


func _bin() -> void:
	var cell_w: float = _width / _cols
	var cell_h: float = _height / _rows
	_start.fill(0)
	for i: int in _count:
		var cx: int = mini(int(_px[i] / cell_w), _cols - 1)
		var cy: int = mini(int(_py[i] / cell_h), _rows - 1)
		var c: int = cy * _cols + cx
		_cell_of[i] = c
		_start[c + 1] += 1
	for c: int in _cols * _rows:
		_start[c + 1] += _start[c]
		_cursor[c] = _start[c]
	for i: int in _count:
		var c: int = _cell_of[i]
		_items[_cursor[c]] = i
		_cursor[c] += 1


@warning_ignore("integer_division")
func _steer(i: int, delta: float) -> void:
	var r2: float = radius * radius
	var p2: float = personal * personal
	var half_w: float = _width * 0.5
	var half_h: float = _height * 0.5
	var x: float = _px[i]
	var y: float = _py[i]
	var home: int = _cell_of[i]
	var hx: int = home % _cols
	var hy: int = home / _cols
	var seen: int = 0
	var ax: float = 0.0
	var ay: float = 0.0
	var cx: float = 0.0
	var cy: float = 0.0
	var sx: float = 0.0
	var sy: float = 0.0
	for dy: int in range(-1, 2):
		var ry: int = (hy + dy + _rows) % _rows
		for dx: int in range(-1, 2):
			var c: int = ry * _cols + (hx + dx + _cols) % _cols
			for k: int in range(_start[c], _start[c + 1]):
				var j: int = _items[k]
				if j == i:
					continue
				var ox: float = _px[j] - x
				var oy: float = _py[j] - y
				if ox > half_w:
					ox -= _width
				elif ox < -half_w:
					ox += _width
				if oy > half_h:
					oy -= _height
				elif oy < -half_h:
					oy += _height
				var d2: float = ox * ox + oy * oy
				if d2 >= r2:
					continue
				seen += 1
				ax += _vx[j]
				ay += _vy[j]
				cx += ox
				cy += oy
				if d2 < p2 and d2 > 0.0:
					sx -= ox / d2
					sy -= oy / d2
	var fx: float = 0.0
	var fy: float = 0.0
	if seen > 0:
		var n: float = seen
		fx = (ax / n - _vx[i]) * alignment + (cx / n) * cohesion + sx * separation
		fy = (ay / n - _vy[i]) * alignment + (cy / n) * cohesion + sy * separation
	if _pointer != 0.0:
		var ox: float = x - _pointer_x
		var oy: float = y - _pointer_y
		var d2: float = ox * ox + oy * oy
		if d2 < POINTER_RADIUS * POINTER_RADIUS and d2 > 0.0:
			fx += ox / d2 * _pointer
			fy += oy / d2 * _pointer
	var vx: float = _vx[i] + fx * delta
	var vy: float = _vy[i] + fy * delta
	var s: float = sqrt(vx * vx + vy * vy)
	if s > max_speed:
		vx *= max_speed / s
		vy *= max_speed / s
	elif s < min_speed and s > 0.0:
		vx *= min_speed / s
		vy *= min_speed / s
	_nvx[i] = vx
	_nvy[i] = vy


func _move(delta: float) -> void:
	var t: PackedFloat64Array = _vx
	_vx = _nvx
	_nvx = t
	t = _vy
	_vy = _nvy
	_nvy = t
	for i: int in _count:
		var x: float = _px[i] + _vx[i] * delta
		var y: float = _py[i] + _vy[i] * delta
		if x < 0.0:
			x += _width
		elif x >= _width:
			x -= _width
		if y < 0.0:
			y += _height
		elif y >= _height:
			y -= _height
		_px[i] = x
		_py[i] = y


func _write() -> void:
	buffer.resize(_count * 8)
	for i: int in _count:
		var vx: float = _vx[i]
		var vy: float = _vy[i]
		var ux: float = 1.0
		var uy: float = 0.0
		var s: float = sqrt(vx * vx + vy * vy)
		if s > 0.0:
			ux = vx / s
			uy = vy / s
		var o: int = i * 8
		buffer[o] = ux
		buffer[o + 1] = -uy
		buffer[o + 2] = 0.0
		buffer[o + 3] = _px[i]
		buffer[o + 4] = uy
		buffer[o + 5] = ux
		buffer[o + 6] = 0.0
		buffer[o + 7] = _py[i]
