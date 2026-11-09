# immortalwrt-hanwckf-firmware-build

GitHub Actions 云编译 **ImmortalWrt 21.02 / Linux 5.4** 固件，一个仓库三条独立编译流：

| Workflow | 机型 | 源码 | 分区布局 | 产物 |
|---|---|---|---|---|
| `build-ax3000t.yml` | Xiaomi AX3000T（MT7981） | 同一个 fork | **112m 大分区** | `xiaomi_mi-router-ax3000t*` |
| `build-wf3000a.yml` | KST WF3000A（MT7981） | 同一个 fork | **114m（expand）** | `kst_wf3000a*` |
| `build-ax6000.yml` | Redmi AX6000（MT7986） | 同一个 fork | **110m 大分区** | `xiaomi_redmi-router-ax6000*` |

另有 `build-u-boot.yml`：AX3000T 的 U-Boot 编译流，保持原样。

> **三个机型都只用大分区，不编小米原厂 stock 布局。** 三条流各写死自己的布局，没有 `layout` 输入框，也不会产出 `*-stock-*` 固件；`make defconfig` 前后都有门禁拦截 stock 机型符号。

## 分区布局对照（刷机时必须对应）

| 机型 | 布局名 | 分区大小依据 | U-Boot Web 里选 | 源码依据 |
|---|---|---|---|---|
| AX3000T | 112m | 112 MiB 大分区（`mt7981.mk` 机型定义） | 112m | 5.4 源码的大分区机型 |
| KST WF3000A | expand(114m) | `ubi` 起始 `0x580000`、大小 `0x7200000`（116736k） | **expand(114m)** | 你已覆盖的 `mt7981-kst-wf3000a.dts` |
| Redmi AX6000 | 110m | `IMAGE_SIZE := 112640k` | 110m | 5.4 源码 `mt7986.mk` 的 `xiaomi_redmi-router-ax6000` |

⚠️ 112m / 114m / 110m **不是同一套 mtdparts**，DTS 与 U-Boot 布局必须一一对应，刷错布局照样起不来。

## 这一版的三个统一

1. **源码统一**：三条固件流都 clone `wangwang623/immortalwrt-mt798x` 的 `openwrt-21.02` 分支。
   AX3000T 不再用上游 `hanwckf/immortalwrt-mt798x`——因为你已把 WF3000A 的 4 个板级移植文件覆盖进这个 fork，三条流共用同一份源码才能保证行为一致。
2. **无线统一**：全部使用 **MTK 闭源驱动**（`kmod-mt_wifi` / `kmod-warp` / `kmod-conninfra` / `wifi-dats` / `mtwifi-cfg` / `luci-app-mtwifi-cfg`）+ `kmod-mediatek_hnat`。这份 5.4 源码没有开源 mt76，缺这组包就没有 WiFi。
3. **插件统一**：**第三方插件只有 `zram-swap`**（含必须同编的 `kmod-zram`、`kmod-lib-lzo`）。PassWall / SSR-Plus / OpenClash / TurboACC / UPnP / Argon / eqos / htop / tcpdump / nano / iptables 扩展全家桶全部不编。

`luci-app-mtwifi-cfg` 是闭源驱动配套的无线配置界面，不是第三方插件，必须保留。

## 包集合怎么来的

三份 config 都是「意图清单」，不是全量快照：

- **非包符号块**：逐行取自源码自带 `defconfig/mt7981-ax3000.config`（MT7981）或 `defconfig/mt7986-ax6000.config`（MT7986），**包括全部 `CONFIG_MTK_*` 和 `# CONFIG_X is not set`**。这批驱动符号很多是 `default y`，漏抄会触发 `eeprom.c` 等编译错误。
- **包清单**：参考 `wangwang623/immortalwrt-mt798x-6.6` 的 `defconfig/wf3000a.config`（纯净固件），并去掉 5.4 不存在的包：`kmod-nft-offload`、`wifi-scripts`、`mtk-smp`、`luci-app-package-manager`、`CONFIG_ZRAM_DEF_COMP_LZ4` 等。
- 依赖不手写，`make defconfig` 会沿依赖树自动展开。
- 三份 config 头部统一标注「大分区专用，无 stock 变体」。

