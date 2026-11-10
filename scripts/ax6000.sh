#!/bin/sh
# 项目 3 / 3 —— AX6000 编译前自检脚本
# 由 .github/workflows/build-ax6000.yml 的 SELF_SCRIPT 调用。
# 在 openwrt 源码根目录执行；配套 config/ax6000.config。
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

# ⑦ 基本中文环境（硬校验：LuCI 简体中文 + 基础汉化 + 闭源无线配置汉化）
#    中文界面实际由 luci-i18n-* 提供；CONFIG_LUCI_LANG_zh_Hans 是 LuCI 语言选择项。
#    两项汉化包缺一即英文界面，这里必须拦住，不能只靠 WARN。
for s in 'CONFIG_PACKAGE_luci=y' \
         'CONFIG_LUCI_LANG_zh_Hans=y' \
         'CONFIG_PACKAGE_luci-i18n-base-zh-cn=y' \
         'CONFIG_PACKAGE_luci-i18n-mtwifi-cfg-zh-cn=y'; do
  if ! grep -q "^${s}$" .config; then
    fail "缺少基本中文环境：$s（刷完会是英文 LuCI）"
  fi
done
ok "中文环境：LuCI 简体中文 + 基础汉化 + 无线配置汉化"

echo "===== 包集合门禁通过 ====="
# ===== 包集合门禁段 END =====

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
# 不改管理地址：保持 ImmortalWrt 默认 192.168.1.1。


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
