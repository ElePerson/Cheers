# 跨端导航信息架构（iOS · Mac / Web）

> **状态**：#355 决策文档 — iOS 与桌面/Mac 设置与导航对齐的源真相。
> 呈现可以不同（抽屉 vs 轨道、整页 vs 弹层）；**目的地、职责与嵌套层级必须一致**。
>
> 英文正文：[CLIENT_NAV_IA.md](./CLIENT_NAV_IA.md)

## 要点

1. **主入口（共享）**：Activity（需要我处理：审批 + 邀请）· Fleet（机器人状态 + 创建/管理）· Friends · Settings。聊天列表仍是 Home。
2. **命名锁定**：用 Activity / Fleet / Friends / Settings；不用 Notifications（仅邀请）、Agents（作主入口名）、把 Profile 当主入口。
3. **Settings 共享分区**：Profile（可编辑）· Account（含设备会话、推送、外部 AI 权限、身份绑定）· Server · Legal & support（链接集合两端一致）。
4. **机器人主场 = Fleet**；桌面 `Settings → Bots` 降为跳转到 Fleet 的次入口。
5. **工作区管理齿轮**在工作区标题栏（抽屉/侧栏），不埋在 Settings  alone。
6. **有意例外**：Connector / About（更新、开机启动）/ 全局管理台仅桌面；iOS「全部会话」可保留。

实施清单与内容契约见英文版 §5–§6。
