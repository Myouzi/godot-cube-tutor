#!/usr/bin/env python3
"""Minkwitz 离线词表管线(v7.4 D1 commit 2,impl-plan §3.2)。

把 SS 表「构建期 GDScript 现算」换成「离线预计算 + 运行期查盘」:
逐阶(n=4..7)构建 Minkwitz 截断链词表 → 质量门全过才出 bin → res://resources/minkwitz/n{N}.bin。

算法血统:移植 /tmp/minkwitz_spike.py 的截断版 fb_build(与引擎 _fb_build
nxn_solver.gd:3454-3596 同构:transversal BFS + Schreier 候选短链优选截断;
rng.shuffle 后稳定排序 = 候选随机 tie-break 的 seed 钩子)。阶段0实验A已证:
orbit 版坏表、v3 完整 SS 集合爆炸死路线,均不采用;gens 只消费引擎导出域
(tests/fixtures/minkwitz_gens.json,commit 1 产物),不自行模拟层转(impl-plan §3.5)。

参数固化(阶段0实测锚定,details 见 docs/next-round-stage0.md §2.2):
  cap 按阶 n4=512 n5=512 n6=1024 n7=2048;seed 扫描序列见 SEED_SCAN(None=默认序)。
  锚定:n5 默认序@512 9/9;n6 默认序@1024 15/15(seed33@512 亦通);n7 默认序@2048
  15/15(seed1@2048 亦通;seed33@2048 仅 8/15 不可用;cap1024 对 n7 未测)。
  n4 无锚定(B0 无 n4 中心卡点),512 起步由质量门兜底。

质量门(每阶全过才出 bin,不过换 seed 重扫,分钟级/轮):
  G1 50σ 自检(复刻 _fb_selfcheck nxn_solver.gd:3424-3451:gen 随机积 8 步,seed=42042+n)
  G2 200σ 随机验收(scramble(40) 同构,seed=20260929)要求 100%
  G3 词长 P100(=max) < 2000(CN_FB_MAX_TOKENS 门)
  G4 B0 卡点态直测(sigma_fixed 主口径,tests/fixtures/stage0_sigma.json,该阶全过)
  G5 9 seed 卡点态直测(sigma_fixed,tests/fixtures/d1_keylock_sigma.json,该阶全过)
注意 G1-G5 是统计验收非数学完备证明(impl-plan §3.2):个别态落覆盖缺口由
运行期 fail loud 兜底(查表 miss 即回退),不静默。

bin 布局(MKW1,读端=commit 3 的 _fb_load):
  magic "MKW1" | version u8=1 | n u8 | domain_hash u32LE(djb2,同 fixture 算法) |
  m u16LE | gen_count u16LE | per gen: alg_len u8 + alg utf8 + tokens u8 |
  level_count u16LE | per level: entry_count u16LE | per entry:
  point u16LE + flat_len u16LE + flat gen下标 LEB128 ×flat_len
  perm 不存(加载端由 alg 重算,alg 是唯一真源);trans 的 perm/iperm、levels[i].s、
  库原子均不落盘——运行期消费端(_cn_fallback/_fb_selfcheck)只用 trans[p].flat
  与 .perm,flat→perm 加载端重算(reversed 顺序复合),gen_inv/orbit 加载端重建。

同名字典正逆坑(EXPERIENCE.md:28):词链 flat 是 gen 下标序列,正逆并存——
  sifting 消费方向=trans[p].flat 直接拼接;复原方向=读端按 gen_inv 求逆链。
  本管线构建与 spike/引擎同款(flat=inv(vflat)+gflat+uflat,前插语义),
  两端口径以 fixture meta.perm_semantics 为准。

用法(复跑):
  python3 tools/minkwitz_build.py             # 全阶 n=4..7
  python3 tools/minkwitz_build.py --only-n 7  # 单阶
  python3 tools/minkwitz_build.py --seeds "0,1,33"  # 覆盖扫描序列(0=默认序)
"""
import json
import random
import struct
import sys
import time
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GENS_FIX = ROOT / "tests/fixtures/minkwitz_gens.json"
B0_FIX = ROOT / "tests/fixtures/stage0_sigma.json"
KEYLOCK_FIX = ROOT / "tests/fixtures/d1_keylock_sigma.json"
OUT_DIR = ROOT / "resources/minkwitz"

