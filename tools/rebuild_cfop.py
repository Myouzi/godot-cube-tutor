#!/usr/bin/env python3
"""重建 data/cfop.json:从 speedsolving.com wiki 重收集 CFOP 公式(A-2 备选,2026-09-25)。

背景:原 cfop.json 打包自 lukejacksonn/cube 的 algorithms.ts,该仓库无 LICENSE 文件,
仅 README 文字声明 MIT,许可存在不确定性。公式序列本身是社区公共知识(操作事实),
不受版权保护;受保护的是编排与呈现。本脚本从社区权威来源(speedsolving wiki)逐条
重新收集公式,以本项目自有结构输出,彻底消除对上游编排的依赖。

数据源(MediaWiki api.php?action=parse&prop=wikitext,算法为 wiki 社区维护的公共算法表):
  - OLL 1..57:OLL 页本体 + Template:OCLL(OCLL 1..8 即 OLL 21..27 等,标题直接为 OLL 编号)
  - F2L 1..41:First Two Layers 页(F2L 重定向至此)
  - PLL 21 个:PLL 页本体(==X Permutation== 节)+ 7 个子模板(Aa/Ab/E/H/Ua/Ub/Z)

记号转换(目标记号集 = main.gd _cfop_steps 支持集):
  - (seq)     → seq          (纯分组/Pre-AUF 括号,剥除后顺序执行)
  - (seq)2/3  → seq seq [seq](重复展开;X3 ≡ X' 的三连转语义由引擎处理,此处只展开括号重复)
  - (seq)'    → 逆序取逆
  - Rw/Lw/... → r/l/...      (宽转双记号归一为小写形式)
  - 括号嵌套按最内层循环展开
  - 含不支持记号的整条 alg 丢弃(如 2R 内层);每 case 须至少剩 1 条,否则报错退出

输出结构兼容原文件:{f2l:[41], oll:[57], pll:[21]},字段 name/case/algs/group
(main.gd 消费 algs[0]/name/group;probability 为上游遗留字段,非消费方,重录不带)。

用法:python3 tools/rebuild_cfop.py [--out data/cfop.json] [--cache-dir /tmp/sswiki]
"""

import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://www.speedsolving.com/wiki/api.php"

PLL_SUBTEMPLATES = {  # 子模板 → 标准 PLL 名
    "A-PLL(a)": "Aa", "A-PLL(b)": "Ab", "E-PLL": "E", "H-PLL": "H",
    "U-PLL(a)": "Ua", "U-PLL(b)": "Ub", "Z-PLL": "Z",
}
PLL_MAIN = ["F", "Ga", "Gb", "Gc", "Gd", "Ja", "Jb", "Na", "Nb", "Ra", "Rb", "T", "V", "Y"]

TOKEN_RE = re.compile(r"^[UDLRFBudlrfbMESxyz][23']*$")
WIDE_RE = re.compile(r"\b([RLUDFB])w([2']*)\b", re.IGNORECASE)
GROUP_REPEAT_RE = re.compile(r"\(([^()]+)\)(\d*)('{0,1})")


