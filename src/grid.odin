package main

import "core:fmt"

OPTIONS_COUNT :: 13

Grid :: struct {
	squares:   [dynamic]^Square,
	row_count: int,
	col_count: int,
}
Square :: struct {
	options:   [dynamic]int,
	collapsed: bool,
}
square_init :: proc(s: ^Square, options_count: int) {
	reserve(&s.options, options_count)
	for i := 0; i < options_count; i += 1 {
		append(&s.options, i)
	}
}
square_destroy :: proc(s: ^Square) {
	delete(s.options)
	free(s)
}

square_less_options :: proc(i, j: ^Square) -> bool {
	return len(i.options) < len(j.options)
}

grid_init :: proc(grid: ^Grid) {
	reserve(&grid.squares, 9)
	grid.row_count = 3
	grid.col_count = 3
	size := grid.row_count * grid.col_count
	for i := 0; i < size; i += 1 {
		square: ^Square = new(Square)
		square_init(square, OPTIONS_COUNT)
		append(&grid.squares, square)
	}
}
grid_destroy :: proc(grid: ^Grid) {
	for _, i in grid.squares {
		square_destroy(grid.squares[i])
	}
	delete(grid.squares)
}

grid_get :: proc(g: ^Grid, x, y: int) -> (square: ^Square) {
	assert(x >= 0 && y >= 0)
	assert(x < g.row_count && y < g.col_count)
	i := y * g.row_count + x
	return g.squares[i]
}
