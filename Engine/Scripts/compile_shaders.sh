#!/usr/bin/env bash
set -euo pipefail

# Compile AcornEngine Slang shaders into macOS Metal 4 (.metallib),
# iOS Metal 4 (.metallib), and validated Vulkan 1.4 SPIR-V (.spv), and verify
# C++ / SPIR-V / Metal root struct layout parity.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHADER_SRC_DIR="${ENGINE_DIR}/Sources/AcornEngine/Renderer/Shaders"
OUT_DIR="${ENGINE_DIR}/Sources/AcornEngine/Renderer/CompiledShaders"
NOGRAPHICS_DIR="${ENGINE_DIR}/Dependencies/NoGraphicsAPI"

if ! command -v slangc >/dev/null 2>&1; then
    if [[ -x "${HOME}/.local/bin/slangc" ]]; then
        export PATH="${HOME}/.local/bin:${PATH}"
    else
        echo "error: slangc (>= 2026.18.2) is required in PATH" >&2
        exit 1
    fi
fi

if ! command -v spirv-val >/dev/null 2>&1; then
    echo "error: spirv-val (>= 2026.3) is required in PATH" >&2
    exit 1
fi

unset SDKROOT

SLANG_COMMON_FLAGS=(
    -fvk-use-c-layout
    -matrix-layout-row-major
    -I "${SHADER_SRC_DIR}"
    -I "${NOGRAPHICS_DIR}/include"
    -I "${NOGRAPHICS_DIR}/utility/include"
)

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/acorn_shaders.XXXXXX")"
trap 'rm -rf "${WORK_DIR}"' EXIT

mkdir -p "${OUT_DIR}/macos" "${OUT_DIR}/ios" "${OUT_DIR}/vulkan"

compile_stage() {
    local base_name="$1"
    local slang_file="$2"
    local entry="$3"
    local stage="$4"
    local artifact_name="${base_name}_${stage}"
    local src_path="${SHADER_SRC_DIR}/${slang_file}"

    echo "==> Compiling ${artifact_name} (${slang_file} : ${entry})"

    # 1. Metal 4 (macOS & iOS share generated .metal source, but require separate .air/.metallib binaries)
    local metal_src="${WORK_DIR}/${artifact_name}.metal"
    slangc "${src_path}" -target metal -DNOGRAPHICSAPI_METAL \
        -entry "${entry}" -stage "${stage}" \
        "${SLANG_COMMON_FLAGS[@]}" \
        -o "${metal_src}"

    xcrun -sdk macosx metal -std=metal4.0 -target air64-apple-macos26.0 \
        -c "${metal_src}" -o "${WORK_DIR}/${artifact_name}_macos.air"
    xcrun -sdk macosx metallib "${WORK_DIR}/${artifact_name}_macos.air" \
        -o "${OUT_DIR}/macos/${artifact_name}.metallib"

    xcrun -sdk iphoneos metal -std=metal4.0 -target air64-apple-ios26.0 \
        -c "${metal_src}" -o "${WORK_DIR}/${artifact_name}_ios.air"
    xcrun -sdk iphoneos metallib "${WORK_DIR}/${artifact_name}_ios.air" \
        -o "${OUT_DIR}/ios/${artifact_name}.metallib"

    # 2. Vulkan 1.4 SPIR-V + validation
    local spv_out="${OUT_DIR}/vulkan/${artifact_name}.spv"
    slangc "${src_path}" -target spirv -profile spirv_1_5 \
        -emit-spirv-directly -fvk-use-entrypoint-name \
        -capability spvDescriptorHeapEXT \
        -entry "${entry}" -stage "${stage}" \
        "${SLANG_COMMON_FLAGS[@]}" \
        -o "${spv_out}"
    spirv-val --target-env vulkan1.4 --scalar-block-layout "${spv_out}"
}

SHADERS=(
    "mesh:mesh.slang"
    "skinned_mesh:skinned_mesh.slang"
    "instanced_mesh:instanced_mesh.slang"
    "sdf_text:sdf_text.slang"
    "sprite:sprite.slang"
    "sprite_instanced:sprite_instanced.slang"
    "road:road.slang"
)

for entry in "${SHADERS[@]}"; do
    name="${entry%%:*}"
    file="${entry##*:}"
    compile_stage "${name}" "${file}" "vertexMain" "vertex"
    compile_stage "${name}" "${file}" "fragmentMain" "fragment"
done

echo "==> Checking GPU_ROOT C++ / SPIR-V / Metal layout parity..."
SLANGC_BIN="$(command -v slangc)"
python3 "${NOGRAPHICS_DIR}/tools/check_root_layouts.py" \
    "${SHADER_SRC_DIR}" \
    --include "${NOGRAPHICS_DIR}/include" \
    --include "${NOGRAPHICS_DIR}/utility/include" \
    --slang "${SLANGC_BIN}" \
    --output "${WORK_DIR}/layout_probe"

echo "==> Compiled and validated all shaders into ${OUT_DIR}"
