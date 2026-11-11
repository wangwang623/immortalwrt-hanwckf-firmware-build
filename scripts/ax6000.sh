#!/bin/sh
# 项目 3 / 3 —— AX6000 编译前自检脚本
# 由 .github/workflows/build-ax6000.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/ax6000.config。
#
# 本脚本 = 三段共用逻辑（三份逐字一致）+ 机型专属自检：
#           · 基本系统硬校验/软校验  · 统一 LAN 地址  · zram 默认 64M/lzo
# 目录约定：config/ 放 .config，scripts/ 放 .sh，workflows/ 放 .yml，
#           三个目录都按 ax3000t / wf3000a / ax6000 一一对应。

# ===== 基本系统校验段 BEGIN（三份 scripts/*.sh 逐字相同，改一处需同步三处）=====
# 执行位置：openwrt 源码根目录、make defconfig【之前】。
# 固定基线：wangwang623/immortalwrt-mt798x @ openwrt-21.02（Linux 5.4）
#           + immortalwrt/luci @ openwrt-21.02。主包的直接包依赖按这两份源码的
#           DEPENDS / LUCI_DEPENDS 逐项核过，显式写进 config/*.config 并纳入硬校验。
#   · 硬校验 FAIL：6 个基本系统主包 + 18 个直接依赖包，缺任一即中止编译。
#   · 软校验 WARN：只查 3 个主包；它们的依赖已显式 =y，但不校验。
#   · 不校验：条件依赖（+IPV6:luci-proto-ipv6）、非包符号（@BUSYBOX_* / @TARGET_*）、
#             二层传递依赖、DHCP 值、新增扩展插件。
# 排除的二层依赖由 make defconfig 自动展开；换源码版本时须重新核对依赖名。
# 所有 grep 都用 || 包裹，避免 bash -e 下「没匹配到」误退。

fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*（可刷完补装，继续编译）"; }

[ -f .config ] || fail "openwrt/.config 不存在（workflow 没有把 config/*.config 拷进来）"

echo "===== 硬校验：基本系统主包 + 直接依赖（缺任一即中止编译）====="
for p in \
  kmod-mt_wifi kmod-mediatek_hnat luci opkg zram-swap kmod-lib-lzo \
  wifi-dats kmod-conninfra kmod-warp kmod-nf-conntrack \
  uhttpd uhttpd-mod-ubus luci-mod-admin-full luci-theme-bootstrap \
  luci-app-firewall luci-app-opkg luci-proto-ppp libiwinfo-lua rpcd-mod-rrdns \
  uclient-fetch libpthread libubox kmod-zram kmod-crypto-acompress ; do
  grep -q "^CONFIG_PACKAGE_${p}=y" .config || fail "缺少基本系统包（主包或直接依赖）：$p"
done
ok "基本系统 24 项齐全（主包 6 + 直接依赖 18）"

echo "===== 软校验：只查主包（依赖已显式 =y、不校验）====="
for p in luci-i18n-base-zh-cn luci-theme-argon kmod-lib-lz4; do
  grep -q "^CONFIG_PACKAGE_${p}=y" .config || warn "缺少 $p"
done
ok "软项检查完毕（不限制新增插件）"
echo "===== 校验结束 ====="
# ===== 基本系统校验段 END =====

# ===== 统一 LAN 管理地址段 BEGIN（三份 scripts/*.sh 逐字相同）=====
# 三机型固件 LAN 统一 192.168.31.1；U-Boot Web failsafe 地址烧在 FIP 里
# （AX3000T / WF3000A = 192.168.1.1，AX6000 = 192.168.31.1），本段只改固件生成的
# network / dhcp 配置，不影响 U-Boot。
# DHCP 池只是个人习惯：改下面 DHCP_START / DHCP_LIMIT 两个变量即可，
# limit 是地址个数不是结束地址（100 + 150 = 100~249）。本段不校验具体值，
# fork 后按自己习惯改不会被拦；只保留文件存在检查，防止源码路径漂移。
CG=package/base-files/files/bin/config_generate
DHCP=package/network/services/dnsmasq/files/dhcp.conf
DHCP_START=100
DHCP_LIMIT=150
[ -f "$CG" ]   || fail "缺少 $CG（源码树路径变了，请核对）"
[ -f "$DHCP" ] || fail "缺少 $DHCP（源码树路径变了，请核对）"

