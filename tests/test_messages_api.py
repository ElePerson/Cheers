"""ChatCore 消息 API 测试."""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Channel, Workspace


@pytest.mark.asyncio
async def test_list_messages_empty(client: AsyncClient, db_session: AsyncSession) -> None:
    """GET /api/channels/{id}/messages 无消息时返回空列表."""
    ws = Workspace(workspace_id="f0000000-0000-0000-0000-000000000001", name="W")
    ch = Channel(
        channel_id="e1000000-0000-0000-0000-000000000001",
        workspace_id=ws.workspace_id,
        name="ch",
        type="public",
    )
    db_session.add(ws)
    db_session.add(ch)
    await db_session.commit()

    resp = await client.get("/api/channels/e1000000-0000-0000-0000-000000000001/messages")
    assert resp.status_code == 200
    assert resp.json()["status"] == "success"
    assert resp.json()["data"] == []


@pytest.mark.asyncio
async def test_create_message_and_list(client: AsyncClient, db_session: AsyncSession) -> None:
    """POST /api/channels/{id}/messages 发送消息，GET 可拉取到."""
    ws = Workspace(workspace_id="f0000000-0000-0000-0000-000000000002", name="W2")
    ch = Channel(
        channel_id="e1000000-0000-0000-0000-000000000002",
        workspace_id=ws.workspace_id,
        name="ch2",
        type="public",
    )
    db_session.add(ws)
    db_session.add(ch)
    await db_session.commit()

    resp = await client.post(
        "/api/channels/e1000000-0000-0000-0000-000000000002/messages",
        json={
            "content": "hello",
            "sender_id": "a0000000-0000-0000-0000-000000000001",
            "sender_type": "user",
        },
    )
    assert resp.status_code == 200
    data = resp.json()["data"]
    assert data["content"] == "hello"
    assert "msg_id" in data
    assert "created_at" in data

    resp2 = await client.get("/api/channels/e1000000-0000-0000-0000-000000000002/messages")
    assert resp2.status_code == 200
    assert len(resp2.json()["data"]) == 1
    assert resp2.json()["data"][0]["content"] == "hello"
