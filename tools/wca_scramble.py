#!/usr/bin/env python3
"""WCA 均匀打乱序列生成器(A-4,游戏侧 UI 打乱按钮用,由 main.gd 经 python3 子进程调用)。

与 MCP 桥 cube_scramble_wca 同源:复用 tools/mcp_bridge.py 的
generate_wca_scramble(随机合法状态 → kociemba.solve → 解取逆,单一实现源)。
stdout 输出一行 JSON(游戏侧解析):
  成功 {"ok": true, "alg": "...", "moves": N, "solution": "...", "state_facelets": "..."}
  失败 {"ok": false, "error": "..."} 且 exit 1(游戏侧据此降级随机步)。
诊断信息走 stderr,保证 stdout 纯 JSON。
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcp_bridge as mb


def main():
    try:
        alg, sol, target = mb.generate_wca_scramble()
    except RuntimeError as e:
        print("kociemba 未安装: %s" % e, file=sys.stderr)
        print(json.dumps({"ok": False, "error": "kociemba 未安装(%s)" % e}, ensure_ascii=False))
        return 1
    except ValueError as e:
        print("kociemba 求解失败: %s" % e, file=sys.stderr)
        print(json.dumps(
            {"ok": False, "error": "kociemba 无法求解生成的打乱状态: %s" % e}, ensure_ascii=False))
        return 1
    print(json.dumps({"ok": True, "alg": alg, "moves": len(alg.split()),
                      "solution": sol, "state_facelets": target}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
