#!/usr/bin/env bash

set -e


echo "== Setting up build environment =="


export ARCH=arm64


KERNEL_DIR="$GITHUB_WORKSPACE/kernel"


cd "$KERNEL_DIR"


echo "Kernel source:"
pwd


mkdir -p out


echo "Using defconfig:"
echo "vendor/kona_defconfig"


make \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    vendor/kona_defconfig


echo "Defconfig completed"


echo "Kernel configuration ready"