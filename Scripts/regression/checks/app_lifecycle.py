from __future__ import annotations

from pathlib import Path


def read(root: Path, rel: str) -> str:
    return (root / rel).read_text()


def test_phosphor_quits_after_last_window_closes(root: Path) -> None:
    src = read(root, "Sources/Phosphor/App/PhosphorApp.swift")
    assert "applicationShouldTerminateAfterLastWindowClosed" in src, "Phosphor should quit when the last app window closes"
    assert "-> Bool {\n        true\n    }" in src, "last-window-close delegate should return true"


def test_phosphor_preserves_reopen_window_recovery(root: Path) -> None:
    src = read(root, "Sources/Phosphor/App/PhosphorApp.swift")
    assert "applicationShouldHandleReopen" in src, "Dock/app reopen should recreate a missing window"
    assert "ensureWindowSoon()" in src, "reopen recovery should keep using the no-window guard"
    assert "CommandGroup(replacing: .newItem)" not in src, "do not remove SwiftUI's standard New Window command"