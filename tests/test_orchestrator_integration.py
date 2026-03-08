"""单 Bot 接入集成测试：发带 @bot 的消息，验证 Bot 回复被持久化并可拉取."""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import BotAccount, Channel, ChannelMembership, Workspace


@pytest.mark.asyncio
async def test_message_at_bot_gets_bot_reply(client: AsyncClient, db_session: AsyncSession) -> None:
    """频道内添加 Bot，发送 @bot 消息，列表中应出现用户消息 + Bot 回复."""
    ws = Workspace(workspace_id="b1000000-0000-0000-0000-000000000001", name="W")
    ch = Channel(
        channel_id="b2000000-0000-0000-0000-000000000001",
        workspace_id=ws.workspace_id,
        name="general",
        type="public",
    )
    bot = BotAccount(
        bot_id="b3000000-0000-0000-0000-000000000001",
        username="mockbot",
        display_name="MockBot",
        openclaw_endpoint="mock://test",
    )
    db_session.add(ws)
    db_session.add(ch)
    db_session.add(bot)
    db_session.add(
        ChannelMembership(
            channel_id=ch.channel_id,
            member_id=bot.bot_id,
            member_type="bot",
        )
    )
    await db_session.commit()

    resp = await client.post(
        f"/api/channels/{ch.channel_id}/messages",
        json={
            "content": "@mockbot 你好，请回复",
            "sender_id": "a0000000-0000-0000-0000-000000000001",
            "sender_type": "user",
        },
    )
    assert resp.status_code == 200

    list_resp = await client.get(f"/api/channels/{ch.channel_id}/messages")
    assert list_resp.status_code == 200
    messages = list_resp.json()["data"]
    assert len(messages) >= 2
    user_msg = next((m for m in messages if m["sender_type"] == "user"), None)
    bot_msg = next((m for m in messages if m["sender_type"] == "bot"), None)
    assert user_msg is not None and "你好" in user_msg["content"]
    assert bot_msg is not None
    assert "Mock Bot" in bot_msg["content"] or "已收到" in bot_msg["content"]


@pytest.mark.asyncio
async def test_message_at_multiple_bots_serial_replies(
    client: AsyncClient, db_session: AsyncSession
) -> None:
    """同一消息 @ 多个 Bot 时，串行执行，每条 Bot 回复均持久化."""
    ws = Workspace(workspace_id="b1000000-0000-0000-0000-000000000002", name="W2")
    ch = Channel(
        channel_id="b2000000-0000-0000-0000-000000000002",
        workspace_id=ws.workspace_id,
        name="general",
        type="public",
    )
    bot1 = BotAccount(
        bot_id="b3000000-0000-0000-0000-000000000002",
        username="bot_a",
        display_name="BotA",
        openclaw_endpoint="mock://test",
    )
    bot2 = BotAccount(
        bot_id="b3000000-0000-0000-0000-000000000003",
        username="bot_b",
        display_name="BotB",
        openclaw_endpoint="mock://test",
    )
    db_session.add(ws)
    db_session.add(ch)
    db_session.add(bot1)
    db_session.add(bot2)
    db_session.add(
        ChannelMembership(channel_id=ch.channel_id, member_id=bot1.bot_id, member_type="bot")
    )
    db_session.add(
        ChannelMembership(channel_id=ch.channel_id, member_id=bot2.bot_id, member_type="bot")
    )
    await db_session.commit()

    resp = await client.post(
        f"/api/channels/{ch.channel_id}/messages",
        json={
            "content": "@bot_a @bot_b 请依次回复",
            "sender_id": "a0000000-0000-0000-0000-000000000002",
            "sender_type": "user",
        },
    )
    assert resp.status_code == 200

    list_resp = await client.get(f"/api/channels/{ch.channel_id}/messages")
    assert list_resp.status_code == 200
    messages = list_resp.json()["data"]
    bot_messages = [m for m in messages if m["sender_type"] == "bot"]
    assert len(bot_messages) >= 2
