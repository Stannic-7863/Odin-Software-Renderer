package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "vendor:stb/image"

import rl "vendor:raylib"

import sr "renderer"

Vertex :: struct {
	pos: sr.Vec3f32,
	col: sr.Vec3f32,
	uv:  sr.Vec2f32,
}

phi := f32(1.6180339887498948482)
icosa_vertices := []Vertex {
	// (0, ±1, ±φ)
	{sr.Vec3f32{0, 1, phi}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0, -1, phi}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0, 1, -phi}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0, -1, -phi}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},

	// (±1, ±φ, 0)
	{sr.Vec3f32{1, phi, 0}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{-1, phi, 0}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{1, -phi, 0}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{-1, -phi, 0}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},

	// (±φ, 0, ±1)
	{sr.Vec3f32{phi, 0, 1}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{-phi, 0, 1}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{phi, 0, -1}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{-phi, 0, -1}, sr.Vec3f32{0, 0, 0}, sr.Vec2f32{0, 0}},
}

// odinfmt: disable
icosa_indices := []int{
	0, 1, 8,
	0, 8, 4,
	0, 4, 5,
	0, 5, 9,
	0, 9, 1,

	1, 6, 8,
	8, 6, 10,
	8, 10, 4,
	4, 10, 2,
	4, 2, 5,

	5, 2, 11,
	5, 11, 9,
	9, 11, 7,
	9, 7, 1,
	1, 7, 6,

	3, 2, 10,
	3, 10, 6,
	3, 6, 7,
	3, 7, 11,
	3, 11, 2,
}
// odinfmt: enable

cube_vertices := []Vertex {
	// Front (+Z)
	{sr.Vec3f32{-0.5, -0.5, 0.5}, sr.Vec3f32{1, 0, 1}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0.5, -0.5, 0.5}, sr.Vec3f32{1, 1, 0}, sr.Vec2f32{1, 0}},
	{sr.Vec3f32{0.5, 0.5, 0.5}, sr.Vec3f32{1, 0, 1}, sr.Vec2f32{1, 1}},
	{sr.Vec3f32{-0.5, 0.5, 0.5}, sr.Vec3f32{0, 1, 1}, sr.Vec2f32{0, 1}},

	// Back (-Z)
	{sr.Vec3f32{0.5, -0.5, -0.5}, sr.Vec3f32{0, 1, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{-0.5, -0.5, -0.5}, sr.Vec3f32{0, 1, 0}, sr.Vec2f32{1, 0}},
	{sr.Vec3f32{-0.5, 0.5, -0.5}, sr.Vec3f32{0, 1, 0}, sr.Vec2f32{1, 1}},
	{sr.Vec3f32{0.5, 0.5, -0.5}, sr.Vec3f32{0, 1, 0}, sr.Vec2f32{0, 1}},

	// Left (-X)
	{sr.Vec3f32{-0.5, -0.5, -0.5}, sr.Vec3f32{0, 0, 1}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{-0.5, -0.5, 0.5}, sr.Vec3f32{0, 0, 1}, sr.Vec2f32{1, 0}},
	{sr.Vec3f32{-0.5, 0.5, 0.5}, sr.Vec3f32{0, 0, 1}, sr.Vec2f32{1, 1}},
	{sr.Vec3f32{-0.5, 0.5, -0.5}, sr.Vec3f32{0, 0, 1}, sr.Vec2f32{0, 1}},

	// Right (+X)
	{sr.Vec3f32{0.5, -0.5, 0.5}, sr.Vec3f32{1, 1, 0}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0.5, -0.5, -0.5}, sr.Vec3f32{1, 1, 0}, sr.Vec2f32{1, 0}},
	{sr.Vec3f32{0.5, 0.5, -0.5}, sr.Vec3f32{1, 1, 0}, sr.Vec2f32{1, 1}},
	{sr.Vec3f32{0.5, 0.5, 0.5}, sr.Vec3f32{1, 1, 0}, sr.Vec2f32{0, 1}},

	// Top (+Y)
	{sr.Vec3f32{-0.5, 0.5, 0.5}, sr.Vec3f32{1, 0, 1}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0.5, 0.5, 0.5}, sr.Vec3f32{1, 0, 1}, sr.Vec2f32{1, 0}},
	{sr.Vec3f32{0.5, 0.5, -0.5}, sr.Vec3f32{1, 0, 1}, sr.Vec2f32{1, 1}},
	{sr.Vec3f32{-0.5, 0.5, -0.5}, sr.Vec3f32{1, 0, 1}, sr.Vec2f32{0, 1}},

	// Bottom (-Y)
	{sr.Vec3f32{-0.5, -0.5, -0.5}, sr.Vec3f32{0, 1, 1}, sr.Vec2f32{0, 0}},
	{sr.Vec3f32{0.5, -0.5, -0.5}, sr.Vec3f32{0, 1, 1}, sr.Vec2f32{1, 0}},
	{sr.Vec3f32{0.5, -0.5, 0.5}, sr.Vec3f32{0, 1, 1}, sr.Vec2f32{1, 1}},
	{sr.Vec3f32{-0.5, -0.5, 0.5}, sr.Vec3f32{0, 1, 1}, sr.Vec2f32{0, 1}},
}

