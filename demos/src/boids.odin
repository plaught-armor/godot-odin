package demos

import "../../godot"
import "core:math"

// A flock on a wrapping field. Each boid steers by its neighbours within `radius`, found through
// a grid of `radius`-sized cells rebuilt each step by counting sort.
Boids :: struct {
	// How far a boid sees its neighbours (px).
	radius:     f64 `range:"4,64,1"`,
	// Neighbours closer than this push the boid away (px).
	personal:   f64 `range:"1,32,1"`,
	// Weights of the three rules.
	separation: f64 `range:"0,4000,1"`,
	alignment:  f64 `range:"0,8,0.01"`,
	cohesion:   f64 `range:"0,8,0.01"`,
	// Speed limits (px/s).
	min_speed:  f64 `range:"0,400,1"`,
	max_speed:  f64 `range:"0,400,1"`,
	// One 2D MultiMesh transform per boid, written by `step`.
	buffer:     godot.PackedFloat32Array,

	count:      int `godot:"-"`,
	width:      f64 `godot:"-"`,
	height:     f64 `godot:"-"`,
	cols, rows: int `godot:"-"`,
	px, py:     []f64 `godot:"-"`,
	vx, vy:     []f64 `godot:"-"`,
	nvx, nvy:   []f64 `godot:"-"`,
	// Boids sorted by cell: cell c's boids are items[start[c]:start[c + 1]].
	start:      []i32 `godot:"-"`,
	cursor:     []i32 `godot:"-"`,
	items:      []i32 `godot:"-"`,
	cell_of:    []i32 `godot:"-"`,
	// The pointer pushes boids within `POINTER_RADIUS` away with this strength; 0 when idle.
	pointer_x:  f64 `godot:"-"`,
	pointer_y:  f64 `godot:"-"`,
	pointer:    f64 `godot:"-"`,
}

POINTER_RADIUS :: 120.0

register_boids :: proc() {
	c := godot.class(Boids, "BoidsOdin", "RefCounted", boids_notification)
	godot.fields(c, &Boids{radius = 24, personal = 10, separation = 600, alignment = 1.2, cohesion = 0.9, min_speed = 60, max_speed = 160})
	godot.method(c, "setup", boids_setup, {"count", "width", "height", "seed"})
	godot.method(c, "step", boids_step, {"delta"})
	godot.method(c, "set_pointer", boids_set_pointer, {"x", "y", "strength"})
}

boids_notification :: proc(self: ^Boids, what: i64) {
	if what == PREDELETE { boids_free(self) }
}

boids_free :: proc(self: ^Boids) {
	delete(self.px); delete(self.py); delete(self.vx); delete(self.vy)
	delete(self.nvx); delete(self.nvy)
	delete(self.start); delete(self.cursor); delete(self.items); delete(self.cell_of)
	self.count = 0
}

// Scatters `count` boids over a `width` by `height` field (px) from `seed`, which must not be 0.
boids_setup :: proc(self: ^Boids, count: i64, width, height: f64, seed: i64) {
	assert(count >= 0 && seed != 0 && width >= 3 * self.radius && height >= 3 * self.radius)
	boids_free(self)
	n := int(count)
	self.count = n
	self.width, self.height = width, height
	self.cols = int(width / self.radius)
	self.rows = int(height / self.radius)
	self.px = make([]f64, n); self.py = make([]f64, n)
	self.vx = make([]f64, n); self.vy = make([]f64, n)
	self.nvx = make([]f64, n); self.nvy = make([]f64, n)
	self.start = make([]i32, self.cols * self.rows + 1)
	self.cursor = make([]i32, self.cols * self.rows)
	self.items = make([]i32, n)
	self.cell_of = make([]i32, n)
	rng := u32(seed)
	for i in 0 ..< n {
		self.px[i] = random_unit(&rng) * width
		self.py[i] = random_unit(&rng) * height
		self.vx[i] = (random_unit(&rng) * 2 - 1) * self.max_speed
		self.vy[i] = (random_unit(&rng) * 2 - 1) * self.max_speed
	}
	self.pointer = 0
	boids_write(self)
}

// Pushes boids near (`x`, `y`) away with `strength` from the next step on; 0 stops it.
boids_set_pointer :: proc(self: ^Boids, x, y, strength: f64) {
	self.pointer_x, self.pointer_y, self.pointer = x, y, strength
}

// Advances the flock `delta` seconds and writes `buffer`.
boids_step :: proc(self: ^Boids, delta: f64) {
	boids_bin(self)
	for i in 0 ..< self.count { boids_steer(self, i, delta) }
	boids_move(self, delta)
	boids_write(self)
}

