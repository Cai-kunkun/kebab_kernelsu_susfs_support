#!/usr/bin/env bash
# 编译内核 (stage1: 仅原生编译,不含 KernelSU/SUSFS)
# 用法: ./scripts/build.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source configs/kernel_source.env
source configs/toolchain.env

if [ ! -d "kernel_source" ]; then
  echo "错误: kernel_source 不存在,请先运行 ./scripts/setup.sh"
  exit 1
fi


# 注意: toolchain 放在 PATH 最后面,不要放最前面!
# proton-clang 自带未加前缀的老版本 ld/as/ar,如果放在 PATH 最前面会覆盖系统的 ld,
# 导致编译 host 端工具(如 fixdep)时,老 ld 无法识别新版 glibc 的 .relr.dyn 重定位段而报错。
# 带 aarch64-linux-gnu- 前缀的交叉编译工具系统里没有,依然会正确从 toolchain 里找到。
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
# struct smb_charger 在这份 tree 里对该驱动只有前向声明、没有完整定义,
# 说明这个文件跟当前 tree 不匹配,直接禁用编译入口(而不是猜 Kconfig 符号名)
if [ -f drivers/power/supply/qcom/Makefile ]; then
  sed -i '/schgm-flash\.o/d' drivers/power/supply/qcom/Makefile
fi

echo "=== 开启 CONFIG_OPLUS_SM8250_CHARGER ==="
# 这个开关关着会导致 drivers/power/oplus/ 整个目录不编译,
# 但别的文件(gpio/socinfo/usb-pd/i2c等)又无条件调用这个目录里定义的函数,
# 导致最后链接阶段一大堆 undefined reference。打开它让这个目录参与编译。
DEFCONFIG_FILE="arch/arm64/configs/${KERNEL_DEFCONFIG}"
if ! grep -q "^CONFIG_OPLUS_SM8250_CHARGER=y" "${DEFCONFIG_FILE}"; then
  echo "CONFIG_OPLUS_SM8250_CHARGER=y" >> "${DEFCONFIG_FILE}"
fi

echo "=== 生成 defconfig: ${KERNEL_DEFCONFIG} ${KERNEL_DEFCONFIG_FRAGMENTS} ===" 
# 注意: CC/CROSS_COMPILE 必须在命令行显式传入,不能只靠 export!
# 内核顶层 Makefile 里是 `CC = $(CROSS_COMPILE)gcc` 这种直接赋值,
# 优先级比 shell export 的环境变量高,只 export 会被这行覆盖掉。
make O=out ARCH="${ARCH}" CC="${CC}" CLANG_TRIPLE="${CLANG_TRIPLE}" \
  CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
  ${KERNEL_DEFCONFIG} ${KERNEL_DEFCONFIG_FRAGMENTS}

echo "=== 开始编译 Image ==="
make O=out ARCH="${ARCH}" CC="${CC}" CLANG_TRIPLE="${CLANG_TRIPLE}" \
  CROSS_COMPILE="${CROSS_COMPILE}" CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
  -j"$(nproc --all)" Image 2>&1 | tee ../build.log

echo "=== 编译完成,产物: kernel_source/out/arch/${ARCH}/boot/Image ==="
