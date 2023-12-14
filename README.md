# :package: odin-vox
A simple loader for `.vox` models from [MagicaVoxel](https://ephtracy.github.io/).

The [base format](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt) is fully implemented.

Supported extensions:
- Materials (including legacy MATT materials)

Latest tested odin version: `dev-2023-12-nightly:31b1aef4`

## Usage
```odin
// Load and parse data from file.
// Alternatively use `vox.load_from_data`.
if data, ok := vox.load_from_file("my_model.vox", context.temp_allocator); ok {
  for model, i in data.models {
    fmt.printf("Model %i:\n", i)
    fmt.printf("\tsize: %v\n", model.size)
    fmt.printf("\tvoxels:\n")
    for voxel, j in model.voxels {
      fmt.printf("\t[%i] %v: %i\n", j, voxel.pos, voxel.color_index)
    }
  }
}
```

## TODO
- Implement more [extensions](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt) as necessary

## Contributing
All contributions are welcome!
