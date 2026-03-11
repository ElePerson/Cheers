#!/bin/sh
set -e
cd /app
# 安装认证所需依赖
pip install "passlib[bcrypt]" bcrypt==4.0.1 -i https://pypi.tuna.tsinghua.edu.cn/simple || true
if [ -d alembic ]; then
  alembic upgrade head 2>/dev/null || true
fi
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
