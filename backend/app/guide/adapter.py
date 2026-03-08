"""引导 Bot 适配器：可选 LLM 或关键词匹配，根据帮助文档回复与动态表单."""
import json

from app.adapters.base import AgentPayload, AgentResponse, OpenClawAdapter
from app.guide.help_index import (
    build_guide_content_with_form,
    get_form_for_intent,
    get_help_context_for_llm,
)
from app.guide.llm_client import chat as llm_chat
from app.guide.llm_client import is_configured as llm_configured

DEFAULT_REPLY = (
    "您可以说：怎么创建项目、怎么加入项目、怎么接入 OpenClaw、怎么发消息、"
    "左边没有项目、@ 没反应、怎么安装、报错排查 等，我会根据说明书为您引导。"
    "完整文档见 docs/使用说明书.md。"
)

SYSTEM_PROMPT_TEMPLATE = """你是 AgentNexus 系统的引导助手。请仅根据以下帮助文档回答用户问题，语气简洁友好。
若用户问题与文档无关，可简要说明你能协助的范围并引导其提问。
不要编造文档中没有的步骤或链接。
回答请使用纯文本；若涉及《系统管理说明书》等，可用 Markdown 链接 [文字](url) 形式。

帮助文档：
---
{help_context}
---
"""


class GuideBotAdapter(OpenClawAdapter):
    """引导 Bot：优先用配置的 LLM 根据帮助文档生成回复；否则关键词匹配+动态表单."""

    async def execute(self, payload: AgentPayload) -> AgentResponse:
        text = (payload.trigger_message or {}).get("text") or ""
        content = ""

        if llm_configured():
            ctx = get_help_context_for_llm()
            system = SYSTEM_PROMPT_TEMPLATE.format(help_context=ctx)
            content = await llm_chat(system, text)

        if not content:
            content = build_guide_content_with_form(text)

        if not content:
            content = DEFAULT_REPLY
        else:
            form = get_form_for_intent(text)
            if form:
                blob = json.dumps(form, ensure_ascii=False)
                content += "\n\n```guide-form\n" + blob + "\n```"

        return AgentResponse(
            content=content,
            task_id=payload.task_id,
            success=True,
        )

    async def health_check(self) -> bool:
        return True
