#!/bin/sh
# 项目 1 / 3 —— AX3000T 编译前自检脚本
# 由 .github/workflows/build-ax3000t.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/ax3000t.config。
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
# 项目 1 / 3 —— AX3000T：5.4 源码原生支持，无需板级移植。
# 与 config/ax3000t.config 配套；本文件由 build-ax3000t.yml 的 SELF_SCRIPT 调用。
# 管理地址 / DHCP 已由上方「统一 LAN 管理地址段」处理（三机型逐字一致），
# 这里不再重复 sed —— 原工程 after-update-custom.sh 的 3 行已并入共用段。

echo "===== AX3000T：源码原生机型，无板级自检项 ====="
ok "AX3000T 配置就绪"
