#!/usr/bin/env bash
# GPU load + free VRAM. NVIDIA via nvidia-smi, AMD via amdgpu sysfs.
# Prints nothing when there is no GPU with its own memory (Intel iGPU, VMs).
. ~/.config/tuxcraft/colors.sh 2>/dev/null
icon="%{F${accent:-#fabd2f}}󰢮%{F-}"

gib() { awk -v b="$1" 'BEGIN { printf "%.1f GB", b / 1073741824 }'; }

if command -v nvidia-smi >/dev/null 2>&1 &&
   read -r util free < <(nvidia-smi --query-gpu=utilization.gpu,memory.free \
     --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ','); then
  [[ $util =~ ^[0-9]+$ && $free =~ ^[0-9]+$ ]] || exit 0
  echo "$icon $util% $(gib $(( free * 1048576 ))) free"   # MiB -> bytes
  exit 0
fi

for dev in /sys/class/drm/card[0-9]*/device; do
  [[ -r $dev/mem_info_vram_total && -r $dev/gpu_busy_percent ]] || continue
  total=$(<"$dev/mem_info_vram_total") used=$(<"$dev/mem_info_vram_used")
  (( total > 0 )) || continue
  echo "$icon $(<"$dev/gpu_busy_percent")% $(gib $(( total - used ))) free"
  exit 0
done
