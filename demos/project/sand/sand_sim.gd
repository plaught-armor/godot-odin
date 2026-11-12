class_name SandSim
extends RefCounted
## The falling-sand grid of SandOdin (demos/src/sand.odin) in GDScript, step for step. Each cell
## is one byte: its material in the low four bits, a shade the painter picked in the high four.

const EMPTY: int = 0
const SAND: int = 1
const WATER: int = 2
const WALL: int = 3
## Offset of the background colour in _colors.
const BACKGROUND: int = 12

## RGBA8 pixels of the grid, one per cell, written by `step` and `paint`.
var image_data: PackedByteArray = []

var _width: int = 0
var _height: int = 0
var _cells: PackedByteArray = []
## 1 for a cell that already moved this step.
var _moved: PackedByteArray = []
var _frame: int = 0
var _rng: int = 1
## RGB per material (EMPTY unused), then the background: the palette of sand.odin.
var _colors: PackedByteArray = [0, 0, 0, 222, 186, 110, 64, 128, 230, 120, 120, 128, 18, 18, 24]


## An empty `width` by `height` grid; `seed` (not 0) drives the shades and the sideways choices.
func setup(width: int, height: int, seed: int) -> void:
	assert(width > 0 and height > 0 and seed != 0)
	_width = width
	_height = height
	_cells.clear()
	_cells.resize(width * height)
	_moved.clear()
	_moved.resize(width * height)
	_frame = 0
	_rng = seed & 0xFFFFFFFF
	_write()


## Fills a disc of `radius` cells around (`x`, `y`) with `material`. Sand and water only fill empty
## cells; a wall overwrites anything, and EMPTY erases anything. `image_data` shows it after the
## next `step`.
func paint(x: int, y: int, radius: int, material: int) -> void:
	assert(material >= EMPTY and material <= WALL and radius >= 0)
	for py: int in range(maxi(y - radius, 0), mini(y + radius, _height - 1) + 1):
		for px: int in range(maxi(x - radius, 0), mini(x + radius, _width - 1) + 1):
			if (px - x) * (px - x) + (py - y) * (py - y) > radius * radius:
				continue
			var i: int = py * _width + px
			if material == EMPTY:
				_cells[i] = 0
			elif material == WALL or _cells[i] == 0:
				var shade: int = _next() & 15
				_cells[i] = material | (shade << 4)


## Cells holding `material`.
func count(material: int) -> int:
	var n: int = 0
	for c: int in _cells:
		if c & 15 == material:
			n += 1
	return n


## Moves every grain and drop once, bottom row first, then writes `image_data`.
func step() -> void:
	_moved.fill(0)
	var w: int = _width
	var forward: bool = _frame % 2 == 0
	for y: int in range(_height - 1, -1, -1):
		for k: int in w:
			var x: int = k if forward else w - 1 - k
			var i: int = y * w + x
			if _moved[i] != 0:
				continue
			var m: int = _cells[i] & 15
			if m == SAND:
				_fall(x, y, true)
			elif m == WATER:
				_fall(x, y, false)
	_frame += 1
	_write()


func _next() -> int:
	var x: int = _rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	_rng = x
	return x


func _fall(x: int, y: int, grain: bool) -> void:
	var w: int = _width
	var i: int = y * w + x
	if y + 1 < _height:
		if _take(i, i + w, grain):
			return
		var d: int = 1 if _next() & 1 == 0 else -1
		if x + d >= 0 and x + d < w and _take(i, i + w + d, grain):
			return
		if x - d >= 0 and x - d < w and _take(i, i + w - d, grain):
			return
	if not grain:
		var d: int = 1 if _next() & 1 == 0 else -1
		if x + d >= 0 and x + d < w and _take(i, i + d, false):
			return
		if x - d >= 0 and x - d < w:
			_take(i, i - d, false)


func _take(from: int, to: int, grain: bool) -> bool:
	var m: int = _cells[to] & 15
	if m != EMPTY and not (grain and m == WATER):
		return false
	var held: int = _cells[to]
	_cells[to] = _cells[from]
	_cells[from] = held
	_moved[from] = 1
	_moved[to] = 1
	return true


func _write() -> void:
	image_data.resize(_cells.size() * 4)
	for i: int in _cells.size():
		var c: int = _cells[i]
		var o: int = i * 4
		var m: int = c & 15
		if m == EMPTY:
			image_data[o] = _colors[BACKGROUND]
			image_data[o + 1] = _colors[BACKGROUND + 1]
			image_data[o + 2] = _colors[BACKGROUND + 2]
		else:
			var s: int = (c >> 4) * 3
			image_data[o] = _colors[m * 3] - s
			image_data[o + 1] = _colors[m * 3 + 1] - s
			image_data[o + 2] = _colors[m * 3 + 2] - s
		image_data[o + 3] = 255