// odinfmt: disable
cube_indices := []int{
    0,1,2,  0,2,3,        // Front
    4,5,6,  4,6,7,        // Back
    8,9,10, 8,10,11,      // Left
    12,13,14, 12,14,15,   // Right
    16,17,18, 16,18,19,   // Top
    20,21,22, 20,22,23,   // Bottom
}
// odinfmt: enable

Mats :: struct {
	perspective: matrix[4, 4]f32,
	model:       matrix[4, 4]f32,
	camera:      matrix[4, 4]f32,
}

basic_vertex_shader :: proc(input: []u8, userdata: rawptr, io: ^sr.Buffer) -> sr.Vec4f32 #no_bounds_check {
	v := (cast(^Vertex)&input[0])^
	position := v.pos
	color := v.col
	uv := v.uv

	mats := (cast(^Mats)userdata)^

	sr.shader_write_out(io, color)
	sr.shader_write_out(io, uv)

	return mats.perspective * mats.camera * mats.model * sr.Vec4f32{position.x, position.y, position.z, 1}
}

basic_frag_shader :: proc(input: []u8, samplers: []sr.Sampler, userdata: rawptr) -> sr.Vec4f32 #no_bounds_check {
	color := (cast(^sr.Vec3f32)&input[0])^
	uv := (cast(^sr.Vec2f32)&input[12])^

	sc := sr.sample_color(samplers[0], uv)

	return {sc.r, sc.g, sc.g, 1}
	// return {color.r * 0.5 + 0.5, color.g * 0.5 + 0.5, color.b * 0.5 + 0.5, 1}
}

