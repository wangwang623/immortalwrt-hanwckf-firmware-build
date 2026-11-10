# ImmortalWrt 5.4 云编译（三机型并行）

GitHub Actions 云编译 ImmortalWrt 21.02 / Linux 5.4 固件，适配三台 MTK Filogic 路由器。
源码统一使用 fork：[wangwang623/immortalwrt-mt798x](https://github.com/wangwang623/immortalwrt-mt798x)（`openwrt-21.02`，**MTK 闭源无线驱动**）。

> 仓库由 `xiaomi-ax3000t-immortalwrt-hanwckf-firmware-build` 改名而来。
> 原来的 AX3000T 编译流完整保留，另外增加 KST WF3000A 与 Redmi AX6000 两条流。

---

## 三个并行项目：按配置项类别分目录，每个目录对应三机型

**相同/相似的配置项放在同一个文件夹，每个文件夹下都是 `ax3000t` / `wf3000a` / `ax6000` 三份文件，一一对应。**
workflow 不持有配置内容，只用两个 env 变量选自己那一套。

| 类别 | 目录 | 三份文件 |
|---|---|---|
| 编译配置（意图清单） | `config/` | `ax3000t.config`、`wf3000a.config`、`ax6000.config` |
| 编译前自检 / 后置脚本 | `scripts/` | `ax3000t.sh`、`wf3000a.sh`、`ax6000.sh` |
| 编译流 | `.github/workflows/` | `build-ax3000t.yml`、`build-wf3000a.yml`、`build-ax6000.yml` |

```yaml
# 每个 workflow 只声明这两个变量
env:
  CONFIG_FILE:  config/<机型>.config
  SELF_SCRIPT:  scripts/<机型>.sh
```

`Load custom config` 步骤用 `cp "$CONFIG_FILE" openwrt/.config`（**不是 `mv`**，配置不会被消耗），然后执行 `"$GITHUB_WORKSPACE/$SELF_SCRIPT"`。

| 项目 | 分区布局 | U-Boot Web 选 | 管理地址 |
|---|---|---|---|
| Xiaomi AX3000T（MT7981） | **112m** | 112m | 192.168.31.1（原设定） |
| KST WF3000A（MT7981） | **expand(114m)** | 114m | 192.168.1.1 |
| Redmi AX6000（MT7986） | **110m** | 110m | 192.168.1.1 |

三机型都只用大分区，**不编小米原厂 stock 布局**。三条流各有独立的 Release tag（`AX3000T_` / `WF3000A_` / `AX6000_110m_`）、cache key 与 artifact 前缀，不会互相覆盖。

### 共用逻辑怎么放

包集合门禁**不再单独占一个文件**，而是内联在三个 `scripts/*.sh` 的头部（`# ===== 包集合门禁段 BEGIN/END =====`）。三份逐字一致，改一处要同步三处——这是「每个目录恰好 3 个机型文件」的代价，换来的是目录干净、项目对称。

`before-update-custom.sh`、`feeds.conf.default`、`LICENSE`、`build-u-boot.yml` 留在仓库根目录：它们是三条流**共用**的基础设施，不是某个机型的配置项，因此不参与按机型分目录。

---

## 固件定位：系统完整功能 + 唯一插件 zram-swap

三份 config 是同一套要求的三个实例：

- **保留原工程的系统本身完整功能**：全部系统库、`kmod-*` 内核模块、netfilter / iptables / ip6tables / ebtables 扩展、
  `ethtool` / `swconfig` / `wireless-tools` / `htop` / `tcpdump` / `ipset` /
  openssh / 系统默认主题 `luci-theme-bootstrap-mod` 等，逐项从原工程 617 行 `.config` 恢复。
  例外：`nano` 在原工程即为 `=n`，按「保持原设定」不动，编辑器由 busybox `vi` 提供。
- **闭源无线驱动齐全**：`kmod-mt_wifi` / `kmod-warp` / `kmod-conninfra` / `wifi-dats` / `mtwifi-cfg` /
  `luci-app-mtwifi-cfg` / `kmod-mediatek_hnat`。这份源码没有开源 mt76，缺一即无 WiFi。
- **第三方插件只有 `zram-swap`**（含必须同编的 `kmod-zram` / `kmod-lib-lzo`）。
  `kmod-zram` 与内核 vermagic 强绑定，事后 `opkg install` 装不上，所以必须编进固件。
- **基本中文环境**：`CONFIG_LUCI_LANG_zh_Hans=y` + `luci-i18n-base-zh-cn` +
  `luci-i18n-mtwifi-cfg-zh-cn`。这四项已列为**编译前硬校验**，任一缺失直接 fail，
  不会产出英文界面的固件。
- **已删除的插件**：PassWall、SSR-Plus、vssr、rclone、TurboACC、UPnP（含 miniupnpd）、
  eqos（含 mtkhqos_util）、Argon 主题，以及它们的汉化包与全部 `INCLUDE_*` 子选项。
- 依赖不手写，`make defconfig` 会沿依赖树自动展开；门禁在编译前拦截白名单外的插件。

> 「非包符号块」（机型 / 平台 / MTK 驱动符号）沿用**已编译成功**的版本，含与 fork 源码匹配的
> `7673 + DEFAULT_FIRMWARE`。不要回退到原工程的 `7672 / mt7981-fw-20240823`，
> 否则会找不到闭源无线固件路径。
>
> AX6000 的非包符号取自源码 `defconfig/mt7986-ax6000.config`（MT7986 专属），
> 不能从 AX3000T 派生 —— 混进 `WARP_CHIPSET="mt7981"` 等符号会把驱动指向错误固件，
> `scripts/ax6000.sh` 会直接拦下。

`scripts/ax3000t.sh` 内含原工程 `after-update-custom.sh` 的 3 行 sed：管理地址 **192.168.31.1**、DHCP `2~55` 保持不变。

---

## 目录结构

```
.github/workflows/
  build-ax3000t.yml      build-wf3000a.yml      build-ax6000.yml
  build-u-boot.yml       原有 U-Boot 流（未改动，不属于三个固件项目）
config/
  ax3000t.config         wf3000a.config         ax6000.config
scripts/
  ax3000t.sh             wf3000a.sh             ax6000.sh
before-update-custom.sh  原工程共用资产，保留在根目录
feeds.conf.default       原工程共用资产，保留在根目录
LICENSE
README.md
```

> 根目录**不再有** `.config`、旧 `scripts/` 的散落副本、`config/*.sh` 或 `check-packages.sh`；
> 旧的 `build-immortalwrt.yml` 应删除。仓库里不应再有 `_unchanged/` 之类存放旧文件的目录，
> 也不应上传本地交付用的 `操作说明.md` / `验证报告.md`（不属于编译工程）。

---

## 使用

1. Settings → Actions → General → Workflow permissions 勾 **Read and write**。
2. Actions 里选择对应 workflow → **Run workflow**：
   - `build-ax3000t.yml`：无输入项，直接跑。
   - `build-wf3000a.yml` / `build-ax6000.yml`：`source_branch` 默认 `openwrt-21.02`；`publish_release=false` 只留 Artifacts。
3. 产物在 Artifacts / Release，文件名含机型：
   ```
   ...-mediatek-mt7981-xiaomi_mi-router-ax3000t-...
   ...-mediatek-mt7981-kst_wf3000a-...
   ...-mediatek-mt7986-xiaomi_redmi-router-ax6000-...
   ```
   WF3000A 还会多产出一个 `initramfs-kernel.bin`。

三条流各设三道编译期门禁（配置存在性与包集合 → `make defconfig` 后机型符号 → 产物文件名），
配置错误会在几分钟内 fail，不会等两小时编译完才发现。

三条流的编译前门禁（`scripts/*.sh` 头部，三份逐字一致）在 `make defconfig` 之前
校验：闭源驱动、zram 三件套、中文环境、无白名单外插件；随后 `scripts/<机型>.sh`
的专属段校验板级文件 / 平台符号 / 大分区。`make defconfig` 后与产物阶段另有两道门禁。

---

## 源码 fork 的依赖

- **AX3000T / AX6000**：5.4 源码原生支持，clone fork 即可。
- **WF3000A**：需要 fork 里已覆盖 4 个板级移植文件（已上传）：
  `mt7981-kst-wf3000a.dts`、`mt7981.mk`、`02_network`、`platform.sh`。
  `scripts/wf3000a.sh` 会在编译前逐个校验，缺文件立即 fail。

**5.4 不需要 oobsize 修复。** 该内核的 W25N01GV 定义为 OOB 64B，与 U-Boot 写进 NMBM 签名的
`spare_size=64` 天然一致；不要加 6.6 的 `mediatek,bmt-mtd-overridden-oobsize`，自检脚本会拦。

---

## ⚠️ 编译成功 ≠ 能正常用

之前三个固件都编译成功，但「能用」还没验证。刷机前请按这个顺序确认：

1. **先 initramfs 内存启动**（WF3000A 有该产物，不写 flash、零风险）：
   确认能进系统、`dmesg | grep -i nmbm` 出现 `NMBM has been successfully attached` 且无 `mismatch`。
2. **确认布局对应**：U-Boot Web 里 112m / expand(114m) / 110m 必须与所刷固件一致，刷错布局起不来。
3. **确认有线与无线**：WF3000A 的 5.4 DTS 是按 6.6 已验证硬件定义重写的，
   静态自检通过但**尚未实机验证有线/无线**；重点看 `ip link`、各 LAN/WAN 口能否拿到 IP、
   `iwpriv ra0` 与校准数据。刷 8103 固件有线不通就是拓扑不同，这一版已改为 3LAN+1WAN。
4. **确认 MAC**：WF3000A 从 `Factory 0x4` 推导 LAN−1 / WAN−2，应与机身标签一致，不要出现随机 MAC。
5. **zram**：5.4 没有 `CONFIG_ZRAM_DEF_COMP_LZ4`，容量/算法由 UCI 决定。
   如需 64M，刷完后设：
   ```sh
   uci set system.@system[0].zram_size_mb='64'
   uci commit system
   ```
6. 有条件接 TTL（115200 8N1），开机日志里 `ubi0 error` / `VFS: Unable to mount root fs` 能一句确诊。

> 边界：沙盒没有交叉工具链与 `dtc`，未实际执行 `make defconfig` / `make` / 编译 DTS，
> 最终以在线编译与实机验证为准。
