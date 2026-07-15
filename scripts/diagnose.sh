#!/usr/bin/env bash
# 诊断: 找出链接报错里的 oplus/qcom 私有符号定义位置、
#       对应 Makefile/Kconfig 入口以及可能缺失的 CONFIG
#
# 用法:
# ./scripts/diagnose.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source configs/kernel_source.env
source configs/toolchain.env

cd kernel_source

export PATH="${PATH}:${ROOT_DIR}/${TOOLCHAIN_DIR}/bin"


REPORT="../diagnose_report.log"

exec > >(tee "${REPORT}") 2>&1


echo "===================================================="
echo " Kernel Diagnose Report"
echo "===================================================="


echo
echo "===================================================="
echo "=== 生成 .config ==="


make \
  O=out \
  ARCH="${KERNEL_ARCH}" \
  CC="${CC}" \
  CLANG_TRIPLE="${CLANG_TRIPLE}" \
  CROSS_COMPILE="${CROSS_COMPILE}" \
  CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
  ${KERNEL_DEFCONFIG} ${KERNEL_DEFCONFIG_FRAGMENTS} \
  > /dev/null 2>&1 || echo "(defconfig生成失败,继续诊断)"



echo
echo "===================================================="
echo "=== 搜索关键 undefined symbol 定义位置 ==="


declare -a SYMBOLS=(
  "get_project"
  "get_boot_mode"
  "get_eng_version"
  "oplus_gauge_init"
  "switch_to_otg_mode"
  "msm_drm_notifier_call_chain"
  "switch_headset_state"
  "opticalfp_irq_handler_register"
)



for sym in "${SYMBOLS[@]}"; do

echo
echo "----------------------------------------------------"
echo " Symbol: ${sym}"
echo "----------------------------------------------------"


echo "[函数定义]"

grep -R \
  -n \
  -E "^[a-zA-Z_].*${sym}[[:space:]]*\(" \
  . \
  --include="*.c" \
  --include="*.h" \
  2>/dev/null || echo "未找到定义"



echo
echo "[EXPORT_SYMBOL]"

grep -R \
  -n \
  "EXPORT_SYMBOL.*${sym}" \
  . \
  --include="*.c" \
  2>/dev/null || echo "未找到导出"



echo
echo "[引用位置]"

grep -R \
  -n \
  "${sym}" \
  . \
  --include="*.c" \
  --include="*.h" \
  2>/dev/null | head -30 || true


done




echo
echo "===================================================="
echo "=== Makefile/Kconfig 路径分析 ==="



declare -A SYMBOL_DIR=(
  ["get_project"]="drivers/soc/oplus"
  ["get_boot_mode"]="drivers/soc/oplus"
  ["get_eng_version"]="drivers/soc/oplus"
  ["oplus_gauge_init"]="drivers/power/oplus"
  ["switch_to_otg_mode"]="drivers/power/oplus"
  ["msm_drm_notifier_call_chain"]="techpack/display"
  ["switch_headset_state"]="drivers/input/touchscreen"
  ["opticalfp_irq_handler_register"]="drivers"
)



for sym in "${!SYMBOL_DIR[@]}"; do

dir="${SYMBOL_DIR[$sym]}"

echo
echo "===================================================="
echo "=== ${sym}"
echo "目录: ${dir}"
echo "===================================================="


if [ ! -d "${dir}" ]; then
    echo "目录不存在"
    continue
fi


cur="${dir}"


while [ "${cur}" != "." ] && [ -n "${cur}" ]; do

    parent="$(dirname "${cur}")"
    childname="$(basename "${cur}")"


    if [ -f "${parent}/Makefile" ]; then

        echo "--- ${parent}/Makefile ---"

        grep -n "${childname}" \
          "${parent}/Makefile" \
          2>/dev/null || true

    fi


    if [ -f "${parent}/Kconfig" ]; then

        echo "--- ${parent}/Kconfig ---"

        grep -n -i "${childname}" \
          "${parent}/Kconfig" \
          2>/dev/null || true

    fi


    cur="${parent}"

done


done





echo
echo "===================================================="
echo "=== 自动搜索相关 Kconfig ==="


grep -R -n \
  -E \
  "OPLUS|OPPO|GAUGE|TOUCH|PROJECT|DISPLAY|NOTIFY|FINGERPRINT|CHARGER" \
  --include="Kconfig" \
  --include="Kconfig.*" \
  . \
  2>/dev/null \
  | head -300 || true





echo
echo "===================================================="
echo "=== 当前 CONFIG 状态 ==="


if [ -f out/.config ]; then

grep -i \
  -E \
  "CONFIG_(OPLUS|OPPO|MSM|QCOM|DRM|TOUCH|GAUGE)" \
  out/.config \
  | head -150

else

echo "out/.config 不存在"

fi




echo
echo "===================================================="
echo "=== 自动寻找关闭状态 CONFIG ==="


if [ -f out/.config ]; then

grep \
  -E \
  "^# CONFIG_(OPLUS|OPPO|MSM|QCOM|DRM|TOUCH|GAUGE).*is not set" \
  out/.config \
  | head -150

fi




echo
echo "===================================================="
echo "诊断完成"
echo "输出文件:"
echo "${REPORT}"
echo "===================================================="
