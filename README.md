# ImmortalWrt hanwckf · 三机型云编译

GitHub Actions 编译 ImmortalWrt 21.02 / Linux 5.4 固件（MTK 闭源驱动）：

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

编译前与 `make defconfig` 后只做**必要包正向校验**（闭源驱动 / zram / 中文 / 基础系统），不检查「不该有哪些包」；以后改 `config/*.config` 增加插件不会被拦。

## 固件内容

- **闭源驱动**：`kmod-mt_wifi` / `kmod-warp` / `kmod-conninfra` / `mtwifi-cfg` / `kmod-mediatek_hnat`，缺一即无 WiFi。
- **完整功能**：hkint 原版 `.config` 的系统工具、库、kmod、netfilter 扩展全部保留；补齐 `luci / opkg / ppp / ca-bundle` 等必要项。
- **中文环境**：`CONFIG_LUCI_LANG_zh_Hans` + `luci-i18n-base-zh-cn` + `luci-i18n-mtwifi-cfg-zh-cn`。
- **插件**：保留 `zram-swap`（内核绑定，默认 64M / lzo）与「网络 → 网络加速」`luci-app-turboacc-mtk`；**不编** 网速控制 / UPnP / 文件传输 / Argon 主题 / PassWall / SSR-Plus / OpenClash 等，config 末尾均有 `is not set` 显式禁用。
- **管理地址**：三机型统一 `192.168.31.1`、DHCP `2~55`；U-Boot Web 地址不变（烧在 FIP 里）。

## 编译与刷机

1. 源码 fork `wangwang623/immortalwrt-mt798x` 的 `openwrt-21.02` 分支须已覆盖 WF3000A 的 4 个板级文件（DTS / mt7981.mk / 02_network / platform.sh）。**本次只需更新 DTS 与 02_network** 为单 GMAC + VLAN 版（`eth0.1`/`eth0.2`、`6t@eth0`、左→右 LAN1/2/3/WAN），mk 与 platform.sh 不动。
2. Actions 里分别运行三条 workflow，WF3000A 的 `source_branch` 填 fork 分支名。
3. U-Boot Web 布局必须与固件对应（112m / expand(114m) / 110m）；WF3000A 建议先用 `initramfs-kernel.bin` 内存启动验有线网口与 `NMBM has been successfully attached`。
4. 5.4 的 W25N01GV OOB 天然 64B，**不要加** 6.6 的 `mediatek,bmt-mtd-overridden-oobsize`。

刷完验收：

```sh
cat /sys/block/zram0/disksize        # 67108864（64M）
cat /sys/block/zram0/comp_algorithm  # [lzo]
swconfig dev switch0 show            # WF3000A：VLAN1=0/1/2+6t，VLAN2=3+6t
```
