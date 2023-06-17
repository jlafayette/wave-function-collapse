package main

import "core:fmt"
import "core:strings"
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
	rotate: f32,
	color: glm.vec3,
) {
	gl.UseProgram(program_id)
	model := glm.mat4(1)
	model = model * glm.mat4Translate({pos.x, pos.y, 0})
	model = model * glm.mat4Translate({.5 * size.x, .5 * size.y, 0})
	model = model * glm.mat4Rotate({0, 0, 1}, glm.radians(rotate))
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
	sprite: u32,
}
Textures :: struct {
	corner: Texture2D,
	cross:  Texture2D,
	empty:  Texture2D,
	line:   Texture2D,
	t:      Texture2D,
}

Renderer :: struct {
	shaders:  ShaderPrograms,
	textures: Textures,
	buffers:  SpriteBuffers,
}
renderer_init :: proc(r: ^Renderer, projection: glm.mat4) -> bool {
	ok: bool
	r.shaders.sprite, ok = gl.load_shaders_source(sprite_vertex_source, sprite_fragment_source)
	if !ok {
		fmt.eprintln("Failed to create GLSL program")
		return false
	}

	r.buffers = sprite_buffers_init()

	textures: [5]Texture2D
	paths: [5]cstring = {
		"Knots/corner.png",
		"Knots/cross.png",
		"Knots/empty.png",
		"Knots/line.png",
		"Knots/t.png",
	}
	for path, i in paths {
		textures[i] = sprite_texture(path, r.shaders.sprite, projection)
	}
	r.textures.corner = textures[0]
	r.textures.cross = textures[1]
	r.textures.empty = textures[2]
	r.textures.line = textures[3]
	r.textures.t = textures[4]

	return true
}
renderer_destroy :: proc(r: ^Renderer) {
	sprite_buffers_destroy(&r.buffers)
	gl.DeleteProgram(r.shaders.sprite)
}

game_render :: proc(g: ^Game, window: ^sdl2.Window) {
	r := &g.renderer
	game := g
	vao := r.buffers.vao

	// render
	gl.Viewport(0, 0, i32(g.window_width), i32(g.window_height))
	gl.ClearColor(0.007843, 0.02353, 0.02745, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	shader := r.shaders.sprite
	x: f32 = 10
	y: f32 = 10
	w: f32 = 100
	h: f32 = 100
	space: f32 = 10
	draw_sprite(shader, r.textures.corner.id, r.buffers.vao, {x, y}, {w, h}, 0, {1, 1, 1})
	x += w + space
	draw_sprite(shader, r.textures.cross.id, r.buffers.vao, {x, y}, {w, h}, 0, {1, 1, 1})
	x += w + space
	draw_sprite(shader, r.textures.empty.id, r.buffers.vao, {x, y}, {w, h}, 0, {1, 1, 1})
	x += w + space
	draw_sprite(shader, r.textures.line.id, r.buffers.vao, {x, y}, {w, h}, 0, {1, 1, 1})
	x += w + space
	draw_sprite(shader, r.textures.t.id, r.buffers.vao, {x, y}, {w, h}, 0, {1, 1, 1})

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
