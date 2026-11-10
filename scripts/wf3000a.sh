#!/bin/sh
# 项目 2 / 3 —— WF3000A 编译前自检脚本
# 由 .github/workflows/build-wf3000a.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/wf3000a.config。
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
# 项目 2 / 3 —— KST WF3000A：5.4 板级移植 4 文件静态自检。
# 与 config/wf3000a.config 配套；本文件由 build-wf3000a.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行（CI 的 "Load custom config" 阶段）。
# 配套：.github/workflows/build-wf3000a.yml → CONFIG_FILE=config/wf3000a.config（本文件在 scripts/）
#
# 不做任何 sed 改写：AX3000T 参考工程把管理地址改成 192.168.31.1，
# WF3000A 保持 ImmortalWrt 默认 192.168.1.1。
# 只做「失败要趁早」的静态自检：4 个板级文件是否真的覆盖进来了，
# 以及是否误把 6.6 / 8103 的错误写法带进来。


DTS=target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-kst-wf3000a.dts
MK=target/linux/mediatek/image/mt7981.mk
NET=target/linux/mediatek/mt7981/base-files/etc/board.d/02_network
PLAT=target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh

echo "===== KST WF3000A / 5.4 板级移植自检 ====="

# 注释里为说明 8103/6.6 的差异会写出那些错误属性名，
# 静态检查只看去掉注释后的代码区，避免误报。
python3 - "$DTS" > /tmp/wf3000a_dts.code <<'PYCODE'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
t = re.sub(r'//[^\n]*', '', t)
print(t)
PYCODE
CODE=/tmp/wf3000a_dts.code

[ -f "$DTS" ]  || fail "缺少 $DTS（源码 fork 的 DTS 没上传）"
grep -q 'compatible = "kst,wf3000a"' "$CODE" || fail "DTS 不是 WF3000A 版"
grep -q 'gmac1: mac@1' "$CODE" || fail "DTS 缺少 gmac1"
if grep -q 'phy-handle' "$CODE"; then fail "DTS 里还有外置 PHY（8103 的写法），WF3000A 没有这颗 PHY"; fi
if grep -q 'ethernet-phy@0' "$CODE"; then fail "DTS 里还有 phy0 节点"; fi
if grep -q 'mediatek,mt7531' "$CODE"; then fail "5.4 用 gsw(mediatek,mt753x)，不是 6.6 的 DSA switch"; fi
if grep -q 'mediatek,bmt-mtd-overridden-oobsize' "$CODE"; then fail "5.4 OOB 天然 64B，不要加 6.6 的 override"; fi
if grep -q '&wifi' "$CODE"; then fail "5.4 的 mt7981.dtsi 没有 wifi 节点"; fi
if grep -q 'nvmem-layout' "$CODE"; then fail "5.4 不读 nvmem-layout"; fi
grep -q 'label = "Factory"' "$CODE" || fail "Factory 分区标签必须是大写（02_network 与闭源驱动依赖）"
grep -q 'reg = <0x580000 0x7200000>' "$CODE" || fail "ubi 分区不是 114m"
grep -q 'port5: port@5' "$CODE" || fail "gsw 缺 port5 CPU port"
grep -q 'port6: port@6' "$CODE" || fail "gsw 缺 port6 CPU port"
ok "DTS：拓扑/分区/NMBM 写法正确"

grep -q '^define Device/kst_wf3000a' "$MK" || fail "$MK 里没有 Device/kst_wf3000a"
grep -q '^TARGET_DEVICES += kst_wf3000a' "$MK" || fail "$MK 里没有 TARGET_DEVICES += kst_wf3000a"
grep -q 'DEVICE_DTS := mt7981-kst-wf3000a' "$MK" || fail "DEVICE_DTS 指向不对"
grep -q 'IMAGE_SIZE := 116736k' "$MK" || fail "IMAGE_SIZE 不是 116736k"
[ "$(grep -c '^define Device/kst_wf3000a' "$MK")" = "1" ] || fail "机型定义重复"
ok "mt7981.mk：机型已注册且唯一"

grep -q 'kst,wf3000a)' "$NET" || fail "$NET 缺 WF3000A 分支"
grep -q '"3:wan" "6u@eth0" "5u@eth1"' "$NET" || fail "$NET 的端口映射不是 3LAN+1WAN"
grep -q 'mtd_get_mac_binary Factory 0x4' "$NET" || fail "$NET 没从 Factory 0x4 推导 MAC"
ok "02_network：端口与 MAC 分支正确"

[ "$(grep -c 'kst,wf3000a |' "$PLAT")" = "2" ] || fail "$PLAT 应在 platform_do_upgrade 与 platform_check_image 各出现一次"
grep -q 'nand_do_upgrade' "$PLAT" || fail "$PLAT 缺 nand_do_upgrade"
ok "platform.sh：升级/校验分支齐全"

[ -f .config ] || fail "openwrt/.config 不存在"
grep -q '^CONFIG_TARGET_mediatek_mt7981=y' .config || fail "config 不是 MT7981 平台"
grep -q '^CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_kst_wf3000a=y' .config || fail "config 里没有 kst_wf3000a 机型"
ok "config：机型符号正确（不复用 AX3000T 的 .config）"

sh -n "$NET" || fail "$NET shell 语法错误"
sh -n "$PLAT" || fail "$PLAT shell 语法错误"
ok "shell 语法"

echo "===== 自检通过，可以 make defconfig ====="
