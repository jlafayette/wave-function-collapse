package main

import "core:fmt"
import "core:math"
import "core:math/rand"

OPTIONS_COUNT :: 13

Grid :: struct {
	squares:   [dynamic]^Square,
	row_count: int,
	col_count: int,
}
Square :: struct {
	x: int,
	y: int,
	options:   [dynamic]int,
	option: int,
	collapsed: bool,
}
square_init :: proc(s: ^Square, x, y: int, options_count: int) {
	reserve(&s.options, options_count)
	for i := 0; i < options_count; i += 1 {
		append(&s.options, i)
	}
	s.x = x
	s.y = y
}
square_destroy :: proc(s: ^Square) {
	delete(s.options)
	free(s)
}
square_collapse :: proc(s: ^Square, r: ^rand.Rand) {
	f := rand.float32(r) * cast(f32)len(s.options)
	i : int = cast(int)math.floor(f)
	s.option = s.options[i]
	s.collapsed = true
}
square_less_options :: proc(i, j: ^Square) -> bool {
	// collapsed should go to the end
	if j.collapsed {
		return true
	}
	if i.collapsed {
		return false
	}
	// if not collapsed, put the one with less options first
	return len(i.options) < len(j.options)
}

grid_init :: proc(grid: ^Grid) {
	reserve(&grid.squares, 9)
	grid.row_count = 3
	grid.col_count = 3
	size := grid.row_count * grid.col_count
	for y:=0; y<grid.col_count; y+=1 {
		for x:=0; x<grid.row_count; x+=1 {
			square: ^Square = new(Square)
			square_init(square, x, y, OPTIONS_COUNT)
			append(&grid.squares, square)
		}
	}
}
grid_destroy :: proc(grid: ^Grid) {
	for _, i in grid.squares {
		square_destroy(grid.squares[i])
	}
	delete(grid.squares)
}

grid_get :: proc(g: ^Grid, x, y: int) -> (square: Maybe(^Square)) {
	if x < 0 || y < 0 || x >= g.row_count || y >= g.col_count {
		return nil
	}
	i := y * g.row_count + x
	return g.squares[i]
}
grid_get_neighbors :: proc(g: ^Grid, square: ^Square) -> [4]Maybe(^Square) {
	neighbors: [4]Maybe(^Square)
	neighbors[0] = grid_get(g, square.x - 1, square.y)
	neighbors[1] = grid_get(g, square.x, square.y - 1)
	neighbors[2] = grid_get(g, square.x + 1, square.y)
	neighbors[3] = grid_get(g, square.x, square.y + 1)
	return neighbors
}
