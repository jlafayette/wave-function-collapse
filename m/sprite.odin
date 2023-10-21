package m

import "core:fmt"
import "core:strings"
import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"
import "vendor:stb/image"
import "vendor:sdl2"


Tile :: enum {
	CORNER,
	CROSS,
	EMPTY,
	LINE,
	T,
}
tile_offset :: proc(tile: Tile) -> (f32, f32) {
	start, end : f32
	switch tile {
	case .CORNER:
		start = 0; end = 0.2
	case .CROSS:
		start = 0.2; end = 0.4
	case .EMPTY:
		start = 0.4; end = 0.6
	case .LINE:
		start = 0.6; end = 0.8
	case .T:
		start = 0.8; end = 1
	}
	return start, end
}
Buffers :: struct {
	vbo: u32,
	vao: u32,
	vertices: [dynamic]Vertex,
}
Vertex :: struct {
	pos: glm.vec2,
	tex: glm.vec2,
}
buffers_init :: proc() -> Buffers {
	vbo, vao: u32
	vertices := make([dynamic]Vertex, 0, 12)
	tmp := []Vertex{
		{{0, 1}, {0, 1}},
		{{1, 0}, {1, 0}},
		{{0, 0}, {0, 0}},
		{{0, 1}, {0, 1}},
		{{1, 1}, {1, 1}},
		{{1, 0}, {1, 0}},
	}
	for v in tmp {
		append(&vertices, v)
	}

	gl.GenVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(
		gl.ARRAY_BUFFER,
		len(vertices) * size_of(vertices[0]),
		raw_data(vertices[:]),
		gl.DYNAMIC_DRAW,
	)
	gl.BindVertexArray(vao)
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(
		0,
		2,
		gl.FLOAT,
		false,
		size_of(Vertex),
		offset_of(Vertex, pos),
	)
	gl.VertexAttribPointer(
		1,
		2,
		gl.FLOAT,
		false,
		size_of(Vertex),
		offset_of(Vertex, tex),
	)

	return Buffers{vbo, vao, vertices}
}
buffers_destroy :: proc(buffers: ^Buffers) {
	gl.DeleteBuffers(1, &buffers.vbo)
	gl.DeleteVertexArrays(1, &buffers.vao)
	delete(buffers.vertices)
}
buffers_append_tile :: proc(b: ^Buffers, tile: Tile, offset: vec2) {
	s, e := tile_offset(tile)
	tmp := []Vertex{
		{{0, 1}, {s, 1}},
		{{1, 0}, {e, 0}},
		{{0, 0}, {s, 0}},
		{{0, 1}, {s, 1}},
		{{1, 1}, {e, 1}},
		{{1, 0}, {e, 0}},
	}
	for v in tmp {
		append(&b.vertices, Vertex{v.pos + offset, v.tex})
	}
}

Texture2D :: struct {
	id:     u32,
	width:  i32,
	height: i32,
}
texture :: proc(filename: cstring, program_id: u32, projection: glm.mat4) -> Texture2D {
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

	gl.UseProgram(program_id)
	gl.Uniform1i(gl.GetUniformLocation(program_id, "image"), 0)
	proj := projection
	gl.UniformMatrix4fv(gl.GetUniformLocation(program_id, "projection"), 1, false, &proj[0, 0])
	return tex
}

draw_tiles :: proc(
	program_id: u32,
	texture_id: u32,
	vao: u32,
	vertex_count: i32,
	size: glm.vec2,
) {
	gl.UseProgram(program_id)
	model := glm.mat4(1)
	model = model * glm.mat4Scale({size.x, size.y, 1})
	gl.UniformMatrix4fv(gl.GetUniformLocation(program_id, "model"), 1, false, &model[0, 0])
	c : glm.vec3 = {1, 1, 1}
	gl.Uniform3fv(gl.GetUniformLocation(program_id, "spriteColor"), 1, &c[0])
	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, texture_id)

	gl.BindVertexArray(vao); defer gl.BindVertexArray(0)

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

	gl.DrawArrays(gl.TRIANGLES, 0, vertex_count)
}

draw_sprite :: proc(
	program_id: u32,
	texture_id: u32,
	vao: u32,
	vertex_count: i32,
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

	gl.DrawArrays(gl.TRIANGLES, 0, vertex_count)
}

Renderer :: struct {
	shader:  u32,
	texture: Texture2D,
	buffers: Buffers,
}
renderer_init :: proc(r: ^Renderer, projection: glm.mat4) -> bool {
	ok: bool
	r.shader, ok = gl.load_shaders_source(vertex_source, fragment_source)
	if !ok {
		fmt.eprintln("Failed to create sprite GLSL program")
		return false
	}

	r.buffers = buffers_init()

	path: cstring = "m/combined.png"

	r.texture = texture(path, r.shader, projection)

	return true
}
renderer_destroy :: proc(r: ^Renderer) {
	buffers_destroy(&r.buffers)
	gl.DeleteProgram(r.shader)
}

render :: proc(g: ^Game, window: ^sdl2.Window) {
	r := &g.renderer
	buffers := &r.buffers
	vao := r.buffers.vao
	vbo := r.buffers.vbo

	// render
	gl.Viewport(0, 0, i32(g.window_width), i32(g.window_height))
	gl.ClearColor(0.007843, 0.02353, 0.02745, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)

	size := cast(f32)r.texture.height
	scale: f32 = 10
	// w := f32(r.texture.width) * scale
	// h := f32(r.texture.height) * scale
	w := size * scale
	h := size * scale

	{
		clear(&buffers.vertices)
		buffers_append_tile(buffers, .CORNER, {0, 0})
		buffers_append_tile(buffers, .T, {1, 0})
		buffers_append_tile(buffers, .LINE, {0, 1})
		buffers_append_tile(buffers, .CROSS, {1, 1})

		gl.BindBuffer(gl.ARRAY_BUFFER, vbo); defer gl.BindBuffer(gl.ARRAY_BUFFER, 0)
		gl.BufferData(
			gl.ARRAY_BUFFER,
			len(buffers.vertices) * size_of(buffers.vertices[0]),
			raw_data(buffers.vertices[:]),
			gl.DYNAMIC_DRAW,
		)
	}

	v_count := cast(i32)len(buffers.vertices)
	draw_tiles(r.shader, r.texture.id, vao, v_count, {w, h})
	// draw_sprite(r.shader, r.texture.id, vao, v_count, {0, 0}, {w, h}, 0, {1, 1, 1})

	gl_report_error()
	sdl2.GL_SwapWindow(window)
}

gl_report_error :: proc() {
	e := gl.GetError()
	if e != gl.NO_ERROR {
		fmt.println("OpenGL Error:", e)
	}
}

vertex_source := `#version 330 core

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

fragment_source := `#version 330 core

in vec2 TexCoords;
out vec4 color;

uniform sampler2D image;
uniform vec3 spriteColor;

void main() {
	color = vec4(spriteColor, 1.0) * texture(image, TexCoords);
}
`
