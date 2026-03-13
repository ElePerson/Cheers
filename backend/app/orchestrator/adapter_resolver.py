"""解析 bot_id -> OpenClawAdapter.

新架构：Bot = AIModel + PromptTemplate
所有 Bot 统一使用 LLMBotAdapter，直接调用配置的 LLM。
"""
import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.base import OpenClawAdapter
from app.adapters.llm_bot import LLMBotAdapter
from app.adapters.mock import MockOpenClawAdapter
from app.db.models import BotAccount

logger = logging.getLogger("app.orchestrator.adapter_resolver")


async def get_adapter_for_bot(bot_id: str, session: AsyncSession) -> OpenClawAdapter:
    """获取 Bot 的适配器.
    
    新架构下，所有 Bot 都使用 LLMBotAdapter。
    """
    result = await session.execute(
        select(BotAccount).where(BotAccount.bot_id == bot_id)
    )
    bot = result.scalar_one_or_none()
    
    if not bot:
        return MockOpenClawAdapter(reply="[未知 Bot] 已收到消息。")
    
    # 检查 Bot 配置
    if not bot.ai_model:
        logger.warning("adapter_resolver: bot_id=%s has no model configured", bot_id)
        return MockOpenClawAdapter(
            reply=f"[{bot.display_name or bot.username}] 未配置模型"
        )
    
    if not bot.prompt_template:
        logger.warning("adapter_resolver: bot_id=%s has no template configured", bot_id)
        return MockOpenClawAdapter(
            reply=f"[{bot.display_name or bot.username}] 未配置提示词模板"
        )
    
    if bot.ai_model.is_enabled is False:
        logger.warning("adapter_resolver: bot_id=%s model is disabled", bot_id)
        return MockOpenClawAdapter(
            reply=f"[{bot.display_name or bot.username}] 模型已禁用"
        )
    
    logger.info(
        "adapter_resolver: bot_id=%s username=%s -> LLMBotAdapter model=%s template=%s",
        bot_id,
        bot.username,
        bot.ai_model.name,
        bot.prompt_template.name,
    )
    
    return LLMBotAdapter(bot)
