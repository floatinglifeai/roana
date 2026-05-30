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