def fetch_wikitext(page: str, cache_dir: Path) -> str:
    cache = cache_dir / (re.sub(r"[^A-Za-z0-9]", "_", page) + ".txt")
    if cache.exists():
        return cache.read_text()
    url = f"{API}?action=parse&page={urllib.parse.quote(page)}&format=json&prop=wikitext"
    req = urllib.request.Request(url, headers={"User-Agent": "godot-cube-tutor-rebuild/1.0"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.load(resp)
    wt = data["parse"]["wikitext"]["*"]
    cache.write_text(wt)
    return wt


def invert_seq(tokens: list[str]) -> list[str]:
    out = []
    for t in reversed(tokens):
        if t.endswith("'"):
            out.append(t[:-1])
        elif t.endswith("2"):
            out.append(t)  # 180° 自逆
        else:
            out.append(t + "'")
    return out


def convert_alg(raw: str) -> str | None:
    """wiki 记号 → 引擎支持集;不可表达返回 None。"""
    s = raw.strip()
    s = WIDE_RE.sub(lambda m: m.group(1).lower() + m.group(2), s)
    while True:
        m = GROUP_REPEAT_RE.search(s)
        if m is None:
            break
        inner = m.group(1).split()
        rep = m.group(2)
        prim = m.group(3) == "'"
        if prim:
            body = invert_seq(inner)
        else:
            body = inner * (int(rep) if rep else 1)
        s = s[: m.start()] + " ".join(body) + " " + s[m.end():]
        s = re.sub(r"\s+", " ", s).strip()
    # 括号应已全部展开;残留括号 = 嵌套异常,丢弃
    if "(" in s or ")" in s:
        return None
    tokens = s.split()
    if not tokens:
        return None
    norm = []
    for t in tokens:
        if not TOKEN_RE.match(t):
            return None
        if t.endswith("3"):  # X3 ≡ X'(三连转归一为标准撇记号,WCA 无 X3 记法)
            t = t[:-1] + "'"
        norm.append(t)
    return " ".join(norm)


def parse_cases(wikitext: str, heading_re: re.Pattern, name_group: int = 1) -> dict[str, dict]:
    """按标题分段提取 {case_name: {names:[], algs:[], group:[]}}。"""
    cases: dict[str, dict] = {}
    cur = None
    section = ""
    for line in wikitext.splitlines():
        sec = re.match(r"^==([^=\s].*?)==\s*$", line)
        if sec and not line.startswith("==="):
            section = sec.group(1).strip()
        hm = heading_re.match(line)
        if hm:
            cur = hm.group(name_group)
            cases.setdefault(cur, {"names": [], "algs": [], "groups": []})
        cm = re.match(r"^\|\s*name\s*=\s*(.+)", line)
        if cm and cur:
            cases[cur]["names"].append(cm.group(1).strip())
        am = re.match(r"^\{\{Alg\|([^|}]+)", line)
        if am and cur:
            cases[cur]["algs"].append(am.group(1).strip())
            cases[cur]["groups"].append(section)
    return cases


def build_entry(category: str, name, wiki: dict) -> tuple[dict, list[str]] | None:
    """组装一条 case;返回 (entry, 丢弃明细) 或 None(全部 alg 不可用)。"""
    algs, dropped = [], []
    for raw in wiki["algs"]:
        conv = convert_alg(raw)
        if conv is None:
            dropped.append(raw)
        elif conv not in algs:
            algs.append(conv)
    if not algs:
        return None
    display = wiki["names"][0].split(",")[0].strip() if wiki["names"] else str(name)
    group = wiki["groups"][0] if wiki["groups"] else category.upper()
    return ({"name": name, "case": f"{category}-{name}", "algs": algs,
             "group": re.sub(r"\s+", " ", group)}, dropped)


def main() -> int:
    out_path = Path(sys.argv[sys.argv.index("--out") + 1]) if "--out" in sys.argv \
        else Path(__file__).resolve().parent.parent / "data" / "cfop.json"
    cache_dir = Path(sys.argv[sys.argv.index("--cache-dir") + 1]) if "--cache-dir" in sys.argv \
        else Path("/tmp/sswiki")
    cache_dir.mkdir(parents=True, exist_ok=True)

    oll_wt = fetch_wikitext("OLL", cache_dir) + "\n" + fetch_wikitext("Template:OCLL", cache_dir)
    f2l_wt = fetch_wikitext("First Two Layers", cache_dir)
    pll_wt = fetch_wikitext("PLL", cache_dir) + "\n" + "\n".join(
        fetch_wikitext(f"Template:{t}", cache_dir) for t in PLL_SUBTEMPLATES)

    oll_cases = parse_cases(oll_wt, re.compile(r"^===\s*OLL\s*(\d+)\s*===\s*$"))
    f2l_cases = parse_cases(f2l_wt, re.compile(r"^===\s*F2L\s*(\d+)\s*===\s*$"))
    # wiki F2L 编号 1..42,其中 37 号标 "Solved"(无 alg,非训练 case)→ 跳过;保留 wiki
    # 原编号(缺 37、最大 42)以便与 wiki 对照,总数仍 41。原 lukejacksonn 数据为 1..41
    # 连续编号,两套编号体系不同,图案分布随之不同(重录旨在此,README 已说明)。
    f2l_cases = {k: v for k, v in f2l_cases.items() if v["algs"]}
    # PLL:主页面 "==X Permutation==" 节 + 子模板内同名节(A-PLL(a) 内标题即 "Aa Permutation"),
    # 两处来源的 key 都是标准 PLL 名,同名合并
    pll_cases = parse_cases(pll_wt, re.compile(r"^==\s*(.+?)\s+Permutation\s*==\s*$"))

    result: dict[str, list] = {"f2l": [], "oll": [], "pll": []}
    dropped_log: list[str] = []
    for cat, cases, key_fn in [
        ("f2l", f2l_cases, lambda k: int(k)),
        ("oll", oll_cases, lambda k: int(k)),
        ("pll", pll_cases, lambda k: k),
    ]:
        for key in sorted(cases, key=key_fn):
            built = build_entry(cat, key_fn(key), cases[key])
            if built is None:
                print(f"FATAL {cat}/{key}: 全部 alg 记号不可转换", file=sys.stderr)
                return 1
            entry, dropped = built
            result[cat].append(entry)
            dropped_log += [f"{cat}/{key}: {d}" for d in dropped]

    expect = {"f2l": 41, "oll": 57, "pll": 21}
    for cat, n in expect.items():
        if len(result[cat]) != n:
            got = {c["name"] for c in result[cat]}
            want = set(range(1, n + 1)) if cat != "pll" else \
                set(PLL_SUBTEMPLATES.values()) | set(PLL_MAIN)
            print(f"FATAL {cat}: 期望 {n} case,实得 {len(result[cat])};缺:{sorted(want - got)}",
                  file=sys.stderr)
            return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n")
    total_algs = sum(len(c["algs"]) for cat in result for c in result[cat])
    print(f"OK {out_path}: f2l 41 / oll 57 / pll 21,共 {total_algs} 条公式"
          f"(丢弃不可转换 {len(dropped_log)} 条)")
    for d in dropped_log[:10]:
        print("  drop:", d)
    if len(dropped_log) > 10:
        print(f"  ... 共 {len(dropped_log)} 条")
    return 0


if __name__ == "__main__":
    sys.exit(main())
