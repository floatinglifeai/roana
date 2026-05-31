#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_IMAGE="${LITERT_AOT_DOCKER_IMAGE:-roana-litert-aot-sm8550:20260531-libcxx}"
DOCKER_PLATFORM="${LITERT_AOT_DOCKER_PLATFORM:-linux/amd64}"
SOC_MODEL="${LITERT_AOT_SOC_MODEL:-SM8550}"
OUTPUT_ROOT="${LITERT_AOT_OUTPUT_ROOT:-$ROOT_DIR/build/litert-aot-sm8550-roana}"
MODEL_SET="${MODEL_SET:-all}"

declare -a model_names=()
declare -a model_assets=()
declare -a output_assets=()

add_model() {
  model_names+=("$1")
  model_assets+=("$2")
  output_assets+=("$3")
}

case "$MODEL_SET" in
  all)
    add_model yolo app/src/main/assets/yolo11n-det-int8-smart.tflite yolo11n-det-int8-smart_Qualcomm_SM8550.tflite
    add_model depth app/src/main/assets/depth_anything_v2.tflite depth_anything_v2_Qualcomm_SM8550.tflite
    ;;
  yolo)
    add_model yolo app/src/main/assets/yolo11n-det-int8-smart.tflite yolo11n-det-int8-smart_Qualcomm_SM8550.tflite
    ;;
  depth)
    add_model depth app/src/main/assets/depth_anything_v2.tflite depth_anything_v2_Qualcomm_SM8550.tflite
    ;;
  *)
    printf 'error: MODEL_SET must be one of: all, yolo, depth.\n' >&2
    exit 1
    ;;
esac

cd "$ROOT_DIR"
mkdir -p "$OUTPUT_ROOT/assets"

for index in "${!model_names[@]}"; do
  input_asset="${model_assets[$index]}"
  if [ ! -f "$input_asset" ]; then
    printf 'error: missing model asset: %s\n' "$input_asset" >&2
    exit 1
  fi
done

docker run --rm \
  --platform "$DOCKER_PLATFORM" \
  --volume "$ROOT_DIR:/workspace" \
  --workdir /workspace \
  --env MODEL_SET="$MODEL_SET" \
  --env SOC_MODEL="$SOC_MODEL" \
  --env OUTPUT_ROOT="${OUTPUT_ROOT#$ROOT_DIR/}" \
  "$DOCKER_IMAGE" \
  python3 - "${model_names[@]}" -- "${model_assets[@]}" -- "${output_assets[@]}" <<'PY'
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from ai_edge_litert.aot import aot_compile
from ai_edge_litert.aot.vendors.qualcomm import target as qnn_target


def split_args(args: list[str]) -> tuple[list[str], list[str], list[str]]:
    first = args.index("--")
    second = args.index("--", first + 1)
    return args[:first], args[first + 1 : second], args[second + 1 :]


def soc_model(name: str):
    try:
        return getattr(qnn_target.SocModel, name)
    except AttributeError as error:
        choices = ", ".join(item for item in dir(qnn_target.SocModel) if item.startswith("SM"))
        raise SystemExit(f"unknown SOC_MODEL {name!r}; available Qualcomm models include: {choices}") from error


names, model_paths, output_assets = split_args(sys.argv[1:])
output_root = Path(os.environ["OUTPUT_ROOT"])
sdk_lib = Path(
    "/usr/local/lib/python3.11/site-packages/"
    "ai_edge_litert_sdk_qualcomm/data/lib/x86_64-linux-clang"
)
os.environ["LD_LIBRARY_PATH"] = f"{sdk_lib}:{os.environ.get('LD_LIBRARY_PATH', '')}"
target = qnn_target.Target(soc_model(os.environ.get("SOC_MODEL", "SM8550")))

for name, model_path, output_asset in zip(names, model_paths, output_assets):
    model_output_dir = output_root / name
    model_output_dir.mkdir(parents=True, exist_ok=True)
    aot_compile.aot_compile(
        model_path,
        output_dir=str(model_output_dir),
        target=target,
        keep_going=False,
    )
    compiled = model_output_dir / f"{Path(model_path).stem}_Qualcomm_SM8550_apply_plugin.tflite"
    if not compiled.is_file():
        raise SystemExit(f"expected compiled artifact missing: {compiled}")
    shutil.copy2(compiled, output_root / "assets" / output_asset)
PY

printf 'Compiled LiteRT Qualcomm AOT assets:\n'
shasum -a 256 "$OUTPUT_ROOT"/assets/*.tflite
