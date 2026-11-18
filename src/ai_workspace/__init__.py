"""Core utilities for ai-workspace."""

__version__ = "0.1.0"


def workspace_status() -> dict[str, str]:
    """Return workspace metadata for health checks."""
    return {
        "name": "ai-workspace",
        "version": __version__,
        "status": "ready",
    }
