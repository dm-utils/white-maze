// Native port of the movement part of MazeSim (sim/sim.gd, sim/slope.gd) and the par search of tools/search_par.gd.
// Design 23.10.4, ADR 0017. Kept equal to the GDScript simulation by tools/check_solver.sh (tick-for-tick trace).
// Rule: a change of movement in sim/sim.gd or sim/slope.gd changes this file in the same commit.
//
//   maze_solver trace <levels.txt> <cases.txt>      case <n> <level> <x,y,face;...|-> <px,py|-> <run script>
//   maze_solver search <levels.txt> --level=<id> [--rings="x,y,face;..."] [--k=4] [--nodes=N] [--weight=W]
//   maze_solver search <levels.txt> --level=<id> --subset=N [--faces=x0,y0,x1,y1] [--anchor=x0,y0,x1,y1] [--part=i/n]
//
// Not ported: throws, undo, flights, cast (the search pre-places rings as presets).

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <queue>
#include <sstream>
#include <string>
#include <vector>

namespace {

// int32 is enough: levels are at most 256 x 64 tiles of 40000 units (about 10.3 million), no product of two states
typedef int32_t num;

// ---- tuning (sim/tuning.gd, integer values) ----
constexpr num TILE = 40000;
constexpr num RUN_SPEED = 5000;
constexpr num GROUND_ACCEL = 667;
constexpr num GROUND_DECEL = 833;
constexpr num AIR_ACCEL = 444;
constexpr num AIR_TURN = 556;
constexpr num AIR_DRAG = 83;
constexpr num JUMP_SPEED = 13333;
constexpr num GRAVITY_UP = 667;
constexpr num GRAVITY_DOWN = 1000;
constexpr num APEX_THRESHOLD = 1000;
constexpr num APEX_GRAVITY = 333;
constexpr num MAX_FALL = 15000;
constexpr num COYOTE_TICKS = 6;
constexpr num JUMP_BUFFER_TICKS = 8;
constexpr num CORNER_CORRECTION = 8000;
constexpr num FLOOR_LAUNCH = 18000;
constexpr num WALL_LAUNCH_X = 10667;
constexpr num WALL_LAUNCH_LIFT = 9333;
constexpr num CEILING_LAUNCH = 15000;
constexpr num WALL_LOCK_TICKS = 12;
constexpr num RING_COOLDOWN_TICKS = 10;
constexpr num DEATH_TICKS = 30;
constexpr num PLAYER_W = 30000;
constexpr num PLAYER_H = 32000;
constexpr num HAZARD_INSET = 4000;
constexpr num RING_DEPTH = 8000;
constexpr num RING_INSET = 4000;
constexpr num SPIKE_INSET = 4000;
constexpr num SLIDE_SPEED = 6000;
constexpr num SLIDE_FAST = 8000;
constexpr num SLIDE_SLOW = 4000;
constexpr num SLIDE_ACCEL = 500;
constexpr num SLOPE_STEP = 16000;
constexpr num SLOPE_SNAP = 16000;
constexpr num HW = PLAYER_W / 2;

enum Cell { EMPTY, SOLID, NO_RING, SPIKE, STEEP_R, STEEP_L, GENTLE_R_LO, GENTLE_R_HI, GENTLE_L_HI, GENTLE_L_LO };
enum Face { UP, DOWN, LEFT, RIGHT };
enum Ground { NONE, FLAT, GENTLE, STEEP };

const char* const CHARS = ".#X^/\\rRLl";
const char* const FACE_NAMES[4] = {"up", "down", "left", "right"};
const int FACE_DX[4] = {0, 0, -1, 1};
const int FACE_DY[4] = {-1, 1, 0, 0};

// ---- slope geometry (sim/slope.gd) ----
bool is_slope(int kind) { return kind >= STEEP_R && kind <= GENTLE_L_LO; }
bool steep(int kind) { return kind == STEEP_R || kind == STEEP_L; }

int downhill(int kind) {
	switch (kind) {
		case STEEP_R:
		case GENTLE_R_LO:
		case GENTLE_R_HI:
			return -1;
	}
	return 1;
}

int high_side(int kind) {
	switch (kind) {
		case STEEP_R:
		case GENTLE_R_HI:
			return RIGHT;
		case STEEP_L:
		case GENTLE_L_HI:
			return LEFT;
	}
	return -1;
}

num surface(int kind, num cy, num lx) {
	num b = cy * TILE;
	switch (kind) {
		case STEEP_R:
			return b + TILE - lx;
		case STEEP_L:
			return b + lx;
		case GENTLE_R_LO:
			return b + TILE - lx / 2;
		case GENTLE_R_HI:
			return b + TILE / 2 - lx / 2;
		case GENTLE_L_HI:
			return b + lx / 2;
		case GENTLE_L_LO:
			return b + TILE / 2 + lx / 2;
	}
	return b + TILE;
}

// ---- helpers (sim/sim.gd statics) ----
num fdiv(num a, num b) { return a >= 0 ? a / b : -((-a + b - 1) / b); }
num posmod(num a, num b) { return ((a % b) + b) % b; }
num approach(num v, num target, num rate) { return v < target ? std::min(v + rate, target) : std::max(v - rate, target); }
num sgn(num v) { return v > 0 ? 1 : (v < 0 ? -1 : 0); }

struct Rect {
	num x, y, w, h;
	bool intersects(const Rect& o) const {
		if (x >= o.x + o.w || x + w <= o.x) return false;
		if (y >= o.y + o.h || y + h <= o.y) return false;
		return true;
	}
};

struct Ring {
	num x, y;
	int face;
	Rect zone;
};

Rect ring_zone(num cx, num cy, int face) {
	num d = RING_DEPTH, i = RING_INSET, x0 = cx * TILE, y0 = cy * TILE;
	switch (face) {
		case UP:
			return {x0 + i, y0 - d, TILE - 2 * i, d + 1};
		case DOWN:
			return {x0 + i, y0 + TILE - 1, TILE - 2 * i, d + 1};
		case LEFT:
			return {x0 - d, y0 + i, d + 1, TILE - 2 * i};
	}
	return {x0 + TILE - 1, y0 + i, d + 1, TILE - 2 * i};
}

constexpr int MAX_RINGS = 24;

struct Level {
	std::string id;
	num width = 0, height = 0;
	int beads = 0, par = 0;
	bool sky = false;
	std::vector<uint8_t> cells;
	int spawn_x = 0, spawn_y = 0, finish_x = 0, finish_y = 0;
	int slope_count = 0;
	std::vector<Ring> presets;  // from the level file
	std::vector<Ring> rings;    // presets plus the extras of one case or search set