// Sorts the boids into cells: a count per cell, its prefix sum, then each boid in index order.
@(private = "file")
boids_bin :: proc(self: ^Boids) #no_bounds_check {
	cell_w := self.width / f64(self.cols)
	cell_h := self.height / f64(self.rows)
	for &s in self.start { s = 0 }
	for i in 0 ..< self.count {
		cx := min(int(self.px[i] / cell_w), self.cols - 1)
		cy := min(int(self.py[i] / cell_h), self.rows - 1)
		c := cy * self.cols + cx
		self.cell_of[i] = i32(c)
		self.start[c + 1] += 1
	}
	for c in 0 ..< self.cols * self.rows {
		self.start[c + 1] += self.start[c]
		self.cursor[c] = self.start[c]
	}
	for i in 0 ..< self.count {
		c := self.cell_of[i]
		self.items[self.cursor[c]] = i32(i)
		self.cursor[c] += 1
	}
}

// Boid `i`'s new velocity from the three rules over its neighbours and the pointer, clamped to the
// speed limits.
@(private = "file")
boids_steer :: proc(self: ^Boids, i: int, delta: f64) #no_bounds_check {
	r2 := self.radius * self.radius
	p2 := self.personal * self.personal
	half_w, half_h := self.width * 0.5, self.height * 0.5
	x, y := self.px[i], self.py[i]
	home := int(self.cell_of[i])
	hx, hy := home % self.cols, home / self.cols
	seen := 0
	ax, ay, cx, cy, sx, sy: f64
	for dy in -1 ..= 1 {
		ry := (hy + dy + self.rows) % self.rows
		for dx in -1 ..= 1 {
			c := ry * self.cols + (hx + dx + self.cols) % self.cols
			for k in self.start[c] ..< self.start[c + 1] {
				j := int(self.items[k])
				if j == i { continue }
				ox := self.px[j] - x
				oy := self.py[j] - y
				if ox > half_w { ox -= self.width } else if ox < -half_w { ox += self.width }
				if oy > half_h { oy -= self.height } else if oy < -half_h { oy += self.height }
				d2 := ox * ox + oy * oy
				if d2 >= r2 { continue }
				seen += 1
				ax += self.vx[j]
				ay += self.vy[j]
				cx += ox
				cy += oy
				if d2 < p2 && d2 > 0 {
					sx -= ox / d2
					sy -= oy / d2
				}
			}
		}
	}
	fx, fy: f64
	if seen > 0 {
		n := f64(seen)
		fx = (ax / n - self.vx[i]) * self.alignment + (cx / n) * self.cohesion + sx * self.separation
		fy = (ay / n - self.vy[i]) * self.alignment + (cy / n) * self.cohesion + sy * self.separation
	}
	if self.pointer != 0 {
		ox := x - self.pointer_x
		oy := y - self.pointer_y
		d2 := ox * ox + oy * oy
		if d2 < POINTER_RADIUS * POINTER_RADIUS && d2 > 0 {
			fx += ox / d2 * self.pointer
			fy += oy / d2 * self.pointer
		}
	}
	vx := self.vx[i] + fx * delta
	vy := self.vy[i] + fy * delta
	s := math.sqrt(vx * vx + vy * vy)
	if s > self.max_speed {
		vx *= self.max_speed / s
		vy *= self.max_speed / s
	} else if s < self.min_speed && s > 0 {
		vx *= self.min_speed / s
		vy *= self.min_speed / s
	}
	self.nvx[i] = vx
	self.nvy[i] = vy
}

// Takes the new velocities and moves every boid, wrapping at the edges.
@(private = "file")
boids_move :: proc(self: ^Boids, delta: f64) #no_bounds_check {
	self.vx, self.nvx = self.nvx, self.vx
	self.vy, self.nvy = self.nvy, self.vy
	for i in 0 ..< self.count {
		x := self.px[i] + self.vx[i] * delta
		y := self.py[i] + self.vy[i] * delta
		if x < 0 { x += self.width } else if x >= self.width { x -= self.width }
		if y < 0 { y += self.height } else if y >= self.height { y -= self.height }
		self.px[i] = x
		self.py[i] = y
	}
}

// One transform per boid, facing along its velocity.
@(private = "file")
boids_write :: proc(self: ^Boids) #no_bounds_check {
	buf := floats_of(&self.buffer, self.count * 8)
	for i in 0 ..< self.count {
		ux, uy := 1.0, 0.0
		s := math.sqrt(self.vx[i] * self.vx[i] + self.vy[i] * self.vy[i])
		if s > 0 {
			ux = self.vx[i] / s
			uy = self.vy[i] / s
		}
		put_transform(buf, i, ux, uy, self.px[i], self.py[i])
	}
}
