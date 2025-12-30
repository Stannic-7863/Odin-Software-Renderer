package software_renderer

import "base:runtime"
import "core:bytes"
import "core:fmt"
import "core:log"
import "core:os/os2"

Image :: struct {
	width, height: int,
	data:          []byte,
	channels:      int,
	alllocator:    runtime.Allocator,
}

create_image :: proc(width: int, height: int, channels: int, allocator: runtime.Allocator) -> Image {
	data := make([]byte, width * height * channels, allocator)
	return {data = data, alllocator = allocator, width = width, height = height, channels = channels}
}

delete_image :: proc(image: Image) {
	delete(image.data, image.alllocator)
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

image_set_color :: #force_inline proc(image: Image, pixel: Vec2f32, color: Vec4f32) #no_bounds_check {
	x := int(pixel.x)
	y := int(pixel.y)

	index := (x + y * image.width) * image.channels
	color_u8 := [4]u8{u8(255 * color.r), u8(255 * color.g), u8(255 * color.b), u8(255 * color.a)}

	for i in 0 ..< image.channels {
		image.data[index + i] = u8(color[i] * 255)
	}
}

image_set_bytes :: #force_inline proc(image: Image, pixel: Vec2f32, bytes: [4]u8) #no_bounds_check {
	x := int(pixel.x)
	y := int(pixel.y)

	index := (x + y * image.width) * image.channels

	for i in 0 ..< image.channels {
		image.data[index + i] = bytes[i]
	}
}

image_get_bytes :: #force_inline proc(image: Image, pixel: Vec2f32) -> []u8 {
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