	// out of bounds left, right, top: NO_RING; below: EMPTY
	int cell(num x, num y) const {
		if (x < 0 || x >= width || y < 0) return NO_RING;
		if (y >= height) return EMPTY;
		return cells[y * width + x];
	}
	bool solid(num x, num y) const {
		int c = cell(x, y);
		return c == SOLID || c == NO_RING;
	}
	bool covered(num x, num y) const { return solid(x, y) || is_slope(cell(x, y)); }
};

// ---- simulation state ----
struct Input {
	int8_t move = 0;
	bool held = false;
	bool pressed = false;
};

struct Sim {
	const Level* lv = nullptr;
	num tick = 0, px = 0, py = 0, vx = 0, vy = 0, facing = 1;
	num ground = NONE;
	num coyote = 0, buffer = 0, lock_ticks = 0, dead_ticks = 0, rings_used = 0;
	bool grounded = false, jumping = false, launched = false, finished = false;
	uint8_t cooldown[MAX_RINGS] = {0};

	explicit Sim(const Level* l) : lv(l) { respawn(); }
	Sim() = default;

	void respawn() {
		px = lv->spawn_x * TILE + TILE / 2;
		py = (lv->spawn_y + 1) * TILE;
		vx = 0;
		vy = 0;
		facing = 1;
		jumping = false;
		launched = false;
		lock_ticks = 0;
		coyote = 0;
		buffer = 0;
		compute_ground();
	}

	// ground kind of the slope under (x, y): (kind, row) or kind -1
	bool slope_under(num x, num y, int* kind, num* row) const {
		if (lv->slope_count == 0) return false;
		num cx = fdiv(x, TILE);
		num rows[2] = {fdiv(y - 1, TILE), fdiv(y, TILE)};
		for (num cy : rows) {
			int k = lv->cell(cx, cy);
			if (is_slope(k)) {
				*kind = k;
				*row = cy;
				return true;
			}
		}
		return false;
	}

	int ground_kind() const {
		if (ground != GENTLE && ground != STEEP) return -1;
		int k;
		num r;
		return slope_under(px, py, &k, &r) ? k : -1;
	}

	void compute_ground() {
		int k;
		num r;
		if (slope_under(px, py, &k, &r) && py == surface(k, r, px - fdiv(px, TILE) * TILE)) {
			ground = steep(k) ? STEEP : GENTLE;
		} else if (posmod(py, TILE) == 0 && (solid_in_cols(py / TILE, px - HW, px + HW) || on_gable_top(py / TILE))) {
			ground = FLAT;
		} else {
			ground = NONE;
		}
		grounded = ground != NONE;
	}

	bool box_free(num left, num top, num right, num bottom) const {
		for (num cy = fdiv(top, TILE); cy <= fdiv(bottom - 1, TILE); cy++)
			for (num cx = fdiv(left, TILE); cx <= fdiv(right - 1, TILE); cx++)
				if (lv->solid(cx, cy)) return false;
		return true;
	}

	bool solid_in_rows(num cx, num top, num bottom) const {
		for (num cy = fdiv(top, TILE); cy <= fdiv(bottom - 1, TILE); cy++)
			if (lv->solid(cx, cy)) return true;
		return false;
	}

	bool solid_in_cols(num cy, num left, num right) const {
		for (num cx = fdiv(left, TILE); cx <= fdiv(right - 1, TILE); cx++)
			if (lv->solid(cx, cy)) return true;
		return false;
	}

	// top corner of a slope's full-height high side in a box column beside the centre, facing the centre
	bool on_gable_top(num cy) const {
		num c = fdiv(px, TILE);
		if (lv->slope_count == 0 || is_slope(lv->cell(c, cy))) return false;
		for (num cx = fdiv(px - HW, TILE); cx <= fdiv(px + HW - 1, TILE); cx++)
			if (cx != c && high_side(lv->cell(cx, cy)) == (cx > c ? LEFT : RIGHT)) return true;
		return false;
	}

	void step(const Input& in) {
		tick++;
		if (finished) return;
		for (size_t i = 0; i < lv->rings.size(); i++)
			if (cooldown[i] > 0) cooldown[i]--;
		if (dead_ticks > 0) {
			dead_ticks--;
			if (dead_ticks == 0) respawn();
			return;
		}
		horizontal(in);
		jump(in);
		gravity(in);
		move(in.move);
		launch_from_rings();
		if (hazard_hit()) {
			dead_ticks = DEATH_TICKS;
			vx = 0;
			vy = 0;
			return;
		}
		Rect box = {px - HW, py - PLAYER_H, PLAYER_W, PLAYER_H};
		if (box.intersects({lv->finish_x * TILE, lv->finish_y * TILE, TILE, TILE})) finished = true;
	}

