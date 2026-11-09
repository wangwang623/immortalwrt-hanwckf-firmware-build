#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本地模拟：验证三条编译流的 config / 包门禁 / 板级自检 / 大分区与无 stock 残留 /
workflow 隔离 / GitHub Actions 的 bash -e 兼容性。
不需要交叉编译工具链，也不需要联网。运行：python3 simulate.py
"""
import os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
REAL_SRC = "/data/workspace/交付/WF3000A-5.4-最终/source-fork"
FORK = "https://github.com/wangwang623/immortalwrt-mt798x.git"
RESULTS = []


def check(cond, label, detail=""):
    RESULTS.append((bool(cond), label, detail))
    print(("[PASS] " if cond else "[FAIL] ") + label + (("  -> " + detail) if detail else ""))


def read(p):
    return open(p, encoding="utf-8").read()


def yaml_load(p):
    try:
        import yaml
        return yaml.safe_load(read(p))
    except Exception as e:
        return {"__error__": str(e)}


def put(base, rel, content):
    p = os.path.join(base, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w", encoding="utf-8").write(content)


WF = {
    "ax3000t": ".github/workflows/build-ax3000t.yml",
    "wf3000a": ".github/workflows/build-wf3000a.yml",
    "ax6000":  ".github/workflows/build-ax6000.yml",
    "uboot":   ".github/workflows/build-u-boot.yml",
}
CFG = {
    "ax3000t": ".config",
    "wf3000a": "config/wf3000a.config",
    "ax6000":  "config/ax6000.config",
}
AFTER = {
    "ax3000t": "_unchanged/after-update-custom.sh",
    "wf3000a": "scripts/after-wf3000a.sh",
    "ax6000":  "scripts/after-ax6000.sh",
}

STUB_MK7986 = """define Device/xiaomi_redmi-router-ax6000
  IMAGE_SIZE := 112640k
endef
TARGET_DEVICES += xiaomi_redmi-router-ax6000

define Device/xiaomi_redmi-router-ax6000-stock
  DEVICE_MODEL := Redmi Router AX6000 (stock layout)
