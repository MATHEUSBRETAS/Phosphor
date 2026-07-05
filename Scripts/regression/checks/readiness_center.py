from __future__ import annotations

from pathlib import Path


def read(root: Path, rel: str) -> str:
    return (root / rel).read_text()


def test_readiness_service_contract(root: Path) -> None:
    path = root / "Sources/Phosphor/Services/ReadinessService.swift"
    assert path.exists(), "ReadinessService.swift should centralize readiness checks"
    src = path.read_text()
    for token in [
        "enum ReadinessStatus",
        "struct ReadinessItem",
        "struct ReadinessReport",
        "enum ReadinessService",
        "static func evaluate",
        "static func dependencyStatus",
        "Task.detached",
        "BackupManager.validateBackupDirectory",
        "diagnosticMarkdown",
    ]:
        assert token in src, f"ReadinessService missing {token}"


def test_dependency_checks_are_not_wrapped_in_global_dispatch(root: Path) -> None:
    for rel in [
        "Sources/Phosphor/Services/DeviceManager.swift",
        "Sources/Phosphor/Views/ContentView.swift",
        "Sources/Phosphor/Views/Onboarding/OnboardingView.swift",
        "Sources/Phosphor/Views/Settings/SettingsView.swift",
    ]:
        src = read(root, rel)
        assert "DispatchQueue.global().async" not in src, f"{rel} still uses global dispatch for readiness/dependencies"
        assert "Shell.checkDependencies()" not in src, f"{rel} still calls Shell.checkDependencies directly"
    assert "ReadinessService.dependencyStatus" in read(root, "Sources/Phosphor/Services/DeviceManager.swift")
    assert "ReadinessService.dependencyStatus" in read(root, "Sources/Phosphor/Views/ContentView.swift")
    assert "ReadinessService.dependencyStatus" in read(root, "Sources/Phosphor/Views/Onboarding/OnboardingView.swift")
    assert "ReadinessService.dependencyStatus" in read(root, "Sources/Phosphor/Views/Settings/SettingsView.swift")


def test_readiness_center_visible_in_navigation(root: Path) -> None:
    sidebar = read(root, "Sources/Phosphor/Views/SidebarView.swift")
    content = read(root, "Sources/Phosphor/Views/ContentView.swift")
    view_path = root / "Sources/Phosphor/Views/Readiness/ReadinessCenterView.swift"
    assert view_path.exists(), "ReadinessCenterView should exist"
    view_src = view_path.read_text()
    assert "case readiness" in sidebar, "SidebarSection should include readiness"
    assert "sidebarRow(.readiness)" in sidebar, "Readiness should be visible in the sidebar"
    assert "ReadinessCenterView" in content, "ContentView should route to the readiness center"
    for phrase in [
        "Tool Readiness",
        "Backup Folder",
        "Device Visibility",
        "Wi-Fi Backup",
        "Safe Operations",
        "Diagnostic Report",
        "Next Steps",
    ]:
        assert phrase in view_src, f"Readiness center missing user-facing section: {phrase}"
