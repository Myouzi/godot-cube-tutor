#!/usr/bin/env python3
"""魔方 MCP 外部控制桥(PLAN §6.3/§6.4)。

零依赖(仅标准库):stdin 逐行 JSON-RPC → stdout 纯 JSON-RPC,任何杂音走 stderr;
initialize 回显客户端 protocolVersion(缺省 "2025-06-18");每个 tools/call 连一次
游戏内 TCP NDJSON 服务器(127.0.0.1,默认 8788)发一行收一行。
端口:--cube-port=N 参数或 CUBE_PORT 环境变量,缺省 8788。
"""

import json
import os
import random
import socket
import sys

HOST = "127.0.0.1"
DEFAULT_PORT = 8788
DEFAULT_PROTOCOL = "2025-06-18"
PIP_MIRROR = "https://pypi.tuna.tsinghua.edu.cn/simple"  # PyPI 直连被重置,安装须走清华镜像

# optional 依赖(§6.3):kociemba 仅 cube_solve_optimal / cube_scramble_wca 需要,
# 未安装时桥照常启动,两工具仍列于 tools/list,调用返回 isError + 安装指引。
try:
    import kociemba as _kociemba
    from kociemba.pykociemba.cubiecube import CubieCube as _CubieCube
    from kociemba.pykociemba.facecube import FaceCube as _FaceCube
    KOCIEMBA_ERROR = ""
except ImportError as _e:
    KOCIEMBA_ERROR = str(_e)

_OBJECT = {"type": "object", "properties": {}, "additionalProperties": False}

TOOLS = [
    {
        "name": "cube_get_state",
        "description": (
            "读取魔方实时状态:{n, facelets(54 字符 URFDLB,已 bake 状态), solved, moves, "
            "animating, queue_len}。animating/queue_len 不为 0 表示动画未完,请轮询至两者清零再取 facelets。"
        ),
        "inputSchema": _OBJECT,
    },
    {
        "name": "cube_scramble",
        "description": (
            "瞬时打乱魔方(同 UI 打乱按钮),撤销栈与步数清零。"
            "可选 seed:同 (seed, steps) 打乱序列完全可复现(自动化测试/问题复现用)。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "steps": {"type": "integer", "description": "打乱步数,1..100,缺省 25"},
                "seed": {"type": "integer", "description": "可选随机种子;缺省走系统熵源"},
            },
        },
    },
    {
        "name": "cube_restore",
        "description": (
            "动画回放 full_log 逆序,把魔方还原到初始态(回放语义,非最优解)。"
            "立即返回 {queued};之后用 cube_get_state 轮询至 animating=false 且 queue_len=0。"
        ),
        "inputSchema": _OBJECT,
    },
    {
        "name": "cube_reset",
        "description": "瞬时重置魔方到复原态(重建 cubie,清空全部历史)。",
        "inputSchema": _OBJECT,
    },
    {
        "name": "cube_apply_alg",
        "description": (
            "以动画播放一条 WCA 记号公式(如 \"R U R' U'\"),不计步;追加语义,"
            "播放中可继续下发,顺序执行不丢步。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "alg": {
                    "type": "string",
                    "description": "WCA 记号:U D L R F B + '(逆) + 2(180°),空格分隔,≤300 token",
                }
            },
            "required": ["alg"],
        },
    },
    {
        "name": "cube_solve",
        "description": (
            "LBL 分层解(3 阶专用):对当前已 bake 状态求七阶段层先法解,纯计算不执行。"
            "返回 {alg, stages:[{name, alg}]×7};N≠3 时返回错误。"
        ),
        "inputSchema": _OBJECT,
    },
    {
        "name": "cube_hint",
        "description": (
            "教学提示(3 阶专用):当前 LBL 阶段/进度与下一步建议。"
            "返回 {stage, progress, suggestion:{piece, alg, text}}。"
        ),
        "inputSchema": _OBJECT,
    },
    {
        "name": "cube_solve_optimal",
        "description": (
            "对当前状态求最优解(桥侧 kociemba 两阶段算法,≤22 步,纯计算不执行)。"
            "需 3 阶;已复原时返回空 alg。"
        ),
        "inputSchema": _OBJECT,
    },
    {
        "name": "cube_scramble_wca",
        "description": (
            "WCA 均匀随机打乱(3 阶专用):桥侧生成随机合法状态(置换奇偶校验 +"
            " 角朝向和≡0 mod3 + 棱朝向和≡0 mod2)→ kociemba.solve → 解取逆为打乱序列,"
            "经打乱标记入口代为执行(计时模块据此进入 scrambled 态)。"
            "可选 seed:同 seed 生成的打乱序列完全可复现(自动化测试/问题复现用)。"
            "返回 {alg(打乱序列), moves, solution, state_facelets}。"
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "seed": {"type": "integer", "description": "可选随机种子;缺省走系统熵源"},
            },
        },
    },
]

