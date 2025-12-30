package software_renderer

import "base:intrinsics"
import "base:runtime"
import "core:math"
import "core:slice"

FIXED_SCALE :: 8
Fixed :: distinct i32

Vec2Fixed :: [2]Fixed
Vec3Fixed :: [3]Fixed
Vec4Fixed :: [4]Fixed

Vec2f32 :: [2]f32
Vec3f32 :: [3]f32
Vec4f32 :: [4]f32

f32_to_fixed :: proc(f: f32) -> Fixed {
	return Fixed(f * (1 << FIXED_SCALE))
}

fixed_to_f32 :: proc(f: Fixed) -> f32 {
	return f32(f) / f32(1 << FIXED_SCALE)
}

fixed_mul :: proc(a, b: Fixed) -> Fixed {
	return Fixed(i64(a) * i64(b) >> FIXED_SCALE)
}

fixed_div :: proc(a, b: Fixed) -> Fixed {
	if b == 0 do return 0
	return Fixed((i64(a) << FIXED_SCALE) / i64(b))
}

fixed_mul_frac :: proc(a, b: Fixed, frac: uint) -> Fixed {
	return Fixed((i64(a) * i64(b)) >> frac)
}

fixed_div_frac :: proc(a, b: Fixed, frac: uint) -> Fixed {
	if b == 0 do return 0
	return Fixed((i64(a) << frac) / i64(b))
}

fixed_cross :: proc(a: Vec2Fixed, b: Vec2Fixed) -> Fixed {
	return fixed_mul(a.x, b.y) - fixed_mul(a.y, b.x)
}


Shader_Data_Type :: union {
	f32,
	Vec2f32,
	Vec3f32,
	Vec4f32,
}

Vertex_Shader :: proc(input: []Shader_Data_Type, userdata: rawptr, io: ^Buffer) -> Vec4f32
Fragment_Shader :: proc(input: []Shader_Data_Type, userdata: rawptr) -> Vec4f32

Buffer :: [dynamic]byte
// NOTE : Should probably make it so each pipeline owns its own framebuffer and depth buffer
Pipeline :: struct {
	stride_size:       int,
	index_buffer:      int,
	vertex_buffer:     int,
	io_buffer:         int,
	vertex_output:     []Shader_Data_Type,
	frag_inputs:       []Shader_Data_Type,
	vertex_shader:     Vertex_Shader,
	fragment_shader:   Fragment_Shader,
	vertex_userdata:   rawptr,
	fragment_userdata: rawptr,
}

Renderer :: struct {
	framebuffer: Image,
	depthbuffer: Image,
	viewport:    Vec4f32,
	pipelines:   [dynamic]Pipeline,
	buffers:     [dynamic]Buffer,
	allocator:   runtime.Allocator,
}

create_renderer :: proc(width, height: int, allocator: runtime.Allocator) -> Renderer {
	r: Renderer
	r.allocator = allocator

	r.pipelines = make([dynamic]Pipeline, r.allocator)
	r.framebuffer = create_image(width, height, 4, r.allocator)
	r.depthbuffer = create_image(width, height, 4, r.allocator)

	r.viewport = {0, 0, f32(width), f32(height)}

	return r
}

create_pipeline :: proc(
	renderer: ^Renderer,
	v_shader: Vertex_Shader,
	f_shader: Fragment_Shader,
	vertex_buffer, index_buffer, stride_size: int,
) -> int {
	p: Pipeline

	p.vertex_shader = v_shader
	p.fragment_shader = f_shader

	p.stride_size = stride_size
	p.index_buffer = index_buffer
	p.vertex_buffer = vertex_buffer

	p.io_buffer = create_buffer(renderer)

	index := len(renderer.pipelines)
	append(&renderer.pipelines, p)
	return index
}

create_buffer :: proc(renderer: ^Renderer) -> int {
	index := len(renderer.buffers)
	buffer := make(Buffer, renderer.allocator)
	append(&renderer.buffers, buffer)
	return index
}

get_buffer :: proc(renderer: ^Renderer, index: int) -> ^Buffer {
	return &renderer.buffers[index]
}

shader_write_out :: proc(io: ^Buffer, data: Shader_Data_Type) {
	data := data
	out_ptr := cast(^[size_of(Shader_Data_Type)]byte)&data
	out := out_ptr^[:]
	append(io, ..out)
}

// NOTE : Should make some nice defaults. And also check for out of bound/invalid parameters
pipeline_set_shader_userdata :: proc(renderer: ^Renderer, pipeline_index: int, v_userdata: rawptr, f_userdata: rawptr) {
	renderer.pipelines[pipeline_index].fragment_userdata = f_userdata
	renderer.pipelines[pipeline_index].vertex_userdata = v_userdata
}

