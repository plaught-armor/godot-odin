class_name FlowSim
extends RefCounted
## The flow field and units of FlowOdin (demos/src/flow.odin) in GDScript, step for step: Dijkstra
## over the same binary heap, the same steering, so from one seed both write the same arrays.

const UNREACHED: int = 2147483647

## Units' speed (px/s) and how fast they turn to the field (1/s).
var speed: float = 90.0
var turn: float = 6.0
## One 2D MultiMesh transform per unit, written by `step`.
var buffer: PackedFloat32Array = []
## RGBA8 pixels, one per cell: walls, and open cells shaded by their cost; written on rebuild.
var field_image: PackedByteArray = []

var _cols: int = 0
var _rows: int = 0
var _cell: float = 1.0
var _walls: PackedByteArray = []
var _cost: PackedInt32Array = []
var _heap: PackedInt64Array = []
var _heap_size: int = 0
var _target: int = 0
var _dirty: bool = false
var _count: int = 0
var _px: PackedFloat64Array = []
var _py: PackedFloat64Array = []
var _vx: PackedFloat64Array = []
var _vy: PackedFloat64Array = []
var _rng: int = 1
## Field rebuilds since `setup`.
var _rebuilt: int = 0
## The eight neighbours, straight ones first.
var _step_x: PackedInt32Array = [1, -1, 0, 0, 1, -1, 1, -1]
var _step_y: PackedInt32Array = [0, 0, 1, -1, 1, 1, -1, -1]


## A `cols` by `rows` grid of `cell`-pixel cells with random wall bars, and `units` units on open
## cells, all from `seed` (not 0). The target starts at the grid's centre.
@warning_ignore("integer_division")
func setup(cols: int, rows: int, cell: float, units: int, seed: int) -> void:
	assert(cols > 2 and rows > 2 and cell > 0.0 and units >= 0 and seed != 0)
	_cols = cols
	_rows = rows
	_cell = cell
	var n: int = cols * rows
	_walls.clear()
	_walls.resize(n)
	_cost.resize(n)
	_rng = seed & 0xFFFFFFFF
	_rebuilt = 0
	for b: int in n / 90:
		var x: int = _next() % cols
		var y: int = _next() % rows
		var long: int = _next() % 14 + 3
		var across: bool = _next() & 1 == 0
		for k: int in long:
			var wx: int = x
			var wy: int = y + k
			if across:
				wx = x + k
				wy = y
			if wx < cols and wy < rows:
				_walls[wy * cols + wx] = 1
	_target = (rows / 2) * cols + cols / 2
	_walls[_target] = 0
	_dirty = true
	_rebuild()
	_count = units
	for a: PackedFloat64Array in [_px, _py, _vx, _vy]:
		a.clear()
	_px.resize(units)
	_py.resize(units)
	_vx.resize(units)
	_vy.resize(units)
	for u: int in units:
		_respawn(u)
	_write()


## Moves the target to the cell under (`x`, `y`) (px), unless that cell is a wall or outside.
func set_target(x: float, y: float) -> void:
	if x < 0.0 or y < 0.0:
		return
	var cx: int = int(x / _cell)
	var cy: int = int(y / _cell)
	if cx >= _cols or cy >= _rows:
		return
	var c: int = cy * _cols + cx
	if _walls[c] != 0 or c == _target:
		return
	_target = c
	_dirty = true


## The field's cost at cell (`x`, `y`); -1 for a wall or a cell the target cannot reach.
func cost_at(x: int, y: int) -> int:
	var c: int = _cost[y * _cols + x]
	return -1 if c == UNREACHED else c


## Field rebuilds since `setup`, counting the one it does.
func rebuilds() -> int:
	return _rebuilt


## Rebuilds the field if the target moved, then moves every unit `delta` seconds.
func step(delta: float) -> void:
	_rebuild()
	for u: int in _count:
		_walk(u, delta)
	_write()


func _next() -> int:
	var x: int = _rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_rng = x
	return x


## Dijkstra from the target; heap entries are cost << 32 | cell.
@warning_ignore("integer_division")
func _rebuild() -> void:
	if not _dirty:
		return
	_dirty = false
	_rebuilt += 1
	_cost.fill(UNREACHED)
	_heap_size = 0
	_cost[_target] = 0
	_push(_target)
	var limit: int = 8 * _cost.size()
	for pops: int in limit + 1:
		if _heap_size == 0:
			break
		assert(pops < limit)
		var top: int = _pop()
		var d: int = top >> 32
		var c: int = top & 0xFFFFFFFF
		if d > _cost[c]:
			continue
		var cx: int = c % _cols
		var cy: int = c / _cols
		for k: int in 8:
			var n: int = _neighbour(cx, cy, k)
			if n < 0:
				continue
			var nd: int = d + (10 if k < 4 else 14)
			if nd >= _cost[n]:
				continue
			_cost[n] = nd
			_push((nd << 32) | n)
	_paint()


