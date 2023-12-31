package vox

import "core:log"
import "core:os"
import "core:strconv"

// Few parts of the code are based on ogt_vox.h from opengametools by Justin Paver:
// https://github.com/jpaver/opengametools/blob/master/src/ogt_vox.h

// Structure containing data of a '.vox' file.
Vox :: struct {
    header:           Header,
    models:           []Model,
    palette:          Palette,
    // Access with voxel's color_index
    material_palette: Material_Palette,
}

Color8 :: [4]u8

Palette :: [256]Color8
Material_Palette :: [256]Material

Model :: struct {
    size:   [3]int,
    voxels: []Voxel `fmt:"-"`,
}

Voxel :: struct {
    pos:         [3]u8,
    color_index: u8,
}

Material :: struct {
    type:            Material_Type,
    assigned_fields: bit_set[Material_Field],
    fields:          [Material_Field]f32,
}

Material_Type :: enum u32 {
    Diffuse = 0,
    Metal   = 1,
    Glass   = 2,
    Emit    = 3,
    Blend   = 4,
    Media   = 5,
}

Material_Field :: enum u8 {
    Metal,
    Rough,
    Spec,
    Ior,
    Att,
    Flux,
    Emit,
    Ldr,
    Trans,
    Alpha,
    D,
    Sp,
    G,
    Media,
}

load_from_file :: proc(file: string, allocator := context.allocator) -> (Vox, bool) {
    if data, ok := os.read_entire_file(file, context.temp_allocator); ok {
        return load_from_data(data, allocator)
    }
    return {}, false
}

load_from_data :: proc(data: []u8, allocator := context.allocator) -> (result: Vox, ok: bool) {
    data := data

    context.allocator = allocator

    result.header = read_data(&data, Header) or_return

    if result.header.id != VOX_ID {
        return {}, false
    }

    main_chunk := read_data(&data, Chunk) or_return

    if main_chunk.id != {'M', 'A', 'I', 'N'} {
        return {}, false
    }

    result.palette = transmute(Palette)DEFAULT_PALETTE

    num_models := 1
    {
        next_id := peek_data(&data, [4]u8) or_return
        if next_id == {'P', 'A', 'C', 'K'} {
            chunk := read_data(&data, Chunk) or_return
            num_models = int(read_data(&data, u32) or_return)
        }
    }

    result.models = make([]Model, num_models)
    model_index := 0

    for len(data) > 0 {
        chunk := read_data(&data, Chunk) or_return

        switch chunk.id {
        case {'S', 'I', 'Z', 'E'}:
            size := read_data(&data, [3]i32) or_return
            xyzi_chunk := read_data(&data, Chunk) or_return
            assert(xyzi_chunk.id == {'X', 'Y', 'Z', 'I'})
            num_voxels := read_data(&data, u32) or_return

            model := Model {
                size = {int(size.x), int(size.y), int(size.z)},
                voxels = make([]Voxel, int(num_voxels)),
            }

            for i in 0 ..< num_voxels {
                model.voxels[i] = read_data(&data, Voxel) or_return
            }

            result.models[model_index] = model
            model_index += 1

        case {'R', 'G', 'B', 'A'}:
            result.palette = read_data(&data, Palette) or_return

        case {'M', 'A', 'T', 'L'}:
            assert(chunk.num_bytes >= 8)

            id := read_data(&data, i32) or_return
            id &= 0xff

            mat: Material

            num_keys := read_data(&data, i32) or_return
            for i in 0 ..< num_keys {
                key := read_string(&data) or_return
                val := read_string(&data) or_return

                switch key {
                case "_type":
                    switch val {
                    case "_diffuse":
                        mat.type = .Diffuse
                    case "_metal":
                        mat.type = .Metal
                    case "_glass":
                        mat.type = .Glass
                    case "_emit":
                        mat.type = .Emit
                    }

                case:
                    field: Material_Field
                    switch key {
                    case "_metal":
                        field = .Metal
                    case "_rough":
                        field = .Rough
                    case "_spec":
                        field = .Spec
                    case "_ior":
                        field = .Ior
                    case "_att":
                        field = .Att
                    case "_flux":
                        field = .Flux
                    case "_emit":
                        field = .Emit
                    case "_ldr":
                        field = .Ldr
                    case "_trans":
                        field = .Trans
                    case "_alpha":
                        field = .Alpha
                    case "_d":
                        field = .D
                    case "_sp":
                        field = .Sp
                    case "_g":
                        field = .G
                    case "_media":
                        field = .Media
                    }

                    mat.fields[field] = strconv.parse_f32(val) or_return
                    mat.assigned_fields += {field}
                }
            }

            result.material_palette[id] = mat

        // Deprecated materials
        case {'M', 'A', 'T', 'T'}:
            id := read_data(&data, u32) or_return
            id &= 0xff

            mat_type := read_data(&data, Material_Type) or_return

            // diffuse  : 1.0
            // metal    : (0.0 - 1.0] : blend between metal and diffuse material
            // glass    : (0.0 - 1.0] : blend between glass and diffuse material
            // emissive : (0.0 - 1.0] : self-illuminated material
            mat_weight := read_data(&data, f32) or_return

            // bit(0) : Plastic
            // bit(1) : Roughness
            // bit(2) : Specular
            // bit(3) : IOR
            // bit(4) : Attenuation
            // bit(5) : Power
            // bit(6) : Glow
            // bit(7) : isTotalPower (*no value)
            mat_properties := read_data(&data, bit_set[0 ..< 32]) or_return
            _ = mat_properties

            mat := Material {
                type = mat_type,
            }

            #partial switch mat_type {
            case .Metal:
                mat.assigned_fields += {.Metal}
                mat.fields[.Metal] = mat_weight
            case .Glass:
                mat.assigned_fields += {.Trans}
                mat.fields[.Trans] = mat_weight
            case .Emit:
                mat.assigned_fields += {.Emit}
                mat.fields[.Emit] = mat_weight
            }

            result.material_palette[id] = mat

            seek_data(&data, int(chunk.num_bytes) - 16)

        case:
            // Skip
            data = data[chunk.num_bytes:]
            log.info("Unknown chunk:", string(chunk.id[:]))
        }
    }

    return result, true
}