CAPS = {4: 512, 5: 512, 6: 1024, 7: 2048}
SEED_SCAN = [None, 1, 33, 42, 7, 99, 2026]  # None=默认序(确定性,引擎 _fb_build 同款)
MAX_TOKENS = 2000  # CN_FB_MAX_TOKENS 同款
NTRIAL_RANDOM = 200
NTRIAL_SELFCHECK = 50


# ---------- 域哈希(与 tests/_probe_d1_export_gens.gd _domain_hash 同款) ----------
def domain_hash(n, gens_with_alg):
    canon = "n=%d;" % n
    for g in gens_with_alg:
        canon += "%s:%s;" % (g["alg"], ",".join(str(x) for x in g["perm"]))
    h = 5381
    for ch in canon:
        h = (h * 33 + ord(ch)) & 0x7FFFFFFF
    return h


# ---------- 置换工具(pull 语义:new[j]=old[perm[j]],同引擎 _cn_apply) ----------
def comp(a, b):
    return [a[b[j]] for j in range(len(a))]


def inv(p):
    out = [0] * len(p)
    for j in range(len(p)):
        out[p[j]] = j
    return out


def pid(m):
    return list(range(m))


# ---------- SS 截断链(spike fb_build 移植,与引擎 _fb_build 同构) ----------
def fb_build(m, gens, cap, rng=None):
    """gens: perm 列表(已去重,层转全集互逆必在内)。rng=None=默认序。
    返回 {"levels": [{"trans": {点: (flat, perm)}}], "gens": glist, "gen_inv": [...], "m": m}"""
    glist = [list(g) for g in gens]
    idx_of = {bytes(gp): i for i, gp in enumerate(glist)}
    gen_inv = []
    while len(gen_inv) < len(glist):
        gi = len(gen_inv)
        iv = inv(glist[gi])
        ki = bytes(iv)
        if ki not in idx_of:
            idx_of[ki] = len(glist)
            glist.append(iv)
        gen_inv.append(idx_of[ki])
    levels = []
    s_cur = [((gi,), glist[gi]) for gi in range(len(glist))]
    for i in range(m):
        trans = {i: ((), pid(m))}
        queue = deque([i])
        while queue:
            x = queue.popleft()
            pre_flat, pre_perm = trans[x]
            for (sflat, sperm) in s_cur:
                y = sperm[x]
                if y in trans:
                    continue
                trans[y] = (tuple(sflat) + tuple(pre_flat), comp(sperm, pre_perm))
                queue.append(y)
        levels.append({"trans": trans})
        if i == m - 1 or not s_cur:
            break
        # Schreier 候选 → 随机 tie-break → 短链优选截断 cap
        seen2 = set()
        cands2 = []
        for p, (uflat, uperm) in trans.items():
            for (gflat, gperm) in s_cur:
                mid = gperm[p]
                if mid not in trans:
                    continue
                vflat, vperm = trans[mid]
                w = comp(inv(vperm), comp(gperm, uperm))
                if w[i] != i:
                    continue
                kb = bytes(w)
                if kb in seen2:
                    continue
                seen2.add(kb)
                cands2.append((len(vflat) + len(gflat) + len(uflat), kb, w, vflat, gflat, uflat))
        if rng is not None:
            rng.shuffle(cands2)
        cands2.sort(key=lambda c: c[0])
        s_next = []
        for (ln, kb, w, vflat, gflat, uflat) in cands2:
            if len(s_next) >= cap:
                break
            fl2 = tuple(gen_inv[x] for x in reversed(vflat)) + tuple(gflat) + tuple(uflat)
            s_next.append((fl2, w))
        s_cur = s_next
    return {"levels": levels, "gens": glist, "gen_inv": gen_inv, "m": m}


# ---------- sifting(诊断版:ok/词长/失败级,消费方向 p=sigma[i],nxn_solver.gd:3821 同款) ----------
def sift(fb, sigma):
    m = fb["m"]
    inv_u_cache = {}
    s = inv(sigma)
    total = 0
    for i in range(len(fb["levels"])):
        p = s[i]
        if p == i:
            continue
        ent = fb["levels"][i]["trans"].get(p)
        if ent is None:
            return False, total, i
        uflat, uperm = ent
        iu = inv_u_cache.get(i)
        if iu is None:
            iu = inv(uperm)
            inv_u_cache[i] = iu
        s = [iu[s[j]] for j in range(m)]
        total += len(uflat)
    return s == pid(m), total, -1


def flat_perm(flat, glist, m):
    """flat→perm 加载端重算口径(与 bin 读端一致):acc=id; for gi in reversed(flat): acc=g∘acc"""
    acc = pid(m)
    for gi in reversed(flat):
        acc = comp(glist[gi], acc)
    return acc


