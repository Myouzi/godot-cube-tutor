# 上游许可确认 issue(A-2,2026-09-25)

**状态更新(2026-09-25)**:用户裁决直接走备选路径——已用 `tools/rebuild_cfop.py` 从
speedsolving wiki 社区公共算法表重录替换 `data/cfop.json`(119 case / 614 条公式,
全部经引擎数学验证),上游许可依赖已消除,**本 issue 无需发送**。
以下文本保留备用:若日后想礼貌性地通知上游其 LICENSE 缺失,仍可用。

## 标题

```
Please add a LICENSE file to clarify MIT status
```

## 正文

```
Hi, thanks for this project — I'm using the CFOP algorithms data
(`src/algorithms.ts`) in a small offline desktop cube trainer.

The README states the project is MIT-licensed, but the repository has no
LICENSE file, so GitHub reports the license as "None" and downstream users
have no verifiable grant to rely on.

Would you mind adding a LICENSE file? Alternatively, a short reply here
confirming that the README's MIT declaration applies would also work.

Thanks!
```

## 发送后

- 上游补了 LICENSE(或回复确认)→ 把确认结果记入本文件与 README「许可」节
- 长期无果 → 按调研报告 A-2 备选:以社区通用公式集重录替换 `data/cfop.json`(公式本身不受版权保护,具体编排与呈现方式受)
