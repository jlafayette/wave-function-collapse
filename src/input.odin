package main

import "vendor:sdl2"

Inputs :: struct {
	quit: bool,
}

game_handle_inputs :: proc(g: ^Game) -> Inputs {
	inputs: Inputs
	event: sdl2.Event
	for sdl2.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			inputs.quit = true
		case .KEYUP:
			if event.key.keysym.sym == .ESCAPE {
				sdl2.PushEvent(&sdl2.Event{type = .QUIT})
			}
		}
	}
	return inputs
}
