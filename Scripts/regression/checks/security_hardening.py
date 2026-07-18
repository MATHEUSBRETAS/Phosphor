from __future__ import annotations

from pathlib import Path


def read(root: Path, rel: str) -> str:
    return (root / rel).read_text()


def test_whatsapp_html_export_escapes_title_and_sender(root: Path) -> None:
    """Issue #38: chat title and sender are device-controlled and must be HTML
    escaped in the WhatsApp HTML export, or a crafted group subject / sender
    injects script into the exported document (stored XSS)."""
    src = read(root, "Sources/Phosphor/Services/WhatsAppExporter.swift")
    assert "<h1>\\(title)</h1>" not in src, "WhatsApp HTML export must not interpolate the raw chat title into <h1>"
    assert "<h1>\\(title.htmlEscaped)</h1>" in src, "WhatsApp HTML export must escape the chat title in <h1>"
    assert "class=\\\"sender\\\">\\(sender)</div>" not in src, "WhatsApp HTML export must not interpolate the raw sender"
    assert "sender.htmlEscaped" in src, "WhatsApp HTML export must escape the sender"
    assert "\\(title.htmlEscaped) - WhatsApp Export" in src, "WhatsApp HTML export must escape the title in <title>"


def test_shared_html_escaper_covers_all_dangerous_characters(root: Path) -> None:
    """The shared escaper must neutralize every character that can break out of
    an HTML text or attribute context."""
    src = read(root, "Sources/Phosphor/Utilities/HTMLEscaping.swift")
    for entity in ("&amp;", "&lt;", "&gt;", "&quot;", "&#39;"):
        assert entity in src, f"shared htmlEscaped must emit {entity}"


def test_backup_password_is_not_passed_on_the_command_line(root: Path) -> None:
    """Issue #39: the backup encryption password must reach the tool via the
    BACKUP_PASSWORD / BACKUP_PASSWORD_NEW environment variables (invisible to
    `ps`), not as a positional argument on the primary path."""
    backup = read(root, "Sources/Phosphor/Services/BackupManager.swift")
    assert "BACKUP_PASSWORD" in backup, "encryption toggle must pass the password via BACKUP_PASSWORD env var"
    assert "BACKUP_PASSWORD_NEW" in backup, "changepw must pass the new password via BACKUP_PASSWORD_NEW env var"
    # The old argv-based idevicebackup2 encryption invocations must be gone.
    assert '"encryption", "on", password' not in backup, "password must not be an idevicebackup2 argv value"
    assert '"encryption", "off", password' not in backup, "password must not be an idevicebackup2 argv value"


def test_shell_runasync_supports_extra_environment(root: Path) -> None:
    """Shell.runAsync must accept extra environment entries so secrets can be
    passed out-of-band from argv."""
    src = read(root, "Sources/Phosphor/Utilities/Shell.swift")
    assert "extraEnvironment" in src, "Shell.runAsync must expose an extraEnvironment parameter"
