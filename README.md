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

三个并行项目：workflow 只按机型选 `config/` 与 `scripts/` 里对应的一对文件，共用逻辑三份逐字一致。

## 当前系统 = 最小完整功能

| 组成 | 内容 |
|---|---|
| 闭源驱动 | `kmod-mt_wifi` / `kmod-warp` / `kmod-conninfra` / `wifi-dats` / `mtwifi-cfg` / `kmod-mediatek_hnat`，缺一即无 WiFi |
| 系统工具 / 库 / kmod | hkint 原版 `.config` 全量保留，补齐 `luci / opkg / ppp / ca-bundle` |
| 中文环境 | `CONFIG_LUCI_LANG_zh_Hans` + `luci-i18n-base-zh-cn` + `luci-i18n-mtwifi-cfg-zh-cn` |
| zram-swap | 内核绑定、事后装不上；编译期固化默认 **64M / lzo**，防内存突发占用；同时编入 `kmod-lib-lz4`，LuCI 里改选 lz4 也能生效 |
| Argon 主题 | `luci-theme-argon` + 依赖 `wget` / `jsonfilter`，首次启动自动设为默认界面 |

另保留 hkint 基线的「网络 → 网络加速」页（turboacc-mtk），不属最小集合、不参与校验。不编：网速控制 / UPnP / 文件传输 / 代理类。三机型固件 LAN 统一 `192.168.31.1`、DHCP `100~249`（`start 100` / `limit 150`，`limit` 为地址个数）。

## 校验规则

- **现在**：编译前 + `make defconfig` 后，只校验上表必要包是否齐全，缺任一即 fail；不检查「不该有哪些包」。
- **以后加扩展插件**（如 ssr-plus）：在 `config/*.config` 把对应行改成 `=y` 即可，门禁不拦。只验三件事——包版本与 5.4 内核 / 闭源驱动兼容、`make defconfig` 后该包及依赖仍为 `=y`、产物无缺失依赖。

## 编译与刷机

1. 源码 fork `wangwang623/immortalwrt-mt798x` 的 `openwrt-21.02` 分支须已含 WF3000A 的 4 个板级文件（DTS 单 GMAC + VLAN / mt7981.mk / 02_network / platform.sh）。
2. Actions 里分别运行三条 workflow。
3. U-Boot Web 布局必须与固件对应（112m / expand(114m) / 110m）；WF3000A 建议先用 `initramfs-kernel.bin` 验有线网口与 `NMBM has been successfully attached`。
4. 5.4 的 W25N01GV OOB 天然 64B，**不要加** 6.6 的 oobsize override。

```sh
cat /sys/block/zram0/disksize        # 67108864（64M）
cat /sys/block/zram0/comp_algorithm  # 列表含 lzo / lz4，[] 为当前算法；默认 [lzo]
swconfig dev switch0 show            # WF3000A：VLAN1=0/1/2+6t，VLAN2=3+6t
```
