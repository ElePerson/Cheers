"""Bot 账号 REST：创建、列表、外部注册申请与审核."""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.chat_core.schemas import (
    BotCreate,
    BotInResponse,
    BotRegisterRequest,
    BotRegistrationRequestInResponse,
)
from app.db.models import BotAccount, BotRegistrationRequest, gen_uuid
from app.db.session import get_session

router = APIRouter(prefix="/api/bots", tags=["bots"])


@router.get("")
async def list_bots(session: AsyncSession = Depends(get_session)) -> dict:
    """获取所有 Bot 账号列表（管理用）."""
    result = await session.execute(
        select(BotAccount).order_by(BotAccount.created_at.desc())
    )
    items = []
    for row in result.scalars().all():
        d = BotInResponse.model_validate(row).model_dump()
        if row.created_at:
            d["created_at"] = row.created_at.isoformat()
        items.append(d)
    return {"status": "success", "data": items}


@router.post("")
async def create_bot(
    body: BotCreate,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """创建（注册）Bot 账号；bot_id 不填则自动生成."""
    bot_id = body.bot_id
    if not bot_id or not bot_id.strip():
        from app.db.models import gen_uuid
        bot_id = gen_uuid()
    else:
        bot_id = bot_id.strip()

    existing = await session.execute(
        select(BotAccount).where(BotAccount.bot_id == bot_id)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="bot_id 已存在")

    existing_user = await session.execute(
        select(BotAccount).where(BotAccount.username == body.username.strip())
    )
    if existing_user.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="username 已存在")

    bot = BotAccount(
        bot_id=bot_id,
        username=body.username.strip(),
        display_name=body.display_name.strip() if body.display_name else None,
        openclaw_endpoint=body.openclaw_endpoint.strip(),
        status=body.status.strip() or "online",
    )
    session.add(bot)
    await session.commit()
    await session.refresh(bot)

    d = BotInResponse.model_validate(bot).model_dump()
    if bot.created_at:
        d["created_at"] = bot.created_at.isoformat()
    return {"status": "success", "data": d}


# ---------- 外部 OpenClaw 发现与注册（无需鉴权，审核后生效） ----------


@router.post("/register-request")
async def submit_register_request(
    body: BotRegisterRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """外部 OpenClaw 提交注册申请；创建为待审核，管理员通过后才能真正被 @。"""
    username = body.username.strip()
    openclaw_endpoint = body.openclaw_endpoint.strip()
    existing = await session.execute(
        select(BotAccount).where(BotAccount.username == username)
    )
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="username 已被使用")
    pending = await session.execute(
        select(BotRegistrationRequest).where(
            BotRegistrationRequest.username == username,
            BotRegistrationRequest.status == "pending",
        )
    )
    if pending.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="该 username 已有待审核申请")
    req = BotRegistrationRequest(
        request_id=gen_uuid(),
        username=username,
        display_name=body.display_name.strip() if body.display_name else None,
        openclaw_endpoint=openclaw_endpoint,
        status="pending",
    )
    session.add(req)
    await session.commit()
    await session.refresh(req)
    return {
        "status": "success",
        "data": {
            "request_id": req.request_id,
            "message": "注册申请已提交，等待管理员在「管理」界面审核通过后可被加入项目并 @。",
        },
    }


@router.get("/registration-requests")
async def list_registration_requests(
    status: str | None = None,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """获取 Bot 注册申请列表（管理用）；可选 status=pending 仅待审核。"""
    q = select(BotRegistrationRequest).order_by(
        BotRegistrationRequest.requested_at.desc()
    )
    if status:
        q = q.where(BotRegistrationRequest.status == status)
    result = await session.execute(q)
    items = []
    for row in result.scalars().all():
        d = BotRegistrationRequestInResponse.model_validate(row).model_dump()
        if row.requested_at:
            d["requested_at"] = row.requested_at.isoformat()
        if row.decided_at:
            d["decided_at"] = row.decided_at.isoformat()
        items.append(d)
    return {"status": "success", "data": items}


@router.post("/registration-requests/{request_id}/approve")
async def approve_registration_request(
    request_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """管理员审核通过：创建 Bot 账号并标记申请为已通过。"""
    result = await session.execute(
        select(BotRegistrationRequest).where(
            BotRegistrationRequest.request_id == request_id,
            BotRegistrationRequest.status == "pending",
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="申请不存在或已处理")
    again = await session.execute(
        select(BotAccount).where(BotAccount.username == req.username)
    )
    if again.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="该 username 已存在 Bot")
    bot = BotAccount(
        bot_id=gen_uuid(),
        username=req.username,
        display_name=req.display_name,
        openclaw_endpoint=req.openclaw_endpoint,
        status="online",
    )
    session.add(bot)
    await session.flush()
    req.status = "approved"
    req.decided_at = datetime.utcnow()
    req.created_bot_id = bot.bot_id
    await session.commit()
    await session.refresh(bot)
    d = BotInResponse.model_validate(bot).model_dump()
    if bot.created_at:
        d["created_at"] = bot.created_at.isoformat()
    return {
        "status": "success",
        "data": d,
        "message": "已通过并创建 Bot，请将 Bot 加入项目后即可 @",
    }


@router.post("/registration-requests/{request_id}/reject")
async def reject_registration_request(
    request_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """管理员拒绝申请。"""
    result = await session.execute(
        select(BotRegistrationRequest).where(
            BotRegistrationRequest.request_id == request_id,
            BotRegistrationRequest.status == "pending",
        )
    )
    req = result.scalar_one_or_none()
    if not req:
        raise HTTPException(status_code=404, detail="申请不存在或已处理")
    req.status = "rejected"
    req.decided_at = datetime.utcnow()
    await session.commit()
    return {"status": "success", "message": "已拒绝"}
