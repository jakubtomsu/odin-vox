package vox_example

import vox ".."
import "core:fmt"
import "core:log"
import "core:os"

main :: proc() {
    if len(os.args) < 2 {
        fmt.println("Please provide a path to .vox model.")
        return
    }

    context.logger = log.create_console_logger()

    if v, ok := vox.load_from_file(os.args[1], context.temp_allocator); ok {
        for m, i in v.models {
            fmt.printf("Model %i: %v\n", i, m.size)
        }

        for c, i in v.palette {
            fmt.printf("Color %i: %v\n", i, c)
        }

        for m, i in v.material_palette {
            fmt.printf("Material %i: %v\n", i, m)
        }

    } else {
        fmt.println("Failed to load file.")
    }
}
