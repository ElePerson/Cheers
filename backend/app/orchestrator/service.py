"""AgentOrchestrator：收到 @Bot 消息后构造 Payload、调 Adapter、回写 Bot 消息；支持 Coordinator 主控聚合。"""
import logging
import uuid
from typing import Callable, Awaitable

from sqlalchemy import select

logger = logging.getLogger("app.orchestrator.service")
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.base import AgentPayload, AgentResponse, OpenClawAdapter
from app.db.models import AgentTask, BotAccount, ChannelMembership, Message
from app.orchestrator.mention import extract_mentions, filter_mentioned_bots

COORDINATOR_USERNAME = "coordinator"


async def run_orchestrator(
    channel_id: str,
    trigger_msg: Message,
    session: AsyncSession,
    adapter_factory: Callable[[str], Awaitable[OpenClawAdapter]],
) -> list[Message]:
    """
    根据触发消息中的 @ 提及，解析出目标 Bot，串行调用 Adapter，每条 Bot 回复持久化并返回。
    若目标包含 coordinator，则主控聚合：串行调用频道内其他 Bot，汇总为一条 Coordinator 回复。
    """
    result = await session.execute(
        select(ChannelMembership, BotAccount)
        .join(BotAccount, ChannelMembership.member_id == BotAccount.bot_id)
        .where(
            ChannelMembership.channel_id == channel_id,
            ChannelMembership.member_type == "bot",
        )
    )
    rows = result.all()
    channel_bot_usernames = [row[1].username for row in rows]
    bot_id_by_username = {row[1].username: row[1].bot_id for row in rows}

    mentioned = extract_mentions(trigger_msg.content)
    target_usernames = filter_mentioned_bots(mentioned, channel_bot_usernames)
    if not target_usernames:
        if mentioned:
            logger.info(
                "no mentioned bots in channel: channel_id=%s mentioned=%s channel_bots=%s",
                channel_id, mentioned, channel_bot_usernames,
            )
        return []

    from app.memory.manager import load as memory_load
    memory_context = await memory_load(channel_id)

    created: list[Message] = []
    for username in target_usernames:
        bot_id = bot_id_by_username[username]
        if username == COORDINATOR_USERNAME:
            # 主控聚合：调用频道内除 coordinator 外的所有 Bot，汇总为一条消息
            other_rows = [(r[0].member_id, r[1].username) for r in rows if r[1].username != COORDINATOR_USERNAME]
            parts = []
            for other_bot_id, other_username in other_rows:
                adapter = await adapter_factory(other_bot_id)
                task_id = str(uuid.uuid4())
                payload = AgentPayload(
                    task_id=task_id,
                    channel_id=channel_id,
                    trigger_message={
                        "user": trigger_msg.sender_id,
                        "text": trigger_msg.content,
                        "timestamp": trigger_msg.created_at.isoformat() if trigger_msg.created_at else "",
                    },
                    memory_context=memory_context,
                    attachments=[],
                )
                resp: AgentResponse = await adapter.execute(payload)
                content = resp.content if resp.success else (resp.error_message or "处理出错")
                parts.append(f"### @{other_username}\n\n{content}")
            combined = "## 汇总\n\n" + "\n\n---\n\n".join(parts) if parts else "（当前频道无其他 Bot 可调度）"
            coord_msg = Message(
                channel_id=channel_id,
                sender_id=bot_id,
                sender_type="bot",
                content=combined,
            )
            session.add(coord_msg)
            await session.flush()
            coord_task = AgentTask(
                task_id=str(uuid.uuid4()),
                channel_id=channel_id,
                bot_id=bot_id,
                trigger_msg_id=trigger_msg.msg_id,
                response_msg_id=coord_msg.msg_id,
            )
            session.add(coord_task)
            await session.flush()
            created.append(coord_msg)
            continue

        adapter = await adapter_factory(bot_id)
        task_id = str(uuid.uuid4())
        payload = AgentPayload(
            task_id=task_id,
            channel_id=channel_id,
            trigger_message={
                "user": trigger_msg.sender_id,
                "text": trigger_msg.content,
                "timestamp": trigger_msg.created_at.isoformat() if trigger_msg.created_at else "",
            },
            memory_context=memory_context,
            attachments=[],
        )
        resp: AgentResponse = await adapter.execute(payload)
        content = resp.content if resp.success else (resp.error_message or "处理出错")
        bot_msg = Message(
            channel_id=channel_id,
            sender_id=bot_id,
            sender_type="bot",
            content=content,
        )
        session.add(bot_msg)
        await session.flush()
        task_record = AgentTask(
            task_id=task_id,
            channel_id=channel_id,
            bot_id=bot_id,
            trigger_msg_id=trigger_msg.msg_id,
            response_msg_id=bot_msg.msg_id,
        )
        session.add(task_record)
        await session.flush()
        created.append(bot_msg)
    return created
