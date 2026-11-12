package demos

import "../../godot"

// A falling-sand grid. Each cell is one byte: its material in the low four bits, a shade the
// painter picked in the high four, which moves with the grain.
Sand :: struct {
	// RGBA8 pixels of the grid, one per cell, written by `step` and `paint`.
	image_data: godot.PackedByteArray,

	width:      int `godot:"-"`,
	height:     int `godot:"-"`,
	cells:      []u8 `godot:"-"`,
	// 1 for a cell that already moved this step.
	moved:      []u8 `godot:"-"`,
	// Flips each step, so the sweep alternates direction and piles stay symmetric.
	frame:      int `godot:"-"`,
	rng:        u32 `godot:"-"`,
}

EMPTY :: 0
GRAIN :: 1
WATER :: 2
WALL :: 3

// Base colour per material, then the background.
@(rodata)
PALETTE := [4][3]u8{{0, 0, 0}, {222, 186, 110}, {64, 128, 230}, {120, 120, 128}}
BACKGROUND :: [3]u8{18, 18, 24}

register_sand :: proc() {
	c := godot.class(Sand, "SandOdin", "RefCounted", sand_notification)
	godot.fields(c)
	godot.constant(c, "EMPTY", EMPTY)
	godot.constant(c, "SAND", GRAIN)
	godot.constant(c, "WATER", WATER)
	godot.constant(c, "WALL", WALL)
	godot.method(c, "setup", sand_setup, {"width", "height", "seed"})
	godot.method(c, "step", sand_step)
	godot.method(c, "paint", sand_paint, {"x", "y", "radius", "material"})
	godot.method(c, "count", sand_count, {"material"})
}

sand_notification :: proc(self: ^Sand, what: i64) {
	if what == PREDELETE { sand_free(self) }
}

sand_free :: proc(self: ^Sand) {
	delete(self.cells)
	delete(self.moved)
	self.width, self.height = 0, 0
}

// An empty `width` by `height` grid; `seed` (not 0) drives the shades and the sideways choices.
sand_setup :: proc(self: ^Sand, width, height, seed: i64) {
	assert(width > 0 && height > 0 && seed != 0)
	sand_free(self)
	self.width, self.height = int(width), int(height)
	self.cells = make([]u8, self.width * self.height)
	self.moved = make([]u8, self.width * self.height)
	self.frame = 0
	self.rng = u32(seed)
	sand_write(self)
}

// Fills a disc of `radius` cells around (`x`, `y`) with `material`. Sand and water only fill empty
// cells; a wall overwrites anything, and EMPTY erases anything. `image_data` shows it after the
// next `step`.
sand_paint :: proc(self: ^Sand, x, y, radius, material: i64) {
	assert(material >= EMPTY && material <= WALL && radius >= 0)
	for py in max(y - radius, 0) ..= min(y + radius, i64(self.height) - 1) {
		for px in max(x - radius, 0) ..= min(x + radius, i64(self.width) - 1) {
			if (px - x) * (px - x) + (py - y) * (py - y) > radius * radius { continue }
			i := int(py) * self.width + int(px)
			if material == EMPTY {
				self.cells[i] = 0
			} else if material == WALL || self.cells[i] == 0 {
				shade := u8(next_random(&self.rng) & 15)
				self.cells[i] = u8(material) | (shade << 4)
			}
		}
	}
}

// Cells holding `material`.
sand_count :: proc(self: ^Sand, material: i64) -> i64 {
	n: i64
	for c in self.cells { if i64(c & 15) == material { n += 1 } }
	return n
}

// Moves every grain and drop once, bottom row first, then writes `image_data`.
sand_step :: proc(self: ^Sand) #no_bounds_check {
	for &m in self.moved { m = 0 }
	w := self.width
	forward := self.frame % 2 == 0
	for y := self.height - 1; y >= 0; y -= 1 {
		for k in 0 ..< w {
			x := k if forward else w - 1 - k
			i := y * w + x
			if self.moved[i] != 0 { continue }
			switch self.cells[i] & 15 {
			case GRAIN: sand_fall(self, x, y, true)
			case WATER: sand_fall(self, x, y, false)
			}
		}
	}
	self.frame += 1
	sand_write(self)
}

// Moves the sand grain or water drop at (`x`, `y`): straight down, else down to one side, picked
// at random, then the other; water then tries sideways the same way. Sand sinks through water.
@(private = "file")
sand_fall :: proc(self: ^Sand, x, y: int, grain: bool) #no_bounds_check {
	w := self.width
	i := y * w + x
	if y + 1 < self.height {
		if sand_take(self, i, i + w, grain) { return }
		d := 1 if next_random(&self.rng) & 1 == 0 else -1
		if x + d >= 0 && x + d < w && sand_take(self, i, i + w + d, grain) { return }
		if x - d >= 0 && x - d < w && sand_take(self, i, i + w - d, grain) { return }
	}
	if grain { return }
	d := 1 if next_random(&self.rng) & 1 == 0 else -1
	if x + d >= 0 && x + d < w && sand_take(self, i, i + d, false) { return }
	if x - d >= 0 && x - d < w { sand_take(self, i, i - d, false) }
}

// Swaps cell `from` into `to` when `to` is empty, or water under a grain; marks both moved.
@(private = "file")
sand_take :: #force_inline proc "contextless" (self: ^Sand, from, to: int, grain: bool) -> bool #no_bounds_check {
	m := self.cells[to] & 15
	if m != EMPTY && !(grain && m == WATER) { return false }
	self.cells[from], self.cells[to] = self.cells[to], self.cells[from]
	self.moved[from] = 1
	self.moved[to] = 1
	return true
}

// One RGBA pixel per cell: the material's colour, darkened by its shade.
@(private = "file")
sand_write :: proc(self: ^Sand) #no_bounds_check {
	px := bytes_of(&self.image_data, len(self.cells) * 4)
	for c, i in self.cells {
		o := i * 4
		m := c & 15
		if m == EMPTY {
			px[o + 0], px[o + 1], px[o + 2] = BACKGROUND[0], BACKGROUND[1], BACKGROUND[2]
		} else {
			s := (c >> 4) * 3
			px[o + 0] = PALETTE[m][0] - s
			px[o + 1] = PALETTE[m][1] - s
			px[o + 2] = PALETTE[m][2] - s
		}
		px[o + 3] = 255
	}
}
