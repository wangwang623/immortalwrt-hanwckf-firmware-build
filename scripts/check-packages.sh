#!/bin/sh
# 在 openwrt 源码根目录、make defconfig【之前】执行。
# 三条编译流共用：确保「闭源驱动齐全 + 唯一第三方插件 zram-swap」。
# 检查对象是 CI 刚拷进来的 .config（意图清单，尚未被 make defconfig 展开）。
fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK]   $*"; }

[ -f .config ] || fail "openwrt/.config 不存在"
echo "===== 包集合门禁：闭源驱动 + 唯一插件 zram-swap ====="

# ① 闭源无线驱动与 HNAT（缺一即没有 WiFi / 没有硬件加速）
for p in kmod-mt_wifi kmod-warp kmod-conninfra wifi-dats mtwifi-cfg \
         luci-app-mtwifi-cfg kmod-mediatek_hnat; do
  grep -q "^CONFIG_PACKAGE_${p}=y" .config || fail "缺少闭源驱动/加速包：$p"
done
ok "闭源无线驱动 + HNAT 齐全"

# ② 唯一允许的第三方插件
grep -q '^CONFIG_PACKAGE_zram-swap=y' .config || fail "缺少 zram-swap（三条流都必须内置）"
grep -q '^CONFIG_PACKAGE_kmod-zram=y'   .config || fail "zram-swap 需要 kmod-zram 同编"
ok "zram-swap + kmod-zram 已内置"

# ③ 白名单外的 luci-app 一律拒绝（只放行闭源驱动配套的无线配置界面）
BAD=""
for line in $(grep '^CONFIG_PACKAGE_luci-app-' .config | grep '=y' || true); do
  p=${line%%=*}; p=${p#CONFIG_PACKAGE_}
  [ "$p" = "luci-app-mtwifi-cfg" ] || BAD="$BAD $p"
done
[ -z "$BAD" ] || fail "白名单外的 luci-app 插件：$BAD"
ok "无第三方 LuCI 应用（仅保留 luci-app-mtwifi-cfg）"

# ④ 第三方主题
THEME=$(grep '^CONFIG_PACKAGE_luci-theme-' .config | grep '=y' || true)
[ -z "$THEME" ] || fail "出现第三方主题：$THEME"
ok "无第三方主题"

# ⑤ 已知插件/调试工具关键词（含 6.6 旧 config 里那一批）
KEY='passwall|ssr-plus|vssr|openclash|homeproxy|adguardhome|tailscale|argon|turboacc|eqos|upnp|ddns|wol|htop|tcpdump|nano|nikki|daed|bypass|mosdns|smartdns|rclone|zerotier|frp|alist|socat|ipset|openvpn|v2ray|xray|sing-box|hysteria|naiveproxy'
HIT=$(grep -E "^CONFIG_PACKAGE_.*(${KEY})" .config | grep '=y' || true)
[ -z "$HIT" ] || fail "出现被禁止的插件/工具：$HIT"
ok "无 PassWall / SSR-Plus / TurboACC / UPnP / Argon / 代理核心等额外包"

# ⑥ 软提示（不阻断，避免 feeds 版本差异误杀）
for p in luci luci-i18n-base-zh-cn ca-certificates ca-bundle; do
  grep -q "^CONFIG_PACKAGE_${p}=y" .config || echo "[WARN] 未显式启用 $p（可能由默认包带出）"
done

echo "===== 包集合门禁通过，可以 make defconfig ====="
