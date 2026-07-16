#!/usr/bin/env bash
# 编译内核 (stage1: 仅原生编译, 不含 KernelSU/SUSFS)
# 用法: ./scripts/build.sh

set -euo pipefail


ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"


source configs/kernel_source.env
source configs/toolchain.env



if [ ! -d "kernel_source" ]; then
    echo "错误: kernel_source 不存在, 请先运行 ./scripts/setup.sh"
    exit 1
fi



# --------------------------------------------------
# Toolchain
# --------------------------------------------------

# 注意:
# proton-clang 自带部分未加前缀工具(ld/as/ar)
# 不要放在 PATH 最前面，否则会覆盖 host 工具链。

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



# --------------------------------------------------
# Prepare output directory
# --------------------------------------------------

echo "=== 创建输出目录 ==="

mkdir -p out


# 防止旧配置污染
if [ -f out/.config ]; then
    echo "=== 删除旧 .config ==="
    rm -f out/.config
fi



# --------------------------------------------------
# Disable incompatible driver
# --------------------------------------------------

echo "=== 禁用不兼容的 schgm-flash 驱动 ==="


if [ -f drivers/power/supply/qcom/Makefile ]; then
    sed -i '/schgm-flash\.o/d' drivers/power/supply/qcom/Makefile
fi


# --------------------------------------------------
# Fix smem header path and uaccess
# --------------------------------------------------

echo "=== 修复 smem.h 头文件路径 ==="

if [ -f drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c ]; then
    sed -i 's|<soc/qcom/smem.h>|<linux/soc/qcom/smem.h>|g' drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c
fi

echo "=== 修复 copy_to_user/copy_from_user 头文件 ==="

if [ -f drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c ]; then
    if ! grep -q "#include <linux/uaccess.h>" drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c; then
        sed -i '/#include <linux\/mutex.h>/a #include <linux/uaccess.h>' drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c
    fi
fi



# --------------------------------------------------
# Merge fragment
# --------------------------------------------------

echo "=== 合并 Stage1 fragment ==="


FRAGMENT_FILE="../configs/kebab_stage1.fragment"


if [ ! -f "${FRAGMENT_FILE}" ]; then
    echo "错误: ${FRAGMENT_FILE} 不存在"
    exit 1
fi


if [ ! -f scripts/kconfig/merge_config.sh ]; then
    echo "错误: scripts/kconfig/merge_config.sh 不存在"
    exit 1
fi



bash scripts/kconfig/merge_config.sh \
    -m \
    -O out \
    arch/arm64/configs/${KERNEL_DEFCONFIG} \
    "${FRAGMENT_FILE}"



# --------------------------------------------------
# Finalize config
# --------------------------------------------------

echo "=== 更新最终配置 ==="


make \
    O=out \
    ARCH="${ARCH}" \
    CC="${CC}" \
    CLANG_TRIPLE="${CLANG_TRIPLE}" \
    CROSS_COMPILE="${CROSS_COMPILE}" \
    CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
    olddefconfig



# --------------------------------------------------
# Verify config
# --------------------------------------------------

echo "=== 当前 Stage1 配置确认 ==="


if [ -f out/.config ]; then

    grep -E \
    "CONFIG_OPLUS_SM8250_CHARGER|CONFIG_OPLUS_FINGERPRINT|CONFIG_TOUCHPANEL_OPLUS|CONFIG_OPLUS_FEATURE_OPROJECT|CONFIG_OPLUS_FEATURE_PROJECTINFO" \
    out/.config || true

else

    echo "错误: out/.config 未生成"
    exit 1

fi



# --------------------------------------------------
# Build
# --------------------------------------------------

echo "=== 开始编译 Image ==="


# Android 4.19 Oplus 驱动存在大量大栈函数
# 仅关闭 frame-larger-than 的 error 化

make \
    O=out \
    ARCH="${ARCH}" \
    CC="${CC}" \
    CLANG_TRIPLE="${CLANG_TRIPLE}" \
    CROSS_COMPILE="${CROSS_COMPILE}" \
    CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
    KCFLAGS="-Wno-error=frame-larger-than" \
    -j"$(nproc --all)" \
    Image 2>&1 | tee ../build.log



# --------------------------------------------------
# Result
# --------------------------------------------------

echo
echo "=== 编译完成 ==="

echo "产物:"
echo "kernel_source/out/arch/${ARCH}/boot/Image"


if [ -f "out/arch/${ARCH}/boot/Image" ]; then
    ls -lh "out/arch/${ARCH}/boot/Image"
else
    echo "警告: Image 未找到"
fi