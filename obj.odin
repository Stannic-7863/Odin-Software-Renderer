package main

import "core:log"
import "core:os/os2"
import "core:strconv"
import "core:strings"

load_obj :: proc(path: string) -> ([dynamic]Vertex, [dynamic]int) {
	data, err := os2.read_entire_file_from_path(path, context.allocator)
	defer delete(data)

	if err != nil {panic("err")}

	vert_norm := make([dynamic][3]f32)
	vert_pos := make([dynamic][3]f32)
	vert_tex := make([dynamic][2]f32)

	defer delete(vert_norm)
	defer delete(vert_pos)
	defer delete(vert_tex)

	v_map := make(map[string]int)
	defer delete(v_map)

	f_indx := make([dynamic]int)
	defer delete(f_indx)

	verts := make([dynamic]Vertex)
	indicies := make([dynamic]int)

	data_str := string(data)

	for line in strings.split_lines_iterator(&data_str) {

		trimmed := strings.trim_space(line)

		if len(trimmed) == 0 || trimmed[0] == '#' {
			continue
		}

		parts, _ := strings.split(trimmed, " ", context.allocator)

		switch parts[0] {
		case "v":
			v1, _ := strconv.parse_f32(parts[1])
			v2, _ := strconv.parse_f32(parts[2])
			v2 = 1 - v2
			v3, _ := strconv.parse_f32(parts[3])
			append(&vert_pos, [3]f32{v1, v2, v3})
		case "vt":
			t1, _ := strconv.parse_f32(parts[1])
			t2, _ := strconv.parse_f32(parts[2])
			append(&vert_tex, [2]f32{t1, t2})
		case "vn":
			n1, _ := strconv.parse_f32(parts[1])
			n2, _ := strconv.parse_f32(parts[2])
			n3, _ := strconv.parse_f32(parts[3])
			append(&vert_norm, [3]f32{n1, n2, n3})
		case "f":
			defer clear(&f_indx)
			for p in parts[1:] {
				if index, ok := v_map[p]; ok {
					append(&f_indx, index)
					continue
				}

				f_parts := strings.split(p, "/")

				v_i, _ := strconv.parse_int(f_parts[0])
				v_t: int = -1
				v_n: int = -1

				if len(f_parts) > 1 {
					v_t, _ = strconv.parse_int(f_parts[1])
				}
				if len(f_parts) > 2 {
					v_n, _ = strconv.parse_int(f_parts[2])
				}

				v_i -= 1
				v_t -= 1
				v_n -= 1

				vert := Vertex {
					pos = vert_pos[v_i],
					uv  = v_t > 0 ? vert_tex[v_t] : 0,
					col = v_n > 0 ? vert_norm[v_n] : 0,
				}

				index := len(verts)
				v_map[p] = index
				append(&verts, vert)
				append(&f_indx, index)
			}

			for i := 1; i < len(f_indx) - 1; i += 1 {
				append(&indicies, f_indx[0])
				append(&indicies, f_indx[i])
				append(&indicies, f_indx[i + 1])
			}
		}
	}

	return verts, indicies
}