pipeline_process :: proc(renderer: ^Renderer, pipeline_index: int) {

	fb_fixed_size := Vec2Fixed{Fixed(renderer.framebuffer.width << FIXED_SCALE), Fixed(renderer.framebuffer.height << FIXED_SCALE)}
	fb_float_size := Vec2f32{f32(renderer.framebuffer.width), f32(renderer.framebuffer.height)}

	pipeline := &renderer.pipelines[pipeline_index]

	raw_index_buf := get_buffer(renderer, pipeline.index_buffer)
	raw_vert_buf := get_buffer(renderer, pipeline.vertex_buffer)
	raw_io_buf := get_buffer(renderer, pipeline.io_buffer)

	index_buf := slice.reinterpret([]int, raw_index_buf^[:])

	for index_i := 0; index_i < len(index_buf); index_i += 3 {
		defer clear(raw_io_buf)
		vertex_index_1 := index_buf[index_i] * pipeline.stride_size
		vertex_index_2 := index_buf[index_i + 1] * pipeline.stride_size
		vertex_index_3 := index_buf[index_i + 2] * pipeline.stride_size

		vertex_1_input_data := slice.reinterpret([]Shader_Data_Type, raw_vert_buf^[vertex_index_1:vertex_index_1 + pipeline.stride_size])
		vertex_2_input_data := slice.reinterpret([]Shader_Data_Type, raw_vert_buf^[vertex_index_2:vertex_index_2 + pipeline.stride_size])
		vertex_3_input_data := slice.reinterpret([]Shader_Data_Type, raw_vert_buf^[vertex_index_3:vertex_index_3 + pipeline.stride_size])

		// Gather data written out from vertex shader
		vertex_out_start := len(raw_io_buf)

		clip_v1 := pipeline.vertex_shader(vertex_1_input_data, pipeline.vertex_userdata, raw_io_buf)
		clip_v2 := pipeline.vertex_shader(vertex_2_input_data, pipeline.vertex_userdata, raw_io_buf)
		clip_v3 := pipeline.vertex_shader(vertex_3_input_data, pipeline.vertex_userdata, raw_io_buf)

		v1_w_inv := 1 / clip_v1.w
		v2_w_inv := 1 / clip_v2.w
		v3_w_inv := 1 / clip_v3.w

		vertex_out_end := len(raw_io_buf)

		vertex_out_stride := ((vertex_out_end - vertex_out_start) / size_of(Shader_Data_Type)) / 3

		// Use the io buffer to also store fragment input data.
		// Use one slot only. The slot will get rewritten for every fragment we process
		for _ in 0 ..< vertex_out_stride {
			shader_write_out(raw_io_buf, nil)
		}

		vertex_out_data := slice.reinterpret([]Shader_Data_Type, raw_io_buf^[vertex_out_start:vertex_out_end])
		frag_input_data := slice.reinterpret([]Shader_Data_Type, raw_io_buf^[vertex_out_end:])

		// Also grab the per vertex data
		v1_data := vertex_out_data[:vertex_out_stride]
		v2_data := vertex_out_data[vertex_out_stride:vertex_out_stride + vertex_out_stride]
		v3_data := vertex_out_data[vertex_out_stride + vertex_out_stride:vertex_out_stride + vertex_out_stride + vertex_out_stride]

		// perspective divide
		// vertex shader output is in clip space
		// perspective info encoded into w component via perspective matrix
		projected_v1 := clip_v1.xyz / clip_v1.w if clip_v1.w != 0 else clip_v1.xyz
		projected_v2 := clip_v2.xyz / clip_v2.w if clip_v2.w != 0 else clip_v2.xyz
		projected_v3 := clip_v3.xyz / clip_v3.w if clip_v3.w != 0 else clip_v3.xyz

		// TODO Clipping and triangle splitting, for now, ball


		// High precision baby
		z_values_fixed := Vec3Fixed {
			Fixed(projected_v1.z * (1 << 23)),
			Fixed(projected_v2.z * (1 << 23)),
			Fixed(projected_v3.z * (1 << 23)),
		}

		// screen space mapping
		space_v1 := Vec2Fixed {
			f32_to_fixed(math.round((projected_v1.x + 1) * 0.5 * fb_float_size.x)),
			f32_to_fixed(math.round((projected_v1.y + 1) * 0.5 * fb_float_size.y)),
		}
		space_v2 := Vec2Fixed {
			f32_to_fixed(math.round((projected_v2.x + 1) * 0.5 * fb_float_size.x)),
			f32_to_fixed(math.round((projected_v2.y + 1) * 0.5 * fb_float_size.y)),
		}
		space_v3 := Vec2Fixed {
			f32_to_fixed(math.round((projected_v3.x + 1) * 0.5 * fb_float_size.x)),
			f32_to_fixed(math.round((projected_v3.y + 1) * 0.5 * fb_float_size.y)),
		}

		if space_v1.x < 0 || space_v1.y < 0 || space_v1.x >= fb_fixed_size.x || space_v1.y >= fb_fixed_size.y {continue}
		if space_v2.x < 0 || space_v2.y < 0 || space_v2.x >= fb_fixed_size.x || space_v2.y >= fb_fixed_size.y {continue}
		if space_v3.x < 0 || space_v3.y < 0 || space_v3.x >= fb_fixed_size.x || space_v3.y >= fb_fixed_size.y {continue}

		min_x := min(space_v1.x, space_v2.x, space_v3.x)
		min_y := min(space_v1.y, space_v2.y, space_v3.y)
		max_x := max(space_v1.x, space_v2.x, space_v3.x)
		max_y := max(space_v1.y, space_v2.y, space_v3.y)

		for fx := min_x; fx < max_x; fx += Fixed(1 << FIXED_SCALE) {
			for fy := min_y; fy < max_y; fy += Fixed(1 << FIXED_SCALE) {
				sample_point_fixed := Vec2Fixed{fx + (1 << (FIXED_SCALE - 1)), fy + (1 << (FIXED_SCALE - 1))}

				weights_fixed, area_fixed := point_in_triangle(space_v1, space_v2, space_v3, sample_point_fixed) or_continue

				weights_normalized := Vec3Fixed {
					fixed_div(weights_fixed.x, area_fixed),
					fixed_div(weights_fixed.y, area_fixed),
					fixed_div(weights_fixed.z, area_fixed),
				}

				weights_float := Vec3f32 {
					fixed_to_f32(weights_normalized.x),
					fixed_to_f32(weights_normalized.y),
					fixed_to_f32(weights_normalized.z),
				}

				depth :=
					fixed_mul_frac(fixed_div_frac(weights_fixed.x, area_fixed, 23), z_values_fixed.x, 23) +
					fixed_mul_frac(fixed_div_frac(weights_fixed.y, area_fixed, 23), z_values_fixed.y, 23) +
					fixed_mul_frac(fixed_div_frac(weights_fixed.z, area_fixed, 23), z_values_fixed.z, 23)


				prev_depth := image_get_bytes(renderer.depthbuffer, sample_point_fixed)

				if (cast(^Fixed)raw_data(prev_depth))^ <= depth {continue}

				for stride_i in 0 ..< vertex_out_stride {
					v1_stride_data := v1_data[stride_i]
					v2_stride_data := v2_data[stride_i]
					v3_stride_data := v3_data[stride_i]

					switch _ in v1_stride_data {
					case f32:
						v1_t := v1_stride_data.(f32) * weights_float.x
						v2_t := v2_stride_data.(f32) * weights_float.y
						v3_t := v3_stride_data.(f32) * weights_float.z
						frag_input_data[stride_i] = f32(v1_t + v2_t + v3_t)
					case Vec2f32:
						v1_t := v1_stride_data.(Vec2f32) * weights_float.x
						v2_t := v2_stride_data.(Vec2f32) * weights_float.y
						v3_t := v3_stride_data.(Vec2f32) * weights_float.z
						frag_input_data[stride_i] = Vec2f32(v1_t + v2_t + v3_t)
					case Vec3f32:
						v1_t := v1_stride_data.(Vec3f32) * weights_float.x
						v2_t := v2_stride_data.(Vec3f32) * weights_float.y
						v3_t := v3_stride_data.(Vec3f32) * weights_float.z
						frag_input_data[stride_i] = Vec3f32(v1_t + v2_t + v3_t)
					case Vec4f32:
						v1_t := v1_stride_data.(Vec4f32) * weights_float.x
						v2_t := v2_stride_data.(Vec4f32) * weights_float.y
						v3_t := v3_stride_data.(Vec4f32) * weights_float.z
						frag_input_data[stride_i] = Vec4f32(v1_t + v2_t + v3_t)
					}
				}

				out_color := pipeline.fragment_shader(frag_input_data, pipeline.fragment_userdata)
				image_set_color(renderer.framebuffer, sample_point_fixed, out_color)
				image_set_bytes(renderer.depthbuffer, sample_point_fixed, transmute([4]u8)depth)
			}
		}
	}
}

