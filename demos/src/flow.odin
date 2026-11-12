package demos

import "../../godot"
import "core:math"

// Units that walk a flow field to a target cell. The field is each open cell's cost to the target
// (10 a straight step, 14 a diagonal), from Dijkstra over a binary heap, rebuilt when the target
// moves. A unit steps toward its cheapest neighbour; one that arrives starts again elsewhere.
Flow :: struct {
	// Units' speed (px/s) and how fast they turn to the field (1/s).
	speed:      f64 `range:"0,400,1"`,
	turn:       f64 `range:"0,40,0.1"`,
	// One 2D MultiMesh transform per unit, written by `step`.
	buffer:     godot.PackedFloat32Array,
	// RGBA8 pixels, one per cell: walls, and open cells shaded by their cost; written on rebuild.
	field_image: godot.PackedByteArray,

	cols, rows: int `godot:"-"`,
	cell:       f64 `godot:"-"`,
	walls:      []u8 `godot:"-"`,
	cost:       []i32 `godot:"-"`,
	heap:       [dynamic]i64 `godot:"-"`,
	target:     int `godot:"-"`,
	dirty:      bool `godot:"-"`,
	count:      int `godot:"-"`,
	px, py:     []f64 `godot:"-"`,
	vx, vy:     []f64 `godot:"-"`,
	// 1 for a unit that started the step on the target, which `flow_step` respawns after the walk.
	held:       []u8 `godot:"-"`,
	rng:        u32 `godot:"-"`,
	rebuilt:    i64 `godot:"-"`,
}

UNREACHED :: max(i32)

// The eight neighbours, straight ones first; a diagonal is open only when both straight cells
// beside it are.
@(rodata)
STEP_X := [8]int{1, -1, 0, 0, 1, -1, 1, -1}
@(rodata)
STEP_Y := [8]int{0, 0, 1, -1, 1, 1, -1, -1}

register_flow :: proc() {
	c := godot.class(Flow, "FlowOdin", "RefCounted", flow_notification)
	godot.fields(c, &Flow{speed = 90, turn = 6})
	godot.method(c, "setup", flow_setup, {"cols", "rows", "cell", "units", "seed"})
	godot.method(c, "set_target", flow_set_target, {"x", "y"})
	godot.method(c, "step", flow_step, {"delta"})
	godot.method(c, "cost_at", flow_cost_at, {"x", "y"})
	godot.method(c, "rebuilds", flow_rebuilds)
}

flow_notification :: proc(self: ^Flow, what: i64) {
	if what == PREDELETE { flow_free(self) }
}

flow_free :: proc(self: ^Flow) {
	delete(self.walls); delete(self.cost); delete(self.heap)
	delete(self.px); delete(self.py); delete(self.vx); delete(self.vy)
	delete(self.held)
	self.heap = nil
	self.count, self.cols, self.rows = 0, 0, 0
}

// A `cols` by `rows` grid of `cell`-pixel cells with random wall bars, and `units` units on open
// cells, all from `seed` (not 0). The target starts at the grid's centre.
flow_setup :: proc(self: ^Flow, cols, rows: i64, cell: f64, units, seed: i64) {
	assert(cols > 2 && rows > 2 && cell > 0 && units >= 0 && seed != 0)
	flow_free(self)
	self.cols, self.rows, self.cell = int(cols), int(rows), cell
	n := self.cols * self.rows
	self.walls = make([]u8, n)
	self.cost = make([]i32, n)
	self.rng = u32(seed)
	self.rebuilt = 0
	for _ in 0 ..< n / 90 {
		x := int(next_random(&self.rng) % u32(self.cols))
		y := int(next_random(&self.rng) % u32(self.rows))
		long := int(next_random(&self.rng) % 14) + 3
		across := next_random(&self.rng) & 1 == 0
		for k in 0 ..< long {
			wx, wy := x, y + k
			if across { wx, wy = x + k, y }
			if wx < self.cols && wy < self.rows { self.walls[wy * self.cols + wx] = 1 }
		}
	}
	self.target = (self.rows / 2) * self.cols + self.cols / 2
	self.walls[self.target] = 0
	self.dirty = true
	flow_rebuild(self)
	self.count = int(units)
	self.px = make([]f64, self.count); self.py = make([]f64, self.count)
	self.vx = make([]f64, self.count); self.vy = make([]f64, self.count)
	self.held = make([]u8, self.count)
	for u in 0 ..< self.count { flow_respawn(self, u) }
	flow_write(self)
}