# 工具名 → (NDJSON cmd, 透传的参数键)
CMD_OF = {
    "cube_get_state": ("state", ()),
    "cube_scramble": ("scramble", ("steps", "seed")),
    "cube_restore": ("restore", ()),
    "cube_reset": ("reset", ()),
    "cube_apply_alg": ("apply_alg", ("alg",)),
    "cube_solve": ("solve", ()),
    "cube_hint": ("hint", ()),
}

# 桥侧本地实现的 kociemba 工具(不走 CMD_OF 转发)
KOCIEMBA_TOOLS = ("cube_solve_optimal", "cube_scramble_wca")


def log(*args):
    print("[cube-mcp]", *args, file=sys.stderr, flush=True)


def ndjson_call(port, cmd, params):
    """连一次 TCP 发一行收一行(§6.1)。网络/协议错误抛 OSError/JSONDecodeError。"""
    req = {"id": 1, "cmd": cmd, **params}
    payload = (json.dumps(req) + "\n").encode("utf-8")
    with socket.create_connection((HOST, port), timeout=5) as sock:
        sock.settimeout(30)
        sock.sendall(payload)
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
    line = buf.split(b"\n", 1)[0].decode("utf-8", "replace").strip()
    if not line:
        raise OSError("empty response")
    return json.loads(line)


def tool_result(payload, is_error=False):
    return {
        "content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}],
        "isError": is_error,
    }


def rpc_result(rid, payload):
    return {"jsonrpc": "2.0", "id": rid, "result": payload}


def rpc_error(rid, code, message):
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": code, "message": message}}


def invert_alg(alg):
    """序列取逆:逆序 + 逐 token 反向(R'→R,R2→R2,R→R')。"""
    out = []
    for t in reversed(alg.split()):
        if t.endswith("'"):
            out.append(t[:-1])
        elif t.endswith("2"):
            out.append(t)
        else:
            out.append(t + "'")
    return " ".join(out)


def _perm_parity(seq):
    p = 0
    for i in range(len(seq)):
        for j in range(i + 1, len(seq)):
            p ^= seq[i] > seq[j]
    return p


def random_valid_state(rng):
    """随机合法状态(§6.3/H4):角 8/棱 12 置换带奇偶校验(两者奇偶须一致),
    角朝向和 ≡ 0 mod 3,棱朝向和 ≡ 0 mod 2。"""
    cp = list(range(8))
    ep = list(range(12))
    rng.shuffle(cp)
    rng.shuffle(ep)
    if _perm_parity(cp) != _perm_parity(ep):
        ep[0], ep[1] = ep[1], ep[0]
    co = [rng.randrange(3) for _ in range(7)]
    co.append((-sum(co)) % 3)
    eo = [rng.randrange(2) for _ in range(11)]
    eo.append(sum(eo) % 2)
    return cp, co, ep, eo


def generate_wca_scramble(rng=None):
    """随机合法状态 → kociemba.solve → 解取逆 = 打乱序列(H4 单一实现源:
    MCP cube_scramble_wca 与游戏侧 tools/wca_scramble.py 共用此函数)。
    返回 (scramble_alg, solution, target_facelets)。
    kociemba 未安装抛 RuntimeError;solve 失败抛 ValueError。"""
    if KOCIEMBA_ERROR:
        raise RuntimeError(KOCIEMBA_ERROR)
    if rng is None:
        rng = random.Random()  # 系统熵源
    cp, co, ep, eo = random_valid_state(rng)
    target = _CubieCube(cp, co, ep, eo).toFaceCube().to_String()
    sol = _kociemba.solve(target)
    return invert_alg(sol), sol, target


def game_state_or_error(rid, port):
    """取游戏当前 state;连不上/出错返回 (None, error_response)。"""
    try:
        resp = ndjson_call(port, "state", {})
    except (OSError, json.JSONDecodeError) as e:
        return None, rpc_result(rid, tool_result(
            {"error": f"无法连接游戏侧 TCP({HOST}:{port}),请确认游戏正在运行: {e}"},
            is_error=True))
    if not resp.get("ok"):
        return None, rpc_result(rid, tool_result(
            {"error": resp.get("error", "state 查询失败")}, is_error=True))
    return resp.get("data"), None


