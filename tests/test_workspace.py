from ai_workspace import __version__, workspace_status


def test_workspace_status() -> None:
    status = workspace_status()
    assert status["name"] == "ai-workspace"
    assert status["version"] == __version__
    assert status["status"] == "ready"
