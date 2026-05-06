"""BotPipeline: orchestrator-side stages.

Today only IngestStage is implemented; the rest of run_orchestrator is
migrated stage-by-stage in subsequent commits. The stages share
BotRunContext (data) and the same EventBus the IngestPipeline uses.
"""
from app.features.bot_runtime.pipeline.bot.capabilities import Capabilities
from app.features.bot_runtime.pipeline.bot.context import BotRunContext
from app.features.bot_runtime.pipeline.bot.stages.auto_takeover import AutoTakeoverStage
from app.features.bot_runtime.pipeline.bot.stages.context_load import ContextLoadStage
from app.features.bot_runtime.pipeline.bot.stages.dispatch import (
    DispatchStage,
    trigger_sub_bots_from_mentions,
)
from app.features.bot_runtime.pipeline.bot.stages.ingest import IngestStage
from app.features.bot_runtime.pipeline.bot.stages.route import RouteStage
from app.features.bot_runtime.pipeline.bot.subagent import (
    build_payload,
    dispatch_many,
    dispatch_one,
)
from app.features.bot_runtime.pipeline.bot.task_timeout import (
    AgentBridgeTaskTimeoutContext,
    ConvertToTaskStage,
    ValidatePendingStage,
    make_agent_bridge_task_timeout_pipeline,
)
from app.features.bot_runtime.pipeline.bot.writer import BotMessageWriter

__all__ = [
    "AutoTakeoverStage",
    "BotMessageWriter",
    "BotRunContext",
    "Capabilities",
    "ContextLoadStage",
    "DispatchStage",
    "IngestStage",
    "RouteStage",
    "ConvertToTaskStage",
    "ValidatePendingStage",
    "AgentBridgeTaskTimeoutContext",
    "build_payload",
    "dispatch_many",
    "dispatch_one",
    "make_agent_bridge_task_timeout_pipeline",
    "trigger_sub_bots_from_mentions",
]
