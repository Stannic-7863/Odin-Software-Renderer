package software_renderer

import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:log"
import "core:os/os2"

Image :: struct {
	width, height: int,
	channels:      int,
	data:          []byte,
}

Sampler :: struct {
	target: ImageIndex,
	image:  Image,
}

create_sampler :: proc(renderer: ^Renderer, image: ImageIndex) -> SamplerIndex {
	index := len(renderer.samplers)
	append(&renderer.samplers, Sampler{target = image})
	return SamplerIndex(index)
}

sample_color :: proc(sampler: Sampler, uv: Vec2f32) -> Vec4f32 {
	img := sampler.image

	uv := uv
	uv.x = min(1, uv.x)
	uv.y = min(1, uv.y)
	uv.x = max(0, uv.x)
	uv.y = max(0, uv.y)

	s := uv * {f32(img.width - 1), f32(img.height - 1)}
	sample_loc := [2]int{int(s.x), int(s.y)}

	index := (sample_loc.x + sample_loc.y * img.width) * img.channels
	col := img.data[index:index + img.channels]

	v4: Vec4f32
	for c, i in col {
		v4[i] = f32(c) / 255
	}

	return v4
}

create_image :: proc(renderer: ^Renderer, width: int, height: int, channels: int) -> ImageIndex {
	data := make([]byte, width * height * channels, renderer.allocator)
	index := len(renderer.images)
	append(&renderer.images, Image{data = data, width = width, height = height, channels = channels})
	return ImageIndex(index)
}

get_image :: proc(renderer: ^Renderer, index: ImageIndex) -> Image {
	return renderer.images[index]
}

image_clear_color :: proc(image: Image, color: Vec4f32) #no_bounds_check {
	color_u8 := [4]u8{u8(255 * color.r), u8(255 * color.g), u8(255 * color.b), u8(255 * color.a)}
	for i := 0; i < len(image.data); i += image.channels {
		copy(image.data[i:i + image.channels], color_u8[:image.channels])
	}
}

image_clear_bytes :: proc(image: Image, bytes: [4]u8) #no_bounds_check {
	bytes := bytes
	for i := 0; i < len(image.data); i += image.channels {
		copy(image.data[i:i + image.channels], bytes[:image.channels])
	}
}

image_set_color :: #force_inline proc(image: Image, pixel: Vec2i32, color: Vec4f32) #no_bounds_check {
	x := int(pixel.x)
	y := int(pixel.y)

	index := (x + y * image.width) * image.channels
	color_u8 := [4]u8{u8(255 * color.r), u8(255 * color.g), u8(255 * color.b), u8(255 * color.a)}

	for i in 0 ..< image.channels {
		image.data[index + i] = u8(color[i] * 255)
	}
}

image_set_bytes :: #force_inline proc(image: Image, pixel: Vec2i32, bytes: [4]u8) #no_bounds_check {
	x := int(pixel.x)
	y := int(pixel.y)

	index := (x + y * image.width) * image.channels

	for i in 0 ..< image.channels {
		image.data[index + i] = bytes[i]
	}
}

image_get_bytes :: #force_inline proc(image: Image, pixel: Vec2i32) -> []u8 {
	x := int(pixel.x)
	y := int(pixel.y)

	index := (x + y * image.width) * image.channels

	return image.data[index:index + image.channels]
}

image_write_to_ppm :: proc(output_path: string, image: Image) {

	file, err := os2.open(output_path, {.Create, .Read, .Write, .Trunc})

	write :: proc(file: ^os2.File, to_write: []byte, offset: ^i64) {
		n, err_w := os2.write_at(file, to_write, offset^)
		offset^ += cast(i64)n
	}

	if err != nil {
		log.error("Error occured creating/opening a file at ", output_path, err)
		panic("")
	}

	offset: i64 = 0
	write(file, {'P', '6', '\n'}, &offset)

	w_h := fmt.tprintf("%i %i\n255\n", image.width, image.height)

	write(file, transmute([]byte)w_h, &offset)

	for i := 0; i < len(image.data); i += 4 {
		write(file, image.data[i:i + 3], &offset)
	}

	os2.close(file)
}
