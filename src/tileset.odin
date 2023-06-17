package main

import glm "core:math/linalg/glsl"

mat4 :: glm.mat4

Sym :: enum {
	X, // None (-)
	T, // (-, rotate90, flipV, flipV+rotate90)
	I, // (-, rotate90)
	L, // corner (-, flipH, flipV, flipV+rotate90)
	// D, // \
}
Transform :: enum {
	None,
	Rotate90,
	FlipH,
	FlipV,
	FlipV_Rotate90,
}
all_transforms: [5]Transform = {.None, .Rotate90, .FlipH, .FlipV, .FlipV_Rotate90}

TileSource :: struct {
	tex: Texture2D,
	sym: Sym,
}
tile_src_contains_transform :: proc(ts: TileSource, xform: Transform) -> bool {
	switch ts.sym {
	case .X:
		return xform == .None
	case .T:
		return xform != .FlipH
	case .I:
		return xform == .None || xform == .Rotate90
	case .L:
		return xform != .Rotate90
	}
	return false
}
Tile :: struct {
	tex:   Texture2D,
	xform: Transform,
}
// tiles_in_source :: proc(ts: TileSource) -> [5]Maybe(Transform) {
// }
transform_mat4 :: proc(t: Transform) -> mat4 {
	m: mat4
	switch t {
	case .None:
		m = glm.mat4(1)
	case .Rotate90:
		m = glm.mat4Rotate({0, 0, 1}, glm.radians_f32(90))
	case .FlipH:
		m = glm.mat4Scale({-1, 1, 1})
	case .FlipV:
		m = glm.mat4Scale({1, -1, 1})
	case .FlipV_Rotate90:
		m = glm.mat4(1)
		m = m * glm.mat4Rotate({0, 0, 1}, glm.radians_f32(90))
		m = m * glm.mat4Scale({1, -1, 1})
	}
	return m
}