	void horizontal(const Input& in) {
		num mv = in.move;
		num target = mv * RUN_SPEED;
		if (lock_ticks > 0) {
			lock_ticks--;
			return;
		}
		if (grounded && ground == STEEP) {
			num d = downhill(ground_kind());
			num goal = d * SLIDE_SPEED;
			if (mv == d)
				goal = d * SLIDE_FAST;
			else if (mv == -d)
				goal = d * SLIDE_SLOW;
			vx = approach(vx, goal, SLIDE_ACCEL);
			if (mv != 0) facing = mv;
			return;
		}
		bool same_dir = vx == 0 || (mv != 0 && sgn(mv) == sgn(vx));
		bool slow = std::abs(vx) <= RUN_SPEED;
		if (grounded)
			vx = approach(vx, target, (same_dir && slow) ? GROUND_ACCEL : GROUND_DECEL);
		else if (mv == 0)
			vx = approach(vx, 0, AIR_DRAG);
		else if (same_dir)
			vx = approach(vx, target, slow ? AIR_ACCEL : AIR_DRAG);
		else
			vx = approach(vx, target, AIR_TURN);
		if (mv != 0) facing = mv;
	}

	void jump(const Input& in) {
		// check the counters as left by the previous tick, then update them
		bool can_jump = grounded || coyote > 0;
		bool wants_jump = in.pressed || buffer > 0;
		coyote = grounded ? COYOTE_TICKS : std::max(0, coyote - 1);
		buffer = in.pressed ? JUMP_BUFFER_TICKS : std::max(0, buffer - 1);
		if (can_jump && wants_jump) {
			vy = -JUMP_SPEED;
			jumping = true;
			launched = false;
			buffer = 0;
			coyote = 0;
			grounded = false;
		}
	}

	void gravity(const Input& in) {
		num g = GRAVITY_DOWN;
		if (jumping && in.held && std::abs(vy) < APEX_THRESHOLD)
			g = APEX_GRAVITY;
		else if (vy < 0 && ((jumping && in.held) || launched))
			g = GRAVITY_UP;
		vy = std::min(vy + g, MAX_FALL);
	}

	void move(num mv) {
		num start = ground;
		bool was_grounded = grounded;
		num vy_before = vy;
		num allow = (start == GENTLE || start == STEEP) ? SLOPE_STEP : 0;
		num ox = px, oy = py;
		move_x(allow);
		if (lv->slope_count > 0) {
			if (start == FLAT)
				stop_at_toe(ox);
			else if (start != NONE)
				leave_roof_top(ox);
		}
		if (lv->slope_count > 0 && lift(allow)) {
			px = ox;
			py = oy;
			vx = 0;
		}
		bool landed = move_y();
		compute_ground();
		if (lv->slope_count > 0 && was_grounded && vy >= 0) {
			if (ground == NONE)
				snap(start, false);
			else if (ground == FLAT)
				snap(start, true);  // leaving a slope past a block corner, or walking off a floor onto a falling roof
		}
		if (grounded && vy > 0) {
			vy = 0;
			landed = true;
		}
		if (landed) {
			jumping = false;
			launched = false;
			if (!was_grounded && ground == STEEP) vx = (vx + downhill(ground_kind()) * vy_before) / 2;
		}
		if (ground == STEEP && start != STEEP) {
			num d = downhill(ground_kind());
			if (mv == 0) facing = d;
		}
		if (vy >= APEX_THRESHOLD) jumping = false;
		if (vy >= 0) launched = false;
	}

	static bool toe(int kind, num dir) { return steep(kind) && downhill(kind) == -dir; }

	// walking up to the low end of a steep roof from a floor: stop at the toe, the roof is not climbed
	void stop_at_toe(num ox) {
		num dir = sgn(px - ox);
		if (dir == 0) return;
		num row = fdiv(py - 1, TILE);
		num front = dir > 0 ? fdiv(px + HW - 1, TILE) : fdiv(px - HW, TILE);
		int kind = lv->cell(front, row);
		num was = dir > 0 ? fdiv(ox + HW - 1, TILE) : fdiv(ox - HW, TILE);
		if (front != was && toe(kind, dir)) {
			px = dir > 0 ? std::max(ox, front * TILE - HW) : std::min(ox, (front + 1) * TILE + HW);
			vx = 0;
			return;
		}
		num centre = fdiv(px, TILE);
		if (centre != fdiv(ox, TILE) && toe(lv->cell(centre, row), dir)) {
			px = ox;
			vx = 0;
		}
	}

	// walking off the top of a roof past a wall: the feet go to the wall's top corner
	void leave_roof_top(num ox) {
		if (fdiv(px, TILE) == fdiv(ox, TILE)) return;
		num row = fdiv(py - 1, TILE);
		if (py > row * TILE && py - row * TILE <= std::abs(px - ox) && on_gable_top(row)) py = row * TILE;
	}

	// true when the lift put the box into a full block outside the step band
	bool lift(num allow) {
		num cx = fdiv(px, TILE);
		num cy = fdiv(py - 1, TILE);
		int kind = lv->cell(cx, cy);
		num before = py;
		if (is_slope(kind)) {
			py = std::min(py, surface(kind, cy, px - cx * TILE));
		} else if (allow > 0 && lv->solid(cx, cy) && py - cy * TILE <= allow) {
			// a roof standing on this block is the floor, not the block top
			int above = lv->cell(cx, cy - 1);
			if (is_slope(above))
				py = std::min(py, surface(above, cy - 1, px - cx * TILE));
			else
				py = cy * TILE;
		}
		if (py == before) return false;
		return !box_free(px - HW, py - PLAYER_H, px + HW, py - allow);
	}

