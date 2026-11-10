#!/bin/sh
# 项目 2 / 3 —— WF3000A 编译前自检脚本
# 由 .github/workflows/build-wf3000a.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/wf3000a.config。
#
# 本脚本 = 三段共用逻辑（三份逐字一致）+ 机型专属自检：
#           · 必要包正向校验  · 统一 LAN 地址  · zram 默认 64M/lzo
# 目录约定：config/ 放 .config，scripts/ 放 .sh，workflows/ 放 .yml，
#           三个目录都按 ax3000t / wf3000a / ax6000 一一对应。

# ===== 必要包正向校验段 BEGIN（三份 scripts/*.sh 逐字相同，改一处需同步三处）=====
# 执行位置：openwrt 源码根目录、make defconfig【之前】。
# 只校验「必要包在不在」，不校验「哪些包不该在」：
#   · 以后改 config/*.config 增删任何非必要包，本段都不会拦
#   · 只有缺了闭源驱动 / zram / 中文环境 / 基础系统包才 fail
# config 末尾的 is not set 行是当前的「不编声明」，不是门禁；
#   想加某个包，把对应行改成 =y 即可，无需改脚本。
# 所有 grep 都用 if 包裹，避免 bash -e 下「没匹配到」误退。

fail() { echo "[FAIL] $*"; exit 1; }
ok()   { echo "[OK]   $*"; }

[ -f .config ] || fail "openwrt/.config 不存在（workflow 没有把 config/*.config 拷进来）"
echo "===== 必要包正向校验（不限制新增包）====="

# ① 闭源无线驱动与 HNAT（硬依赖，缺一即无 WiFi / 无硬件加速）
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

# ④ 基本中文环境（硬校验：LuCI 简体中文 + 基础汉化 + 无线配置汉化）
for s in 'CONFIG_LUCI_LANG_zh_Hans=y' \
         'CONFIG_PACKAGE_luci-i18n-base-zh-cn=y' \
         'CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn=y'; do
  if ! grep -q "^${s}$" .config; then
    fail "缺少基本中文环境：$s（刷完会是英文 LuCI）"
  fi
done
ok "中文环境：LuCI 简体中文 + 基础汉化 + 无线配置汉化"

# ⑤ 软提示（不阻断）：保留项与系统工具缺了只提醒，不 fail
for p in luci-app-turboacc-mtk luci-i18n-turboacc-mtk-zh-cn \
         htop tcpdump ipset iptables-mod-tproxy ethtool swconfig \
         wireless-tools openssh-sftp-server luci-theme-bootstrap-mod \
         kmod-tun kmod-tcp-bbr ca-certificates; do
  if ! grep -q "^CONFIG_PACKAGE_${p}=y" .config; then
    echo "[WARN] 可选包 $p 未启用（如需请检查 config/*.config）"
  fi
done

echo "===== 必要包校验通过（config 可自由增包）====="
# ===== 必要包正向校验段 END =====

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
# 项目 2 / 3 —— KST WF3000A：5.4 板级移植 4 文件静态自检。
# 与 config/wf3000a.config 配套；本文件由 build-wf3000a.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行（CI 的 "Load custom config" 阶段）。
#
# 管理地址 / DHCP 已由上方「统一 LAN 管理地址段」改为 192.168.31.1（三机型一致），
# 这里不再重复 sed。以下只做「失败要趁早」的静态自检：4 个板级文件是否真的
# 覆盖进来了，以及是否又退回到 8103 / 双 GMAC / 6.6 的错误写法。

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

# 只取 02_network 里 kst,wf3000a 的 ucidef 分支做检查：其它机型（360,t7 /
# 8103 等）本来就用 eth0/eth1 + 5u@eth1，全文件 grep 会误报。
python3 - "$NET" > /tmp/wf3000a_net.branch <<'PYCODE'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'^\s*kst,wf3000a\).*?^\s*;;', t, re.M | re.S)
print(m.group(0) if m else '')
PYCODE
BRANCH=/tmp/wf3000a_net.branch
[ -s "$BRANCH" ] || fail "$NET 里找不到 kst,wf3000a 的 ucidef 分支"

