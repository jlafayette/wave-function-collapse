package main

import "core:fmt"
import "core:slice"
import "core:mem"

wfc_step :: proc(game: ^Game) {
	fmt.println("step")
	grid := game.grid

	// copy so sorting doesn't rearange placement in grid
	squares_backing := make_dynamic_array_len([dynamic]^Square, len(grid.squares), context.temp_allocator)
	for s, i in grid.squares {
		squares_backing[i] = s
	}
	squares := squares_backing[:]

	// sort by fewest possible states
	unordered_remove(&squares[4].options, 3)
	print_options(squares)
	slice.sort_by(squares, square_less_options)
	print_options(squares)
}

print_options :: proc(squares: []^Square) {
	for s in squares {
		fmt.println(s.collapsed, " ", len(s.options), " ", s.options)
	}
	fmt.println("")
}