# ---------- 质量门 ----------
def quality_gate(fb, n, stuck, keylock, verbose=True):
    """返回 (pass: bool, report: str, word_lens: list)。G1-G5 逐项统计。"""
    glist = fb["gens"]
    m = fb["m"]
    lines = []
    ok_all = True
    # G1: 50σ 自检(gen 随机积 8 步,seed=42042+n,同 _fb_selfcheck)
    rng = random.Random(42042 + n)
    ok1 = 0
    for _ in range(NTRIAL_SELFCHECK):
        sig = pid(m)
        for _ in range(8):
            sig = comp(glist[rng.randrange(len(glist))], sig)
        o, _, _ = sift(fb, sig)
        ok1 += o
    ok1 = ok1 == NTRIAL_SELFCHECK
    ok_all &= ok1
    lines.append("G1 自检50σ(8步): %s" % ("PASS" if ok1 else "FAIL"))
    # G2: 200σ 随机验收(40 步 scramble(40) 同构,seed=20260929)
    rng = random.Random(20260929)
    ok2 = 0
    lens2 = []
    for t in range(NTRIAL_RANDOM):
        sig = pid(m)
        for _ in range(40):
            sig = comp(glist[rng.randrange(len(glist))], sig)
        o, L, fl = sift(fb, sig)
        ok2 += o
        if o:
            lens2.append(L)
        elif verbose:
            cov = len(fb["levels"][fl]["trans"]) if 0 <= fl < len(fb["levels"]) else -1
            lines.append("  随机σ miss t%d @L%s(trans %s/%d)" % (t, fl, cov, m))
    g2 = ok2 == NTRIAL_RANDOM
    ok_all &= g2
    lines.append("G2 随机200σ(40步): %d/%d %s" % (ok2, NTRIAL_RANDOM, "PASS" if g2 else "FAIL"))
    # G3: 词长 P100(max) < 2000(含 G2 词长与卡点态词长)
    # G4: B0 卡点态直测(sigma_fixed)
    ok4 = 0
    lens4 = []
    for s in stuck:
        o, L, fl = sift(fb, list(s["sigma_fixed"]))
        ok4 += o
        if o:
            lens4.append(L)
        elif verbose:
            cov = len(fb["levels"][fl]["trans"]) if 0 <= fl < len(fb["levels"]) else -1
            lines.append("  B0 miss n=%d t%s @L%s(trans %s/%d)" % (n, s["trial"], fl, cov, m))
    g4 = ok4 == len(stuck)
    ok_all &= g4
    lines.append("G4 B0卡点态(sigma_fixed): %d/%d %s" % (ok4, len(stuck), "PASS" if g4 else "FAIL"))
    # G5: 9 seed 卡点态直测(sigma_fixed)
    ok5 = 0
    lens5 = []
    for s in keylock:
        o, L, fl = sift(fb, list(s["sigma_fixed"]))
        ok5 += o
        if o:
            lens5.append(L)
        elif verbose:
            cov = len(fb["levels"][fl]["trans"]) if 0 <= fl < len(fb["levels"]) else -1
            lines.append("  keylock miss n=%d seed%s @L%s(trans %s/%d)" % (n, s["seed"], fl, cov, m))
    g5 = ok5 == len(keylock)
    ok_all &= g5
    lines.append("G5 9seed卡点态(sigma_fixed): %d/%d %s" % (ok5, len(keylock), "PASS" if g5 else "FAIL"))
    # G3: 词长门(全部来源合并取 max=P100)
    all_lens = lens2 + lens4 + lens5
    p100 = max(all_lens) if all_lens else -1
    g3 = p100 < MAX_TOKENS
    ok_all &= g3
    lines.append("G3 词长P100: %d < %d %s (avg=%.0f n=%d)" % (
        p100, MAX_TOKENS, "PASS" if g3 else "FAIL",
        (sum(all_lens) / len(all_lens)) if all_lens else -1, len(all_lens)))
    return ok_all, "\n".join(lines), all_lens