	// keep the feet on the roof: nearest support below within SLOPE_SNAP + abs(vx)
	void snap(num start, bool slope_only) {
		num reach = SLOPE_SNAP + std::abs(vx);
		num floor_y = -1;
		for (num cy = fdiv(py + TILE - 1, TILE); cy <= fdiv(py + reach, TILE); cy++) {
			if (solid_in_cols(cy, px - HW, px + HW)) {
				floor_y = cy * TILE;
				break;
			}
		}
		num slope_y = -1;
		num cx = fdiv(px, TILE);
		for (num cy = fdiv(py - 1, TILE); cy <= fdiv(py + reach, TILE); cy++) {
			int kind = lv->cell(cx, cy);
			if (is_slope(kind)) {
				num sy = surface(kind, cy, px - cx * TILE);
				if (sy >= py && sy <= py + reach) {
					slope_y = sy;
					break;
				}
			}
		}
		if (slope_only && slope_y < 0) return;
		// on a roof the slope under the centre wins over a nearer block corner at the high end of the next slope
		bool on_slope = slope_y >= 0 && (slope_only || start != FLAT || floor_y < 0 || slope_y <= floor_y);
		num support = on_slope ? slope_y : floor_y;
		if (support < 0 || support > py + reach) return;
		if (!(start == GENTLE || start == STEEP || on_slope)) return;
		py = support;
		vy = 0;
		compute_ground();
	}

	// full blocks in rows top..bottom of column cx, or a slope whose vertical high side faces the mover
	bool blocks_x(num cx, num top, num bottom, num dir) const {
		if (solid_in_rows(cx, top, bottom)) return true;
		if (lv->slope_count == 0) return false;
		for (num cy = fdiv(top, TILE); cy <= fdiv(bottom - 1, TILE); cy++)
			if (high_side(lv->cell(cx, cy)) == (dir > 0 ? LEFT : RIGHT)) return true;
		return false;
	}

	void move_x(num allow) {
		if (vx == 0) return;
		num top = py - PLAYER_H;
		num bottom = py - allow;
		if (vx > 0) {
			for (num cx = fdiv(px + HW - 1, TILE) + 1; cx <= fdiv(px + vx + HW - 1, TILE); cx++) {
				if (blocks_x(cx, top, bottom, 1)) {
					px = cx * TILE - HW;
					vx = 0;
					return;
				}
			}
		} else {
			for (num cx = fdiv(px - HW, TILE) - 1; cx > fdiv(px + vx - HW, TILE) - 1; cx--) {
				if (blocks_x(cx, top, bottom, -1)) {
					px = (cx + 1) * TILE + HW;
					vx = 0;
					return;
				}
			}
		}
		px += vx;
	}

	// true when the player lands
	bool move_y() {
		if (vy > 0) {
			num floor_y = -1;
			for (num cy = fdiv(py - 1, TILE) + 1; cy <= fdiv(py + vy - 1, TILE); cy++) {
				if (solid_in_cols(cy, px - HW, px + HW) || on_gable_top(cy)) {
					floor_y = cy * TILE;
					break;
				}
			}
			if (lv->slope_count > 0) {
				num cx = fdiv(px, TILE);
				for (num cy = fdiv(py - 1, TILE); cy <= fdiv(py + vy, TILE); cy++) {
					int kind = lv->cell(cx, cy);
					if (is_slope(kind)) {
						num sy = surface(kind, cy, px - cx * TILE);
						if (sy >= py && sy <= py + vy && (floor_y < 0 || sy < floor_y)) floor_y = sy;
						break;
					}
				}
			}
			if (floor_y >= 0) {
				py = floor_y;
				vy = 0;
				return true;
			}
			py += vy;
		} else if (vy < 0) {
			move_up();
		}
		return false;
	}

	void move_up() {
		num new_py = py + vy;
		num new_top = new_py - PLAYER_H;
		num left = px - HW;
		num right = px + HW;
		num c_lo = fdiv(left, TILE);
		num c_hi = fdiv(right - 1, TILE);
		bool lo_blocked = false, hi_blocked = false, mid_blocked = false;
		int blocked = 0;
		num lowest_row = -1000000;
		for (num cy = fdiv(new_top, TILE); cy <= fdiv(py - PLAYER_H - 1, TILE); cy++) {
			for (num cx = c_lo; cx <= c_hi; cx++) {
				if (lv->solid(cx, cy)) {
					bool was = cx == c_lo ? lo_blocked : (cx == c_hi ? hi_blocked : mid_blocked);
					if (!was) blocked++;
					if (cx == c_lo)
						lo_blocked = true;
					else if (cx == c_hi)
						hi_blocked = true;
					else
						mid_blocked = true;
					lowest_row = std::max(lowest_row, cy);
				}
			}
		}
		if (blocked == 0) {
			py = new_py;
			return;
		}
		// corner correction: head clips a corner by a few px, slide off it
		num shift = 0;
		num left_overlap = (c_lo + 1) * TILE - left;
		num right_overlap = right - c_hi * TILE;
		if (blocked == 1 && lo_blocked && left_overlap <= CORNER_CORRECTION)
			shift = left_overlap;
		else if (blocked == 1 && hi_blocked && right_overlap <= CORNER_CORRECTION)
			shift = -right_overlap;
		if (shift != 0 && box_free(left + shift, new_top, right + shift, new_py)) {
			px += shift;
			py = new_py;
			return;
		}
		py = (lowest_row + 1) * TILE + PLAYER_H;
		vy = 0;
	}

