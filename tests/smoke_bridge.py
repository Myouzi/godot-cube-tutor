#!/usr/bin/env python3
"""端到端冒烟(PLAN §6/§7.3):godot --headless 跑主场景 → 等 8788 接受 →
spawn tools/mcp_bridge.py → initialize/tools/list → tools/call 全链路。
任何断言失败 exit 1,全过 exit 0。纯标准库。
"""

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE = os.path.join(ROOT, "tools", "mcp_bridge.py")
DEFAULT_PORT = 8788
SOLVED_STR = "U" * 9 + "R" * 9 + "F" * 9 + "D" * 9 + "L" * 9 + "B" * 9
TOKEN_RE = re.compile(r"^[UDLRFB](2|')?$")

# kociemba 为 optional 依赖(§6.3):未装时相关段打 SKIP,其余段照跑,仍 exit 0。
try:
    import kociemba  # noqa: F401
    HAVE_KOCIEMBA = True
except ImportError as e:
    HAVE_KOCIEMBA = False
    KOCIEMBA_SKIP = str(e)


def valid_alg(alg):
    """打乱/解序列合法性:非空且每 token 均为合法 WCA 记号。"""
    toks = alg.split()
    return bool(toks) and all(TOKEN_RE.match(t) for t in toks)


def fail(msg):
    print("FAIL " + msg)
    sys.exit(1)


def ok(msg):
    print("PASS " + msg)


def wait_port(port, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1.0):
                return True
        except OSError:
            time.sleep(0.3)
    return False


