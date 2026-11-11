#!/bin/sh
# 项目 1 / 3 —— AX3000T 编译前自检脚本
# 由 .github/workflows/build-ax3000t.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/ax3000t.config。
#
# 本脚本 = 三段共用逻辑（三份逐字一致）+ 机型专属自检：
#           · 最小系统必要包校验  · 统一 LAN 地址  · zram 默认 64M/lzo
# 目录约定：config/ 放 .config，scripts/ 放 .sh，workflows/ 放 .yml，
#           三个目录都按 ax3000t / wf3000a / ax6000 一一对应。

# ===== 最小系统必要包正向校验段 BEGIN（三份 scripts/*.sh 逐字相同，改一处需同步三处）=====
# 执行位置：openwrt 源码根目录、make defconfig【之前】。
# 校验范围只限「当前最小完整功能系统」必须的包：
#   闭源驱动 / HNAT · 基础系统 · 中文环境 · zram-swap · Argon 主题
# 不校验「哪些包不该在」；以后在 config/*.config 增删扩展插件，本段都不拦，
# 那时只需另验「新包版本是否兼容、依赖是否完整」。
# config 末尾的 is not set 行是当前的不编声明，不是门禁；加包改成 =y 即可。
# 所有 grep 都用 if 包裹，避免 bash -e 下「没匹配到」误退。

fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK]   $*"; }

[ -f .config ] || fail "openwrt/.config 不存在（workflow 没有把 config/*.config 拷进来）"
echo "===== 最小系统必要包校验（不限制新增包）====="

# ① 闭源无线驱动与 HNAT（缺一即无 WiFi / 无硬件加速）
for p in kmod-mt_wifi kmod-warp kmod-conninfra wifi-dats mtwifi-cfg \
         luci-app-mtwifi-cfg kmod-mediatek_hnat; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    fail "缺少闭源驱动/加速包：$p"
  fi
done
ok "闭源无线驱动 + HNAT 齐全"

# ② zram-swap 三件套（与内核绑定，事后 opkg install 装不上）
for p in kmod-zram kmod-lib-lzo zram-swap; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    fail "缺少 $p（zram-swap 三件套必须编进固件）"
  fi
done
ok "zram-swap + kmod-zram + kmod-lib-lzo 已内置"

# ③ 基础系统包
for p in luci opkg ppp ca-bundle; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    fail "缺少基础系统包：$p"
  fi
done
ok "luci / opkg / ppp / ca-bundle 齐全"

# ④ 基本中文环境（缺了刷完是英文 LuCI）
for s in 'CONFIG_LUCI_LANG_zh_Hans=y' \
         'CONFIG_PACKAGE_luci-i18n-base-zh-cn=y' \
         'CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn=y'; do
  if ! grep -q "^${s}$" .config; then
    fail "缺少基本中文环境：$s"
  fi
done
ok "中文环境：LuCI 简体中文 + 基础汉化 + 无线配置汉化"

# ⑤ Argon 主题及依赖（最小系统的界面组成，漏了退回默认主题、体验欠佳）
for p in luci-theme-argon wget jsonfilter; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    fail "缺少 Argon 主题或其依赖：$p"
  fi
done
ok "Argon 主题 + wget / jsonfilter 已内置"

echo "===== 最小系统齐全（config 可自由增包）====="
# ===== 最小系统必要包正向校验段 END =====

# ===== 统一 LAN 管理地址段 BEGIN（三份 scripts/*.sh 逐字相同）=====
# 三机型固件 LAN 统一 192.168.31.1、DHCP 池 2~55。
# U-Boot Web failsafe 地址烧在 FIP 里（AX3000T / WF3000A = 192.168.1.1，
# AX6000 = 192.168.31.1），本段只改固件生成的 network / dhcp 配置，不影响 U-Boot。
# 目标文件来自源码树；缺失即 fail，避免 bash -e 下 sed 静默失败或源码路径漂移。
CG=package/base-files/files/bin/config_generate
DHCP=package/network/services/dnsmasq/files/dhcp.conf
[ -f "$CG" ]   || fail "缺少 $CG（源码树路径变了，请核对）"
[ -f "$DHCP" ] || fail "缺少 $DHCP（源码树路径变了，请核对）"

sed -i 's/192\.168\.1\.1/192.168.31.1/g' "$CG"
sed -i "s/option start.*/option start '2'/g" "$DHCP"
sed -i "s/option limit.*/option limit '55'/g" "$DHCP"

grep -q '192\.168\.31\.1' "$CG" || fail "config_generate 改写未生效（源码里可能已不是字面 192.168.1.1）"
ok "LAN 192.168.31.1 / DHCP 2~55（三机型统一）"
# ===== 统一 LAN 管理地址段 END =====

# ===== zram 默认参数段 BEGIN（三份 scripts/*.sh 逐字相同）=====
# 把 64M / lzo 固化进固件：通过 OpenWrt 标准 rootfs 叠加目录 openwrt/files/
# 注入 uci-defaults，首次启动即写入 /etc/config/system，无需刷完在 LuCI 手动设。
# sysupgrade -n / U-Boot Web 重刷后，脚本随新固件 squashfs 再次出现并重新执行。
# 只编了 kmod-lib-lzo，算法固定 lzo（LuCI 下拉里其它算法是静态枚举，选了不生效）。
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