	void launch_from_rings() {
		Rect box = {px - HW, py - PLAYER_H, PLAYER_W, PLAYER_H};
		for (size_t i = 0; i < lv->rings.size(); i++) {
			const Ring& r = lv->rings[i];
			if (cooldown[i] > 0 || !box.intersects(r.zone)) continue;
			switch (r.face) {
				case UP:
					vy = -FLOOR_LAUNCH;
					break;
				case DOWN:
					vy = CEILING_LAUNCH;
					break;
				case LEFT:
					vx = -WALL_LAUNCH_X;
					vy = std::min(vy, -WALL_LAUNCH_LIFT);
					lock_ticks = WALL_LOCK_TICKS;
					facing = -1;
					break;
				default:
					vx = WALL_LAUNCH_X;
					vy = std::min(vy, -WALL_LAUNCH_LIFT);
					lock_ticks = WALL_LOCK_TICKS;
					facing = 1;
			}
			launched = r.face != DOWN;
			jumping = false;
			coyote = 0;
			buffer = 0;
			grounded = false;
			ground = NONE;
			cooldown[i] = RING_COOLDOWN_TICKS;
			return;
		}
	}

	bool hazard_hit() const {
		num inset = HAZARD_INSET;
		Rect box = {px - HW + inset, py - PLAYER_H + inset, PLAYER_W - 2 * inset, PLAYER_H - 2 * inset};
		if (py - PLAYER_H >= lv->height * TILE) return true;
		num si = SPIKE_INSET;
		for (num cy = fdiv(box.y, TILE); cy <= fdiv(box.y + box.h - 1, TILE); cy++) {
			for (num cx = fdiv(box.x, TILE); cx <= fdiv(box.x + box.w - 1, TILE); cx++) {
				if (lv->cell(cx, cy) == SPIKE) {
					Rect spike = {cx * TILE + si, cy * TILE + TILE / 2, TILE - 2 * si, TILE / 2};
					if (box.intersects(spike)) return true;
				}
			}
		}
		return false;
	}
};

// ---- level text (tools/export_levels.gd) ----
bool read_levels(const std::string& path, std::vector<Level>* out) {
	std::ifstream f(path);
	if (!f) return false;
	std::string line;
	Level cur;
	std::vector<std::string> rows;
	while (std::getline(f, line)) {
		std::istringstream ss(line);
		std::string word;
		ss >> word;
		if (word == "level") {
			cur = Level();
			rows.clear();
			int sky = 0;
			ss >> cur.id >> cur.width >> cur.height >> cur.beads >> cur.par >> sky;
			cur.sky = sky != 0;
		} else if (word == "row") {
			std::string r;
			ss >> r;
			rows.push_back(r);
		} else if (word == "ring") {
			Ring r;
			ss >> r.x >> r.y >> r.face;
			r.zone = ring_zone(r.x, r.y, r.face);
			cur.presets.push_back(r);
		} else if (word == "end") {
			cur.cells.assign(cur.width * cur.height, EMPTY);
			for (num y = 0; y < cur.height; y++) {
				for (num x = 0; x < cur.width; x++) {
					char ch = rows[y][x];
					if (ch == 'S') {
						cur.spawn_x = x;
						cur.spawn_y = y;
					} else if (ch == 'F') {
						cur.finish_x = x;
						cur.finish_y = y;
					} else {
						const char* p = std::strchr(CHARS, ch);
						if (p == nullptr) return false;
						int kind = static_cast<int>(p - CHARS);
						cur.cells[y * cur.width + x] = static_cast<uint8_t>(kind);
						if (is_slope(kind)) cur.slope_count++;
					}
				}
			}
			cur.rings = cur.presets;
			out->push_back(cur);
		}
	}
	return true;
}

const Level* find_level(const std::vector<Level>& levels, const std::string& id) {
	for (const Level& l : levels)
		if (l.id == id) return &l;
	return nullptr;
}

std::vector<std::string> split(const std::string& s, char sep) {
	std::vector<std::string> out;
	std::string item;
	std::istringstream ss(s);
	while (std::getline(ss, item, sep)) out.push_back(item);
	return out;
}

// ---- run scripts (sim/run_script.gd, hold tokens only) ----
bool is_number(const std::string& s) {
	if (s.empty()) return false;
	for (char c : s)
		if (c < '0' || c > '9') return false;
	return true;
}

// false on a malformed token; T and U are not supported
bool parse_script(const std::string& text, std::vector<Input>* out, std::string* error) {
	bool prev_held = false;
	for (const std::string& token : split(text, ' ')) {
		if (token.empty() || token == "U" || token[0] == 'T') {
			*error = "unsupported token '" + token + "'";
			return false;
		}
		size_t pos = 0;
		int move = 0;
		bool held = false, press = false, any = false;
		if (token[0] == '-') {
			pos = 1;
			any = true;
		} else {
			if (token[pos] == 'L' || token[pos] == 'R') {
				move = token[pos] == 'L' ? -1 : 1;
				pos++;
				any = true;
			}
			if (pos < token.size() && token[pos] == 'J') {
				held = true;
				pos++;
				any = true;
			}
			if (pos < token.size() && token[pos] == 'P') {
				press = true;
				pos++;
				any = true;
			}
		}
		std::string digits = token.substr(pos);
		if (!any || !is_number(digits) || digits[0] == '0' || digits.size() > 5) {
			*error = "bad hold token '" + token + "'";
			return false;
		}
		int count = std::atoi(digits.c_str());
		for (int i = 0; i < count; i++) {
			Input in;
			in.move = static_cast<int8_t>(move);
			in.held = held;
			in.pressed = (held && !prev_held) || (i == 0 && press);
			prev_held = held;
			out->push_back(in);
		}
	}
	return true;
}

// canonical script of a hold-only input list, as MazeRunScript.encode
std::string encode_script(const std::vector<Input>& inputs) {
	std::string out;
	bool prev_held = false;
	size_t i = 0;
	while (i < inputs.size()) {
		const Input& first = inputs[i];
		bool derived = first.held && !prev_held;
		std::string letters = first.move < 0 ? "L" : (first.move > 0 ? "R" : "");
		if (first.held) letters += "J";
		if (first.pressed && !derived) letters += "P";
		std::string flags = letters.empty() ? "-" : letters;
		size_t count = 1;
		while (i + count < inputs.size() && count < 99999) {
			const Input& next = inputs[i + count];
			if (next.move != first.move || next.held != first.held || next.pressed) break;
			count++;
		}
		if (!out.empty()) out += " ";
		out += flags + std::to_string(count);
		prev_held = first.held;
		i += count;
	}
	return out;
}

// ---- trace mode ----
// "x,y,face;..." with the face as 0..3 (cases.txt) or as a name (--rings); false on error
bool parse_rings(const std::string& text, const Level& lv, std::vector<Ring>* out) {
	if (text == "-" || text.empty()) return true;
	for (const std::string& item : split(text, ';')) {
		std::vector<std::string> f = split(item, ',');
		if (f.size() != 3) return false;
		Ring r;
		r.x = std::atoi(f[0].c_str());
		r.y = std::atoi(f[1].c_str());
		r.face = -1;
		if (is_number(f[2])) {
			r.face = std::atoi(f[2].c_str());
		} else {
			for (int i = 0; i < 4; i++)
				if (f[2] == FACE_NAMES[i]) r.face = i;
		}
		if (r.face < 0 || r.face > 3) return false;
		r.zone = ring_zone(r.x, r.y, r.face);
		out->push_back(r);
	}
	(void)lv;
	return true;
}

int run_trace(const std::string& levels_path, const std::string& cases_path) {
	std::vector<Level> levels;
	if (!read_levels(levels_path, &levels)) {
		std::fprintf(stderr, "cannot read levels %s\n", levels_path.c_str());
		return 2;
	}
	std::ifstream f(cases_path);
	if (!f) {
		std::fprintf(stderr, "cannot read cases %s\n", cases_path.c_str());
		return 2;
	}
	std::string line;
	std::string out;
	while (std::getline(f, line)) {
		std::istringstream ss(line);
		std::string word, id, rings, start;
		int n = 0;
		ss >> word >> n >> id >> rings >> start;
		std::string script;
		std::getline(ss, script);
		if (!script.empty() && script[0] == ' ') script.erase(0, 1);
		const Level* base = find_level(levels, id);
		if (word != "case" || base == nullptr) {
			std::fprintf(stderr, "bad case line: %s\n", line.c_str());
			return 2;
		}
		Level lv = *base;
		if (!parse_rings(rings, lv, &lv.rings) || lv.rings.size() > MAX_RINGS) {
			std::fprintf(stderr, "bad rings in case %d\n", n);
			return 2;
		}
		std::vector<Input> inputs;
		std::string error;
		if (!parse_script(script, &inputs, &error)) {
			std::fprintf(stderr, "case %d: %s\n", n, error.c_str());
			return 2;
		}
		Sim sim(&lv);
		if (start != "-") {
			std::vector<std::string> p = split(start, ',');
			if (p.size() != 2) {
				std::fprintf(stderr, "bad start in case %d\n", n);
				return 2;
			}
			sim.px = std::atoi(p[0].c_str());
			sim.py = std::atoi(p[1].c_str());
			sim.compute_ground();
		}
		char buf[256];
		for (const Input& in : inputs) {
			sim.step(in);
			std::snprintf(buf, sizeof buf, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", n, sim.tick, sim.px,
					sim.py, sim.vx, sim.vy, sim.ground, sim.grounded ? 1 : 0, sim.dead_ticks, sim.rings_used,
					sim.coyote, sim.buffer, sim.jumping ? 1 : 0, sim.launched ? 1 : 0, sim.lock_ticks, sim.facing,
					sim.finished ? 1 : 0);
			out += buf;
			if (sim.finished) break;
		}
	}
	std::fwrite(out.data(), 1, out.size(), stdout);
	return 0;
}

// ---- search mode (tools/search_par.gd) ----
struct Node {
	Sim sim;
	int parent;
	bool held;
	int8_t move;
	bool jump;
};

uint64_t mix(uint64_t h, uint64_t v) {
	h ^= v + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
	h *= 0xff51afd7ed558ccdULL;
	h ^= h >> 32;
	return h;
}

// quantised state key of search_par.gd with ground; 64-bit hash instead of an exact tuple
uint64_t state_key(const Sim& s, bool held, size_t ring_count) {
	uint64_t cd = 0;
	uint64_t h = 1469598103934665603ULL;
	for (size_t i = 0; i < ring_count; i++) {
		cd = cd * 4 + (s.cooldown[i] > 0 ? 1 : 0);
		if ((i & 15) == 15) {
			h = mix(h, cd);
			cd = 0;
		}
	}
	h = mix(h, cd);
	uint64_t flags = (s.grounded ? 1 : 0) | ((s.coyote > 0) ? 2 : 0) | ((s.buffer > 0) ? 4 : 0) |
			(s.jumping ? 8 : 0) | (s.launched ? 16 : 0) | (held ? 32 : 0);
	h = mix(h, static_cast<uint64_t>(static_cast<int64_t>(s.px / 3000)));
	h = mix(h, static_cast<uint64_t>(static_cast<int64_t>(s.py / 3000)));
	h = mix(h, static_cast<uint64_t>(static_cast<int64_t>(s.vx / 1500)));
	h = mix(h, static_cast<uint64_t>(static_cast<int64_t>(s.vy / 1500)));
	h = mix(h, flags | (static_cast<uint64_t>(s.ground) << 8) | (static_cast<uint64_t>(s.lock_ticks) << 16) |
			(static_cast<uint64_t>(s.dead_ticks) << 24) | (static_cast<uint64_t>(s.rings_used) << 32));
	return h == 0 ? 1 : h;
}

// open addressing set of keys, cleared by the slots that were touched
struct KeySet {
	std::vector<uint64_t> table;
	std::vector<uint32_t> used;
	uint64_t mask = 0;

