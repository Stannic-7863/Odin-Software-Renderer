package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import "core:prof/spall"
import "core:slice"
import "core:sync"

import rl "vendor:raylib"

import sr "renderer"

Vertex :: [3]sr.Shader_Data_Type

cube_vertices := []Vertex {
	// Front (+Z)
	{sr.Vec3f32{-0.5, -0.5, 0.5}, sr.Vec3f32{1, 0, 0}, sr.Vec2f32{0, 0}},
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

basic_vertex_shader :: proc(input: []sr.Shader_Data_Type, userdata: rawptr, io: ^sr.Buffer) -> sr.Vec4f32 #no_bounds_check {
	position := input[0].(sr.Vec3f32)
	color := input[1].(sr.Vec3f32)
	uv := input[2].(sr.Vec2f32)

	mats := (cast(^Mats)userdata)^

	sr.shader_write_out(io, color)
	sr.shader_write_out(io, uv)

	return mats.perspective * mats.camera * mats.model * sr.Vec4f32{position.x, position.y, position.z, 1}
}

basic_frag_shader :: proc(input: []sr.Shader_Data_Type, userdata: rawptr) -> sr.Vec4f32 #no_bounds_check {
	color := input[0].(sr.Vec3f32)
	uv := input[1].(sr.Vec2f32)

	return {uv.x, uv.y, 0, 1}
}

main :: proc() {
	when ODIN_DEBUG {
		spall_ctx = spall.context_create("trace_test.spall")
		defer spall.context_destroy(&spall_ctx)

		buffer_backing := make([]u8, spall.BUFFER_DEFAULT_SIZE)
		defer delete(buffer_backing)

		spall_buffer = spall.buffer_create(buffer_backing, u32(sync.current_thread_id()))
		defer spall.buffer_destroy(&spall_ctx, &spall_buffer)
	}

	context.logger = log.create_console_logger(opt = {.Level})
	defer log.destroy_console_logger(context.logger)

	width, height := 200, 200

	r := sr.create_renderer(width, height, context.allocator)

	v_buf_index := sr.create_buffer(&r)
	i_buf_index := sr.create_buffer(&r)

	{
		v_buf := sr.get_buffer(&r, v_buf_index)
		i_buf := sr.get_buffer(&r, i_buf_index)

		append(v_buf, ..slice.to_bytes(cube_vertices))
		append(i_buf, ..slice.to_bytes(cube_indices))
	}

	cube_pipeline := sr.create_pipeline(&r, basic_vertex_shader, basic_frag_shader, v_buf_index, i_buf_index, size_of(Vertex))

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(i32(width * 2), i32(height), "Window")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)

	framebuffer_texture := rl.LoadTextureFromImage(
		{width = cast(i32)width, height = cast(i32)height, data = raw_data(r.framebuffer.data), format = .UNCOMPRESSED_R8G8B8A8, mipmaps = 1},
	)

	depthbuffer_texture := rl.LoadTextureFromImage(
		{width = cast(i32)width, height = cast(i32)height, data = raw_data(r.depthbuffer.data), format = .UNCOMPRESSED_R8G8B8A8, mipmaps = 1},
	)


	frametime: f32

	mats: Mats

	camera_position := sr.Vec3f32{0, 0, 0}
	camera_front := sr.Vec3f32{0, 0, 1}
	camera_up := sr.Vec3f32{0, 1, 0}
	camera_right := linalg.cross(camera_front, camera_up)

	for !rl.WindowShouldClose() {
		mats.perspective = linalg.matrix4_perspective_f32(linalg.PI / 2.5, f32(width / height), 0.001, 1000, true)
		mats.model =
			linalg.matrix4_translate_f32({0, 0, -2}) *
			linalg.matrix4_scale_f32(1) *
			linalg.matrix4_rotate_f32(frametime, {0, 1, 1}) *
			linalg.MATRIX4F32_IDENTITY
		mats.camera = linalg.matrix4_look_at_f32(camera_position, camera_position - camera_front, camera_up)

		{
			sr.image_clear_color(r.framebuffer, {1, 1, 1, 1})
			sr.image_clear_bytes(r.depthbuffer, transmute([4]u8)max(f32))
			sr.pipeline_set_shader_userdata(&r, cube_pipeline, &mats, nil)
			sr.pipeline_process(&r, cube_pipeline)
		}

		{
			if rl.IsKeyDown(.UP) {camera_position -= camera_front * rl.GetFrameTime()}
			if rl.IsKeyDown(.DOWN) {camera_position += camera_front * rl.GetFrameTime()}
			if rl.IsKeyDown(.LEFT) {camera_position -= camera_right * rl.GetFrameTime()}
			if rl.IsKeyDown(.RIGHT) {camera_position += camera_right * rl.GetFrameTime()}

			frametime += rl.GetFrameTime() / 10
			rl.BeginDrawing()
			rl.ClearBackground({0, 0, 0, 1})

			for i := 0; i < len(r.depthbuffer.data); i += 4 {
				data := r.depthbuffer.data[i:i + 4]
				f := ((cast(^f32)raw_data(data))^ / 2) + 0.5
				z_linear := (2 * 0.01 * 100) / (100 + 0.01 - f * (100 - 0.01))
				u := u8(linalg.pow(f, 0.25) * 255)

				r.depthbuffer.data[i] = u
				r.depthbuffer.data[i + 1] = u
				r.depthbuffer.data[i + 2] = u
				r.depthbuffer.data[i + 3] = 255
			}

			rl.UpdateTexture(framebuffer_texture, raw_data(r.framebuffer.data))
			rl.UpdateTexture(depthbuffer_texture, raw_data(r.depthbuffer.data))

			rl.DrawTexturePro(
				depthbuffer_texture,
				{0, 0, f32(width), f32(height)},
				{f32(rl.GetScreenWidth() / 2), 0, f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight())},
				0,
				0,
				255,
			)

			rl.DrawTexturePro(
				framebuffer_texture,
				{0, 0, f32(width), f32(height)},
				{0, 0, f32(rl.GetScreenWidth() / 2), f32(rl.GetScreenHeight())},
				0,
				0,
				255,
			)

			rl.DrawFPS(0, 0)
			rl.EndDrawing()
		}
	}
}


when ODIN_DEBUG {
	spall_ctx: spall.Context
	@(thread_local)
	spall_buffer: spall.Buffer


	@(instrumentation_enter)
	spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
		spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
	}

	@(instrumentation_exit)
	spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
		spall._buffer_end(&spall_ctx, &spall_buffer)
	}
}
