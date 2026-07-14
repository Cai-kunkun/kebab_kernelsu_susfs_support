#!/usr/bin/env bash

set -e


echo "== Setting up build environment =="


export ARCH=arm64


KERNEL_DIR="$GITHUB_WORKSPACE/kernel"


cd "$KERNEL_DIR"


echo "Kernel source:"
pwd


echo "Applying clang compatibility fixes"


python3 <<'EOF'
from pathlib import Path

p = Path("kernel/locking/lockdep.c")

if p.exists():
    s = p.read_text()

    old = "__lock_release(lock, nested, ip)"
    new = "__lock_release(lock, 0, ip)"

    if old in s:
        s = s.replace(old, new)
        p.write_text(s)
        print("Applied lockdep clang fix")
    else:
        print("lockdep fix not needed")
EOF


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