main :: proc() {
	context.logger = log.create_console_logger(opt = {.Level})
	defer log.destroy_console_logger(context.logger)

	width, height := 500, 400

	r := sr.create_renderer(width, height, context.allocator)

	v_buf_index := sr.create_buffer(&r)
	i_buf_index := sr.create_buffer(&r)

	verts, indicies := load_obj("./assets/models/stuff.obj")

	defer delete(verts)
	defer delete(indicies)

	{
		for i in 0 ..< len(icosa_vertices) {
			p := linalg.normalize(icosa_vertices[i].pos)
			icosa_vertices[i].pos = p

			icosa_vertices[i].col = sr.Vec3f32{p.x * 0.5 + 0.5, p.y * 0.5 + 0.5, p.z * 0.5 + 0.5}

			u := 0.5 + linalg.atan2(p.z, p.x) / (2 * linalg.PI)
			v := 0.5 - linalg.asin(p.y) / linalg.PI
			icosa_vertices[i].uv = sr.Vec2f32{u, v}
		}

		v_buf := sr.get_buffer(&r, v_buf_index)
		i_buf := sr.get_buffer(&r, i_buf_index)

		append(v_buf, ..slice.to_bytes(verts[:]))
		append(i_buf, ..slice.to_bytes(indicies[:]))
	}

	main_pipeline := sr.create_pipeline(&r, basic_vertex_shader, basic_frag_shader, v_buf_index, i_buf_index, 1, size_of(Vertex))
	framebuffer := r.pipelines[main_pipeline].framebuffer
	depthbuffer := r.pipelines[main_pipeline].depthbuffer

	texture_image: sr.ImageIndex

	{
		w, h, c: i32
		moyai := image.load("./assets/images/Moyai.png", &w, &h, &c, 0)
		texture_image = sr.create_image(&r, int(w), int(h), int(c))

		for b, i in moyai[:w * h * c] {
			r.images[texture_image].data[i] = b
		}
	}

	texture_sampler := sr.create_sampler(&r, texture_image)

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(i32(width), i32(height), "Window")
	defer rl.CloseWindow()
	rl.DisableCursor()

	framebuffer_texture := rl.LoadTextureFromImage(
		{
			width = cast(i32)width,
			height = cast(i32)height,
			data = raw_data(r.images[framebuffer].data),
			format = .UNCOMPRESSED_R8G8B8A8,
			mipmaps = 1,
		},
	)

	frametime: f32
	mats: Mats
	yaw: f32 = 6.740693
	pitch: f32 = 10.0103235
	camera_position := sr.Vec3f32{-3.4018359, -5.518117, -8.8438425}
	camera_front := sr.Vec3f32{0, 0, 1}
	camera_up := sr.Vec3f32{0, 1, 0}
	camera_right := linalg.cross(camera_front, camera_up)
	speed: f32 = 1

	for !rl.WindowShouldClose() {
		speed = 1
		mats.perspective = linalg.matrix4_perspective_f32(linalg.PI / 2.5, f32(width) / f32(height), 0.01, 100, true)
		mats.model = linalg.matrix4_translate_f32({0, 0, -2}) * linalg.matrix4_scale_f32(1) * linalg.MATRIX4F32_IDENTITY
		mats.camera = linalg.matrix4_look_at_f32(camera_position, camera_position - camera_front, camera_up)

		{
			sr.image_clear_color(r.images[framebuffer], {1, 1, 1, 1})
			sr.image_clear_bytes(r.images[depthbuffer], transmute([4]u8)max(f32))
			sr.pipeline_set_shader_userdata(&r, main_pipeline, &mats, nil)
			sr.pipeline_set_shader_samplers(&r, main_pipeline, {texture_sampler})
			sr.pipeline_process(&r, main_pipeline)
		}

		{
			frametime += rl.GetFrameTime()
			frametime = linalg.mod(frametime, linalg.PI * 20)

			camera_front.x = linalg.cos(pitch) * linalg.sin(yaw)
			camera_front.y = linalg.sin(pitch)
			camera_front.z = linalg.cos(pitch) * linalg.cos(yaw)

			camera_front = linalg.normalize(camera_front)
			camera_right = linalg.normalize(linalg.cross(camera_front, camera_up))
			camera_up := linalg.normalize(linalg.cross(camera_front, camera_right))

			pitch += rl.GetMouseDelta().y * rl.GetFrameTime()
			yaw += -rl.GetMouseDelta().x * rl.GetFrameTime()

			if rl.IsKeyDown(.LEFT_SHIFT) {speed = 10}
			if rl.IsKeyDown(.W) {camera_position -= camera_front * rl.GetFrameTime() * speed}
			if rl.IsKeyDown(.S) {camera_position += camera_front * rl.GetFrameTime() * speed}
			if rl.IsKeyDown(.A) {camera_position += camera_right * rl.GetFrameTime() * speed}
			if rl.IsKeyDown(.D) {camera_position -= camera_right * rl.GetFrameTime() * speed}


			rl.BeginDrawing()
			rl.ClearBackground({0, 0, 0, 1})

			rl.UpdateTexture(framebuffer_texture, raw_data(r.images[framebuffer].data))

			rl.DrawTexturePro(
				framebuffer_texture,
				{0, 0, f32(width), f32(height)},
				{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())},
				0,
				0,
				255,
			)

			rl.DrawFPS(0, 0)
			rl.EndDrawing()
		}
	}
}
