#!/usr/bin/env bash

set -e


echo "== Building kernel =="


export ARCH=arm64


KERNEL_DIR="$GITHUB_WORKSPACE/kernel"


cd "$KERNEL_DIR"


echo "Starting compilation"


make \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    Image.gz \
    -j4


echo "Build finished"


echo "Output files:"


ls -lh out/arch/arm64/boot/