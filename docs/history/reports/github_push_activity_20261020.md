# GitHub 推送情况报告 —— PolyTouch-FPGA-Synth

- **仓库**：`Interstellar-530/PolyTouch-FPGA-Synth`（私有，default branch `main`）
- **采集时间**：2026-10-20 下午（Asia/Shanghai）
- **数据来源**：GitHub REST API（仓库元数据、协作者、分支、各分支提交、仓库事件流、Release、PR），并用本地 git 对象补齐事件流遗漏的推送
- **仓库创建**：2026-10-08 20:58:54（+08）
- **最后一次推送**：2026-10-19 20:27:12（+08）
- **规模**：7 个分支、84 个唯一提交（`main` 上 39 个）、约 70.6 MiB

## 1. 开发者名单

| GitHub 账号 | 权限 | 加入时间 | 说明 |
|---|---|---|---|
| Interstellar-530 | admin | 2026-10-08（建仓） | 仓库所有者，本地提交身份为 `fpga-project@local`（显示名 `FPGA Project`） |
| RubiaAwakening | write | 2026-10-08 21:05 | 协作者，独立 GitHub 邮箱身份 |
| Binskin-0825 | write | 2026-10-13 21:54 | 协作者，截至采集时无任何提交或推送 |

## 2. 推送与提交总览

| 开发者 | 记录推送次数 | 推送分支 | 提交数（唯一） | 代码/文档改动文件数 | 首次提交 | 末次提交 | 活跃天数 |
|---|---|---|---|---|---|---|---|
| Interstellar-530 | 53（另有 1 次未进入事件流，见 §5） | `main` 37、`codex/s4-s6-pressure` 16 | 66 | 1324 | 2026-10-08 20:56 | 2026-10-19 20:27 | 8 |
| RubiaAwakening | 5 | `codex/s4-s6-review` 2、`codex/s4-s6-integration` 3 | 18 | 349 | 2026-10-08 21:45 | 2026-10-16 00:29 | 3 |
| Binskin-0825 | 0 | — | 0 | 0 | — | — | 0 |

## 3. 分支归属

| 分支 | 提交总数 | Interstellar-530 | RubiaAwakening | 创建者 | 记录推送次数 |
|---|---|---|---|---|---|
| `main` | 39 | 39 | 0 | Interstellar-530（10-08） | 37 |
| `codex/s2-gpio-keyboard` | 41 | 41 | 0 | Interstellar-530（10-14） | 0（见 §5） |
| `codex/s3-i2s-tx` | 43 | 43 | 0 | Interstellar-530（10-14） | 0（见 §5） |
| `codex/s4-s6-integration` | 55 | 43 | 12 | RubiaAwakening（10-15） | 3（全部 Rubia） |
| `codex/s4-s6-pressure` | 78 | 66 | 12 | Interstellar-530（10-17） | 16（全部 Interstellar） |
| `codex/s4-s6-review` | 7 | 1 | 6 | RubiaAwakening（10-15） | 2（全部 Rubia） |
| `fix/m2-build-issues` | 2 | 1 | 1 | RubiaAwakening（10-08） | 0（见 §5） |

> 说明：`codex/s4-s6-pressure` 从 `codex/s4-s6-integration` 拉出，因此 Rubia 的 12 个提交同时出现在两条分支上，不是重复劳动。

## 4. 时间线

推送次数按事件发生日统计，提交数按提交作者日期统计，两者不必同日对应。

| 日期（+08） | Interstellar-530 推送 | RubiaAwakening 推送 | 提交数 |
|---|---|---|---|
| 10-08 | 0 | 0 | 2（建仓首日，各 1） |
| 10-10 | 24 | 0 | 25 |
| 10-12 | 5 | 0 | 5 |
| 10-13 | 7 | 0 | 7 |
| 10-14 | 1 | 0 | 5 |
| 10-15 | 0 | 2 | 14（全部 Rubia） |
| 10-16 | 0 | 3 | 7（Rubia 3、Interstellar 4） |
| 10-17 | 16 | 0 | 18 |
| 10-19 | 1（未入事件流） | 0 | 1 |

## 5. 数据完整性说明（重要）

1. **事件流不是全量**。仓库事件流只返回了 58 条 `PushEvent`，时间范围 10-08～10-17；而 `pushed_at` 显示 10-19 20:27 还有一次推送，分支指针也确认 `codex/s4-s6-pressure` 头部为 `9d467e0`（该提交同时刻产生）。因此 Interstellar-530 的实际推送次数 ≥ 54。
2. **`codex/s2-gpio-keyboard`、`codex/s3-i2s-tx` 分支各含 41/43 个提交但无对应 PushEvent**，说明这些分支的创建推送未被事件流记录（事件流对私有仓库存在丢失）。
3. 因此本报告的**提交数、分支归属、时间跨度为权威值**（直接来自分支历史）；**推送次数为下限值**（事件流记录数），用于比较两人节奏仍是有效的相对指标。
4. 事件流中的其余事件：7 次 `CreateEvent`（建分支）、2 次 `ReleaseEvent`（v1.0.0 于 10-13、v1.01 于 10-14，均由 Interstellar-530 发布）、2 次 `MemberEvent`（加入协作者）、1 次 `PullRequestEvent`。

## 6. 协作状态

- **PR #1**：RubiaAwakening 于 2026-10-08 21:46 提交「Fix Gowin wavetable and GAO build flows」（`fix/m2-build-issues` → `main`），状态 **open，未合并**，之后没有评论或评审记录。
- **合并方式**：全部 84 个提交中**没有 merge commit**，分支演进为线性 rebase/ff 模式；Rubia 的评审成果通过 `codex/s4-s6-integration` → `codex/s4-s6-pressure` 的拉分支方式汇入，而非走 PR 合并。
- **节奏差异**：Interstellar-530 从建仓持续到 10-19，覆盖主线实现、证据归档和发布；RubiaAwakening 集中在 10-15～10-16 两天完成 S4–S6 评审与集成（10-15 单日 14 个提交、6 个推送中的 2 个），10-16 后无新提交。
- **Binskin-0825** 于 10-13 被加入协作者，仅 3 天后仓库进入评审阶段，但无提交、无推送，属只读协作者。

## 7. 采集方法

1. `GET /repos/{owner}/{repo}`、`/collaborators`、`/branches`、`/branches/{b}/commits`、`/events`、`/releases`、`/pulls` 抓取原始 JSON；
2. 以分支历史去重得到 84 个唯一提交，按 `author.email` 归并为两名开发者（`fpga-project@local` → Interstellar-530，`RubiaAwakening@users.noreply.github.com` → RubiaAwakening）；
3. 以 `before..head` 区间把每条 PushEvent 还原为提交数，并对事件流漏记的推送用本地 `refs/remotes/origin/*` 指针补正；
4. 原始 JSON 与脚本为临时产物，已在任务结束时清理，聚合结果全部落在本报告。
