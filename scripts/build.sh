#!/usr/bin/env bash

set -e

export ARCH=arm64

KERNEL_DIR="$GITHUB_WORKSPACE/kernel"
OUT_DIR="$KERNEL_DIR/out"


echo "== Building kernel =="


cd "$KERNEL_DIR"


echo "== Verify config =="

test -f "$OUT_DIR/.config" || {
    echo "Missing out/.config"
    exit 1
}


echo "== Start compilation =="


make \
    O="$OUT_DIR" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    KBUILD_BUILD_USER=arrbrants \
    KBUILD_BUILD_HOST=github-actions \
    -j$(nproc)


echo "== Build finished =="


echo "== Kernel output =="

ls -lh "$OUT_DIR/arch/arm64/boot/"