"""OpenClawAdapter 契约测试."""
import pytest

from app.adapters.base import AgentPayload, AgentResponse, OpenClawAdapter
from app.adapters.mock import MockOpenClawAdapter


@pytest.mark.asyncio
async def test_mock_adapter_execute() -> None:
    adapter = MockOpenClawAdapter(reply="你好，我是 Mock。")
    payload = AgentPayload(
        task_id="t1",
        channel_id="c1",
        trigger_message={"user": "张三", "text": "@bot 你好", "timestamp": "2026-03-07T00:00:00Z"},
        memory_context={"anchor": "", "decisions": "", "files_index": "", "recent": ""},
    )
    resp = await adapter.execute(payload)
    assert isinstance(resp, AgentResponse)
    assert resp.success is True
    assert resp.content == "你好，我是 Mock。"
    assert resp.task_id == "t1"


@pytest.mark.asyncio
async def test_mock_adapter_health_check() -> None:
    adapter = MockOpenClawAdapter(healthy=True)
    assert await adapter.health_check() is True
    adapter2 = MockOpenClawAdapter(healthy=False)
    assert await adapter2.health_check() is False