	void init(size_t want) {
		size_t n = 1 << 12;
		while (n < want * 2) n <<= 1;
		if (n != table.size()) table.assign(n, 0);
		mask = n - 1;
	}
	void clear() {
		for (uint32_t i : used) table[i] = 0;
		used.clear();
	}
	// true when the key was new
	bool insert(uint64_t key) {
		uint64_t i = (key * 0x9e3779b97f4a7c15ULL) >> 20 & mask;
		while (table[i] != 0) {
			if (table[i] == key) return false;
			i = (i + 1) & mask;
		}
		table[i] = key;
		used.push_back(static_cast<uint32_t>(i));
		return true;
	}
};

struct Search {
	int k = 4;
	size_t max_nodes = 30000;
	int weight = 1;
	uint64_t nodes_total = 0;
	KeySet seen;
	std::vector<Node> nodes;

	int heuristic(const Level& lv, const Sim& s) const {
		num dx = std::abs(s.px - (lv.finish_x * TILE + TILE / 2));
		num dy = std::abs(s.py - (lv.finish_y * TILE + TILE));
		return std::max(dx, dy) / 5000;
	}

	// finish script, or empty when none within the node limit
	std::string run(Level& lv, bool report_open) {
		size_t ring_count = lv.rings.size();
		nodes.clear();
		nodes.reserve(max_nodes + 8);
		seen.init(max_nodes);
		seen.clear();
		Sim root(&lv);
		nodes.push_back({root, -1, false, 0, false});
		seen.insert(state_key(root, false, ring_count));
		typedef std::pair<int64_t, int64_t> Item;  // (f, -index): lowest f first, newest first among equals
		std::priority_queue<Item, std::vector<Item>, std::greater<Item>> heap;
		heap.push({static_cast<int64_t>(heuristic(lv, root)) * weight, 0});
		std::string script;
		while (!heap.empty() && nodes.size() < max_nodes) {
			int idx = static_cast<int>(-heap.top().second);
			heap.pop();
			static const int moves[3] = {1, -1, 0};
			for (int m : moves) {
				for (int j = 0; j < 2; j++) {
					Sim n = nodes[idx].sim;
					bool hh = nodes[idx].held;
					bool jump = j == 1;
					for (int i = 0; i < k; i++) {
						Input in;
						in.move = static_cast<int8_t>(m);
						in.held = jump;
						in.pressed = jump && !hh;
						hh = jump;
						n.step(in);
						if (n.finished) break;
					}
					if (n.finished) {
						nodes.push_back({n, idx, hh, static_cast<int8_t>(m), jump});
						script = build_script(static_cast<int>(nodes.size()) - 1, lv);
						nodes_total += nodes.size();
						return script;
					}
					if (n.dead_ticks > 0) continue;
					if (!seen.insert(state_key(n, hh, ring_count))) continue;
					nodes.push_back({n, idx, hh, static_cast<int8_t>(m), jump});
					heap.push({static_cast<int64_t>(n.tick) + static_cast<int64_t>(heuristic(lv, n)) * weight,
							-static_cast<int64_t>(nodes.size() - 1)});
				}
			}
		}
		if (report_open) std::printf("  nodes %zu, open %zu\n", nodes.size(), heap.size());
		nodes_total += nodes.size();
		return "";
	}

