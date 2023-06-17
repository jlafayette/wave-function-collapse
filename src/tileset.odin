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
T_COUNT :: 5
all_transforms: [T_COUNT]Transform = {.None, .Rotate90, .FlipH, .FlipV, .FlipV_Rotate90}
Side :: enum {
	OPEN,
	PIPE,
}
X_xforms : [1]Transform = {.None}
T_xforms : [4]Transform = {.None, .Rotate90, .FlipV, .FlipV_Rotate90}
I_xforms : [2]Transform = {.None, .Rotate90}
L_xforms : [4]Transform = {.None, .FlipH, .FlipV, .FlipV_Rotate90}

TileSource :: struct {
	tex: Texture2D,
	sym: Sym,
	sides: [4]Side,
	xforms: []Transform,
}
/*
tile_sides :: proc(ts: TileSource, xform: Transform) -> [4]Side {
	sides : [4]Side = ts.sides
	switch ts.sym {
	case .X:
	case .T:
		switch xform {
		case .None:
		case .Rotate90:
			sides = sides.xyzw
		case .FlipH:
			sides = sides.xyzw
		case .FlipV:
			sides = sides.xyzw
		case .FlipV_Rotate90:
			sides = sides.xyzw
		}
	case .I:
		switch xform {
		case .None:
		case .Rotate90:
			sides = sides.xyzw
		case .FlipH:
			sides = sides.xyzw
		case .FlipV:
			sides = sides.xyzw
		case .FlipV_Rotate90:
			sides = sides.xyzw
		}
	}
	return sides
}
*/
Tile :: struct {
	tex:   Texture2D,
	xform: Transform,
}
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