seek_data :: proc(data: ^[]u8, num_bytes: int) -> bool {
    if num_bytes <= 0 do return true

    if len(data) < num_bytes {
        return false
    }

    data^ = data[num_bytes:]
    return true
}

peek_data :: proc(data: ^[]u8, $T: typeid) -> (result: T, ok: bool) {
    if len(data) < size_of(T) {
        return {}, false
    }

    result = (transmute(^T)&data[0])^
    return result, true
}

read_data :: proc(data: ^[]u8, $T: typeid) -> (T, bool) {
    if result, ok := peek_data(data, T); ok {
        seek_data(data, size_of(T))
        return result, true
    }
    return {}, false
}

read_string :: proc(data: ^[]u8) -> (result: string, ok: bool) {
    size := read_data(data, i32) or_return
    result = string(data[:size])
    seek_data(data, int(size)) or_return
    return result, true
}

VOX_ID: [4]u8 : {'V', 'O', 'X', ' '}

Header :: struct {
    id:      [4]u8,
    version: i32,
}

Chunk_Id :: [4]u8

Chunk :: struct {
    id:                 Chunk_Id,
    num_bytes:          u32,
    num_bytes_children: u32,
}

DEFAULT_PALETTE: [256]u32 :  {
    0x00000000,
    0xffffffff,
    0xffccffff,
    0xff99ffff,
    0xff66ffff,
    0xff33ffff,
    0xff00ffff,
    0xffffccff,
    0xffccccff,
    0xff99ccff,
    0xff66ccff,
    0xff33ccff,
    0xff00ccff,
    0xffff99ff,
    0xffcc99ff,
    0xff9999ff,
    0xff6699ff,
    0xff3399ff,
    0xff0099ff,
    0xffff66ff,
    0xffcc66ff,
    0xff9966ff,
    0xff6666ff,
    0xff3366ff,
    0xff0066ff,
    0xffff33ff,
    0xffcc33ff,
    0xff9933ff,
    0xff6633ff,
    0xff3333ff,
    0xff0033ff,
    0xffff00ff,
    0xffcc00ff,
    0xff9900ff,
    0xff6600ff,
    0xff3300ff,
    0xff0000ff,
    0xffffffcc,
    0xffccffcc,
    0xff99ffcc,
    0xff66ffcc,
    0xff33ffcc,
    0xff00ffcc,
    0xffffcccc,
    0xffcccccc,
    0xff99cccc,
    0xff66cccc,
    0xff33cccc,
    0xff00cccc,
    0xffff99cc,
    0xffcc99cc,
    0xff9999cc,
    0xff6699cc,
    0xff3399cc,
    0xff0099cc,
    0xffff66cc,
    0xffcc66cc,
    0xff9966cc,
    0xff6666cc,
    0xff3366cc,
    0xff0066cc,
    0xffff33cc,
    0xffcc33cc,
    0xff9933cc,
    0xff6633cc,
    0xff3333cc,
    0xff0033cc,
    0xffff00cc,
    0xffcc00cc,
    0xff9900cc,
    0xff6600cc,
    0xff3300cc,
    0xff0000cc,
    0xffffff99,
    0xffccff99,
    0xff99ff99,
    0xff66ff99,
    0xff33ff99,
    0xff00ff99,
    0xffffcc99,
    0xffcccc99,
    0xff99cc99,
    0xff66cc99,
    0xff33cc99,
    0xff00cc99,
    0xffff9999,
    0xffcc9999,
    0xff999999,
    0xff669999,
    0xff339999,
    0xff009999,
    0xffff6699,
    0xffcc6699,
    0xff996699,
    0xff666699,
    0xff336699,
    0xff006699,
    0xffff3399,
    0xffcc3399,
    0xff993399,
    0xff663399,
    0xff333399,
    0xff003399,
    0xffff0099,
    0xffcc0099,
    0xff990099,
    0xff660099,
    0xff330099,
    0xff000099,
    0xffffff66,
    0xffccff66,
    0xff99ff66,
    0xff66ff66,
    0xff33ff66,
    0xff00ff66,
    0xffffcc66,
    0xffcccc66,
    0xff99cc66,
    0xff66cc66,
    0xff33cc66,
    0xff00cc66,
    0xffff9966,
    0xffcc9966,
    0xff999966,
    0xff669966,
    0xff339966,
    0xff009966,
    0xffff6666,
    0xffcc6666,
    0xff996666,
    0xff666666,
    0xff336666,
    0xff006666,
    0xffff3366,
    0xffcc3366,
    0xff993366,
    0xff663366,
    0xff333366,
    0xff003366,
    0xffff0066,
    0xffcc0066,
    0xff990066,
    0xff660066,
    0xff330066,
    0xff000066,
    0xffffff33,
    0xffccff33,
    0xff99ff33,
    0xff66ff33,
    0xff33ff33,
    0xff00ff33,
    0xffffcc33,
    0xffcccc33,
    0xff99cc33,
    0xff66cc33,
    0xff33cc33,
    0xff00cc33,
    0xffff9933,
    0xffcc9933,
    0xff999933,
    0xff669933,
    0xff339933,
    0xff009933,
    0xffff6633,
    0xffcc6633,
    0xff996633,
    0xff666633,
    0xff336633,
    0xff006633,
    0xffff3333,
    0xffcc3333,
    0xff993333,
    0xff663333,
    0xff333333,
    0xff003333,
    0xffff0033,
    0xffcc0033,
    0xff990033,
    0xff660033,
    0xff330033,
    0xff000033,
    0xffffff00,
    0xffccff00,
    0xff99ff00,
    0xff66ff00,
    0xff33ff00,
    0xff00ff00,
    0xffffcc00,
    0xffcccc00,
    0xff99cc00,
    0xff66cc00,
    0xff33cc00,
    0xff00cc00,
    0xffff9900,
    0xffcc9900,
    0xff999900,
    0xff669900,
    0xff339900,
    0xff009900,
    0xffff6600,
    0xffcc6600,
    0xff996600,
    0xff666600,
    0xff336600,
    0xff006600,
    0xffff3300,
    0xffcc3300,
    0xff993300,
    0xff663300,
    0xff333300,
    0xff003300,
    0xffff0000,
    0xffcc0000,
    0xff990000,
    0xff660000,
    0xff330000,
    0xff0000ee,
    0xff0000dd,
    0xff0000bb,
    0xff0000aa,
    0xff000088,
    0xff000077,
    0xff000055,
    0xff000044,
    0xff000022,
    0xff000011,
    0xff00ee00,
    0xff00dd00,
    0xff00bb00,
    0xff00aa00,
    0xff008800,
    0xff007700,
    0xff005500,
    0xff004400,
    0xff002200,
    0xff001100,
    0xffee0000,
    0xffdd0000,
    0xffbb0000,
    0xffaa0000,
    0xff880000,
    0xff770000,
    0xff550000,
    0xff440000,
    0xff220000,
    0xff110000,
    0xffeeeeee,
    0xffdddddd,
    0xffbbbbbb,
    0xffaaaaaa,
    0xff888888,
    0xff777777,
    0xff555555,
    0xff444444,
    0xff222222,
    0xff111111,
}