func _neighbour(cx: int, cy: int, k: int) -> int:
	var nx: int = cx + _step_x[k]
	var ny: int = cy + _step_y[k]
	if nx < 0 or ny < 0 or nx >= _cols or ny >= _rows:
		return -1
	if _walls[ny * _cols + nx] != 0:
		return -1
	if k >= 4 and (_walls[cy * _cols + nx] != 0 or _walls[ny * _cols + cx] != 0):
		return -1
	return ny * _cols + nx


@warning_ignore("integer_division")
func _push(v: int) -> void:
	if _heap_size == _heap.size():
		_heap.append(v)
	else:
		_heap[_heap_size] = v
	var i: int = _heap_size
	_heap_size += 1
	while i > 0:
		var p: int = (i - 1) / 2
		if _heap[p] <= _heap[i]:
			break
		var held: int = _heap[p]
		_heap[p] = _heap[i]
		_heap[i] = held
		i = p


func _pop() -> int:
	var top: int = _heap[0]
	_heap_size -= 1
	var n: int = _heap_size
	if n == 0:
		return top
	_heap[0] = _heap[n]
	var i: int = 0
	while true:
		var l: int = 2 * i + 1
		if l >= n:
			break
		var m: int = l
		if l + 1 < n and _heap[l + 1] < _heap[l]:
			m = l + 1
		if _heap[i] <= _heap[m]:
			break
		var held: int = _heap[i]
		_heap[i] = _heap[m]
		_heap[m] = held
		i = m
	return top


@warning_ignore("integer_division")
func _respawn(u: int) -> void:
	for t: int in 64:
		var c: int = _next() % _cost.size()
		if _cost[c] == UNREACHED or c == _target:
			continue
		_px[u] = (float(c % _cols) + 0.5) * _cell
		_py[u] = (float(c / _cols) + 0.5) * _cell
		_vx[u] = 0.0
		_vy[u] = 0.0
		return


@warning_ignore("integer_division")
func _walk(u: int, delta: float) -> void:
	var x: float = _px[u]
	var y: float = _py[u]
	var cx: int = int(x / _cell)
	var cy: int = int(y / _cell)
	var c: int = cy * _cols + cx
	if c == _target:
		_respawn(u)
		return
	var best: int = -1
	var best_cost: int = _cost[c]
	for k: int in 8:
		var n: int = _neighbour(cx, cy, k)
		if n >= 0 and _cost[n] < best_cost:
			best = n
			best_cost = _cost[n]
	var wx: float = 0.0
	var wy: float = 0.0
	if best >= 0:
		var ox: float = (float(best % _cols) + 0.5) * _cell - x
		var oy: float = (float(best / _cols) + 0.5) * _cell - y
		var l: float = sqrt(ox * ox + oy * oy)
		wx = ox / l * speed
		wy = oy / l * speed
	var t: float = minf(turn * delta, 1.0)
	var vx: float = _vx[u] + (wx - _vx[u]) * t
	var vy: float = _vy[u] + (wy - _vy[u]) * t
	var nx: float = x + vx * delta
	var ny: float = y + vy * delta
	if _blocked(nx, y):
		nx = x
		vx = 0.0
	if _blocked(nx, ny):
		ny = y
		vy = 0.0
	_px[u] = nx
	_py[u] = ny
	_vx[u] = vx
	_vy[u] = vy


func _blocked(x: float, y: float) -> bool:
	if x < 0.0 or y < 0.0:
		return true
	var cx: int = int(x / _cell)
	var cy: int = int(y / _cell)
	if cx >= _cols or cy >= _rows:
		return true
	return _walls[cy * _cols + cx] != 0


func _write() -> void:
	buffer.resize(_count * 8)
	for u: int in _count:
		var vx: float = _vx[u]
		var vy: float = _vy[u]
		var ux: float = 1.0
		var uy: float = 0.0
		var s: float = sqrt(vx * vx + vy * vy)
		if s > 0.0:
			ux = vx / s
			uy = vy / s
		var o: int = u * 8
		buffer[o] = ux
		buffer[o + 1] = -uy
		buffer[o + 2] = 0.0
		buffer[o + 3] = _px[u]
		buffer[o + 4] = uy
		buffer[o + 5] = ux
		buffer[o + 6] = 0.0
		buffer[o + 7] = _py[u]


func _paint() -> void:
	field_image.resize(_cost.size() * 4)
	for i: int in _cost.size():
		var c: int = _cost[i]
		var o: int = i * 4
		var r: int = 0
		var g: int = 0
		var b: int = 0
		if _walls[i] != 0:
			r = 90
			g = 90
			b = 100
		elif c != UNREACHED:
			@warning_ignore("integer_division")
			var band: int = (c / 10) % 32
			r = 20 + band
			g = 30 + band * 2
			b = 60 + band * 3
		field_image[o] = r
		field_image[o + 1] = g
		field_image[o + 2] = b
		field_image[o + 3] = 255
