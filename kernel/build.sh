  export PATH=/work/kernel/toolchain/clang/bin:/work/kernel/toolchain/gcc/bin:/work/kernel/toolchain/gcc32/bin:$PATH
  export ARCH=arm64
  export SUBARCH=arm64
  export REAL_CC=/work/kernel/toolchain/clang/bin/clang
  export CLANG_TRIPLE=aarch64-linux-android-
  export CROSS_COMPILE=aarch64-linux-android-
  export CROSS_COMPILE_COMPAT=arm-linux-androideabi-
  scripts/config --file out/kona/.config -d MODVERSIONS
  make O=out/kona olddefconfig
  make O=out/kona -j"$(nproc)" Image.gz modules