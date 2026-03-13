"""种子数据：默认工作空间、AI 模型、提示词模板、Bot、测试用户."""
import asyncio
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.auth.routes import hash_password
from app.db.models import (
    AIModel,
    BotAccount,
    Channel,
    ChannelMembership,
    PromptTemplate,
    User,
    Workspace,
)
from app.db.session import async_session_factory

# 固定 ID，便于文档与脚本引用
WORKSPACE_ID = "ws-default-001"
CHANNEL_ID = "ch-seed-001"
DEV_USER_ID = "a0000000-0000-0000-0000-000000000001"
ADMIN_USER_ID = "admin-0000-0000-0000-000000000001"

# 内置模型 ID
MODEL_OLLAMA_ID = "model-ollama-001"
MODEL_OPENAI_ID = "model-openai-001"

# 内置模板 ID
TEMPLATE_GENERAL_ID = "template-general-001"
TEMPLATE_CODE_REVIEW_ID = "template-codereview-001"
TEMPLATE_CREATIVE_ID = "template-creative-001"

# 内置 Bot ID
BOT_ASSISTANT_ID = "bot-assistant-001"
BOT_CODE_REVIEWER_ID = "bot-codereviewer-001"


async def _seed_models(session: AsyncSession) -> bool:
    """创建内置 AI 模型."""
    did_write = False
    
    # Ollama 本地模型（默认）
    r = await session.execute(select(AIModel).where(AIModel.model_id == MODEL_OLLAMA_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            AIModel(
                model_id=MODEL_OLLAMA_ID,
                name="Ollama (Llama 3.2)",
                provider="ollama",
                model_name="llama3.2",
                base_url="http://localhost:11434/v1",
                api_key=None,  # 本地模型不需要 API Key
                description="本地 Ollama 运行的 Llama 3.2 模型，无需联网，适合代码和一般问答",
                is_enabled=True,
                is_builtin=True,
                config={"temperature": 0.7, "max_tokens": 2000},
            )
        )
        did_write = True
    
    # OpenAI GPT-4o（示例，需要配置 API Key）
    r = await session.execute(select(AIModel).where(AIModel.model_id == MODEL_OPENAI_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            AIModel(
                model_id=MODEL_OPENAI_ID,
                name="OpenAI GPT-4o",
                provider="openai",
                model_name="gpt-4o",
                base_url="https://api.openai.com/v1",
                api_key=None,  # 需要用户自行配置
                description="OpenAI GPT-4o，强大的通用能力，需要配置 API Key",
                is_enabled=False,  # 默认禁用，直到配置了 API Key
                is_builtin=True,
                config={"temperature": 0.7, "max_tokens": 4000},
            )
        )
        did_write = True
    
    return did_write


async def _seed_templates(session: AsyncSession) -> bool:
    """创建内置提示词模板."""
    did_write = False
    
    # 通用助手模板
    r = await session.execute(select(PromptTemplate).where(PromptTemplate.template_id == TEMPLATE_GENERAL_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            PromptTemplate(
                template_id=TEMPLATE_GENERAL_ID,
                name="通用助手",
                description="通用的 AI 助手，适合回答各种问题",
                system_prompt="你是一个有用的 AI 助手。请简洁、专业地回答用户问题。",
                user_template="{{message}}",
                variables=["message"],
                is_builtin=True,
            )
        )
        did_write = True
    
    # 代码审查模板
    r = await session.execute(select(PromptTemplate).where(PromptTemplate.template_id == TEMPLATE_CODE_REVIEW_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            PromptTemplate(
                template_id=TEMPLATE_CODE_REVIEW_ID,
                name="代码审查",
                description="专业的代码审查助手，发现潜在问题和优化点",
                system_prompt="""你是一个专业的代码审查助手。请审查用户提供的代码，关注以下方面：
1. 潜在的 Bug 和错误处理
2. 代码风格和可读性
3. 性能优化建议
4. 安全漏洞
5. 最佳实践

请用中文回复，使用 Markdown 格式，结构清晰。""",
                user_template="请审查以下代码：\n\n```\n{{message}}\n```\n\n请给出详细的审查意见，包括问题和改进建议。",
                variables=["message"],
                is_builtin=True,
            )
        )
        did_write = True
    
    # 创意写作模板
    r = await session.execute(select(PromptTemplate).where(PromptTemplate.template_id == TEMPLATE_CREATIVE_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            PromptTemplate(
                template_id=TEMPLATE_CREATIVE_ID,
                name="创意写作",
                description="富有创意的写作助手，帮助撰写和润色文字",
                system_prompt="你是一个富有创意的写作助手。请用生动、有趣的语言帮助用户撰写和润色文字。",
                user_template="请帮我完善以下内容：\n\n{{message}}",
                variables=["message"],
                is_builtin=True,
            )
        )
        did_write = True
    
    return did_write


async def _seed_bots(session: AsyncSession) -> bool:
    """创建内置 Bot."""
    did_write = False
    
    # 通用助手 Bot
    r = await session.execute(select(BotAccount).where(BotAccount.bot_id == BOT_ASSISTANT_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            BotAccount(
                bot_id=BOT_ASSISTANT_ID,
                username="助手",
                display_name="AI 助手",
                description="通用的 AI 助手，可以回答各种问题",
                model_id=MODEL_OLLAMA_ID,
                template_id=TEMPLATE_GENERAL_ID,
                status="online",
                intro='{"capabilities":["问答","写作","分析","编程帮助"],"description":"通用 AI 助手"}',
            )
        )
        did_write = True
    
    # 代码审查 Bot
    r = await session.execute(select(BotAccount).where(BotAccount.bot_id == BOT_CODE_REVIEWER_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            BotAccount(
                bot_id=BOT_CODE_REVIEWER_ID,
                username="代码审查",
                display_name="Code Reviewer",
                description="专业的代码审查助手，帮助发现代码中的问题和优化点",
                model_id=MODEL_OLLAMA_ID,
                template_id=TEMPLATE_CODE_REVIEW_ID,
                status="online",
                intro='{"capabilities":["代码审查","Bug 发现","优化建议","安全检测"],"description":"专业代码审查助手"}',
            )
        )
        did_write = True
    
    return did_write


async def _seed_workspace_and_users(session: AsyncSession) -> bool:
    """创建工作区、频道、用户."""
    did_write = False
    
    # 工作空间
    r = await session.execute(select(Workspace).where(Workspace.workspace_id == WORKSPACE_ID))
    if r.scalar_one_or_none() is None:
        session.add(Workspace(workspace_id=WORKSPACE_ID, name="默认空间"))
        did_write = True

    # 项目（频道）
    r = await session.execute(select(Channel).where(Channel.channel_id == CHANNEL_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            Channel(
                channel_id=CHANNEL_ID,
                workspace_id=WORKSPACE_ID,
                name="测试项目",
                type="public",
                purpose="开箱测试与 Bot 演示",
            )
        )
        did_write = True

    # 开发/测试用户
    r = await session.execute(select(User).where(User.user_id == DEV_USER_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            User(
                user_id=DEV_USER_ID,
                username="dev",
                password_hash=hash_password("dev"),
                display_name="开发测试用户",
                role="member",
            )
        )
        did_write = True

    # 系统管理员
    r = await session.execute(select(User).where(User.user_id == ADMIN_USER_ID))
    if r.scalar_one_or_none() is None:
        session.add(
            User(
                user_id=ADMIN_USER_ID,
                username="admin",
                password_hash=hash_password("admin"),
                display_name="系统管理员",
                role="system_admin",
            )
        )
        did_write = True
    
    return did_write


async def _seed_memberships(session: AsyncSession) -> bool:
    """创建频道成员关系."""
    did_write = False
    
    # Bot 加入频道
    bots_to_add = [BOT_ASSISTANT_ID, BOT_CODE_REVIEWER_ID]
    for bot_id in bots_to_add:
        r = await session.execute(
            select(ChannelMembership).where(
                ChannelMembership.channel_id == CHANNEL_ID,
                ChannelMembership.member_id == bot_id,
            )
        )
        if r.scalar_one_or_none() is None:
            session.add(
                ChannelMembership(
                    channel_id=CHANNEL_ID,
                    member_id=bot_id,
                    member_type="bot",
                )
            )
            did_write = True
    
    # 测试用户加入频道
    r = await session.execute(
        select(ChannelMembership).where(
            ChannelMembership.channel_id == CHANNEL_ID,
            ChannelMembership.member_id == DEV_USER_ID,
        )
    )
    if r.scalar_one_or_none() is None:
        session.add(
            ChannelMembership(
                channel_id=CHANNEL_ID,
                member_id=DEV_USER_ID,
                member_type="user",
            )
        )
        did_write = True
    
    return did_write


async def seed(session: AsyncSession) -> bool:
    """写入种子数据（若已存在则跳过）。返回是否执行了写入。"""
    did_write = False
    
    # 顺序：模型 -> 模板 -> Bot -> 工作区/用户 -> 成员关系
    did_write |= await _seed_models(session)
    did_write |= await _seed_templates(session)
    did_write |= await _seed_bots(session)
    did_write |= await _seed_workspace_and_users(session)
    did_write |= await _seed_memberships(session)
    
    return did_write


async def run_seed() -> None:
    """在独立会话中执行种子并提交。"""
    async with async_session_factory() as session:
        try:
            await seed(session)
            await session.commit()
        except Exception:
            await session.rollback()
            raise


def _ensure_data_dir() -> None:
    """确保主库所在目录存在（SQLite 文件路径）。"""
    url = settings.database_url
    if not url.startswith("sqlite"):
        return
    path = url.split("///")[-1].split("?")[0]
    if not path:
        return
    dir_path = Path(path).parent
    if not dir_path.is_absolute():
        base = Path(__file__).resolve().parent.parent.parent
        dir_path = base / dir_path
    dir_path.mkdir(parents=True, exist_ok=True)


if __name__ == "__main__":
    _ensure_data_dir()
    asyncio.run(run_seed())
    print(
        "Seed done.\n"
        f"  Workspace: {WORKSPACE_ID}\n"
        f"  Channel: {CHANNEL_ID}\n"
        f"  Models: Ollama (Llama 3.2), OpenAI GPT-4o\n"
        f"  Templates: 通用助手, 代码审查, 创意写作\n"
        f"  Bots: @助手 @代码审查"
    )
