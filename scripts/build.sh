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

echo "=== 处理驱动冲突 ==="

# 禁用 upstream DRM MSM 驱动以避免与 techpack/display 冲突
if [ -f drivers/gpu/drm/msm/Makefile ]; then
    # 备份原始 Makefile
    cp drivers/gpu/drm/msm/Makefile drivers/gpu/drm/msm/Makefile.bak
    # 清空 Makefile 内容，禁用所有编译
    echo "# Disabled to avoid conflict with techpack/display" > drivers/gpu/drm/msm/Makefile
fi

# 禁用 fg-util.o 以避免与 qg-util.o 的 is_input_present 符号冲突
if [ -f drivers/power/supply/qcom/Makefile ]; then
    sed -i 's/^.*fg-util\.o.*$/# &/' drivers/power/supply/qcom/Makefile
fi


# --------------------------------------------------
# Fix OPLUS fingerprint driver headers
# --------------------------------------------------

echo "=== 修复 OPLUS 指纹驱动头文件 ==="

if [ -f drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c ]; then
    sed -i 's|<soc/qcom/smem.h>|<linux/soc/qcom/smem.h>|g' drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c
    sed -i '/#include <linux\/mutex.h>/a #include <linux/uaccess.h>' drivers/input/oplus_fp_drivers/oplus_fp_common/oplus_fp_common.c
fi


# --------------------------------------------------
# Fix OPLUS touchpanel unused functions
# --------------------------------------------------

echo "=== 修复 OPLUS 触摸屏未使用函数警告 ==="

if [ -f drivers/input/touchscreen/oplus_touchscreen/touchpanel_common_driver.c ]; then
    sed -i 's/^static int tp_suspend/__attribute__((unused)) static int tp_suspend/g' drivers/input/touchscreen/oplus_touchscreen/touchpanel_common_driver.c
    sed -i 's/^static void tp_resume/__attribute__((unused)) static void tp_resume/g' drivers/input/touchscreen/oplus_touchscreen/touchpanel_common_driver.c
fi


# --------------------------------------------------
# Fix MSM DRM notifier
# --------------------------------------------------

echo "=== 修复 MSM DRM notifier 符号导出 ==="

if [ -f techpack/display/msm/msm_drv.c ]; then
    if ! grep -q "msm_drm_notifier_call_chain" techpack/display/msm/msm_drv.c; then
        # 查找文件中是否存在 msm_drm_notifier_list
        if grep -q "BLOCKING_NOTIFIER_HEAD(msm_drm_notifier_list)" techpack/display/msm/msm_drv.c; then
            # 如果存在 notifier_list，在其后添加 call_chain 函数
            sed -i '/BLOCKING_NOTIFIER_HEAD(msm_drm_notifier_list);/a \\nint msm_drm_notifier_call_chain(unsigned long val, void *v)\n{\n\treturn blocking_notifier_call_chain(\&msm_drm_notifier_list, val, v);\n}\nEXPORT_SYMBOL(msm_drm_notifier_call_chain);' techpack/display/msm/msm_drv.c
        else
            # 如果不存在，在所有 include 之后添加
            sed -i '/#include/a \\nstatic BLOCKING_NOTIFIER_HEAD(msm_drm_notifier_list);\n\nint msm_drm_notifier_call_chain(unsigned long val, void *v)\n{\n\treturn blocking_notifier_call_chain(\&msm_drm_notifier_list, val, v);\n}\nEXPORT_SYMBOL(msm_drm_notifier_call_chain);' techpack/display/msm/msm_drv.c | head -1
        fi
    fi
fi


# --------------------------------------------------
# Fix MSM DRM strnstr call
# --------------------------------------------------

echo "=== 修复 MSM DRM strnstr 调用 ==="

if [ -f drivers/gpu/drm/msm/msm_drv.c ]; then
    sed -i 's/strnstr(dev_name(dev), "mdp")/strstr(dev_name(dev), "mdp")/g' drivers/gpu/drm/msm/msm_drv.c
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