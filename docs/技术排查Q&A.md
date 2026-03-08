# AgentNexus 技术排查 Q&A

> 面向**运维与开发**：常见故障现象、可能原因、排查步骤与解决思路。日常使用类问题见 [普通用户使用说明](普通用户使用说明.md)。

---

## 一、故障现象与处理

| 现象 | 可能原因 | 排查与处理 |
|------|----------|------------|
| 前端打不开 / 白屏 | 前端未启动、端口被占、静态资源 404 | 检查前端进程或 Docker 前端容器；确认访问端口（80 或 5173）；看浏览器控制台报错。 |
| 接口返回 503 | 主库不可达、DATABASE_URL 错误、迁移未执行 | 检查 DATABASE_URL 与数据目录权限；执行 `alembic upgrade head`；看后端日志是否有连接错误。 |
| 接口返回 404 | 资源不存在（频道/文件/成员等） | 确认 URL 中的 ID 正确（channel_id、file_id、member_id）；用 GET 列表接口核对是否存在。 |
| 接口返回 400 | 参数错误、格式不支持（如文件类型） | 查看响应 body 中的 message；M1 文件上传仅支持 .txt、.md、.docx。 |
| 频道列表为空 / 之前创建的频道消失 | 未建空间/频道；或**数据库路径随启动目录变化**导致连到空库 | 见下方「频道/测试频道消失」；确认迁移已执行、先建工作空间再建项目。 |
| 发送消息无反应 | 网络异常、后端报错、WebSocket 未连上 | 浏览器开发者工具看接口是否 4xx/5xx；看后端日志；刷新页面重试。 |
| WebSocket 断开、消息不实时 | 网络抖动、服务重启、代理超时 | 刷新页面重建连接；检查 Nginx/代理的 WebSocket 超时与配置。 |
| 文件上传 400 | 非支持格式或缺少参数 | M1 仅支持 .txt、.md、.docx；确认请求含 channel_id、uploader_id、filename 及 body。 |
| 文件状态为 failed | 转换失败（格式异常、mammoth 等报错） | 查看后端日志中转换异常；确认文件未损坏、扩展名与内容一致。 |
| @ Bot 无回复 | Bot 未加入频道、username 不匹配、真实服务不可达 | 确认 Bot 已加入该频道（见 [系统管理说明书](系统管理说明书.md)）；@ 的名字与 bot_accounts.username 一致；若 openclaw_endpoint 为 http(s)，确认该服务已实现 POST /execute 约定且可访问。 |

---

## 二、日志与错误码

- **后端日志**：由 uvicorn/FastAPI 输出；Docker 下用 `docker compose logs backend` 查看。  
- **统一响应格式**：`{"status":"success|error","data":...,"message":"可选"}`；出错时看 **message** 和 HTTP 状态码。  
- **503**：通常表示数据库不可用（如 SQLite 路径错误、连接失败）。  
- **404**：资源不存在，检查 ID 与业务数据是否已创建。

---

## 三、常见技术问题 Q&A

**Q：必须安装 Redis 吗？**  
A：M1 阶段可选；不装也能运行，部分异步能力可能受限。Docker Compose 默认带 Redis。

**Q：频道/测试频道消失，之前建的频道看不到了？**  
A：多半是**同一台机上用了不同的数据库文件**。主库是 SQLite，默认路径为相对路径 `data/main.db`，会随**进程当前工作目录**变化：从项目根启动时可能是 `项目根/data/main.db`，从 backend 目录启动时可能是 `backend/data/main.db`，两边数据互不相通，所以会看到“空列表”或“频道消失”。  
**处理**：  
1. 代码已改为相对路径统一解析为**相对 backend 根目录**的绝对路径，即本地固定使用 `backend/data/main.db`（Docker 仍为容器内 `/app/data/main.db`）。重启后端后，以后无论从哪启动都会用同一库。  
2. 若你之前的数据在项目根下 `data/main.db`，可把该文件复制到 `backend/data/main.db`（先停服务），再重启。  
3. Docker 下数据在卷 **agentnexus_data** 中；若执行过 `docker-compose down -v`，卷被删会导致数据清空，需避免带 `-v` 或提前备份卷内数据。

**Q：如何修改主库或 Context Store 路径？**  
A：修改 .env 中 **DATABASE_URL**、**SQLITE_CONTEXT_PATH**（可为相对或绝对路径）；主库变更后需执行 `alembic upgrade head` 并重启服务。

**Q：Docker 下数据存在哪？**  
A：使用命名卷 **agentnexus_data**，默认挂载到 backend 容器内（如 /app/data）；具体见 docker-compose.yml 的 volumes。

**Q：如何确认 OpenClaw 是否被调用？**  
A：当 bot 的 openclaw_endpoint 为 **http://** 或 **https://** 时，系统会向该地址 **POST /execute** 发起请求；可在后端日志或对方服务日志中确认。若 endpoint 为 guide:// 或非 http，则不会发起真实 HTTP 调用。

**Q：支持多少用户/频道？**  
A：当前按 SQLite 单机设计，适合小团队与原型；规模扩大可考虑将主库迁移至 PostgreSQL（见 [关键技术文档](关键技术文档.md) §5.4）。

**Q：完整 API 文档在哪？**  
A：后端启动后访问 **http://localhost:8000/docs**（Swagger）。

---

## 四、相关文档

- [使用说明书](使用说明书.md)（总索引）
- [普通用户使用说明](普通用户使用说明.md)（用户侧常见问题）
- [系统管理说明书](系统管理说明书.md)（建项目、加人、加 Bot）
- [安装部署说明](安装部署说明.md)（环境与部署）
