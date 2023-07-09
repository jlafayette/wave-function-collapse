package main

import "core:fmt"
import "core:strings"
import "core:slice"
import "core:strconv"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"
import "vendor:sdl2"
import "vendor:stb/image"

SpriteBuffers :: struct {
	vbo: u32,
	vao: u32,
}
SpriteVertex :: struct {
	pos: glm.vec2,
	tex: glm.vec2,
}
sprite_vertices := []SpriteVertex{
	{{0, 1}, {0, 1}},
	{{1, 0}, {1, 0}},
	{{0, 0}, {0, 0}},
	{{0, 1}, {0, 1}},
	{{1, 1}, {1, 1}},
	{{1, 0}, {1, 0}},
}
sprite_buffers_init :: proc() -> SpriteBuffers {
	vbo, vao: u32

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(sprite_vertices) * size_of(sprite_vertices[0]),
		raw_data(sprite_vertices),
		gl.STATIC_DRAW,
	)
	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(
		0,
		2,
		gl.FLOAT,
		false,
		size_of(SpriteVertex),
		offset_of(SpriteVertex, pos),
	)
	gl.VertexAttribPointer(
		1,
		2,
		gl.FLOAT,
		false,
		size_of(SpriteVertex),
		offset_of(SpriteVertex, tex),
	)

	return SpriteBuffers{vbo, vao}
}
sprite_buffers_destroy :: proc(buffers: ^SpriteBuffers) {
	gl.DeleteBuffers(1, &buffers.vbo)
	gl.DeleteVertexArrays(1, &buffers.vao)
}

Texture2D :: struct {
	id:     u32,
	width:  i32,
	height: i32,
}
sprite_texture :: proc(filename: cstring, sprite_program: u32, projection: glm.mat4) -> Texture2D {
	tex: Texture2D
	gl.GenTextures(1, &tex.id)
	nr_channels: i32
	data := image.load(filename, &tex.width, &tex.height, &nr_channels, 0)
	internal_format: i32 = gl.RGB
	image_format: u32 = gl.RGB
	if nr_channels == 4 {
		internal_format = gl.RGBA
		image_format = gl.RGBA
	}
	if nr_channels == 1 {
		internal_format = gl.RED
		image_format = gl.RED
	}
	defer image.image_free(data)
	fmt.println("w:", tex.width, "h:", tex.height, "channels:", nr_channels)
	// 1 (byte-alignment), default is 4 (word alignment)
	// Not sure how to determine this alignment automatically
	// https://www.khronos.org/opengl/wiki/Pixel_Transfer#Pixel_layout
	// https://registry.khronos.org/OpenGL-Refpages/es2.0/xhtml/glPixelStorei.xml
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
	gl.BindTexture(gl.TEXTURE_2D, tex.id);defer gl.BindTexture(gl.TEXTURE_2D, 0)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		internal_format,
		tex.width,
		tex.height,
		0,
		image_format,
		gl.UNSIGNED_BYTE,
		data,
	)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

	gl.UseProgram(sprite_program)
	gl.Uniform1i(gl.GetUniformLocation(sprite_program, "image"), 0)
	proj := projection
	gl.UniformMatrix4fv(gl.GetUniformLocation(sprite_program, "projection"), 1, false, &proj[0, 0])
	return tex
}

draw_sprite :: proc(
	program_id: u32,
	texture_id: u32,
	vao: u32,
	pos, size: glm.vec2,
	transform: glm.mat4,
	color: glm.vec3,
) {
	gl.UseProgram(program_id)
	model := glm.mat4(1)
	model = model * glm.mat4Translate({pos.x, pos.y, 0})
	model = model * glm.mat4Translate({.5 * size.x, .5 * size.y, 0})
	model = model * transform
	model = model * glm.mat4Translate({-.5 * size.x, -.5 * size.y, 0})
	model = model * glm.mat4Scale({size.x, size.y, 1})

	gl.UniformMatrix4fv(gl.GetUniformLocation(program_id, "model"), 1, false, &model[0, 0])
	c := color
	gl.Uniform3fv(gl.GetUniformLocation(program_id, "spriteColor"), 1, &c[0])
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture_id)

	gl.BindVertexArray(vao);defer gl.BindVertexArray(0)

	// needed for alpha channel to work
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.DrawArrays(gl.TRIANGLES, 0, 6)
}

ShaderPrograms :: struct {
	sprite:           u32,
	sprite_grayscale: u32,
}

Renderer :: struct {
	shaders:  ShaderPrograms,
	textures: [Tile]Texture2D,
	square:   Texture2D,
	buffers:  SpriteBuffers,
}
renderer_init :: proc(r: ^Renderer, projection: glm.mat4) -> bool {
	ok: bool
	r.shaders.sprite, ok = gl.load_shaders_source(sprite_vertex_source, sprite_fragment_source)
	if !ok {
		fmt.eprintln("Failed to create sprite GLSL program")
		return false
	}
	r.shaders.sprite_grayscale, ok = gl.load_shaders_source(
		sprite_vertex_source,
		sprite_grayscale_fragment_source,
	)
	if !ok {
		fmt.eprintln("Failed to create grayscale GLSL program")
		return false
	}

	r.buffers = sprite_buffers_init()

	paths: [Tile]cstring = {
		.CORNER = "Knots/corner.png",
		.CROSS  = "Knots/cross.png",
		.EMPTY  = "Knots/empty.png",
		.LINE   = "Knots/line.png",
		.T      = "Knots/t.png",
	}
	for tile in Tile {
		r.textures[tile] = sprite_texture(paths[tile], r.shaders.sprite, projection)
	}
	r.square = sprite_texture("square.png", r.shaders.sprite_grayscale, projection)

	return true
}
renderer_destroy :: proc(r: ^Renderer) {
	sprite_buffers_destroy(&r.buffers)
	gl.DeleteProgram(r.shaders.sprite)
}

