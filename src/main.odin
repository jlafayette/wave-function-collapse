package main

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

ModePlay :: struct {
	frames_per_step: int,
	frames_elapsed: int,
}
ModePause :: struct {}
Mode :: union {
	ModePlay,
	ModePause,
}

Game :: struct {
	window_width:  int,
	window_height: int,
	rand:          rand.Rand,
	sec_elapsed:   f64,
	projection:    glm.mat4,
	renderer:      Renderer,
	grid:          Grid,
	writer:        Writer,
	tile_options: [dynamic]TileOption,
	mode: Mode,
	tile_size: f32,
}
game_init :: proc(g: ^Game, width, height: int) {
	size: f32 = 10
	rows := cast(int)math.floor(f32(width) / size)
	cols := cast(int)math.floor(f32(height) / size)
	g.tile_size = size
	
	g.window_width = width
	g.window_height = height
	g.mode = ModePause{}
	rand.init(&g.rand, 111)
	g.projection = glm.mat4Ortho3d(0, f32(width), f32(height), 0, -1.0, 1)

	assert(renderer_init(&g.renderer, g.projection), "Failed to init renderer")

	grid_init(&g.grid, rows, cols)
	assert(writer_init(&g.writer, TERMINAL_TTF, 16, g.projection), "Failed to init text writer")

	for tile in Tile {
		ts := tile_set[tile]
		for xform in ts.xforms {
			append(&g.tile_options, TileOption{tile, xform})
		}
	}
}
game_destroy :: proc(g: ^Game) {
	renderer_destroy(&g.renderer)
	grid_destroy(&g.grid)
	writer_destroy(&g.writer)
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
	when DEBUG_FPS {
		_lo_ms: f64 = 999
		_hi_ms: f64 = 0
		_ms: f64 = 0
		_sec_tick: time.Tick = time.tick_now()
		_frames: int = 0
	}

	// game loop
	game_loop: for {
		start_tick := time.tick_now()
		dt = f32(ms_elapsed / 1000)
		when DEBUG_FPS {
			fmt.printf("\nFPS: %f\n", fps)
			fmt.printf("ms: %f\n", ms_elapsed)
			fmt.printf("dt: %f\n", dt)
			fmt.printf("tgt dt: %f\n", target_dt)
		}
		game_duration := time.tick_since(game_start_tick)
		game.sec_elapsed = time.duration_seconds(game_duration)

		// debug time tracking
		when DEBUG_FPS {
			_frames += 1
			_ms += ms_elapsed
			_lo_ms = min(ms_elapsed, _lo_ms)
			_hi_ms = max(ms_elapsed, _hi_ms)
			if time.duration_seconds(time.tick_since(_sec_tick)) >= 1.0 {
				fmt.printf(
					"%d FPS, min: %.2f, max: %.2f, avg: %.2f\n",
					_frames,
					_lo_ms,
					_hi_ms,
					_ms / cast(f64)_frames,
				)
				// reset
				_lo_ms = 999
				_hi_ms = 0
				_ms = 0
				_sec_tick = time.tick_now()
				_frames = 0
			}
		}

		inputs := game_handle_inputs(&game)
		if inputs.quit {
			break game_loop
		}
		if inputs.play_toggle {
			switch m in game.mode {
			case ModePlay:
				game.mode = ModePause{}
			case ModePause:
				game.mode = ModePlay{1, 0}
				fmt.println("play", game.mode)
			}
		}
		step: bool = inputs.next_step
		play_mode : ModePlay
		ok : bool
		play_mode, ok = game.mode.(ModePlay)
		if ok {
			new_mode := play_mode
			new_mode.frames_elapsed += 1
			if new_mode.frames_elapsed >= new_mode.frames_per_step {
				step = true
				new_mode.frames_elapsed = 0
			}
			game.mode = new_mode
		}
		if step {
			wfc_step(&game)
		}

		game_render(&game, window, game.tile_size, game.tile_size)

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

get_mouse_pos :: proc(window_width, window_height: i32) -> [2]f32 {
	cx, cy: c.int
	sdl2.GetMouseState(&cx, &cy)
	return {f32(cx), f32(cy)}
}
