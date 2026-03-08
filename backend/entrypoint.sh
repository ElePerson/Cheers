#!/bin/sh
set -e
cd /app
if [ -d alembic ]; then
  alembic upgrade head 2>/dev/null || true
fi
exec uvicorn app.main:app --host 0.0.0.0 --port 8000