game_render :: proc(g: ^Game, window: ^sdl2.Window, square_width, square_height: f32) {
	r := &g.renderer
	vao := r.buffers.vao
	w := square_width
	h := square_height

	// render
	gl.Viewport(0, 0, i32(g.window_width), i32(g.window_height))
	gl.ClearColor(0.007843, 0.02353, 0.02745, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	shader := r.shaders.sprite
	orig_x: f32 = 0
	orig_y: f32 = 0
	x: f32 = orig_x
	y: f32 = orig_y
	/*
	space: f32 = 10
	for tile in Tile {

		ts := tile_set[tile]

		y = orig_y
		for xform in ts.xforms {
			m := transform_mat4(xform)
			draw_sprite(shader, r.textures[tile].id, vao, {x, y}, {w, h}, m, {1, 1, 1})

			// draw sides (for debugging if sides+transform is working correctly)
			sides := tile_sides(ts.sides, xform)
			side := sides[0]
			color: glm.vec3 = {0.5, 0.5, 1}
			if side == .PIPE do color = {0.5, 1, 0.5}
			draw_sprite(shader, r.textures[tile].id, vao, {x, y + (h / 2)}, {10, 10}, m, color)

			side = sides[1]
			color = {0.5, 0.5, 1}
			if side == .PIPE do color = {0.5, 1, 0.5}
			draw_sprite(shader, r.textures[tile].id, vao, {x + (w / 2), y}, {10, 10}, m, color)

			side = sides[2]
			color = {0.5, 0.5, 1}
			if side == .PIPE do color = {0.5, 1, 0.5}
			draw_sprite(
				shader,
				r.textures[tile].id,
				vao,
				{x + w - 10, y + (h / 2)},
				{10, 10},
				m,
				color,
			)

			side = sides[3]
			color = {0.5, 0.5, 1}
			if side == .PIPE do color = {0.5, 1, 0.5}
			draw_sprite(
				shader,
				r.textures[tile].id,
				vao,
				{x + (w / 2), y + h - 10},
				{10, 10},
				m,
				color,
			)

			y += h + space
		}
		x += w + space
	}
	*/
	orig_x = x
	orig_y = y
	hw := w / 2
	hh := h / 2
	display_debug: bool = w >= 100 && h >= 60
	// if !display_debug {
	// 	return
	// }
	for yi := 0; yi < g.grid.col_count; yi += 1 {
		x = orig_x
		for xi := 0; xi < g.grid.row_count; xi += 1 {
			square, ok := grid_get(&g.grid, xi, yi).?
			if !ok {
				fmt.printf("error, no square at %d,%d\n", xi, yi)
				continue
			}
			if square.collapsed {
				to := g.tile_options[square.option]
				m := transform_mat4(to.xform)
				draw_sprite(shader, r.textures[to.tile].id, vao, {x, y}, {w, h}, m, {1, 1, 1})
			} else {
				if display_debug {
					draw_sprite(
						r.shaders.sprite_grayscale,
						r.square.id,
						vao,
						{x, y},
						{w, h},
						glm.mat4(1),
						{1, 1, 1},
					)
					buf: [2]byte
					text := strconv.itoa(buf[:], len(square.options))
					size := text_get_size(&g.writer, text)
					write_text(&g.writer, text, {x, y} + {hw, hh} - size / 2, {0.5, 0.5, 0.5})
				}
			}
			x += w
		}
		y += h
	}

	gl_report_error()
	sdl2.GL_SwapWindow(window)
}

gl_report_error :: proc() {
	e := gl.GetError()
	if e != gl.NO_ERROR {
		fmt.println("OpenGL Error:", e)
	}
}

sprite_vertex_source := `#version 330 core

layout(location=0) in vec2 aPos;
layout(location=1) in vec2 aTexCoords;

out vec2 TexCoords;

uniform mat4 model;
uniform mat4 projection;

void main() {
	TexCoords = aTexCoords;
	gl_Position = projection * model * vec4(aPos, 0.0, 1.0);
}
`

sprite_fragment_source := `#version 330 core

in vec2 TexCoords;
out vec4 color;

uniform sampler2D image;
uniform vec3 spriteColor;

void main() {
	color = vec4(spriteColor, 1.0) * texture(image, TexCoords);
}
`

sprite_grayscale_fragment_source := `#version 330 core

in vec2 TexCoords;
out vec4 color;

uniform sampler2D image;
uniform vec3 spriteColor;

void main() {
	color = vec4(spriteColor, 1.0) * texture(image, TexCoords).rrra;
}
`
