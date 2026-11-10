# ImmortalWrt 5.4 云编译（三机型并行）

GitHub Actions 云编译 ImmortalWrt 21.02 / Linux 5.4 固件。
源码统一使用 fork：[wangwang623/immortalwrt-mt798x](https://github.com/wangwang623/immortalwrt-mt798x)（`openwrt-21.02`，MTK 闭源无线驱动）。

三条编译流各自独立：`build-ax3000t.yml` / `build-wf3000a.yml` / `build-ax6000.yml`。

## 三个并行项目

同类配置项放同一目录，每个目录恰好是三机型三份文件；workflow 只用 `CONFIG_FILE`、`SELF_SCRIPT` 两个变量选自己那一套。

| 类别 | 目录 | 文件 |
|---|---|---|
| 编译配置 | `config/` | `ax3000t.config`、`wf3000a.config`、`ax6000.config` |
| 编译前自检 | `scripts/` | `ax3000t.sh`、`wf3000a.sh`、`ax6000.sh` |
| 编译流 | `.github/workflows/` | `build-*.yml` |

## 三机型

| 机型 | 分区布局（U-Boot Web 选） | U-Boot Web | 固件 LAN |
|---|---|---|---|
| Xiaomi AX3000T（MT7981） | 112m | 192.168.1.1 | **192.168.31.1** |
| KST WF3000A（MT7981） | expand(114m) | 192.168.1.1 | **192.168.31.1** |
| Redmi AX6000（MT7986） | 110m | 192.168.31.1 | **192.168.31.1** |

只编大分区，不编 stock。固件 LAN 统一 `192.168.31.1`、DHCP `2~55`，由三份 `scripts/*.sh` 里逐字相同的地址段改写。U-Boot Web 地址烧在 FIP 里，不受本工程影响——AX3000T / WF3000A 刷完会从 1.1 跳到 31.1，浏览器改到 `http://192.168.31.1` 即可，不是变砖。

## 固件内容

- **闭源无线驱动**全套（这份源码没有开源 mt76，缺一即无 WiFi）
- **系统完整功能**：系统库、内核模块、netfilter/iptables 扩展、系统工具、默认主题
- 第三方插件**只有 `zram-swap`**（含内核绑定的 `kmod-zram` / `kmod-lib-lzo`，事后装不上，必须编进固件）
- **中文环境**：LuCI 中文 + 基础/无线汉化包
- 依赖由 `make defconfig` 自动展开；编译前门禁校验以上四项，并拦截任何其它插件

5.4 的 W25N01GV 是 OOB 64B，与 U-Boot NMBM 签名天然一致，**不要加 6.6 的 oobsize override**。

## 使用

1. Settings → Actions → Workflow permissions 勾 **Read and write**
2. Actions → 选对应 workflow → **Run workflow**（WF3000A / AX6000 的 `source_branch` 默认 `openwrt-21.02`）
3. 产物在 Artifacts / Release，文件名含机型；WF3000A 另有 `initramfs-kernel.bin`

WF3000A 需要 fork 里已覆盖 4 个板级文件（DTS、`mt7981.mk`、`02_network`、`platform.sh`），`scripts/wf3000a.sh` 会逐个校验，缺文件立即 fail。

## 刷机验收

1. **布局对应**：112m / expand(114m) / 110m，刷错布局起不来
2. **地址跳转**：固件 LAN 是 `192.168.31.1`
3. **先验再刷**：WF3000A 先 initramfs 内存启动，确认 `NMBM has been successfully attached` 且无 mismatch，重点验有线网口与 MAC
4. **zram**（可选 64M）：
   ```sh
   uci set system.@system[0].zram_size_mb='64' && uci commit system
   ```

> 未实际执行 `make` / 编译 DTS / 实机验证，最终以在线编译与实机为准。
