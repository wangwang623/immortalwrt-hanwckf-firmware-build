#!/bin/sh
# 在 openwrt 源码根目录执行（CI 的 "Load custom config" 阶段）。
# 配套：.github/workflows/build-ax6000.yml → CONFIG_FILE=config/ax6000.config
#
# 5.4 源码原生支持 Redmi AX6000，不需要板级移植，所以这里只校验
# 「config 用对了平台 / 机型 / 固定 110m 大分区 / 没有混进 MT7981 专属符号」。
# 本工程三机型都只用大分区，不编 stock 原厂布局：config 里出现 -stock
# 机型符号即失败。
# 不改管理地址：保持 ImmortalWrt 默认 192.168.1.1。

fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK]   $*"; }

MK=target/linux/mediatek/image/mt7986.mk

echo "===== Redmi AX6000 / 5.4 · 110m 大分区配置自检 ====="

[ -f .config ] || fail "openwrt/.config 不存在"
grep -q '^CONFIG_TARGET_mediatek=y' .config      || fail "config 不是 mediatek 平台"
grep -q '^CONFIG_TARGET_mediatek_mt7986=y' .config || fail "config 不是 MT7986 平台"
if grep -q '^CONFIG_TARGET_mediatek_mt7981=y' .config; then fail "config 里混入了 MT7981 平台"; fi
ok "平台：mediatek / mt7986"

N=$(grep -c '^CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_.*=y' .config)
[ "$N" = "1" ] || fail "应只启用 1 个机型，实际 $N 个（检查 config/ax6000.config 是否被改动）"
grep -q '^CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_xiaomi_redmi-router-ax6000=y' .config \
  || fail "启用的机型不是 110m 大分区版 xiaomi_redmi-router-ax6000"
if grep -qE '^CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_.*-stock=y' .config; then
  fail "config 出现 stock 布局机型，本工程不编原厂布局"
fi
grep -E '^CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_.*=y' .config
ok "机型：AX6000 110m 大分区且唯一（无 stock 变体）"

# 这些符号只属于 MT7981 的闭源无线驱动配置，混进来会把固件路径指到 mt7981-fw
for s in 'CONFIG_MTK_CHIP_MT7981' 'CONFIG_WARP_CHIPSET="mt7981"' \
         'CONFIG_first_card_name="MT7981"' 'CONFIG_MTK_MT_WIFI_FIRMWARE_PATH_MT7981' \
         'CONFIG_MTK_CONNINFRA_APSOC_MT7981' 'CONFIG_MTK_FIRST_IF_MT7981'; do
  if grep -qF "$s" .config; then fail "config 混入 MT7981 专属符号：$s"; fi
done
ok "无 MT7981 专属符号"

[ -f "$MK" ] || fail "缺少 $MK"
grep -q '^define Device/xiaomi_redmi-router-ax6000$' "$MK" || fail "源码缺 110m 机型定义"
grep -q 'IMAGE_SIZE := 112640k' "$MK" || fail "110m 机型 IMAGE_SIZE 不是 112640k"
ok "源码：110m 机型定义与 IMAGE_SIZE 正确"

# 用户偏好：zram-swap 编进固件（5.4 官方 defconfig 已带），仅提示不阻断
if grep -q '^CONFIG_PACKAGE_zram-swap=y' .config; then
  ok "zram-swap 已内置（不要事后 opkg install 重复安装）"
else
  echo "[INFO] config 未启用 zram-swap，如需请自行加 CONFIG_PACKAGE_zram-swap=y"
fi

echo "===== 自检通过，可以 make defconfig ====="