endef
TARGET_DEVICES += xiaomi_redmi-router-ax6000-stock
"""


def make_tree(tree):
    """构造模拟 openwrt 源码树：优先用真实板级文件。"""
    for rel in [
        "target/linux/mediatek/files-5.4/arch/arm64/boot/dts/mediatek/mt7981-kst-wf3000a.dts",
        "target/linux/mediatek/image/mt7981.mk",
        "target/linux/mediatek/mt7981/base-files/etc/board.d/02_network",
        "target/linux/mediatek/mt7981/base-files/lib/upgrade/platform.sh",
    ]:
        src = os.path.join(REAL_SRC, rel)
        if os.path.isfile(src):
            put(tree, rel, read(src))
    put(tree, "target/linux/mediatek/image/mt7986.mk", STUB_MK7986)
    put(tree, "package/base-files/files/bin/config_generate", "lan) ipaddr=192.168.1.1 ;;\n")
    put(tree, "package/network/services/dnsmasq/files/dhcp.conf", "option start '100'\noption limit '150'\n")


def run(script, cwd, shell=None, env_extra=None):
    env = dict(os.environ)
    if env_extra:
        env.update(env_extra)
    argv = list(shell or ["sh"]) + [script]
    return subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True)


def simulate(kind, cfg_text, shell=None):
    """完整模拟 CI 的 Load custom config 步骤。"""
    with tempfile.TemporaryDirectory(prefix="ci-sim-") as tmp:
        tree = os.path.join(tmp, "openwrt")
        os.makedirs(tree)
        make_tree(tree)
        put(tree, ".config", cfg_text)
        r1 = run(os.path.join(ROOT, "scripts/check-packages.sh"), tree, shell,
                 {"GITHUB_WORKSPACE": ROOT})
        r2 = run(os.path.join(ROOT, AFTER[kind]), tree, shell,
                 {"GITHUB_WORKSPACE": ROOT})
        return r1, r2


print("=" * 72)
print("三条编译流 · 统一 fork 源码 + 闭源驱动 + zram-swap + 大分区专用（无 stock）")
print("=" * 72)

# ---------------------------------------------------------------- 1 文件与 workflow
print("\n[1] 文件与 workflow")
for k, rel in WF.items():
    check(os.path.isfile(os.path.join(ROOT, rel)), "存在 " + rel)
for k, rel in CFG.items():
    check(os.path.isfile(os.path.join(ROOT, rel)), "存在 " + rel)
for rel in ["scripts/check-packages.sh", "scripts/after-wf3000a.sh", "scripts/after-ax6000.sh",
            "_unchanged/.config", "_unchanged/after-update-custom.sh",
            "_unchanged/before-update-custom.sh", "README.md", "操作说明.md"]:
    check(os.path.isfile(os.path.join(ROOT, rel)), "存在 " + rel)
check(not os.path.exists(os.path.join(ROOT, ".github/workflows/build-immortalwrt.yml")),
      "交付包内不含旧的 build-immortalwrt.yml")

docs, texts = {}, {}
for k, rel in WF.items():
    p = os.path.join(ROOT, rel)
    d = yaml_load(p)
    docs[k], texts[k] = d, read(p)
    check("__error__" not in d, "YAML 解析 " + k, d.get("__error__", ""))
names = [d.get("name") for d in docs.values() if isinstance(d, dict)]
check(len(set(names)) == 4, "4 个 workflow name 互不相同", str(names))

for k in ("ax3000t", "wf3000a", "ax6000"):
    check(FORK in texts[k], k + " REPO_URL 指向 fork 源码")
    check("scripts/check-packages.sh" in texts[k], k + " 调用包集合门禁")
    check("workflow_dispatch" in texts[k], k + " 支持手动触发")
    check("Mattraks/delete-workflow-runs" not in texts[k] and
          "dev-drprasad/delete-older-releases" not in texts[k],
          k + " 无全仓库清理步骤")
    # 大分区专用：不能有 layout 输入框 / 运行时切换
    check("github.event.inputs.layout" not in texts[k], k + " 无 layout 输入引用")
    check("select layout" not in texts[k], k + " 无 layout 切换步骤")
    check("-stock=y" in texts[k], k + " defconfig 后会拦截 stock 机型")
check("layout:" not in texts["ax6000"], "AX6000 无 layout 输入框定义")
check("REPO_URL: https://github.com/hanwckf/immortalwrt-mt798x.git" not in texts["ax3000t"],
      "AX3000T 不再引用上游 hanwckf 源码")
for k, pre in [("ax3000t", "AX3000T_"), ("wf3000a", "WF3000A_"), ("ax6000", "AX6000_110m_")]:
    check(("release_tag=" + pre) in texts[k], k + " Release tag 带机型/布局前缀")
for k, key in [("ax3000t", "ax3000t"), ("wf3000a", "wf3000a"), ("ax6000", "ax6000")]:
    check(("openwrt-" + key + "-") in texts[k], k + " cache key 带机型前缀")
check("AX6000_stock_" not in texts["ax6000"], "AX6000 不再产出 stock Release tag")
check("DEVICE_NAME=_redmi-ax6000-110m" in texts["ax6000"], "AX6000 artifact 固定 110m")
check("ls bin/targets/mediatek/mt7986/*redmi-router-ax6000*" in texts["ax6000"],
      "AX6000 有产物校验")
check("grep -q 'stock' &&" not in texts["ax6000"] and "grep -q 'stock' && {" not in texts["ax6000"],
      "AX6000 产物校验无 set -e 短路写法")

# ---------------------------------------------------------------- 2 config 静态
print("\n[2] 三份 config 静态检查（大分区专用 / 无 stock）")
cfgs = {k: read(os.path.join(ROOT, v)) for k, v in CFG.items()}
REQ = ["kmod-mt_wifi", "kmod-warp", "kmod-conninfra", "wifi-dats", "mtwifi-cfg",
       "luci-app-mtwifi-cfg", "kmod-mediatek_hnat", "kmod-zram", "zram-swap"]
BAN = ["luci-app-passwall", "luci-app-ssr-plus", "luci-app-turboacc-mtk",
       "luci-app-upnp", "luci-app-eqos-mtk", "luci-theme-argon",
       "CONFIG_ZRAM_DEF_COMP_LZ4", "kmod-nft-offload", "luci-app-package-manager"]
for k, t in cfgs.items():
    code_lines = [l.strip() for l in t.splitlines() if l.strip() and not l.lstrip().startswith("#")]
    bad = [l for l in code_lines if not re.match(r"^[A-Za-z0-9_.\-]+=.*$", l)]
    check(not bad, k + " config 行格式合法", str(bad[:2]))
    for p in REQ:
        check(("CONFIG_PACKAGE_" + p + "=y") in t, k + " 含 " + p)
    check(not any(any(b in l for b in BAN) for l in code_lines),
          k + " 无第三方插件 / 6.6 专属符号")
    check(len(re.findall(r"^CONFIG_MTK_", t, re.M)) >= 80, k + " 保留完整 MTK 驱动符号块",
          str(len(re.findall(r"^CONFIG_MTK_", t, re.M))))
    check("# CONFIG_MTK_" in t, k + " 保留 is not set 行（防 default y 编译失败）")
    check("CONFIG_PACKAGE_zram-swap=y" in t, k + " 唯一插件 zram-swap 在位")
    check("大分区专用" in t, k + " 注释头标注大分区专用")
    check(not re.search(r"^CONFIG_TARGET_DEVICE_.*-stock=y", t, re.M),
          k + " 不含 stock 机型符号")
    check("layout=stock" not in t, k + " 不含 layout=stock 说明")

check("CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_xiaomi_mi-router-ax3000t=y" in cfgs["ax3000t"] and
      len(re.findall(r"^CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_.*=y", cfgs["ax3000t"], re.M)) == 2,
      "AX3000T 只编 2 个 112m 大分区机型")
check("CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_kst_wf3000a=y" in cfgs["wf3000a"] and
      len(re.findall(r"^CONFIG_TARGET_DEVICE_.*=y", cfgs["wf3000a"], re.M)) == 1,
      "WF3000A 仅 1 个 114m 机型")
check("CONFIG_TARGET_mediatek_mt7986=y" in cfgs["ax6000"] and
      "CONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_xiaomi_redmi-router-ax6000=y" in cfgs["ax6000"],
      "AX6000 平台与 110m 机型正确")
for s in ["CONFIG_MTK_CHIP_MT7981", 'WARP_CHIPSET="mt7981"', 'first_card_name="MT7981"']:
    check(s not in cfgs["ax6000"], "AX6000 未混入 " + s)
check("112640k" in read(os.path.join(ROOT, "scripts/after-ax6000.sh")),
      "AX6000 自检校验 110m 的 IMAGE_SIZE")
check("(-stock)?" not in read(os.path.join(ROOT, "scripts/after-ax6000.sh")),
      "AX6000 自检不再放行 -stock 机型")

# ---------------------------------------------------------------- 3 包门禁正/负例
print("\n[3] scripts/check-packages.sh 门禁正例与负例")
gate = os.path.join(ROOT, "scripts/check-packages.sh")
check(subprocess.run(["sh", "-n", gate], capture_output=True).returncode == 0,
      "check-packages.sh shell 语法")


def gate_run(cfg_text):
    with tempfile.TemporaryDirectory(prefix="gate-") as tmp:
        put(tmp, ".config", cfg_text)
        return run(gate, tmp, env_extra={"GITHUB_WORKSPACE": ROOT})


base = cfgs["wf3000a"]
check(gate_run(base).returncode == 0, "正例：纯净 config 通过")
for label, mutate in [
    ("加入 luci-app-passwall", lambda t: t + "\nCONFIG_PACKAGE_luci-app-passwall=y\n"),
    ("加入 luci-theme-argon", lambda t: t + "\nCONFIG_PACKAGE_luci-theme-argon=y\n"),
    ("加入 htop", lambda t: t + "\nCONFIG_PACKAGE_htop=y\n"),
    ("删除 zram-swap", lambda t: t.replace("CONFIG_PACKAGE_zram-swap=y", "# CONFIG_PACKAGE_zram-swap is not set")),
    ("删除 kmod-mt_wifi", lambda t: t.replace("CONFIG_PACKAGE_kmod-mt_wifi=y", "# CONFIG_PACKAGE_kmod-mt_wifi is not set")),
]:
    r = gate_run(mutate(base))
    check(r.returncode != 0, "负例被拦下：" + label,
          (r.stdout.strip().splitlines() or [""])[-1][:100])

# ---------------------------------------------------------------- 4 CI 流程模拟（sh）
print("\n[4] 模拟 CI 的 Load custom config 步骤（sh）")
for k in ("ax3000t", "wf3000a", "ax6000"):
    r1, r2 = simulate(k, cfgs[k])
    check(r1.returncode == 0, k + " 包门禁执行通过",
          (r1.stdout + r1.stderr).strip().splitlines()[-1][:100] if (r1.stdout + r1.stderr).strip() else "")
    check(r2.returncode == 0, k + " after 自检执行通过",
          (r2.stdout + r2.stderr).strip().splitlines()[-1][:100] if (r2.stdout + r2.stderr).strip() else "")

# ---------------------------------------------------------------- 5 GitHub Actions 的 bash -e
print("\n[5] GitHub Actions 兼容性：bash -e -o pipefail")
E = ["bash", "-e", "-o", "pipefail"]
for k in ("ax3000t", "wf3000a", "ax6000"):
    r1, r2 = simulate(k, cfgs[k], shell=E)
    check(r1.returncode == 0, k + " 包门禁在 bash -e 下通过",
          ((r1.stdout + r1.stderr).strip().splitlines() or [""])[-1][:100])
    check(r2.returncode == 0, k + " after 自检在 bash -e 下通过",
          ((r2.stdout + r2.stderr).strip().splitlines() or [""])[-1][:100])
for rel in ["scripts/after-wf3000a.sh", "scripts/after-ax6000.sh", "scripts/check-packages.sh"]:
    t = read(os.path.join(ROOT, rel))
    body = "\n".join(l for l in t.splitlines() if not l.lstrip().startswith("#"))
    check("&& fail" not in body and "&& exit" not in body,
          rel + " 无 grep&&fail / &&exit 短路写法")

# ---------------------------------------------------------------- 6 负例
print("\n[6] 负例：早期拦下错误配置")
r1, r2 = simulate("ax6000", cfgs["ax6000"] + "\nCONFIG_TARGET_DEVICE_mediatek_mt7986_DEVICE_xiaomi_redmi-router-ax6000-stock=y\n")
check(r2.returncode != 0, "负例：AX6000 混入 stock 机型 → 自检被拦下")
r1, r2 = simulate("ax3000t", cfgs["ax3000t"] + "\nCONFIG_PACKAGE_luci-app-passwall=y\n")
check(r1.returncode != 0, "负例：AX3000T 混入插件 → 编译前被拦下")
r1, r2 = simulate("ax6000", cfgs["ax6000"] + '\nCONFIG_MTK_CHIP_MT7981=y\n')
check(r2.returncode != 0, "负例：AX6000 混入 MT7981 符号 → 自检被拦下")
r1, r2 = simulate("wf3000a", cfgs["wf3000a"].replace(
    "CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_kst_wf3000a=y",
    "CONFIG_TARGET_DEVICE_mediatek_mt7981_DEVICE_newland_nl-wr8103=y"))
check(r2.returncode != 0, "负例：WF3000A 机型符号被换掉 → 自检被拦下")

# ---------------------------------------------------------------- 7 shell 语法与文档
print("\n[7] shell 语法与文档")
for rel in list(AFTER.values()) + ["scripts/after-wf3000a.sh", "scripts/after-ax6000.sh",
                                   "scripts/check-packages.sh"]:
    if rel.endswith(".sh"):
        r = subprocess.run(["sh", "-n", os.path.join(ROOT, rel)], capture_output=True)
        check(r.returncode == 0, "sh -n " + rel, r.stderr.strip()[:100])
readme = read(os.path.join(ROOT, "README.md"))
check("immortalwrt-hanwckf-firmware-build" in readme, "README 指向改名后的仓库")
check("zram-swap" in readme, "README 说明唯一插件")
check("112m" in readme and "114m" in readme and "110m" in readme,
      "README 有三机型布局对照")
check("stock 可选" not in readme and "layout=stock" not in readme,
      "README 不再提供 stock 选项")
ops = read(os.path.join(ROOT, "操作说明.md"))
check("112m / 114m / 110m" in ops, "操作说明写明三机型大分区")

# ---------------------------------------------------------------- 汇总
ok = sum(1 for c, _, _ in RESULTS if c)
total = len(RESULTS)
print("\n" + "=" * 72)
print("结果：%d/%d PASS" % (ok, total))
print("=" * 72)
failed = [(l, d) for c, l, d in RESULTS if not c]
report = ["# 本地模拟验证报告", "",
          "运行方式：`python3 simulate.py`（无需联网、无需交叉工具链）", "",
          "## 结果", "", "**%d/%d PASS**" % (ok, total), "",
          "## 覆盖范围", "",
          "- 4 个 workflow 的 YAML 解析、name 唯一、三流 REPO_URL 统一指向 `wangwang623/immortalwrt-mt798x`",
          "- **三机型大分区专用**：三流无 `layout` 输入框 / 无运行时切换、tag 与 artifact 固定、defconfig 后均拦截 `-stock` 机型",
          "- 三份 config：格式、机型符号（AX3000T 2 / WF3000A 1 / AX6000 1）、闭源驱动 9 包、zram、无第三方插件、MTK 符号块与 `is not set` 行完整、注释头标注大分区专用、无 `-stock` 机型符号",
          "- 包集合门禁 `scripts/check-packages.sh`：正例 + 5 个负例（passwall / argon / htop / 删 zram / 删 kmod-mt_wifi）",
          "- 模拟 CI 的 Load custom config：`sh` 与 **`bash -e -o pipefail`** 双跑，验证 `grep && fail` 短路写法已清除",
          "- 负例：AX6000 混入 stock 机型、AX3000T 混入插件、AX6000 混入 MT7981 符号、WF3000A 机型被换掉，均被早期拦下",
          "- `sh -n` 全部 shell 脚本；README / 操作说明的布局表述核对", "",
          "## 明细", ""]
report += ["- [%s] %s%s" % ("PASS" if c else "FAIL", l, ("  -> " + d) if d else "")
           for c, l, d in RESULTS]
report += ["", "## 边界", "",
           "- 沙盒没有 dtc 与交叉编译工具链，**没有实际跑 make / 编译内核**，最终以在线编译为准。",
           "- 模拟源码树优先使用你已覆盖的真实 4 个板级文件；AX6000 的 mt7986.mk 用等价桩（含 stock 定义，用于确认本工程不依赖它）。",
           "- 门禁在 `make defconfig` 之前执行，检查的是未被依赖展开的『意图清单』。",
           "- `bash -e` 模拟覆盖的是自检脚本本身；workflow 其余 run 步骤未逐段执行。", ""]
open(os.path.join(ROOT, "验证报告.md"), "w", encoding="utf-8").write("\n".join(report))
if failed:
    print("失败项：")
    for l, d in failed:
        print("  -", l, d)
sys.exit(0 if ok == total else 1)