class Bridge:
    """冒烟用 stdio MCP 客户端。"""

    def __init__(self, proc):
        self.proc = proc
        self._id = 0

    def call(self, method, params=None):
        self._id += 1
        rid = self._id
        req = {"jsonrpc": "2.0", "id": rid, "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + 60.0
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                fail("bridge stdout 已关闭(method=%s)" % method)
            resp = json.loads(line)
            if resp.get("id") == rid:
                return resp
        fail("bridge 响应超时(method=%s)" % method)

    def notify(self, method, params=None):
        req = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()

    def tool(self, name, arguments=None):
        resp = self.call("tools/call", {"name": name, "arguments": arguments or {}})
        result = resp.get("result")
        if result is None:
            fail("%s -> 无 result: %r" % (name, resp))
        if result.get("isError"):
            fail("%s -> isError: %s" % (name, result.get("content")))
        return json.loads(result["content"][0]["text"])

    def tool_maybe(self, name, arguments=None):
        """返回 (payload, is_error);不因 isError 而 fail(条件化 SKIP 用)。"""
        resp = self.call("tools/call", {"name": name, "arguments": arguments or {}})
        result = resp.get("result")
        if result is None:
            fail("%s -> 无 result: %r" % (name, resp))
        return json.loads(result["content"][0]["text"]), bool(result.get("isError"))


def poll_state(bridge, timeout):
    """轮询 cube_get_state 直至 animating=false 且 queue_len=0。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        st = bridge.tool("cube_get_state")
        if not st["animating"] and st["queue_len"] == 0:
            return st
        time.sleep(0.4)
    fail("轮询 state 超时(动画未结束)")


def parse_port(argv):
    """--port=N 指定隔离端口(缺省 8788):游戏与桥同端口起子进程,
    避让常驻游戏实例/并行测试。"""
    port = DEFAULT_PORT
    for a in argv:
        if a.startswith("--port="):
            port = int(a.split("=", 1)[1])
    return port


def main():
    port = parse_port(sys.argv[1:])
    godot = shutil.which("godot")
    if not godot:
        fail("未找到 godot(PATH)")
    env = dict(os.environ, DISPLAY=":0")
    game = subprocess.Popen(
        [godot, "--headless", "--path", ROOT, "--", "--cube-port=%d" % port],
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    bridge = None
    try:
        if not wait_port(port, 30):
            fail("游戏未在 127.0.0.1:%d 监听(主场景缺 CubeServer?)" % port)
        ok("godot headless 已监听 127.0.0.1:%d" % port)
        time.sleep(1.0)  # 探测连接已断开,等服务端单连接槽释放

        bridge = Bridge(subprocess.Popen(
            [sys.executable, BRIDGE, "--cube-port=%d" % port],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, bufsize=1))

        resp = bridge.call("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "smoke", "version": "0"}})
        ver = resp.get("result", {}).get("protocolVersion")
        if ver != "2024-11-05":
            fail("initialize 未回显 protocolVersion: %r" % ver)
        ok("initialize 回显 protocolVersion=%s" % ver)
        bridge.notify("notifications/initialized")

        tools = bridge.call("tools/list").get("result", {}).get("tools", [])
        names = sorted(t.get("name") for t in tools)
        want = sorted(["cube_get_state", "cube_scramble", "cube_restore",
                       "cube_reset", "cube_apply_alg",
                       "cube_solve", "cube_hint", "cube_solve_optimal", "cube_scramble_wca"])
        if names != want:
            fail("tools/list 工具集不符: %r" % names)
        ok("tools/list 9 工具齐全(kociemba 两工具恒列出)")

        st = poll_state(bridge, 30)
        if len(st["facelets"]) != 54 or not st["solved"]:
            fail("初始 state 应 54 字符且 solved=true: %r" % st)
        ok("cube_get_state: facelets 54 字符 solved=true")

        st = bridge.tool("cube_scramble")
        if st["solved"] or st["facelets"] == SOLVED_STR:
            fail("scramble 后应非 solved: %r" % st)
        ok("cube_scramble: solved=false")

        # A-6 种子化端到端:同 (seed, steps) 从复原态两次打乱 facelets 完全一致,不同 seed 不同
        bridge.tool("cube_reset")
        st1 = bridge.tool("cube_scramble", {"steps": 25, "seed": 424242})
        bridge.tool("cube_reset")
        st2 = bridge.tool("cube_scramble", {"steps": 25, "seed": 424242})
        if st1["facelets"] != st2["facelets"]:
            fail("cube_scramble 同 seed=424242 两次打乱应 facelets 一致: %r vs %r"
                 % (st1["facelets"], st2["facelets"]))
        ok("cube_scramble seed=424242 可复现(两次 facelets 一致)")
        bridge.tool("cube_reset")
        st3 = bridge.tool("cube_scramble", {"steps": 25, "seed": 424243})
        if st3["facelets"] == st2["facelets"]:
            fail("cube_scramble 不同 seed(424243 vs 424242)应产生不同 facelets")
        ok("cube_scramble seed=424243 序列不同")

        # solve/hint 条件化:教学引擎 lbl_solver.gd 由并行任务交付,未就绪时游戏侧返回
        # ok:false + "lbl_solver not ready" → 打 SKIP 继续(exit 0),就绪后自动变全测。
        st, is_err = bridge.tool_maybe("cube_solve")
        if is_err and "lbl_solver not ready" in st.get("error", ""):
            print("SKIP cube_solve/cube_hint: 引擎未就绪(%s);"
                  "scripts/lbl_solver.gd 就绪后自动全测" % st["error"])
        else:
            if is_err:
                fail("cube_solve -> isError: %r" % st)
            if not st.get("alg") or not isinstance(st.get("alg"), str):
                fail("cube_solve 应返回非空 alg: %r" % st)
            stages = st.get("stages")
            if not isinstance(stages, list) or len(stages) != 7:
                fail("cube_solve.stages 应为 7 段: %r" % (stages,))
            for seg in stages:
                if not (isinstance(seg, dict) and isinstance(seg.get("name"), str)
                        and isinstance(seg.get("alg"), str)):
                    fail("cube_solve.stages 段结构应为 {name, alg}: %r" % seg)
            ok("cube_solve: alg 非空 + stages 7 段")

            st, is_err = bridge.tool_maybe("cube_hint")
            if is_err:
                fail("cube_hint -> isError: %r" % st)
            sug = st.get("suggestion")
            # stage 口径 = 引擎 stage_check 0..7(0 = 完全打乱;服务器契约表 "1..7"
            # 与引擎契约矛盾,以引擎为准——见 tests/test_server.gd S2 注释,2026-09-24)
            if not (isinstance(st.get("stage"), int) and 0 <= st["stage"] <= 7
                    and "progress" in st
                    and isinstance(sug, dict) and "piece" in sug and "alg" in sug and "text" in sug):
                fail("cube_hint 结构应为 {stage, progress, suggestion{piece,alg,text}}: %r" % st)
            ok("cube_hint: stage=%s + suggestion 结构完整" % st["stage"])

        if HAVE_KOCIEMBA:
            st = bridge.tool("cube_solve_optimal")
            if not valid_alg(st.get("alg", "")):
                fail("cube_solve_optimal 应返回合法 WCA 记号解: %r" % st)
            if len(st["alg"].split()) > 22:
                fail("cube_solve_optimal 应 ≤22 步: %r" % st["alg"])
            ok("cube_solve_optimal: %d 步合法解" % len(st["alg"].split()))
        else:
            print("SKIP kociemba 段(cube_solve_optimal/cube_scramble_wca):未安装 %s;"
                  "安装: pip install kociemba -i https://pypi.tuna.tsinghua.edu.cn/simple" % KOCIEMBA_SKIP)

        st = bridge.tool("cube_apply_alg", {"alg": "R"})
        if st.get("queued") != 1:
            fail("cube_apply_alg('R') 应 queued=1: %r" % st)
        ok("cube_apply_alg R: queued=1")

        st = bridge.tool("cube_restore")
        if not isinstance(st.get("queued"), int) or st["queued"] < 1:
            fail("cube_restore 应 queued>=1: %r" % st)
        ok("cube_restore: queued=%d,轮询回放..." % st["queued"])

        final = poll_state(bridge, 90)
        if final["facelets"] != SOLVED_STR or not final["solved"]:
            fail("restore 后应回到打乱前状态(solved): %s" % final["facelets"])
        ok("cube_restore 回到打乱前状态(solved)")

        st = bridge.tool("cube_reset")
        if not st["solved"] or st["facelets"] != SOLVED_STR:
            fail("reset 后应 solved 且复原序: %r" % st)
        ok("cube_reset: solved=true")

        if HAVE_KOCIEMBA:
            st = bridge.tool("cube_scramble_wca")
            alg = st.get("alg", "")
            if not valid_alg(alg):
                fail("cube_scramble_wca 打乱序列应全为合法 WCA 记号: %r" % st)
            if len(alg.split()) != st.get("moves") or not st.get("solution"):
                fail("cube_scramble_wca 返回应含 moves 与 solution: %r" % st)
            ok("cube_scramble_wca: 打乱序列 %d 步合法,等待代执行..." % st["moves"])
            final = poll_state(bridge, 90)
            if final["solved"]:
                fail("cube_scramble_wca 代执行后应非 solved: %r" % final)
            if final["facelets"] == SOLVED_STR:
                fail("cube_scramble_wca 代执行后 facelets 应变化")
            # §18 T-bridge:解取逆 apply 应回到生成的目标打乱态
            if final["facelets"] != st.get("state_facelets"):
                fail("cube_scramble_wca 代执行后 facelets 应等于目标打乱态 state_facelets: %r != %r"
                     % (final["facelets"], st.get("state_facelets")))
            ok("cube_scramble_wca: 代执行完成,facelets == state_facelets(取逆 apply 回到该状态)")

            # A-6 扩展:cube_scramble_wca 可选 seed——同 seed 两次生成 alg 完全一致
            # (生成只依赖 rng,与游戏态无关;每次调用仍会代执行,入队即可,无需再轮询)
            w1 = bridge.tool("cube_scramble_wca", {"seed": 424242})
            w2 = bridge.tool("cube_scramble_wca", {"seed": 424242})
            if w1.get("alg") != w2.get("alg") or not valid_alg(w1.get("alg", "")):
                fail("cube_scramble_wca 同 seed=424242 应生成同一合法打乱序列: %r vs %r"
                     % (w1.get("alg"), w2.get("alg")))
            ok("cube_scramble_wca seed=424242 可复现(两次 alg 一致)")

            # 非整数 seed 显式报错(不静默降为系统熵源,与游戏侧 validate_seed 同口径)
            st, is_err = bridge.tool_maybe("cube_scramble_wca", {"seed": "abc"})
            if not is_err or "seed" not in st.get("error", ""):
                fail("cube_scramble_wca seed='abc' 应 isError 且提示 seed: %r" % st)
            ok("cube_scramble_wca seed='abc' 显式报错(不静默降熵)")

        print("ALL PASSED")
    finally:
        for proc in ([bridge.proc if bridge else None, game]):
            if proc is None:
                continue
            try:
                proc.terminate()
                proc.wait(timeout=5)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass


if __name__ == "__main__":
    main()
