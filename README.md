# ImmortalWrt hanwckf · 三机型云编译

GitHub Actions 编译 ImmortalWrt 21.02 / Linux 5.4 固件（MTK 闭源驱动）。

| 机型 | 芯片 | 分区 | U-Boot Web | 固件 LAN |
|---|---|---|---|---|
| Xiaomi AX3000T | MT7981 | 112m | 192.168.1.1 | 192.168.31.1 |
| KST WF3000A | MT7981 | expand(114m) | 192.168.1.1 | 192.168.31.1 |
| Redmi AX6000 | MT7986 | 110m | 192.168.31.1 | 192.168.31.1 |

## 目录

```
config/    ax3000t.config   wf3000a.config   ax6000.config
scripts/   ax3000t.sh       wf3000a.sh       ax6000.sh
.github/workflows/  build-ax3000t.yml  build-wf3000a.yml  build-ax6000.yml
```

三个并行项目：workflow 按机型选 `config/` 与 `scripts/` 里对应的一对文件，共用逻辑三份逐字一致。

## 最小完整功能系统

闭源驱动（MTK 闭源 WiFi + HNAT 硬件加速）、基础系统工具 / 库 / kmod、中文环境、
zram-swap（编译期固化 **64M / lzo**，防内存突增）、Argon 主题。
不编：网速控制 / UPnP / 文件传输 / 代理类；保留 hkint 基线的「网络加速」页。

## 校验规则（固定源码 5.4 / luci 21.02 基线）

| 层级 | 内容 | 处理 |
|---|---|---|
| 硬 | 6 个主包 + 18 个直接依赖包（按源码 Makefile 的 DEPENDS / LUCI_DEPENDS 核对，均已显式 `=y`） | 编译前 + defconfig 后各查一次，缺任一 `[FAIL]` 中止编译 |
| 软 | 只查 3 个主包：`luci-i18n-base-zh-cn` `luci-theme-argon` `kmod-lib-lz4` | 缺项 `[WARN]`，继续编译（可后装） |
| 不校验 | 软项依赖（已在 config 显式 `=y`）、条件依赖 `+IPV6:luci-proto-ipv6`、非包符号 `@BUSYBOX_*`、二层传递依赖、DHCP 值、新增扩展插件 | 不拦 |

- 硬依赖：`kmod-mt_wifi→wifi-dats/kmod-conninfra/kmod-warp`；`kmod-mediatek_hnat→kmod-nf-conntrack`；
  `luci→uhttpd 等 9 项`；`opkg→uclient-fetch/libpthread/libubox`；`zram-swap→kmod-zram`；
  `kmod-lib-lzo→kmod-crypto-acompress`。二层依赖由 `make defconfig` 自动展开。
- 软项依赖 `luci-base / wget / jsonfilter / kmod-crypto-acompress` 显式 `=y`，但校验时不查；
  `kmod-crypto-acompress` 同时是 lzo 的硬依赖，按硬身份校验。
- `kmod-lib-lz4` 编了 LuCI 可选 lz4，没编则回退 lzo；`lz4` 只作软检查。
- 以后加 ssr-plus 等：`config/*.config` 对应行改 `=y`，另验版本兼容与依赖完整；换源码版本须重新核对依赖名。

LAN 统一 `192.168.31.1`；DHCP 池由 `scripts/*.sh` 顶部 `DHCP_START` / `DHCP_LIMIT`
设定（`limit` 是地址个数），属个人习惯、不校验，fork 后随意改不会被拦。

## 编译与刷机

1. 源码 fork `wangwang623/immortalwrt-mt798x` 的 `openwrt-21.02` 分支须已含 WF3000A 的 4 个板级文件（DTS 单 GMAC + VLAN / mt7981.mk / 02_network / platform.sh）。
2. Actions 里分别运行三条 workflow。
3. U-Boot Web 布局必须与固件对应（112m / expand(114m) / 110m）；WF3000A 建议先用 `initramfs-kernel.bin` 验有线网口与 `NMBM has been successfully attached`。
4. 5.4 的 W25N01GV OOB 天然 64B，**不要加** 6.6 的 oobsize override。

```sh
cat /sys/block/zram0/disksize        # 67108864（64M）
cat /sys/block/zram0/comp_algorithm  # 默认 [lzo]；编了 lz4 则列表里也会出现 lz4
swconfig dev switch0 show            # WF3000A：VLAN1=0/1/2+6t，VLAN2=3+6t
```
