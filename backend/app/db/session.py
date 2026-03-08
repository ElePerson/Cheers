"""异步数据库引擎与会话."""
from collections.abc import AsyncGenerator

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings
from app.db.models import Base

async_engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
    future=True,
)


def _set_sqlite_pragma(dbapi_connection, connection_record):
    """主业务库 SQLite 连接建立时启用 WAL 模式."""
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.close()


# 仅对 SQLite 主库启用 WAL（Context Store 在 context_store 模块内单独设置）
if "sqlite" in settings.database_url:
    event.listen(async_engine.sync_engine, "connect", _set_sqlite_pragma)

async_session_factory = async_sessionmaker(
    async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_session() -> AsyncGenerator[AsyncSession, None]:
    """依赖注入用：获取异步会话."""
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db() -> None:
    """创建所有表（仅用于测试或非迁移场景；生产用 Alembic 迁移）."""
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