// Moves the target to the cell under (`x`, `y`) (px), unless that cell is a wall or outside.
flow_set_target :: proc(self: ^Flow, x, y: f64) {
	if x < 0 || y < 0 { return }
	cx, cy := int(x / self.cell), int(y / self.cell)
	if cx >= self.cols || cy >= self.rows { return }
	c := cy * self.cols + cx
	if self.walls[c] != 0 || c == self.target { return }
	self.target = c
	self.dirty = true
}

// The field's cost at cell (`x`, `y`); -1 for a wall or a cell the target cannot reach.
flow_cost_at :: proc(self: ^Flow, x, y: i64) -> i64 {
	c := self.cost[int(y) * self.cols + int(x)]
	return -1 if c == UNREACHED else i64(c)
}

// Field rebuilds since `setup`, counting the one it does.
flow_rebuilds :: proc(self: ^Flow) -> i64 {
	return self.rebuilt
}

// Rebuilds the field if the target moved, then moves every unit `delta` seconds.
flow_step :: proc(self: ^Flow, delta: f64) {
	flow_rebuild(self)
	job := Walk_Job{self, delta}
	chunks := (self.count + WALK_CHUNK - 1) / WALK_CHUNK
	if chunks > 1 {
		godot.wait_group(godot.run_group(walk_chunk, &job, chunks))
	} else if chunks == 1 {
		walk_chunk(&job, 0)
	}
	// Respawns draw from the shared generator, so they run here, in unit order, as the loop the
	// GDScript version runs would draw them.
	for u in 0 ..< self.count {
		if self.held[u] != 0 { flow_respawn(self, u) }
	}
	flow_write(self)
}

// Units per worker task. A unit's walk reads only the field and writes only that unit, so the
// ranges run in parallel; a unit on the target is only marked, for `flow_step` to respawn.
WALK_CHUNK :: 512

@(private = "file")
Walk_Job :: struct {
	self:  ^Flow,
	delta: f64,
}

// Walks chunk `k`'s units. Runs on a worker thread, so it must not call into the engine.
@(private = "file")
walk_chunk :: proc(job: ^Walk_Job, k: int) {
	lo := k * WALK_CHUNK
	hi := min(lo + WALK_CHUNK, job.self.count)
	for u in lo ..< hi { flow_walk(job.self, u, job.delta) }
}

// Dijkstra from the target. Heap entries are cost << 32 | cell, so the smallest entry is the
// cheapest cell; a stale entry, whose cost is above the cell's, is skipped.
@(private = "file")
flow_rebuild :: proc(self: ^Flow) #no_bounds_check {
	if !self.dirty { return }
	self.dirty = false
	self.rebuilt += 1
	for &c in self.cost { c = UNREACHED }
	clear(&self.heap)
	self.cost[self.target] = 0
	append(&self.heap, i64(self.target))
	for pops := 0; len(self.heap) > 0; pops += 1 {
		assert(pops <= 8 * len(self.cost))
		top := heap_pop(&self.heap)
		d := i32(top >> 32)
		c := int(top & 0xFFFFFFFF)
		if d > self.cost[c] { continue }
		cx, cy := c % self.cols, c / self.cols
		for k in 0 ..< 8 {
			n := flow_neighbour(self, cx, cy, k)
			if n < 0 { continue }
			nd := d + (10 if k < 4 else 14)
			if nd >= self.cost[n] { continue }
			self.cost[n] = nd
			heap_push(&self.heap, i64(nd) << 32 | i64(n))
		}
	}
	flow_paint(self)
}

// Cell index of neighbour `k` of (`cx`, `cy`), or -1 for outside, a wall, or a diagonal past a
// corner.
@(private = "file")
flow_neighbour :: #force_inline proc "contextless" (self: ^Flow, cx, cy, k: int) -> int #no_bounds_check {
	nx, ny := cx + STEP_X[k], cy + STEP_Y[k]
	if nx < 0 || ny < 0 || nx >= self.cols || ny >= self.rows { return -1 }
	if self.walls[ny * self.cols + nx] != 0 { return -1 }
	if k >= 4 && (self.walls[cy * self.cols + nx] != 0 || self.walls[ny * self.cols + cx] != 0) { return -1 }
	return ny * self.cols + nx
}

@(private = "file")
heap_push :: proc(h: ^[dynamic]i64, v: i64) #no_bounds_check {
	append(h, v)
	i := len(h) - 1
	for i > 0 {
		p := (i - 1) / 2
		if h[p] <= h[i] { break }
		h[p], h[i] = h[i], h[p]
		i = p
	}
}

