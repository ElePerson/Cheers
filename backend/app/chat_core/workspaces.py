"""工作空间 REST：列表与创建（供管理表格表单使用）."""
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel, ConfigDict

from app.db.models import Workspace
from app.db.session import get_session
from fastapi import APIRouter, Depends, HTTPException

router = APIRouter(prefix="/api/workspaces", tags=["workspaces"])


class WorkspaceInResponse(BaseModel):
    """工作空间响应."""
    model_config = ConfigDict(from_attributes=True)
    workspace_id: str
    name: str


class WorkspaceCreate(BaseModel):
    """创建工作空间."""
    name: str


@router.post("")
async def create_workspace(
    body: WorkspaceCreate,
    session: AsyncSession = Depends(get_session),
) -> dict:
    """创建工作空间（管理界面表格表单可调用）。"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="name 不能为空")
    ws = Workspace(name=name)
    session.add(ws)
    await session.commit()
    await session.refresh(ws)
    return {
        "status": "success",
        "data": WorkspaceInResponse.model_validate(ws).model_dump(),
    }


@router.get("")
async def list_workspaces(
    session: AsyncSession = Depends(get_session),
) -> dict:
    """获取工作空间列表（创建项目时选择）."""
    result = await session.execute(
        select(Workspace).order_by(Workspace.created_at)
    )
    workspaces = result.scalars().all()
    data = [
        WorkspaceInResponse.model_validate(w).model_dump()
        for w in workspaces
    ]
    return {"status": "success", "data": data}