point_in_triangle :: #force_inline proc(p1, p2, p3: Vec2Fixed, sample_point: Vec2Fixed) -> (Vec3Fixed, Fixed, bool) #no_bounds_check {
	v1 := p1 - sample_point
	v2 := p2 - sample_point
	v3 := p3 - sample_point

	e1 := p2 - p1
	e2 := p3 - p2
	e3 := p1 - p3

	t1 := fixed_cross(e1, -v1)
	t2 := fixed_cross(e2, -v2)
	t3 := fixed_cross(e3, -v3)

	area := fixed_cross(p2 - p1, p3 - p1)

	w1 := fixed_cross(v2, v3)
	w2 := fixed_cross(v3, v1)
	w3 := fixed_cross(v1, v2)
	if area <= 0 {

		w1 = -w1
		w2 = -w2
		w3 = -w3
		t1 = -t1
		t2 = -t2
		t3 = -t3
		area = -area

	}

	is_top_left :: proc(e: Vec2Fixed) -> bool {
		return e.y > 0 || (e.y == 0 && e.x < 0)
	}

	return {w1, w2, w3},
		area,
		(t1 > 0 || (t1 == 0 && is_top_left(e1))) && (t2 > 0 || (t2 == 0 && is_top_left(e2))) && (t3 > 0 || (t3 == 0 && is_top_left(e3)))
}
