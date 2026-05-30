# iOS Model Assets

Place Core ML model resources for local iPhone testing in this directory, or add
them directly to the Roana app target resources with the same bundle names.

- `YOLO11n.mlpackage` or compiled `YOLO11n.mlmodelc`
- `DepthAnythingV2Small.mlpackage` or compiled `DepthAnythingV2Small.mlmodelc`

Do not commit model binaries in normal source commits. The repository ignores
`.mlpackage`, `.mlmodel`, and `.mlmodelc` outputs; keep large assets in an
explicit model-fetch path or Git LFS if that policy changes.

Validate the local asset contract with:

```bash
scripts/check-ios-model-assets.py
scripts/check-ios-model-assets.py --require-present
```

Stage local exports into the expected bundle names with:

```bash
scripts/install-ios-model-assets.py --model yolo11n --source /path/to/yolo-export.mlpackage --symlink
scripts/install-ios-model-assets.py --model depth-anything-v2-small --source /path/to/DepthAnything.mlpackage --symlink
```

Symlink mode is preferred for large local model resources. Copy mode refuses
large sources by default; pass `--allow-large-copy` only when you explicitly
want a copied local asset. Use `--force` to replace an existing staged resource
with the same extension.
