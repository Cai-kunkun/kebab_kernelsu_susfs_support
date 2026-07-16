#!/usr/bin/env bash
# 诊断:
# 1. 找出 OPLUS/QCOM 私有符号定义位置
# 2. 分析 Makefile/Kconfig 入口
# 3. 自动定位可能缺失 CONFIG
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
echo "=== 生成 Stage1 .config ==="


if [ -f "scripts/kconfig/merge_config.sh" ]; then

    bash scripts/kconfig/merge_config.sh \
      -m \
      -O out \
      arch/arm64/configs/${KERNEL_DEFCONFIG} \
      ../configs/kebab_stage1.fragment \
      || echo "(merge_config失败,继续诊断)"

else

    echo "merge_config.sh 不存在, fallback defconfig"

    make \
      O=out \
      ARCH="${KERNEL_ARCH}" \
      CC="${CC}" \
      CLANG_TRIPLE="${CLANG_TRIPLE}" \
      CROSS_COMPILE="${CROSS_COMPILE}" \
      CROSS_COMPILE_ARM32="${CROSS_COMPILE_ARM32}" \
      ${KERNEL_DEFCONFIG} \
      || echo "(defconfig生成失败,继续诊断)"

fi




echo
echo "===================================================="
echo "=== 搜索关键 symbol 定义位置 ==="



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
echo "Symbol: ${sym}"
echo "----------------------------------------------------"



echo "[函数定义]"

grep -R \
  -n \
  -E "^[a-zA-Z_].*${sym}[[:space:]]*\(" \
  . \
  --include="*.c" \
  --include="*.h" \
  2>/dev/null || echo "未找到"



echo
echo "[EXPORT_SYMBOL]"

grep -R \
  -n \
  "EXPORT_SYMBOL.*${sym}" \
  . \
  --include="*.c" \
  2>/dev/null || echo "未找到"



echo
echo "[引用位置]"

grep -R \
  -n \
  "${sym}" \
  . \
  --include="*.c" \
  --include="*.h" \
  2>/dev/null \
  | head -30 || true


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

  ["opticalfp_irq_handler_register"]="drivers/input/oplus_fp_drivers"

)



for sym in "${!SYMBOL_DIR[@]}"; do


dir="${SYMBOL_DIR[$sym]}"


echo
echo "===================================================="
echo "${sym}"
echo "目录: ${dir}"
echo "===================================================="



if [ ! -d "${dir}" ]; then

    echo "目录不存在"
    continue

fi



cur="${dir}"


while [ "${cur}" != "." ] && [ -n "${cur}" ]; do


    parent="$(dirname "${cur}")"
    child="$(basename "${cur}")"



    if [ -f "${parent}/Makefile" ]; then

        echo "--- ${parent}/Makefile ---"

        grep -n "${child}" \
          "${parent}/Makefile" \
          2>/dev/null || true

    fi



    if [ -f "${parent}/Kconfig" ]; then

        echo "--- ${parent}/Kconfig ---"

        grep -n -i "${child}" \
          "${parent}/Kconfig" \
          2>/dev/null || true

    fi



    cur="${parent}"

done


done





echo
echo "===================================================="
echo "=== 精确 Kconfig CONFIG 定义搜索 ==="



declare -A CONFIG_SEARCH_PATHS=(

  ["OPLUS Project"]="drivers/soc/oplus"

  ["OPLUS Display"]="techpack/display"

  ["OPLUS Fingerprint"]="drivers/input/oplus_fp_drivers"

  ["OPLUS Touchpanel"]="drivers/input/touchscreen"

  ["OPLUS Charger"]="drivers/power/oplus"

  ["Qualcomm SMEM"]="drivers/soc/qcom"

)



for name in "${!CONFIG_SEARCH_PATHS[@]}"; do


path="${CONFIG_SEARCH_PATHS[$name]}"


echo
echo "----------------------------------------------------"
echo "${name}"
echo "Path: ${path}"
echo "----------------------------------------------------"



if [ -d "${path}" ]; then


grep -R \
  -n \
  -E "^config[[:space:]].*(OPLUS|OPPO|PROJECT|DISPLAY|NOTIFY|FINGER|TOUCH|GAUGE|CHARGER|SMEM|QCOM)" \
  "${path}" \
  --include="Kconfig" \
  --include="Kconfig.*" \
  2>/dev/null || echo "未找到 CONFIG"



else

echo "目录不存在"

fi


done






echo
echo "===================================================="
echo "=== 当前 CONFIG 状态 ==="



if [ -f out/.config ]; then


grep -i \
  -E \
  "CONFIG_(OPLUS|OPPO|MSM|QCOM|DRM|TOUCH|GAUGE|FINGER)" \
  out/.config \
  | head -200


else


echo "out/.config 不存在"


fi





echo
echo "===================================================="
echo "=== 当前关闭 CONFIG ==="



if [ -f out/.config ]; then


grep \
  -E \
  "^# CONFIG_(OPLUS|OPPO|MSM|QCOM|DRM|TOUCH|GAUGE|FINGER).*is not set" \
  out/.config \
  | head -200


fi





echo
echo "===================================================="
echo "=== 诊断完成 ==="

echo "报告:"
echo "${REPORT}"

echo "===================================================="