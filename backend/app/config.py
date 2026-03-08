"""应用配置，从环境变量加载。相对路径统一解析为相对 backend 根目录，避免因启动目录不同而使用不同数据库。"""
from pathlib import Path

from pydantic_settings import BaseSettings

# backend 根目录（app/config.py -> app -> backend）
_BACKEND_ROOT = Path(__file__).resolve().parent.parent


def _resolve_sqlite_url(url: str) -> str:
    """若为 sqlite 且路径为相对路径，则解析为基于 backend 根的绝对路径，保证同一 DB 不受 cwd 影响。"""
    if not url.startswith("sqlite"):
        return url
    # sqlite+aiosqlite:///data/main.db -> 取 data/main.db
    if "///" in url:
        rest = url.split("///", 1)[1].split("?")[0]
    else:
        return url
    if not rest or Path(rest).is_absolute():
        return url
    abs_path = (_BACKEND_ROOT / rest).resolve()
    abs_path.parent.mkdir(parents=True, exist_ok=True)
    return url.replace("///" + rest, "///" + str(abs_path), 1)


class Settings(BaseSettings):
    """全局配置."""

    # 数据库（主业务库 SQLite；相对路径会解析为 backend 根目录下的绝对路径）
    database_url: str = "sqlite+aiosqlite:///data/main.db"
    sqlite_context_path: str = "data/context_store/context.db"

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # 数据目录（相对项目根或绝对路径）
    data_dir: str = "data"

    # 调试
    debug: bool = False

    # 日志目录（相对项目根或绝对路径）；留空则仅控制台
    log_dir: str = "data/logs"
    # 单日志文件最大字节，0 表示不轮转
    log_max_bytes: int = 5 * 1024 * 1024  # 5MB
    log_backup_count: int = 3

    # 引导 Bot 使用的 LLM（可选；不配置则用关键词匹配；默认连本地 Ollama）
    guide_llm_base_url: str = "http://localhost:11434/v1"
    guide_llm_model: str = "llama3.2"
    guide_llm_api_key: str = ""
    guide_llm_temperature: float = 0.7
    guide_llm_max_tokens: int = 1000

    # 系统 LLM（RECENT 压缩、文件摘要等；不配置则简单截断）
    system_llm_api_key: str = ""
    system_llm_base_url: str = ""  # OpenAI 兼容
    system_llm_model: str = "gpt-4o-mini"

    model_config = {
        "env_file": ".env",
        "env_file_encoding": "utf-8",
        "extra": "ignore",
    }


def get_data_dir(base: Path) -> Path:
    """解析 data 目录路径."""
    p = Path(settings.data_dir)
    if not p.is_absolute():
        p = base / p
    return p


settings = Settings()
# 将 SQLite 相对路径解析为基于 backend 根的绝对路径，避免因启动 cwd 不同而使用不同 DB
if "sqlite" in settings.database_url and "///" in settings.database_url:
    rest = settings.database_url.split("///", 1)[1].split("?")[0]
    if rest and not Path(rest).is_absolute():
        settings.database_url = _resolve_sqlite_url(settings.database_url)