def handle_kociemba_tool(rid, name, port, args=None):
    """cube_solve_optimal / cube_scramble_wca:桥侧 kociemba 本地实现。"""
    if KOCIEMBA_ERROR:
        return rpc_result(rid, tool_result({
            "error": (
                "kociemba 未安装(%s)。安装:pip install kociemba -i %s"
                "(本环境 PyPI 直连被重置,须走清华镜像)" % (KOCIEMBA_ERROR, PIP_MIRROR)
            )}, is_error=True))
    state, err = game_state_or_error(rid, port)
    if err is not None:
        return err
    if state.get("n") != 3:
        return rpc_result(rid, tool_result(
            {"error": "仅支持 3 阶(当前 n=%s),kociemba 面级解法限 3 阶" % state.get("n")},
            is_error=True))
    facelets = state["facelets"]

    if name == "cube_solve_optimal":
        if state.get("solved"):
            return rpc_result(rid, tool_result(
                {"alg": "", "moves": 0, "facelets": facelets, "note": "已复原,无需求解"}))
        try:
            sol = _kociemba.solve(facelets)
        except ValueError as e:
            return rpc_result(rid, tool_result(
                {"error": "kociemba 无法求解该状态(串非法?): %s" % e}, is_error=True))
        return rpc_result(rid, tool_result(
            {"alg": sol, "moves": len(sol.split()), "facelets": facelets}))

    # cube_scramble_wca:随机合法状态 → solve → 解取逆 = 打乱序列 → 代为执行
    # 可选 seed(A-6):同 seed 生成序列完全可复现(生成只依赖 rng,与游戏态无关);
    # 非整数 seed 显式报错(与游戏侧 cube_scramble 的 validate_seed 同口径,不静默降熵)
    seed = (args or {}).get("seed")
    if seed is not None and (not isinstance(seed, int) or isinstance(seed, bool)):
        return rpc_result(rid, tool_result(
            {"error": "seed 必须为整数(JSON integer)"}, is_error=True))
    try:
        rng = random.Random(seed) if seed is not None else None
        scramble_alg, sol, target = generate_wca_scramble(rng)
    except ValueError as e:
        return rpc_result(rid, tool_result(
            {"error": "kociemba 无法求解生成的打乱状态: %s" % e}, is_error=True))
    try:
        resp = ndjson_call(port, "scramble_wca_apply", {"alg": scramble_alg})
    except (OSError, json.JSONDecodeError) as e:
        return rpc_result(rid, tool_result(
            {"error": f"无法连接游戏侧 TCP({HOST}:{port}),请确认游戏正在运行: {e}"},
            is_error=True))
    if not resp.get("ok"):
        return rpc_result(rid, tool_result(
            {"error": resp.get("error", "scramble_wca_apply 失败")}, is_error=True))
    return rpc_result(rid, tool_result({
        "alg": scramble_alg,
        "moves": len(scramble_alg.split()),
        "solution": sol,
        "state_facelets": target,
        "queued": resp.get("data", {}).get("queued"),
    }))


def handle(req, port):
    method = req.get("method")
    rid = req.get("id")
    params = req.get("params") or {}

    if method == "initialize":
        return rpc_result(rid, {
            "protocolVersion": params.get("protocolVersion", DEFAULT_PROTOCOL),  # echo 客户端版本
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": "cube-mcp", "title": "魔方 MCP 外部控制", "version": "1.0.0"},
        })

    if method == "tools/list":
        return rpc_result(rid, {"tools": TOOLS})

    if method == "tools/call":
        name = params.get("name", "")
        if name in KOCIEMBA_TOOLS:
            return handle_kociemba_tool(rid, name, port, params.get("arguments") or {})
        entry = CMD_OF.get(name)
        if entry is None:
            return rpc_result(rid, tool_result({"error": f"unknown tool: {name}"}, is_error=True))
        cmd, keys = entry
        args = params.get("arguments") or {}
        nd_params = {k: args[k] for k in keys if k in args}
        try:
            resp = ndjson_call(port, cmd, nd_params)
        except (OSError, json.JSONDecodeError) as e:
            return rpc_result(rid, tool_result(
                {"error": f"无法连接游戏侧 TCP({HOST}:{port}),请确认游戏正在运行: {e}"},
                is_error=True))
        if resp.get("ok"):
            return rpc_result(rid, tool_result(resp.get("data")))
        return rpc_result(rid, tool_result({"error": resp.get("error", "unknown error")}, is_error=True))

    if rid is not None:
        return rpc_error(rid, -32601, f"method not found: {method}")
    return None  # 未知 notification:静默


def parse_port(argv):
    port = int(os.environ.get("CUBE_PORT", DEFAULT_PORT))
    for a in argv:
        if a.startswith("--cube-port="):
            port = int(a.split("=", 1)[1])
    return port


def main():
    port = parse_port(sys.argv[1:])
    log(f"stdio bridge up -> tcp {HOST}:{port}")
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            req = json.loads(raw)
        except json.JSONDecodeError as e:
            log("invalid json request:", e)
            continue
        try:
            resp = handle(req, port)
        except Exception as e:  # 兜底:任何 handler 异常都不许弄死桥进程
            log("handler error:", repr(e))
            resp = rpc_error(req.get("id"), -32603, f"internal error: {e}") if req.get("id") is not None else None
        if resp is not None:
            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()
    log("stdin closed, bye")


if __name__ == "__main__":
    main()
