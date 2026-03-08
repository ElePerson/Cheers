"""文件上传与状态查询 API."""
import shutil
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.models import Channel, FileRecord
from app.db.session import get_session
from app.file_processor.convert import to_markdown

router = APIRouter(prefix="/api/files", tags=["files"])


def _data_dir() -> Path:
    base = Path(settings.data_dir)
    if not base.is_absolute():
        base = Path(__file__).resolve().parent.parent.parent.parent / base
    return base


@router.post("/upload")
async def upload_file(
    request: Request,
    channel_id: str = Query(...),
    uploader_id: str = Query(...),
    filename: str = Query(..., description="原始文件名，如 doc.pdf"),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """上传文件（body 为文件二进制），创建 FileRecord 并转换（M1 支持 .txt/.md/.docx）。"""
    result = await session.execute(select(Channel).where(Channel.channel_id == channel_id))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=404, detail="channel not found")
    ext = Path(filename).suffix.lower()
    allowed = (".txt", ".md", ".docx", ".pdf", ".xlsx", ".png", ".jpg", ".jpeg", ".webp")
    if ext not in allowed:
        raise HTTPException(status_code=400, detail=f"supported formats: {', '.join(allowed)}")
    file_id = str(uuid.uuid4())
    data_dir = _data_dir()
    upload_dir = data_dir / "uploads" / channel_id
    upload_dir.mkdir(parents=True, exist_ok=True)
    raw_path = upload_dir / f"{file_id}{ext}"
    body = await request.body()
    raw_path.write_bytes(body)
    conv_dir = data_dir / "converted" / channel_id
    conv_dir.mkdir(parents=True, exist_ok=True)
    md_path = conv_dir / f"{file_id}.md"
    status = "converting"
    try:
        content = to_markdown(raw_path)
        md_path.write_text(content, encoding="utf-8")
        status = "ready"
    except Exception:
        status = "failed"
    record = FileRecord(
        file_id=file_id,
        channel_id=channel_id,
        uploader_id=uploader_id,
        original_path=str(raw_path),
        md_path=str(md_path) if status == "ready" else None,
        status=status,
    )
    session.add(record)
    await session.flush()
    return {"status": "success", "data": {"file_id": file_id, "status": record.status}}


@router.get("/{file_id}/status")
async def file_status(
    file_id: str,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """查询文件转换状态."""
    result = await session.execute(select(FileRecord).where(FileRecord.file_id == file_id))
    rec = result.scalar_one_or_none()
    if not rec:
        raise HTTPException(status_code=404, detail="file not found")
    return {
        "status": "success",
        "data": {
            "file_id": rec.file_id,
            "status": rec.status,
            "md_path": rec.md_path,
        },
    }