[ -f "$DTS" ]  || fail "缺少 $DTS（源码 fork 的 DTS 没上传）"
grep -q 'compatible = "kst,wf3000a"' "$CODE" || fail "DTS 不是 WF3000A 版"
grep -q 'gmac0: mac@0' "$CODE" || fail "DTS 缺少 gmac0"
if grep -q 'gmac1: mac@1' "$CODE"; then fail "DTS 里还有 gmac1（应只用单 GMAC，5.4 双通道跑不通）"; fi
if grep -q 'phy-handle' "$CODE"; then fail "DTS 里还有外置 PHY（8103 的写法），WF3000A 没有这颗 PHY"; fi
if grep -q 'ethernet-phy@0' "$CODE"; then fail "DTS 里还有 phy0 节点"; fi
if grep -q 'mediatek,mt7531' "$CODE"; then fail "5.4 用 gsw(mediatek,mt753x)，不是 6.6 的 DSA switch"; fi
if grep -q 'mediatek,portmap' "$CODE"; then fail "不要写 mediatek,portmap（驱动 4 种内建映射均不对应 port3=WAN，VLAN 由 02_network/swconfig 配置）"; fi
if grep -q 'mediatek,bmt-mtd-overridden-oobsize' "$CODE"; then fail "5.4 OOB 天然 64B，不要加 6.6 的 override"; fi
if grep -q '&wifi' "$CODE"; then fail "5.4 的 mt7981.dtsi 没有 wifi 节点"; fi
if grep -q 'nvmem-layout' "$CODE"; then fail "5.4 不读 nvmem-layout"; fi
grep -q 'label = "Factory"' "$CODE" || fail "Factory 分区标签必须是大写（02_network 与闭源驱动依赖）"
grep -q 'reg = <0x580000 0x7200000>' "$CODE" || fail "ubi 分区不是 114m"
grep -q 'port5: port@5' "$CODE" || fail "gsw 缺 port5 CPU port（ct3003 VLAN 模式标准声明）"
grep -q 'port6: port@6' "$CODE" || fail "gsw 缺 port6 CPU port"
grep -q 'mtketh-wan = "eth0.2"' "$CODE" || fail "hnat WAN 未指向 eth0.2（单 GMAC VLAN）"
grep -q 'mtketh-max-gmac = <1>' "$CODE" || fail "hnat max-gmac 不是 1"
ok "DTS：单 GMAC + VLAN / 分区 / NMBM / hnat 写法正确"

grep -q '^define Device/kst_wf3000a' "$MK" || fail "$MK 里没有 Device/kst_wf3000a"
grep -q '^TARGET_DEVICES += kst_wf3000a' "$MK" || fail "$MK 里没有 TARGET_DEVICES += kst_wf3000a"
grep -q 'DEVICE_DTS := mt7981-kst-wf3000a' "$MK" || fail "DEVICE_DTS 指向不对"
grep -q 'IMAGE_SIZE := 116736k' "$MK" || fail "IMAGE_SIZE 不是 116736k"
[ "$(grep -c '^define Device/kst_wf3000a' "$MK")" = "1" ] || fail "机型定义重复"
ok "mt7981.mk：机型已注册且唯一（无需改动）"

grep -q 'kst,wf3000a)' "$NET" || fail "$NET 缺 WF3000A 分支"
grep -q 'ucidef_set_interfaces_lan_wan "eth0.1" "eth0.2"' "$BRANCH" || fail "$NET 的 WF3000A 分支未用 eth0.1/eth0.2 VLAN"
grep -q '"0:lan" "1:lan" "2:lan" "3:wan" "6t@eth0"' "$BRANCH" || fail "$NET 的端口映射不是左→右 LAN1/2/3+WAN（单 CPU port）"
if grep -q '5u@eth1' "$BRANCH"; then fail "$NET 回退到 5u@eth1 双 GMAC 写法（WAN 收 0 包）"; fi
if grep -q '"eth0" "eth1"' "$BRANCH"; then fail "$NET 回退到 eth0/eth1 双 GMAC 写法"; fi
grep -q 'mtd_get_mac_binary Factory 0x4' "$NET" || fail "$NET 没从 Factory 0x4 推导 MAC"
ok "02_network：单 GMAC VLAN / 端口顺序 / MAC 推导正确"

[ "$(grep -c 'kst,wf3000a |' "$PLAT")" = "2" ] || fail "$PLAT 应在 platform_do_upgrade 与 platform_check_image 各出现一次"
grep -q 'nand_do_upgrade' "$PLAT" || fail "$PLAT 缺 nand_do_upgrade"
ok "platform.sh：升级/校验分支齐全（无需改动）"

[ -f .config ] || fail "openwrt/.config 不存在"
grep -q '^CONFIG_TARGET_mediatek_mt7981=y' .config || fail "config 不是 MT7981 平台"
grep -q '^CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_kst_wf3000a=y' .config || fail "config 里没有 kst_wf3000a 机型"
ok "config：机型符号正确（不复用 AX3000T 的 .config）"

sh -n "$NET" || fail "$NET shell 语法错误"
sh -n "$PLAT" || fail "$PLAT shell 语法错误"
ok "shell 语法"

echo "===== 自检通过，可以 make defconfig ====="