sed -i 's/192\.168\.1\.1/192.168.31.1/g' "$CG"
sed -i "s/option start.*/option start '$DHCP_START'/g" "$DHCP"
sed -i "s/option limit.*/option limit '$DHCP_LIMIT'/g" "$DHCP"

grep -q '192\.168\.31\.1' "$CG" || fail "config_generate 改写未生效（源码里可能已不是字面 192.168.1.1）"
ok "LAN 192.168.31.1 / DHCP start $DHCP_START / limit $DHCP_LIMIT（DHCP 值不校验）"
# ===== 统一 LAN 管理地址段 END =====

# ===== zram 默认参数段 BEGIN（三份 scripts/*.sh 逐字相同）=====
# 把 64M / lzo 固化进固件：通过 OpenWrt 标准 rootfs 叠加目录 openwrt/files/
# 注入 uci-defaults，首次启动即写入 /etc/config/system，无需刷完在 LuCI 手动设。
# sysupgrade -n / U-Boot Web 重刷后，脚本随新固件 squashfs 再次出现并重新执行。
# 默认仍是 64M / lzo；lz4 编入与否都不影响本段，未编则由 zram.init 回退 lzo。
# workflow 的 "Load custom config" 可能已把 CI 根目录 files/ mv 进来，
# 这里用 mkdir -p 兼容两种情形，不覆盖其它 uci-defaults。
UCI_D=files/etc/uci-defaults
mkdir -p "$UCI_D"
cat > "$UCI_D/99-zram-default" <<'UCI_EOF'
#!/bin/sh
# 首次启动由 /etc/init.d/boot 执行；成功退出后由 boot 自动删除。
# 键名含 [0]，整段加单引号，避免 shell 把 [0] 当作文件名通配符展开。
uci -q get 'system.@system[0]' >/dev/null 2>&1 || uci add system system >/dev/null
uci set 'system.@system[0].zram_size_mb=64'
uci set 'system.@system[0].zram_comp_algo=lzo'
uci commit system
exit 0
UCI_EOF
chmod 755 "$UCI_D/99-zram-default"
sh -n "$UCI_D/99-zram-default" || fail "uci-defaults 脚本语法错误"
[ -x "$UCI_D/99-zram-default" ] || fail "uci-defaults 脚本没有可执行权限"
grep -q "^uci set 'system.@system\[0\].zram_size_mb=64'$" "$UCI_D/99-zram-default" \
  || fail "zram 容量 64M 未写入 uci-defaults"
grep -q "^uci set 'system.@system\[0\].zram_comp_algo=lzo'$" "$UCI_D/99-zram-default" \
  || fail "zram 算法 lzo 未写入 uci-defaults"
grep -q '^exit 0$' "$UCI_D/99-zram-default" || fail "uci-defaults 缺少 exit 0（boot 不会删除它）"
ok "zram 默认 64M / lzo（files/etc/uci-defaults/99-zram-default）"
# ===== zram 默认参数段 END =====

# ===== 机型专属段 =====
# 项目 3 / 3 —— Redmi AX6000：110m 大分区 / MT7986 符号静态自检。
# 与 config/ax6000.config 配套；本文件由 build-ax6000.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行（CI 的 "Load custom config" 阶段）。
# 配套：.github/workflows/build-ax6000.yml → CONFIG_FILE=config/ax6000.config（本文件在 scripts/）
#
# 5.4 源码原生支持 Redmi AX6000，不需要板级移植，所以这里只校验
# 「config 用对了平台 / 机型 / 固定 110m 大分区 / 没有混进 MT7981 专属符号」。
# 本工程三机型都只用大分区，不编 stock 原厂布局：config 里出现 -stock
# 机型符号即失败。
# 管理地址 / DHCP 已由上方「统一 LAN 管理地址段」改为 192.168.31.1（三机型一致）。


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
