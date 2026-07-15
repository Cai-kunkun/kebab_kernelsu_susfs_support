#!/usr/bin/env bash
# 把 KernelSU-Next 接入内核源码 (stage2, kprobe 方式)
# 用法: ./scripts/apply_kernelsu.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source configs/kernelsu_version.txt
source configs/kernel_source.env

if [ ! -d "kernel_source" ]; then
  echo "错误: kernel_source 不存在,请先运行 ./scripts/setup.sh"
  exit 1
fi

cd kernel_source

echo "=== 接入 KernelSU-Next (分支: ${KSU_SETUP_BRANCH}) ==="
curl -LSs "${KSU_SETUP_URL}" | bash -s "${KSU_SETUP_BRANCH}"

echo "=== 检查 kprobe 相关 config ==="
DEFCONFIG_PATH="arch/arm64/configs/${KERNEL_DEFCONFIG}"
for cfg in CONFIG_KPROBES CONFIG_HAVE_KPROBES CONFIG_KPROBE_EVENTS; do
  if ! grep -q "^${cfg}=y" "${DEFCONFIG_PATH}"; then
    echo "${cfg}=y" >> "${DEFCONFIG_PATH}"
    echo "已添加 ${cfg}=y 到 ${DEFCONFIG_PATH}"
  fi
done

echo "=== KernelSU-Next 接入完成,请重新运行 build.sh 编译 ==="
echo "注意: 编译通过只代表代码能编译,实际 su 功能是否生效需要刷到真机上测试"