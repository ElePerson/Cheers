curl -sS http://10.1.20.45:18789/v1/chat/completions \
  -H 'Authorization: Bearer REDACTED_TOKEN' \
  -H 'Content-Type: application/json' \
  -H 'x-openclaw-agent-id: main' \
  -d '{
    "model": "openclaw",
    "messages": [{"role":"user","content":"找出Download文件夹下的第一个json文件，并且显示他的内容"}],
    "stream": true
  }'
