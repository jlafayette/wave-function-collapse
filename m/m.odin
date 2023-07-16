package m

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:runtime"
import "core:slice"
import "core:strings"
import "core:time"
import glm "core:math/linalg/glsl"

import "vendor:sdl2"
import gl "vendor:OpenGL"

mat4 :: glm.mat4
vec2 :: glm.vec2

_main :: proc(display_index: i32) {
	assert(sdl2.Init({.VIDEO}) == 0, sdl2.GetErrorString())
	defer sdl2.Quit()

	display_mode: sdl2.DisplayMode
	sdl2.GetCurrentDisplayMode(display_index, &display_mode)
	refresh_rate := display_mode.refresh_rate

	window_width: i32 = 1280
	window_height: i32 = 960

	window := sdl2.CreateWindow(
		"Wave Function Collapse",
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		sdl2.WINDOWPOS_UNDEFINED_DISPLAY(display_index),
		window_width,
		window_height,
		{.OPENGL},
	)
	assert(window != nil, sdl2.GetErrorString())
	defer sdl2.DestroyWindow(window)

	fmt.printf("%dx%d %d\n", window_width, window_height, refresh_rate)

	run(window, window_width, window_height, refresh_rate)
}


main :: proc() {
	args := os.args[1:]
	display_index: i32 = 0
	if slice.contains(args, "-1") {
		// open window on second monitor
		display_index = 1
	}
	if slice.contains(args, "-m") || slice.contains(args, "--mem-track") {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		_main(display_index)

		for _, leak in track.allocation_map {
			fmt.printf("%v leaked %v bytes\n", leak.location, leak.size)
		}
		for bad_free in track.bad_free_array {
			fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
		}
	} else {
		_main(display_index)
	}
}

DEBUG_FPS :: true
TILE_SIZE :: 100


Game :: struct {
	window_width:  int,
	window_height: int,
	rand:          rand.Rand,
	projection:    glm.mat4,
	renderer:      Renderer,
}
game_init :: proc(g: ^Game, width, height: int) {
	g.window_width = width
	g.window_height = height
	rand.init(&g.rand, 111)
	g.projection = glm.mat4Ortho3d(0, f32(width), f32(height), 0, -1.0, 1)

	assert(renderer_init(&g.renderer, g.projection), "Failed to init renderer")

}
game_destroy :: proc(g: ^Game) {
	renderer_destroy(&g.renderer)
}

run :: proc(window: ^sdl2.Window, window_width, window_height, refresh_rate: i32) {
	game_start_tick := time.tick_now()

	// Init OpenGL
	sdl2.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl2.GLprofile.CORE))
	sdl2.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, 3)
	sdl2.GL_SetAttribute(.CONTEXT_MINOR_VERSION, 3)
	gl_context := sdl2.GL_CreateContext(window)
	defer sdl2.GL_DeleteContext(gl_context)
	gl.load_up_to(3, 3, sdl2.gl_set_proc_address)

	game: Game
	game_init(&game, int(window_width), int(window_height))
	defer game_destroy(&game)

	// timing stuff
	fps: f64 = 0
	target_ms_elapsed: f64 = 1000 / f64(refresh_rate)
	ms_elapsed: f64 = target_ms_elapsed
	target_dt: f64 = (1000 / f64(refresh_rate)) / 1000
	dt := f32(ms_elapsed / 1000)

	// game loop
	game_loop: for {
		start_tick := time.tick_now()
		dt = f32(ms_elapsed / 1000)

		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break game_loop
			case .KEYUP:
				if event.key.keysym.sym == .ESCAPE {
					sdl2.PushEvent(&sdl2.Event{type = .QUIT})
				}
			}
		}

		render(&game, window)

		// timing (avoid looping too fast)
		duration := time.tick_since(start_tick)
		tgt_duration := time.Duration(target_ms_elapsed * f64(time.Millisecond))
		to_sleep := tgt_duration - duration
		time.accurate_sleep(to_sleep - (2 * time.Microsecond))
		duration = time.tick_since(start_tick)
		ms_elapsed = f64(time.duration_milliseconds(duration))
		fps = 1000 / ms_elapsed

		free_all(context.temp_allocator)
	}
}