	// the macro steps from the root to idx as one run script; the last macro stops at the finish tick
	std::string build_script(int idx, Level& lv) {
		std::vector<int> chain;
		while (idx > 0) {
			chain.push_back(idx);
			idx = nodes[idx].parent;
		}
		std::reverse(chain.begin(), chain.end());
		std::vector<Input> inputs;
		bool hh = false;
		Sim sim(&lv);
		for (int id : chain) {
			for (int i = 0; i < k; i++) {
				Input in;
				in.move = nodes[id].move;
				in.held = nodes[id].jump;
				in.pressed = nodes[id].jump && !hh;
				hh = nodes[id].jump;
				inputs.push_back(in);
				sim.step(in);
				if (sim.finished) break;
			}
		}
		return encode_script(inputs);
	}
};

struct Rect2 {
	int x0 = 0, y0 = 0, x1 = 100000, y1 = 100000;  // inclusive tile rectangle
	bool has(int x, int y) const { return x >= x0 && x <= x1 && y >= y0 && y <= y1; }
};

bool parse_rect(const std::string& text, Rect2* r) {
	std::vector<std::string> f = split(text, ',');
	if (f.size() != 4) return false;
	r->x0 = std::atoi(f[0].c_str());
	r->y0 = std::atoi(f[1].c_str());
	r->x1 = std::atoi(f[2].c_str());
	r->y1 = std::atoi(f[3].c_str());
	return true;
}

std::string label_of(const std::vector<Ring>& rings, size_t from) {
	std::string s;
	for (size_t i = from; i < rings.size(); i++)
		s += " (" + std::to_string(rings[i].x) + "," + std::to_string(rings[i].y) + "," + FACE_NAMES[rings[i].face] + ")";
	return s;
}

// true when a finish was found
bool try_set(Search& search, Level& lv, size_t preset_count, bool quiet) {
	std::string script = search.run(lv, !quiet);
	std::string label = label_of(lv.rings, preset_count);
	if (script.empty()) {
		if (!quiet) std::printf("extra rings%s: no finish within the node limit\n", label.c_str());
		return false;
	}
	std::printf("extra rings%s: FINISH script %s\n", label.c_str(), script.c_str());
	return true;
}

int run_search(int argc, char** argv) {
	std::string levels_path = argv[2];
	std::string id = "l001";
	std::string rings_text;
	int subset = 0;
	Rect2 rect, anchor;
	int part_i = 0, part_n = 1;
	Search search;
	for (int a = 3; a < argc; a++) {
		std::string arg = argv[a];
		std::string val = arg.find('=') == std::string::npos ? "" : arg.substr(arg.find('=') + 1);
		if (arg.rfind("--level=", 0) == 0) id = val;
		else if (arg.rfind("--rings=", 0) == 0) rings_text = val;
		else if (arg.rfind("--k=", 0) == 0) search.k = std::atoi(val.c_str());
		else if (arg.rfind("--nodes=", 0) == 0) search.max_nodes = static_cast<size_t>(std::atoll(val.c_str()));
		else if (arg.rfind("--weight=", 0) == 0) search.weight = std::atoi(val.c_str());
		else if (arg.rfind("--subset=", 0) == 0) subset = std::atoi(val.c_str());
		else if (arg.rfind("--faces=", 0) == 0) { if (!parse_rect(val, &rect)) return 2; }
		else if (arg.rfind("--anchor=", 0) == 0) { if (!parse_rect(val, &anchor)) return 2; }
		else if (arg.rfind("--part=", 0) == 0) {
			std::vector<std::string> p = split(val, '/');
			if (p.size() != 2) return 2;
			part_i = std::atoi(p[0].c_str());
			part_n = std::atoi(p[1].c_str());
			if (part_n < 1) return 2;
		} else {
			std::fprintf(stderr, "unknown argument %s\n", arg.c_str());
			return 2;
		}
	}
	std::vector<Level> levels;
	if (!read_levels(levels_path, &levels)) {
		std::fprintf(stderr, "cannot read levels %s\n", levels_path.c_str());
		return 2;
	}
	const Level* base = find_level(levels, id);
	if (base == nullptr) {
		std::fprintf(stderr, "no level %s in %s\n", id.c_str(), levels_path.c_str());
		return 2;
	}
	Level lv = *base;
	size_t preset_count = lv.presets.size();
	auto t0 = std::chrono::steady_clock::now();
	if (subset == 0) {
		if (!parse_rings(rings_text, lv, &lv.rings) || lv.rings.size() > MAX_RINGS) {
			std::fprintf(stderr, "bad --rings\n");
			return 2;
		}
		try_set(search, lv, preset_count, false);
	} else {
		if (preset_count + subset > MAX_RINGS) {
			std::fprintf(stderr, "too many rings\n");
			return 2;
		}
		std::vector<Ring> faces;
		for (num y = 0; y < lv.height; y++) {
			for (num x = 0; x < lv.width; x++) {
				if (!rect.has(x, y) || lv.cell(x, y) != SOLID) continue;
				for (int face = 0; face < 4; face++) {
					num fx = x + FACE_DX[face], fy = y + FACE_DY[face];
					if (lv.covered(fx, fy) || lv.cell(fx, fy) == SPIKE) continue;
					bool preset = false;
					for (const Ring& r : lv.presets) preset = preset || (r.x == x && r.y == y && r.face == face);
					if (preset) continue;
					Ring r;
					r.x = x;
					r.y = y;
					r.face = face;
					r.zone = ring_zone(x, y, face);
					faces.push_back(r);
				}
			}
		}
		std::printf("%zu candidate faces\n", faces.size());
		int found = 0;
		long counted = 0;
		std::vector<int> idx(subset);
		for (int i = 0; i < subset; i++) idx[i] = i;
		int n = static_cast<int>(faces.size());
		while (subset <= n) {
			bool anchored = false;
			for (int i : idx) anchored = anchored || anchor.has(faces[i].x, faces[i].y);
			if (anchored) {
				counted++;
				if (counted % part_n == part_i) {
					lv.rings = lv.presets;
					for (int i : idx) lv.rings.push_back(faces[i]);
					if (try_set(search, lv, preset_count, true)) found++;
				}
			}
			int i = subset - 1;
			while (i >= 0 && idx[i] == n - subset + i) i--;
			if (i < 0) break;
			idx[i]++;
			for (int j = i + 1; j < subset; j++) idx[j] = idx[j - 1] + 1;
		}
		std::printf("sets with a finish: %d\n", found);
	}
	long ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
	std::printf("nodes %llu ms %ld\n", static_cast<unsigned long long>(search.nodes_total), ms);
	return 0;
}

}  // namespace

int main(int argc, char** argv) {
	if (argc >= 4 && std::strcmp(argv[1], "trace") == 0) return run_trace(argv[2], argv[3]);
	if (argc >= 3 && std::strcmp(argv[1], "search") == 0) return run_search(argc, argv);
	std::fprintf(stderr,
			"usage: maze_solver trace <levels.txt> <cases.txt>\n"
			"       maze_solver search <levels.txt> --level=<id> [--rings=\"x,y,face;...\"] [--k=4] [--nodes=N] "
			"[--weight=W]\n"
			"       maze_solver search <levels.txt> --level=<id> --subset=N [--faces=x0,y0,x1,y1] "
			"[--anchor=x0,y0,x1,y1] [--part=i/n]\n");
	return 2;
}
