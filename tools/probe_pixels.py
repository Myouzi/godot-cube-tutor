#!/usr/bin/env python3
"""像素级渲染核验:采样截图 PNG 中各贴纸投影点的颜色,与游戏内导出的预期
albedo 比对(6 色最近余弦分类 + 多数投票)。比对对象为 6n² 个贴纸中朝向
相机的可见子集(由 tests/sticker_probe.gd 导出)。
用法: python3 tools/probe_pixels.py [--n N]   # N 缺省 3
  n=3: out/shot_alg_final.png      + out/sticker_probe.json
  n=4: out/sticker_probe_n4.png    + out/sticker_probe_n4.json
退出码:全匹配 0;任何失配/无探针非 0。全匹配时打印含 "MATCH 100%" 的行。
"""
import argparse
import json
import sys

from PIL import Image

# cube.gd FACES 表的 6 色 albedo(线性 RGB 近似 sRGB 直用)
FACES = {
    "U白": (0.95, 0.95, 0.95),
    "R红": (0.85, 0.12, 0.12),
    "F绿": (0.10, 0.70, 0.25),
    "D黄": (0.95, 0.85, 0.10),
    "L橙": (0.95, 0.50, 0.05),
    "B蓝": (0.15, 0.35, 0.90),
}


def classify(px):
    """像素 RGB(0-255) -> 6 色中余弦最近者 + 分数"""
    r, g, b = px[0] / 255.0, px[1] / 255.0, px[2] / 255.0
    n = (r * r + g * g + b * b) ** 0.5
    if n < 1e-6:
        return None, 0.0
    best, score = None, -1.0
    for name, (ar, ag, ab) in FACES.items():
        an = (ar * ar + ag * ag + ab * ab) ** 0.5
        cos = (r * ar + g * ag + b * ab) / (n * an)
        if cos > score:
            best, score = name, cos
    return best, score


def sample_median(img, x, y, r=1):
    """(x,y) 周边 (2r+1)^2 像素的中位 RGB,抗高光/抗锯齿"""
    pxs = []
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            pxs.append(img.getpixel((x + dx, y + dy)))
    chans = list(zip(*pxs))
    return tuple(sorted(c)[len(c) // 2] for c in chans)


def main():
    ap = argparse.ArgumentParser(description="贴纸投影像素比对(可见子集,6n² 口径)")
    ap.add_argument("--n", type=int, default=3, help="魔方阶数(缺省 3,决定读取的产物)")
    n = ap.parse_args().n
    if n < 2:
        print(f"FAIL  --n={n} 非法(须 >=2)")
        return 1
    shot = "out/shot_alg_final.png" if n == 3 else f"out/sticker_probe_n{n}.png"
    probe = "out/sticker_probe.json" if n == 3 else f"out/sticker_probe_n{n}.json"
    img = Image.open(shot).convert("RGB")
    with open(probe) as f:
        probes = json.load(f)
    offsets = [(0, 0), (-9, 0), (9, 0), (0, -9), (0, 9)]
    match = 0
    mismatch = []
    for p in probes:
        x, y = int(round(p["x"])), int(round(p["y"]))
        if not (2 <= x < img.width - 2 and 2 <= y < img.height - 2):
            mismatch.append((p, None, None, "越界"))
            continue
        expect, _ = classify((p["r"] * 255, p["g"] * 255, p["b"] * 255))
        votes = {}
        for dx, dy in offsets:
            if not (2 <= x + dx < img.width - 2 and 2 <= y + dy < img.height - 2):
                continue
            name, score = classify(sample_median(img, x + dx, y + dy))
            if name:
                votes[name] = votes.get(name, 0) + 1
        got = max(votes, key=votes.get) if votes else None
        if got == expect:
            match += 1
        else:
            center = sample_median(img, x, y)
            mismatch.append((p, expect, got, f"像素{center} 票{votes}"))
    total = len(probes)
    print(f"n={n}(总贴纸 {6 * n * n})截图 {shot}:可见投影 {total} 个,"
          f"颜色匹配 {match},不匹配 {len(mismatch)}")
    for p, exp, got, why in mismatch:
        print(f"  MISMATCH @({p['x']:.0f},{p['y']:.0f}) 格{p['gp']} 法线{p['n']}: "
              f"预期{exp} 实判{got} [{why}]")
    rate = match / total if total else 0.0
    print(f"匹配率 {rate:.1%}")
    if total > 0 and match == total:
        print("MATCH 100%")
        return 0
    print(f"FAILED  匹配率 {rate:.1%} != 100%(探针 {total})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
