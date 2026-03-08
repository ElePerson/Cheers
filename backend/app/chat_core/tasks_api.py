"""Agent 任务日志 API：质量监控看板数据."""
from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AgentTask, BotAccount
from app.db.session import get_session

router = APIRouter(prefix="/api", tags=["tasks"])


@router.get("/channels/{channel_id}/tasks")
async def list_channel_tasks(
    channel_id: str,
    limit: int = Query(50, ge=1, le=200),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """获取频道内 Agent 任务列表（质量监控）。"""
    result = await session.execute(
        select(AgentTask, BotAccount.username, BotAccount.display_name)
        .outerjoin(BotAccount, AgentTask.bot_id == BotAccount.bot_id)
        .where(AgentTask.channel_id == channel_id)
        .order_by(AgentTask.created_at.desc())
        .limit(limit)
    )
    rows = result.all()
    items = []
    for row in rows:
        task, username, display_name = row[0], row[1], row[2]
        items.append({
            "task_id": task.task_id,
            "channel_id": task.channel_id,
            "bot_id": task.bot_id,
            "bot_username": username,
            "bot_display_name": display_name,
            "trigger_msg_id": task.trigger_msg_id,
            "response_msg_id": task.response_msg_id,
            "latency_ms": task.latency_ms,
            "token_count": task.token_count,
            "feedback": task.feedback,
            "created_at": task.created_at.isoformat() if task.created_at else None,
        })
    return {"status": "success", "data": items}


@router.get("/tasks")
async def list_tasks(
    channel_id: str | None = Query(None),
    limit: int = Query(50, ge=1, le=200),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """获取任务列表，可选按 channel_id 筛选（质量监控看板）。"""
    q = (
        select(AgentTask, BotAccount.username, BotAccount.display_name)
        .outerjoin(BotAccount, AgentTask.bot_id == BotAccount.bot_id)
        .order_by(AgentTask.created_at.desc())
        .limit(limit)
    )
    if channel_id:
        q = q.where(AgentTask.channel_id == channel_id)
    result = await session.execute(q)
    rows = result.all()
    items = []
    for row in rows:
        task, username, display_name = row[0], row[1], row[2]
        items.append({
            "task_id": task.task_id,
            "channel_id": task.channel_id,
            "bot_id": task.bot_id,
            "bot_username": username,
            "bot_display_name": display_name,
            "trigger_msg_id": task.trigger_msg_id,
            "response_msg_id": task.response_msg_id,
            "latency_ms": task.latency_ms,
            "token_count": task.token_count,
            "feedback": task.feedback,
            "created_at": task.created_at.isoformat() if task.created_at else None,
        })
    return {"status": "success", "data": items}
