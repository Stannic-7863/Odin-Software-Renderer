package software_renderer

import "base:runtime"
import "core:math/linalg"
import "core:slice"

SUBPIXELS :: 4

ImageIndex :: distinct int
BufferIndex :: distinct int
SamplerIndex :: distinct int
PipelineIndex :: distinct int
ShaderSamplerIndex :: distinct int

Vec2f32 :: [2]f32
Vec3f32 :: [3]f32
Vec4f32 :: [4]f32

Vec2i32 :: [2]i32
Vec3i32 :: [3]i32

Vec2int :: [2]int
Vec4int :: [4]int

Vertex_Shader :: proc(info: Vert_Info, input: []u8, userdata: rawptr, io: ^Buffer) -> Vec4f32
Fragment_Shader :: proc(info: Frag_Info, input: []u8, samplers: []Sampler, userdata: rawptr) -> Vec4f32

Buffer :: [dynamic]byte

Pipeline :: struct {
	stride_size:       int,
	sampler_count:     int,
	index_buffer:      BufferIndex,
	vertex_buffer:     BufferIndex,
	io_buffer:         BufferIndex,
	samplers:          ShaderSamplerIndex,
	vertex_shader:     Vertex_Shader,
	fragment_shader:   Fragment_Shader,
	vertex_userdata:   rawptr,
	fragment_userdata: rawptr,
	framebuffer:       ImageIndex,
	depthbuffer:       ImageIndex,
}

Renderer :: struct {
	viewport:        Vec4int,
	pipelines:       [dynamic]Pipeline,
	buffers:         [dynamic]Buffer,
	images:          [dynamic]Image,
	samplers:        [dynamic]Sampler,
	shader_samplers: [dynamic]SamplerIndex,
	allocator:       runtime.Allocator,
}

Frag_Info :: struct {
	frag_coord: Vec4f32,
}

Vert_Info :: struct {
	vertex_id: int,
}

create_renderer :: proc(width, height: int, allocator: runtime.Allocator) -> Renderer {
	r: Renderer
	r.allocator = allocator

	r.images = make([dynamic]Image, r.allocator)
	r.buffers = make([dynamic]Buffer, r.allocator)
	r.samplers = make([dynamic]Sampler, r.allocator)
	r.pipelines = make([dynamic]Pipeline, r.allocator)
	r.shader_samplers = make([dynamic]SamplerIndex, r.allocator)

	r.viewport = {0, 0, width, height}

	return r
}

create_pipeline :: proc(
	renderer: ^Renderer,
	v_shader: Vertex_Shader,
	f_shader: Fragment_Shader,
	vertex_buffer, index_buffer: BufferIndex,
	sample_count: int,
	stride_size: int,
) -> PipelineIndex {
	p: Pipeline

	p.vertex_shader = v_shader
	p.fragment_shader = f_shader

	p.stride_size = stride_size
	p.index_buffer = index_buffer
	p.vertex_buffer = vertex_buffer

	p.framebuffer = create_image(renderer, renderer.viewport.z, renderer.viewport.w, 4)
	p.depthbuffer = create_image(renderer, renderer.viewport.z, renderer.viewport.w, 4)

	p.io_buffer = BufferIndex(create_buffer(renderer))

	p.sampler_count = sample_count
	p.samplers = ShaderSamplerIndex(len(renderer.shader_samplers))
	for _ in 0 ..< sample_count {
		append(&renderer.shader_samplers, 0)
	}

	index := len(renderer.pipelines)
	append(&renderer.pipelines, p)
	return PipelineIndex(index)
}

create_buffer :: proc(renderer: ^Renderer) -> BufferIndex {
	index := len(renderer.buffers)
	buffer := make(Buffer, renderer.allocator)
	append(&renderer.buffers, buffer)
	return BufferIndex(index)
}

get_pipeline :: proc(renderer: ^Renderer, index: PipelineIndex) -> ^Pipeline {
	return &renderer.pipelines[index]
}

get_buffer :: proc(renderer: ^Renderer, index: BufferIndex) -> ^Buffer {
	return &renderer.buffers[index]
}

get_pipeline_shader_samplers :: proc(renderer: ^Renderer, pipeline: ^Pipeline) -> []SamplerIndex {
	return renderer.shader_samplers[pipeline.samplers:int(pipeline.samplers) + pipeline.sampler_count]
}

shader_write_out :: proc(io: ^Buffer, data: $T) {
	data := data
	out_ptr := cast(^[size_of(T)]byte)&data
	out := out_ptr^[:]
	append(io, ..out)
}

pipeline_set_shader_userdata :: proc(renderer: ^Renderer, index: PipelineIndex, v_userdata: rawptr, f_userdata: rawptr) {
	pipeline := get_pipeline(renderer, index)
	pipeline.fragment_userdata = f_userdata
	pipeline.vertex_userdata = v_userdata
}