`scripts/check-packages.sh` 在每条流 `make defconfig` **之前**执行，强制校验「闭源驱动齐全 + 只有 zram-swap 一个插件」。混入任何被禁包会在几分钟内 fail，不会等两小时编译完才发现固件不对。

## 三条流的差异（只在这些地方）

| | AX3000T | WF3000A | AX6000 |
|---|---|---|---|
| 平台 | mediatek/mt7981 | mediatek/mt7981 | mediatek/mt7986 |
| 机型数 | 2（MT7531 / AN8855，均 112m 大分区） | 1 | 1（110m 大分区） |
| 布局 | 112m | **expand(114m)** | 110m |
| initramfs | 不生成 | **生成**（先内存启动验证） | 不生成 |
| 管理地址 | 192.168.31.1（沿用原编译流） | 192.168.1.1 | 192.168.1.1 |
| Release tag | `AX3000T_*` | `WF3000A_*` | `AX6000_110m_*` |

三条流的 tag、cache key、artifact 名都带机型前缀，互不覆盖；且都不再执行「清理全仓库运行记录 / 旧 Release」的步骤。

## 使用

1. 仓库名改为 `immortalwrt-hanwckf-firmware-build`；Settings → Actions → Workflow permissions 勾 **Read and write**。
2. 按 `操作说明.md` 覆盖文件（**连根目录 `.config` 也要覆盖**）；若旧的 `.github/workflows/build-immortalwrt.yml` 还在，删掉。
3. Actions → 建议顺序：**Build KST WF3000A Firmware**（自检最直接，会检查 fork 的 4 个板级文件）→ **Build Redmi AX6000 Firmware** → **Build AX3000T Firmware**。不要三条同时跑。
4. 产物在 Artifacts / Releases；文件名带机型名即选对机型。

WF3000A / AX6000 的 `source_branch` 输入框用于 fork 分支名不是 `openwrt-21.02` 时填写实际值。AX6000 流**没有 layout 选项**，固定 110m。

## 刷完后设置 zram（可选）

5.4 内核没有 6.6 的 `CONFIG_ZRAM_DEF_COMP_LZ4` choice，`zram-swap` 的容量与算法由 UCI 决定（默认按 `MemTotal/2048`，算法 lzo）。要与 6.6 版 WF3000A 一致的 **64M + LZ4**：

```sh
uci set system.@system[0].zram_size_mb='64'
uci set system.@system[0].zram_comp_algo='lz4'
uci commit system
/etc/init.d/zram-swap restart
zram status        # 或 cat /sys/block/zram0/comp_algorithm
```

> 若内核未带 LZ4 压缩，`comp_algorithm` 里没有 `lz4`，保持默认 lzo 即可，不影响使用。
> `kmod-zram` 与内核 vermagic 强绑定，**已编进固件，不要再 `opkg install zram-swap`**。

## 源码 fork 的前提

WF3000A 需要 `wangwang623/immortalwrt-mt798x` 里已经覆盖这 4 个文件（本仓库不含它们）：

```
target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-kst-wf3000a.dts
target/linux/mediatek/image/mt7981.mk
target/linux/mediatek/mt7981/base-files/etc/board.d/02_network
target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh
```

5.4 的 W25N01GV 定义为 OOB 64B，与 U-Boot 的 NMBM 签名天然相等，**不要加 6.6 那行 `mediatek,bmt-mtd-overridden-oobsize`**；`after-wf3000a.sh` 会把误加判为失败。

## 边界

- 本仓库只做云编译编排，**不含源码**；源码是上面那个 fork。
- 本地 `python3 simulate.py` 可验证 config / 包门禁 / 板级自检 / 大分区与无 stock 残留 / workflow 隔离，但沙盒没有交叉工具链，**没有实际跑 `make`**，最终以在线编译为准。
- WF3000A 的 5.4 DTS 按你确认可用的 6.6 `mt7981b-kst-wf3000a.dts` 硬件定义重写，静态检查通过，有线/无线尚未实机验证。
- 闭源驱动固有行为：LuCI 里 `iwinfo` 不可用，无线状态看 `luci-app-mtwifi-cfg`；无线配置在 `/etc/wireless/mt7981/` 的 `.dat` profile，不是 `/etc/config/wireless`。