# ---------- bin 序列化(MKW1 布局,见模块 docstring) ----------
def write_bin(fb, n, dom_hash, algs, path):
    glist = fb["gens"]
    buf = bytearray()
    buf += b"MKW1"
    buf += struct.pack("<B", 1)        # version
    buf += struct.pack("<B", n)
    buf += struct.pack("<I", dom_hash)
    buf += struct.pack("<H", fb["m"])
    buf += struct.pack("<H", len(glist))
    for gi, gp in enumerate(glist):
        alg = algs[gi]
        ba = alg.encode("utf-8")
        assert len(ba) < 256
        buf += struct.pack("<B", len(ba)) + ba
        buf += struct.pack("<B", 1)    # tokens(层转恒 1)
    buf += struct.pack("<H", len(fb["levels"]))
    for lv in fb["levels"]:
        entries = sorted(lv["trans"].items())
        buf += struct.pack("<H", len(entries))
        for p, (flat, _perm) in entries:
            buf += struct.pack("<H", p)
            buf += struct.pack("<H", len(flat))
            for x in flat:
                while True:
                    b7 = x & 0x7F
                    x >>= 7
                    if x:
                        buf.append(b7 | 0x80)
                    else:
                        buf.append(b7)
                        break
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(buf))
    return len(buf)


def varint_len(x):
    n = 1
    while x >= 128:
        x >>= 7
        n += 1
    return n


# ---------- 主流程 ----------
def build_one(n, gens_json, cap, seed, stuck, keylock):
    gens = [list(g["perm"]) for g in gens_json]
    m = len(gens[0])
    rng = None if seed is None else random.Random(seed)
    t0 = time.time()
    fb = fb_build(m, gens, cap, rng)
    dt = time.time() - t0
    terms = sum(len(lv["trans"]) for lv in fb["levels"])
    nlev = len(fb["levels"])
    full = sum(1 for lv in fb["levels"] if len(lv["trans"]) == m)
    seed_tag = "默认序" if seed is None else "seed%d" % seed
    print("[n=%d] cap=%d %s 建表 %.1fs levels=%d 表项=%d 满覆盖级=%d/%d" % (
        n, cap, seed_tag, dt, nlev, terms, full, nlev))
    ok, rep, lens = quality_gate(fb, n, stuck, keylock)
    print(rep)
    flat_bytes = 0
    for lv in fb["levels"]:
        for (flat, _p) in lv["trans"].values():
            flat_bytes += sum(varint_len(x) for x in flat)
    print("[n=%d] flat字节≈%d (bin 预算 <100KB)" % (n, flat_bytes))
    return fb, ok


def main():
    args = sys.argv[1:]
    only_n = int(args[args.index("--only-n") + 1]) if "--only-n" in args else None
    seeds = SEED_SCAN
    if "--seeds" in args:
        raw = args[args.index("--seeds") + 1]
        seeds = [(None if int(x) == 0 else int(x)) for x in raw.split(",")]
    gd = json.load(open(GENS_FIX))
    b0 = json.load(open(B0_FIX))
    kl = json.load(open(KEYLOCK_FIX))
    stuck_by_n = {}
    for s in b0["stuck_states"]:
        stuck_by_n.setdefault(s["n"], []).append(s)
    kl_by_n = {}
    for s in kl["keylock_states"]:
        kl_by_n.setdefault(s["n"], []).append(s)

    total_bytes = 0
    for n in sorted(CAPS):
        if only_n is not None and n != only_n:
            continue
        gens_json = gd["gens_by_n"][str(n)]
        expect_hash = gd["domain_hash_by_n"][str(n)]
        dh = domain_hash(n, gens_json)
        assert dh == expect_hash, "n=%d 域哈希不一致: %d vs fixture %d" % (n, dh, expect_hash)
        algs = [g["alg"] for g in gens_json]
        stuck = stuck_by_n.get(n, [])
        keylock = kl_by_n.get(n, [])
        cap = CAPS[n]
        fb = None
        ok = False
        for seed in seeds:
            fb, ok = build_one(n, gens_json, cap, seed, stuck, keylock)
            if ok:
                print("[n=%d] 质量门 PASS (%s cap=%d) → 出 bin" % (
                    n, "默认序" if seed is None else "seed%d" % seed, cap))
                break
            print("[n=%d] 质量门 FAIL,换下一 seed 重扫" % n)
        if not ok:
            print("[n=%d] 全 seed 扫描仍 FAIL——按 impl-plan §3.2 换 cap/扩扫描后人工复盘,不出 bin" % n)
            sys.exit(1)
        size = write_bin(fb, n, dh, algs, OUT_DIR / ("n%d.bin" % n))
        total_bytes += size
        print("[n=%d] WROTE %s (%d bytes)" % (n, OUT_DIR / ("n%d.bin" % n), size))
    print("=== 完成,共 %d bytes ===" % total_bytes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
