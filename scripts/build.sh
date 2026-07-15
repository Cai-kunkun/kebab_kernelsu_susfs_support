#!/usr/bin/env bash
# 编译内核 (stage1: 仅原生编译，不含 KernelSU/SUSFS)
# 用法: ./scripts/build.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source configs/kernel_source.env
source configs/toolchain.env

if [ ! -d "kernel_source" ]; then
  echo "错误: kernel_source 不存在，请先运行 ./scripts/setup.sh"
  exit 1
fi

# 注意: toolchain 放在 PATH 最后面，不要放最前面!
# proton-clang 自带未加前缀的老版本 ld/as/ar，如果放在 PATH 最前面会覆盖系统的 ld,
# 导致编译 host 端工具(如 fixdep)时，老 ld 无法识别新版 glibc 的 .relr.dyn 重定位段而报错。
# 带 aarch64-linux-gnu- 前缀的交叉编译工具系统里没有，依然会正确从 toolchain 里找到。
export PATH="${PATH}:${ROOT_DIR}/${TOOLCHAIN_DIR}/bin"
export HOSTCC=gcc
export HOSTCXX=g++
export HOSTLD=ld

export ARCH="${KERNEL_ARCH}"
export SUBARCH="${KERNEL_ARCH}"
export CC="${CC}"
export CLANG_TRIPLE="${CLANG_TRIPLE}"
export CROSS_COMPILE="${CROSS_COMPILE}"
export CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}"

cd kernel_source

echo "=== 禁用不兼容的 schgm-flash 驱动 ==="
if [ -f drivers/power/supply/qcom/Makefile ]; then
  sed -i '/schgm-flash\.o/d' drivers/power/supply/qcom/Makefile
fi

echo "=== 开启 CONFIG_OPLUS_SM8250_CHARGER ==="
DEFCONFIG_FILE="arch/arm64/configs/${KERNEL_DEFCONFIG}"
if ! grep -q "^CONFIG_OPLUS_SM8250_CHARGER=y" "${DEFCONFIG_FILE}"; then
  echo "CONFIG_OPLUS_SM8250_CHARGER=y" >> "${DEFCONFIG_FILE}"
fi

# 修复 oplus_chg_track.c 栈帧过大问题
echo "=== 修复 oplus_chg_track.c 栈帧限制 ==="
if [ -f drivers/power/oplus/v1/Makefile ]; then
  if ! grep -q "CFLAGS_oplus_chg_track.o" drivers/power/oplus/v1/Makefile; then
    echo "CFLAGS_oplus_chg_track.o += -Wframe-larger-than=4096" >> drivers/power/oplus/v1/Makefile
  fi
fi

echo "=== 生成 defconfig: ${KERNEL_DEFCONFIG} ${KERNEL_DEFCONFIG_FRAGMENTS} ==="
make O=out ARCH="${ARCH}" CC="${CC}" CLANG_TRIPLE="${CLANG_TRIPLE}" \
  CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
  ${KERNEL_DEFCONFIG} ${KERNEL_DEFCONFIG_FRAGMENTS}

echo "=== 开始编译 Image ==="
make O=out ARCH="${ARCH}" CC="${CC}" CLANG_TRIPLE="${CLANG_TRIPLE}" \
  CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
  -j"$(nproc --all)" Image 2>&1 | tee ../build.log

echo "=== 编译完成，产物: kernel_source/out/arch/${ARCH}/boot/Image ==="
