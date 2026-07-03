from __future__ import annotations

from pathlib import Path


def read(root: Path, rel: str) -> str:
    return (root / rel).read_text()


def swift_block_after(text: str, signature: str) -> str:
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise AssertionError(f"unterminated Swift block after {signature}")


def test_shell_run_does_not_block_global_dispatch_workers(root: Path) -> None:
    src = read(root, "Sources/Phosphor/Utilities/Shell.swift")
    body = swift_block_after(src, "static func run(_ command: String")
    assert "process.terminationHandler" in body, "Shell.run should wait via Process.terminationHandler"
    assert "SIGKILL" in body, "Shell.run should force-kill commands that ignore graceful timeout termination"
    assert "waitUntilExit()" not in body, "Shell.run must not burn a global dispatch worker in waitUntilExit()"
    assert "DispatchQueue.global" not in body, "Shell.run must not allocate a global queue worker per process"


def test_shell_run_async_does_not_block_global_dispatch_workers(root: Path) -> None:
    src = read(root, "Sources/Phosphor/Utilities/Shell.swift")
    body = swift_block_after(src, "static func runAsync(_ command: String")
    assert "process.terminationHandler" in body, "Shell.runAsync should wait via Process.terminationHandler"
    assert "readabilityHandler" in body, "Shell.runAsync should collect pipe output without blocking reader workers"
    assert "SIGKILL" in body, "Shell.runAsync should force-kill commands that ignore graceful timeout termination"
    assert "waitUntilExit()" not in body, "Shell.runAsync must not block a worker in waitUntilExit()"
    assert "DispatchQueue.global" not in body, "Shell.runAsync must not allocate a global queue worker per process"


def test_shell_run_async_cancels_timeout_watchdog_on_finish(root: Path) -> None:
    src = read(root, "Sources/Phosphor/Utilities/Shell.swift")
    body = swift_block_after(src, "static func runAsync(_ command: String")
    assert "attachWatchdog" in body, "runAsync should hand its timeout watchdog to the state so it can be cancelled early"
    assert "pendingWatchdog?.cancel()" in src, "finish should cancel the watchdog so pipe fds are freed the moment the command completes"
    assert "timedOut ? -1 : process.terminationStatus" in body, "runAsync must not read terminationStatus on the timed-out path (process may still be running)"


def test_no_crash_only_swift_shortcuts(root: Path) -> None:
    offenders: list[str] = []
    for path in (root / "Sources").rglob("*.swift"):
        text = path.read_text(errors="ignore")
        for lineno, line in enumerate(text.splitlines(), start=1):
            if "try!" in line or "as!" in line or "fatalError(" in line or "preconditionFailure(" in line:
                offenders.append(f"{path.relative_to(root)}:{lineno}: {line.strip()}")
    assert not offenders, "Avoid crash-only Swift shortcuts:\n" + "\n".join(offenders)