@(private = "file")
heap_pop :: proc(h: ^[dynamic]i64) -> i64 #no_bounds_check {
	top := h[0]
	last := pop(h)
	n := len(h)
	if n == 0 { return top }
	h[0] = last
	i := 0
	for {
		l := 2 * i + 1
		if l >= n { break }
		m := l
		if l + 1 < n && h[l + 1] < h[l] { m = l + 1 }
		if h[i] <= h[m] { break }
		h[i], h[m] = h[m], h[i]
		i = m
	}
	return top
}

// Unit `u` on a random open cell the target can reach, at rest; it stays put after 64 misses.
@(private = "file")
flow_respawn :: proc(self: ^Flow, u: int) {
	for _ in 0 ..< 64 {
		c := int(next_random(&self.rng) % u32(len(self.cost)))
		if self.cost[c] == UNREACHED || c == self.target { continue }
		self.px[u] = (f64(c % self.cols) + 0.5) * self.cell
		self.py[u] = (f64(c / self.cols) + 0.5) * self.cell
		self.vx[u], self.vy[u] = 0, 0
		return
	}
}

// Steers unit `u` toward its cell's cheapest neighbour and moves it, sliding along walls. A unit
// on the target stays put and is marked in `held` instead.
@(private = "file")
flow_walk :: proc(self: ^Flow, u: int, delta: f64) #no_bounds_check {
	x, y := self.px[u], self.py[u]
	cx, cy := int(x / self.cell), int(y / self.cell)
	c := cy * self.cols + cx
	self.held[u] = u8(c == self.target)
	if c == self.target { return }
	best, best_cost := -1, self.cost[c]
	for k in 0 ..< 8 {
		n := flow_neighbour(self, cx, cy, k)
		if n >= 0 && self.cost[n] < best_cost { best, best_cost = n, self.cost[n] }
	}
	wx, wy := 0.0, 0.0
	if best >= 0 {
		ox := (f64(best % self.cols) + 0.5) * self.cell - x
		oy := (f64(best / self.cols) + 0.5) * self.cell - y
		l := math.sqrt(ox * ox + oy * oy)
		wx, wy = ox / l * self.speed, oy / l * self.speed
	}
	t := min(self.turn * delta, 1.0)
	vx := self.vx[u] + (wx - self.vx[u]) * t
	vy := self.vy[u] + (wy - self.vy[u]) * t
	nx, ny := x + vx * delta, y + vy * delta
	if flow_blocked(self, nx, y) { nx, vx = x, 0 }
	if flow_blocked(self, nx, ny) { ny, vy = y, 0 }
	self.px[u], self.py[u], self.vx[u], self.vy[u] = nx, ny, vx, vy
}

// Whether (`x`, `y`) (px) is outside the grid or in a wall.
@(private = "file")
flow_blocked :: #force_inline proc "contextless" (self: ^Flow, x, y: f64) -> bool #no_bounds_check {
	if x < 0 || y < 0 { return true }
	cx, cy := int(x / self.cell), int(y / self.cell)
	if cx >= self.cols || cy >= self.rows { return true }
	return self.walls[cy * self.cols + cx] != 0
}

// One transform per unit, facing along its velocity, or along +x at rest.
@(private = "file")
flow_write :: proc(self: ^Flow) #no_bounds_check {
	buf := floats_of(&self.buffer, self.count * 8)
	for u in 0 ..< self.count {
		ux, uy := 1.0, 0.0
		s := math.sqrt(self.vx[u] * self.vx[u] + self.vy[u] * self.vy[u])
		if s > 0 {
			ux = self.vx[u] / s
			uy = self.vy[u] / s
		}
		put_transform(buf, u, ux, uy, self.px[u], self.py[u])
	}
}

// The field as pixels: walls grey, unreached cells black, open cells banded by cost.
@(private = "file")
flow_paint :: proc(self: ^Flow) #no_bounds_check {
	px := bytes_of(&self.field_image, len(self.cost) * 4)
	for c, i in self.cost {
		o := i * 4
		r, g, b: u8
		if self.walls[i] != 0 {
			r, g, b = 90, 90, 100
		} else if c != UNREACHED {
			band := u8((c / 10) % 32)
			r, g, b = 20 + band, 30 + band * 2, 60 + band * 3
		}
		px[o + 0], px[o + 1], px[o + 2], px[o + 3] = r, g, b, 255
	}
}