pipeline_set_shader_samplers :: proc(renderer: ^Renderer, index: PipelineIndex, samplers: []SamplerIndex) {
	pipeline := get_pipeline(renderer, index)

	ensure(len(samplers) == pipeline.sampler_count, "Provided samplers must be equal to number of samplers set in pipeline")
	shader_samplers := get_pipeline_shader_samplers(renderer, pipeline)
	copy(shader_samplers, samplers)
}

pipeline_process :: proc(renderer: ^Renderer, pipeline_index: PipelineIndex) {
	pipeline := &renderer.pipelines[pipeline_index]

	framebuffer := get_image(renderer, pipeline.framebuffer)
	depthbuffer := get_image(renderer, pipeline.depthbuffer)

	fb_float_size := Vec2f32{f32(framebuffer.width), f32(framebuffer.height)}


	raw_io_buf := get_buffer(renderer, pipeline.io_buffer)
	raw_vert_buf := get_buffer(renderer, pipeline.vertex_buffer)
	raw_index_buf := get_buffer(renderer, pipeline.index_buffer)

	sampler_size := 0
	samplers := []Sampler{}

	{
		shader_samplers := get_pipeline_shader_samplers(renderer, pipeline)
		sampler_size = size_of(Sampler) * len(shader_samplers)
		resize(raw_io_buf, sampler_size)
		samplers = slice.reinterpret([]Sampler, raw_io_buf^[:sampler_size])

		for sampler_index, i in shader_samplers {
			renderer.samplers[sampler_index].image = renderer.images[renderer.samplers[sampler_index].target]
			samplers[i] = renderer.samplers[sampler_index]
		}
	}

	index_buf := slice.reinterpret([]int, raw_index_buf^[:])

	raster_loop: for index_i := 0; index_i < len(index_buf); index_i += 3 {
		defer resize(raw_io_buf, sampler_size)

		vertex_out_end, vertex_out_stride := 0, 0

		planes := [6]Vec4f32 {
			{1, 0, 0, 1}, //  x + w >= 0   (left)
			{-1, 0, 0, 1}, // -x + w >= 0   (right)
			{0, 1, 0, 1}, //  y + w >= 0   (bottom)
			{0, -1, 0, 1}, // -y + w >= 0   (top)
			{0, 0, 1, 1}, //  z + w >= 0   (near)
			{0, 0, -1, 1}, // -z + w >= 0   (far)
		}

		verts := [12]Vec4f32{}
		verts_count := 3

		{
			vertex_index_1 := index_buf[index_i] * pipeline.stride_size
			vertex_index_2 := index_buf[index_i + 1] * pipeline.stride_size
			vertex_index_3 := index_buf[index_i + 2] * pipeline.stride_size

			vertex_1_input_data := raw_vert_buf^[vertex_index_1:vertex_index_1 + pipeline.stride_size]
			vertex_2_input_data := raw_vert_buf^[vertex_index_2:vertex_index_2 + pipeline.stride_size]
			vertex_3_input_data := raw_vert_buf^[vertex_index_3:vertex_index_3 + pipeline.stride_size]

			verts[0] = pipeline.vertex_shader({vertex_id = index_buf[index_i]}, vertex_1_input_data, pipeline.vertex_userdata, raw_io_buf)
			vertex_out_stride = len(raw_io_buf^) - sampler_size
			verts[1] = pipeline.vertex_shader({vertex_id = index_buf[index_i + 1]}, vertex_2_input_data, pipeline.vertex_userdata, raw_io_buf)
			verts[2] = pipeline.vertex_shader({vertex_id = index_buf[index_i + 2]}, vertex_3_input_data, pipeline.vertex_userdata, raw_io_buf)

			vertex_out_end = len(raw_io_buf^) - sampler_size
		}

		// Use the io buffer to also store fragment input data. The input data will be reused per fragment

		// 3 for original attributes, 1 for fragment data, 12 vertex attributes and 12 temp vertex attributes
		resize(raw_io_buf, sampler_size + vertex_out_stride * (3 + 1 + 12 + 12))
		shader_data := raw_io_buf^[sampler_size:]

		frag_input_data := shader_data[vertex_out_end:vertex_out_end + vertex_out_stride]


		// clip tests

		verts_attrs := shader_data[vertex_out_stride * 4:vertex_out_stride * 16]

		// Also grab the per vertex data
		copy(verts_attrs[:vertex_out_stride], shader_data[vertex_out_stride * 0:vertex_out_stride * 1])
		copy(verts_attrs[vertex_out_stride:vertex_out_stride * 2], shader_data[vertex_out_stride * 1:vertex_out_stride * 2])
		copy(verts_attrs[vertex_out_stride * 2:vertex_out_stride * 3], shader_data[vertex_out_stride * 2:vertex_out_stride * 3])

		for plane in planes {
			out_count := 0
			out_attrs := shader_data[vertex_out_stride * 16:vertex_out_stride * 28]
			out_verts := [12]Vec4f32{}

			for vert in 0 ..< verts_count {
				a, b := verts[vert], verts[(vert + 1) % verts_count]

				a_attrs := verts_attrs[vert * vertex_out_stride:(vert + 1) * vertex_out_stride]
				b_attrs := verts_attrs[((vert + 1) % verts_count) *
				vertex_out_stride:((vert + 1) % verts_count) * vertex_out_stride +
				vertex_out_stride]

				a_dot_plane := linalg.dot(plane, a)
				b_dot_plane := linalg.dot(plane, b)

				a_inside := a_dot_plane >= 0
				b_inside := b_dot_plane >= 0

				if !a_inside && !b_inside {
					continue
				}

				if a_inside && b_inside {
					out_verts[out_count] = b
					copy(out_attrs[out_count * vertex_out_stride:(out_count + 1) * vertex_out_stride], b_attrs)
					out_count += 1
					continue
				}

				intersection_parameter := a_dot_plane / (a_dot_plane - b_dot_plane)
				intersection := a + intersection_parameter * (b - a)

				if a_inside && !b_inside {
					out_verts[out_count] = intersection
					for i := 0; i < vertex_out_stride; i += 4 {
						a_attr_f := (cast(^f32)(&a_attrs[i]))^
						b_attr_f := (cast(^f32)(&b_attrs[i]))^

						interpolated := transmute([4]u8)(a_attr_f + intersection_parameter * (b_attr_f - a_attr_f))

						for b, j in interpolated {
							out_attrs[out_count * vertex_out_stride + i + j] = b
						}
					}
					out_count += 1
					continue
				}

				if !a_inside && b_inside {
					out_verts[out_count] = intersection
					out_verts[out_count + 1] = b

					for i := 0; i < vertex_out_stride; i += 4 {
						a_attr_f := (cast(^f32)(&a_attrs[i]))^
						b_attr_f := (cast(^f32)(&b_attrs[i]))^

						interpolated := transmute([4]u8)(a_attr_f + intersection_parameter * (b_attr_f - a_attr_f))

						for b, j in interpolated {
							out_attrs[out_count * vertex_out_stride + i + j] = b
						}
					}

					copy(out_attrs[(out_count + 1) * vertex_out_stride:(out_count + 2) * vertex_out_stride], b_attrs)

					out_count += 2
					continue
				}
			}

			verts_count = out_count
			verts = out_verts

			copy(verts_attrs, out_attrs)

			if verts_count == 0 {
				continue raster_loop
			}
		}

		for i in 0 ..< verts_count {
			w_inv := 1 / verts[i].w

			for j := 0; j < vertex_out_stride; j += 4 {
				data := transmute(^f32)(&verts_attrs[i * vertex_out_stride + j])
				data^ *= w_inv
			}
		}

		for vert_i := 1; vert_i < verts_count - 1; vert_i += 1 {
			clip_v1 := verts[0]
			clip_v2 := verts[vert_i + 1]
			clip_v3 := verts[vert_i]

			v1_w_inv := 1 / clip_v1.w
			v2_w_inv := 1 / clip_v2.w
			v3_w_inv := 1 / clip_v3.w

			v1_data := verts_attrs[0:vertex_out_stride]
			v2_data := verts_attrs[(vert_i + 1) * vertex_out_stride:(vert_i + 2) * vertex_out_stride]
			v3_data := verts_attrs[vert_i * vertex_out_stride:(vert_i + 1) * vertex_out_stride]


			// perspective divide
			// vertex shader output is in clip space
			// perspective info encoded into w component via perspective matrix
			projected_v1 := clip_v1.xyz / clip_v1.w if clip_v1.w != 0 else clip_v1.xyz
			projected_v2 := clip_v2.xyz / clip_v2.w if clip_v2.w != 0 else clip_v2.xyz
			projected_v3 := clip_v3.xyz / clip_v3.w if clip_v3.w != 0 else clip_v3.xyz

			// TODO Clipping and triangle splitting, for now, ball
			z_values_fixed := Vec3f32{projected_v1.z, projected_v2.z, projected_v3.z}

			// screen space mapping
			space_v1 := Vec2f32{((projected_v1.x + 1) * 0.5 * fb_float_size.x), ((projected_v1.y + 1) * 0.5 * fb_float_size.y)}
			space_v2 := Vec2f32{((projected_v2.x + 1) * 0.5 * fb_float_size.x), ((projected_v2.y + 1) * 0.5 * fb_float_size.y)}
			space_v3 := Vec2f32{((projected_v3.x + 1) * 0.5 * fb_float_size.x), ((projected_v3.y + 1) * 0.5 * fb_float_size.y)}

			space_v1_fixed := Vec2i32{i32(space_v1.x * (1 << SUBPIXELS)), i32(space_v1.y * (1 << SUBPIXELS))}
			space_v2_fixed := Vec2i32{i32(space_v2.x * (1 << SUBPIXELS)), i32(space_v2.y * (1 << SUBPIXELS))}
			space_v3_fixed := Vec2i32{i32(space_v3.x * (1 << SUBPIXELS)), i32(space_v3.y * (1 << SUBPIXELS))}

			min_x := min(space_v1_fixed.x, space_v2_fixed.x, space_v3_fixed.x)
			min_y := min(space_v1_fixed.y, space_v2_fixed.y, space_v3_fixed.y)
			max_x := max(space_v1_fixed.x, space_v2_fixed.x, space_v3_fixed.x)
			max_y := max(space_v1_fixed.y, space_v2_fixed.y, space_v3_fixed.y)

			min_x = max(min_x, 0)
			min_y = max(min_y, 0)
			max_x = min(max_x, i32(fb_float_size.x * (1 << SUBPIXELS)) - 1)
			max_y = min(max_y, i32(fb_float_size.y * (1 << SUBPIXELS)) - 1)

			sample_initial := Vec2i32 {
				(min_x & ~(i32(1 << SUBPIXELS) - 1)) + (1 << (SUBPIXELS - 1)),
				(min_y & ~(i32(1 << SUBPIXELS) - 1)) + (1 << (SUBPIXELS - 1)),
			}

			e1 := space_v3_fixed - space_v2_fixed
			e2 := space_v1_fixed - space_v3_fixed
			e3 := space_v2_fixed - space_v1_fixed

			dx := Vec3i32{e1.y, e2.y, e3.y} * (1 << SUBPIXELS)
			dy := Vec3i32{e1.x, e2.x, e3.x} * (1 << SUBPIXELS)

			cross :: proc(a, b: Vec2i32) -> i32 {
				return i32((i64(a.x) * i64(b.y) - i64(b.x) * i64(a.y)))
			}

			weights_initial := Vec3i32{}
			weights_comparison := Vec3i32{}
			weights_initial.x = cross(e1, sample_initial - space_v2_fixed) - ((e1.y > 0 || (e1.y == 0 && e1.x < 0)) ? 1 : 0)
			weights_initial.y = cross(e2, sample_initial - space_v3_fixed) - ((e2.y > 0 || (e2.y == 0 && e2.x < 0)) ? 1 : 0)
			weights_initial.z = cross(e3, sample_initial - space_v1_fixed) - ((e3.y > 0 || (e3.y == 0 && e3.x < 0)) ? 1 : 0)

			area := cross(e3, -e2)

			if area <= 0 {continue}

			area_f32 := f32(area)
			weights_row := weights_initial

			for fy := sample_initial.y >> SUBPIXELS; fy <= max_y >> SUBPIXELS; fy += 1 {
				weights_col := weights_row
				for fx := sample_initial.x >> SUBPIXELS; fx <= max_x >> SUBPIXELS; fx += 1 {
					sp := Vec2i32{fx, fy}

					defer weights_col -= dx

					if weights_col.x < 0 || weights_col.y < 0 || weights_col.z < 0 {
						continue
					}

					weights := Vec3f32{f32(weights_col.x), f32(weights_col.y), f32(weights_col.z)} / area_f32
					w_inv := weights.x * v1_w_inv + weights.y * v2_w_inv + weights.z * v3_w_inv
					depth := (weights.x * z_values_fixed.x + weights.y * z_values_fixed.y + weights.z * z_values_fixed.z) / w_inv

					prev_depth := image_get_bytes(depthbuffer, sp)
					if (cast(^f32)raw_data(prev_depth))^ <= depth {continue}

					for i := 0; i < vertex_out_stride; i += 4 {
						v1_stride_data := (transmute(^f32)&v1_data[i])^
						v2_stride_data := (transmute(^f32)&v2_data[i])^
						v3_stride_data := (transmute(^f32)&v3_data[i])^

						v1_t := v1_stride_data * weights.x
						v2_t := v2_stride_data * weights.y
						v3_t := v3_stride_data * weights.z

						out := (transmute([4]u8)((v1_t + v2_t + v3_t) / w_inv))
						for &d, j in frag_input_data[i:i + 4] {
							d = out[j]
						}

					}


					out_color := pipeline.fragment_shader(
						{frag_coord = {f32(fx), f32(fy), depth, w_inv}},
						frag_input_data,
						samplers,
						pipeline.fragment_userdata,
					)
					image_set_color(framebuffer, sp, out_color)
					image_set_bytes(depthbuffer, sp, transmute([4]u8)depth)
				}
				weights_row += dy
			}
		}
	}
}
