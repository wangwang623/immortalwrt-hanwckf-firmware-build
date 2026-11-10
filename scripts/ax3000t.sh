#!/bin/sh
# 项目 1 / 3 —— AX3000T 编译前自检脚本
# 由 .github/workflows/build-ax3000t.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/ax3000t.config。
#
# 本脚本 = 共用包集合门禁（头部，三份逐字一致）+ 本机型的自检/后置处理。
# 目录约定：config/ 放 .config，scripts/ 放 .sh，workflows/ 放 .yml，
#           三个目录都按 ax3000t / wf3000a / ax6000 一一对应。

# ===== 包集合门禁段 BEGIN（三份 scripts/*.sh 逐字相同，改一处需同步三处）=====
# 执行位置：openwrt 源码根目录、make defconfig【之前】。
# 内联在 scripts/<机型>.sh 头部，不再单独占用一个共用文件。
#
# 校验目标：
#   · 系统本身的完整功能全部保留（系统工具 / 库 / kmod / netfilter 扩展等）
#   · MTK 闭源无线驱动齐全（缺一即无 WiFi）
#   · 第三方插件【只有 zram-swap】，其余一律拒绝
#
# 注意：htop / tcpdump / nano / ipset / iptables 扩展 / ebtables / tc /
#       ethtool / swconfig / wireless-tools 等属于「系统功能」，不在禁用词里。
#       所有 grep 都用 if / || true 包裹，避免 bash -e 下「没匹配到」误退。

fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK]   $*"; }

[ -f .config ] || fail "openwrt/.config 不存在（workflow 没有把 config/*.config 拷进来）"
echo "===== 包集合门禁：系统完整功能 + 闭源驱动 + 唯一插件 zram-swap ====="

# ① 闭源无线驱动与 HNAT（硬依赖，缺一即无 WiFi / 无硬件加速）
for p in kmod-mt_wifi kmod-warp kmod-conninfra wifi-dats mtwifi-cfg \
         luci-app-mtwifi-cfg kmod-mediatek_hnat; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    fail "缺少闭源驱动/加速包：$p"
  fi
done
ok "闭源无线驱动 + HNAT 齐全"

# ② 唯一允许的第三方插件：zram-swap（kmod-zram 与内核绑定，必须同编）
for p in kmod-zram kmod-lib-lzo zram-swap; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    fail "缺少 $p（zram-swap 三件套必须编进固件）"
  fi
done
ok "zram-swap + kmod-zram + kmod-lib-lzo 已内置"

# ③ 白名单外的 luci-app 一律拒绝（只放行闭源驱动配套的无线配置界面）
BAD=""
for line in $(grep '^CONFIG_PACKAGE_luci-app-' .config | grep '=y' || true); do
  p=${line%%=*}; p=${p#CONFIG_PACKAGE_}
  [ "$p" = "luci-app-mtwifi-cfg" ] || BAD="$BAD $p"
done
[ -z "$BAD" ] || fail "白名单外的 luci-app 插件：$BAD"
ok "无第三方 LuCI 应用（仅保留 luci-app-mtwifi-cfg）"

# ④ 第三方主题（放行系统自带 luci-theme-bootstrap-mod）
THEME=$(grep -E '^CONFIG_PACKAGE_luci-theme-.*=y' .config \
        | grep -v 'luci-theme-bootstrap-mod' || true)
[ -z "$THEME" ] || fail "出现第三方主题：$THEME"
ok "无第三方主题（系统默认 bootstrap-mod 保留）"

# ⑤ 已知第三方插件 / 代理核心 / 后端关键词
KEY='passwall|ssr-plus|vssr|openclash|homeproxy|adguardhome|tailscale'\
'|turboacc|eqos|upnp|miniupnpd|mtkhqos_util|argon|ddns|wol|nikki|daed'\
'|bypass|mosdns|smartdns|rclone|zerotier|frp|alist|openvpn|v2ray|xray'\
'|sing-box|hysteria|naiveproxy|haproxy|clash|tuic|shadowtls|chinadns'\
'|TURBOACC_INCLUDE_'
HIT=$(grep -E "^CONFIG_PACKAGE_.*(${KEY})" .config | grep '=y' || true)
[ -z "$HIT" ] || fail "出现被禁止的第三方插件：$HIT"
ok "无 PassWall / SSR-Plus / TurboACC / UPnP / eqos / Argon / 代理核心等插件"

# ⑥ 系统完整功能软提示（不阻断，仅提醒排查「功能被误删」）
for p in htop tcpdump ipset iptables-mod-tproxy ethtool swconfig \
         wireless-tools openssh-sftp-server luci-theme-bootstrap-mod \
         kmod-tun kmod-tcp-bbr ca-certificates; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    echo "[WARN] 系统功能包 $p 未启用（如需完整功能请检查对应 config/*.config）"
  fi
done

echo "===== 包集合门禁通过 ====="
# ===== 包集合门禁段 END =====

# ===== 机型专属段 =====
# 项目 1 / 3 —— AX3000T：保持原工程设定（管理地址 192.168.31.1、DHCP 2~55）。
# 与 config/ax3000t.config 配套；本文件由 build-ax3000t.yml 的 SELF_SCRIPT 调用。
# Description: (After Update feeds)

# Modify default IP
sed -i 's/192.168.1.1/192.168.31.1/g' package/base-files/files/bin/config_generate

# Set DHCP IP Address start and end
sed -i "s/option start.*/option start \'2\'/g" package/network/services/dnsmasq/files/dhcp.conf
sed -i "s/option limit.*/option limit \'55\'/g" package/network/services/dnsmasq/files/dhcp.conf
