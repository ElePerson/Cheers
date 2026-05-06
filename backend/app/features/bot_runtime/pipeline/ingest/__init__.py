"""IngestPipeline: validate → secret-envelope → persist → emit → fanout-unread.

Used by every code path that creates a Message in a channel: HTTP send,
SSE-streaming send, builtin-bot post-back. Routes the
final emit through EventBus so frontend / SSE / unread-badges all see the
same wire format.
"""
from app.features.bot_runtime.pipeline.ingest.context import IngestContext
from app.features.bot_runtime.pipeline.ingest.stages import (
    CommitStage,
    EmitStage,
    FanoutUnreadStage,
    PersistStage,
    SecretEnvelopeStage,
    ValidateStage,
    make_ingest_pipeline,
)

__all__ = [
    "CommitStage",
    "EmitStage",
    "FanoutUnreadStage",
    "IngestContext",
    "PersistStage",
    "SecretEnvelopeStage",
    "ValidateStage",
    "make_ingest_pipeline",
]
