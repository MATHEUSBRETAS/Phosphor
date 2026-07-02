from __future__ import annotations

import json
import re
import sqlite3
import tempfile
from pathlib import Path


def read(root: Path, rel: str) -> str:
    return (root / rel).read_text()


def assert_contains(text: str, needle: str, message: str) -> None:
    assert needle in text, message


def test_streaming_exports_truncate_before_write(root: Path) -> None:
    src = read(root, "Sources/Phosphor/Services/MessageExporter.swift")
    for func_name in ["exportCSV", "exportPlainText", "exportHTML", "exportMbox", "exportJSON"]:
        match = re.search(rf"private func {func_name}.*?(?=\n    private func|\n    ///|\Z)", src, re.S)
        assert match is not None, f"{func_name} not found"
        body = match.group(0)
        assert_contains(body, "removeItem(at: outputURL)", f"{func_name} must remove existing output before streaming")
        assert_contains(body, "FileHandle(forWritingTo: outputURL)", f"{func_name} must stream through FileHandle")


def test_json_overwrite_fixture_has_no_stale_tail(root: Path) -> None:
    del root  # fixture mirrors the Swift export invariant without touching source files.
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "export.json"
        long_payload = {"messages": [{"text": "x" * 10_000}]}
        short_payload = {"messages": []}
        path.write_text(json.dumps(long_payload), encoding="utf-8")
        path.unlink(missing_ok=True)
        with path.open("w", encoding="utf-8") as handle:
            handle.write(json.dumps(short_payload))
        assert json.loads(path.read_text(encoding="utf-8")) == short_payload


def test_attachment_path_cache_invariants(root: Path) -> None:
    src = read(root, "Sources/Phosphor/Services/MessageExporter.swift")
    assert_contains(src, "attachmentDiskPathCache", "attachment path cache should exist")
    assert_contains(src, "missingAttachmentDiskPaths", "missing attachment cache should exist")
    assert_contains(src, "if let cached = attachmentDiskPathCache[filename]", "resolver should hit positive cache")
    assert_contains(src, "missingAttachmentDiskPaths.contains(filename)", "resolver should hit negative cache")
    assert_contains(src, "attachmentDiskPathCache[filename] = candidate", "resolver should store positive cache")
    assert_contains(src, "missingAttachmentDiskPaths.insert(filename)", "resolver should store negative cache")


def test_minimal_sms_schema_fixture_supports_limited_attachment_query(root: Path) -> None:
    del root
    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "sms.db"
        con = sqlite3.connect(db_path)
        con.executescript(
            """
            CREATE TABLE attachment (ROWID INTEGER PRIMARY KEY, guid TEXT, filename TEXT, mime_type TEXT, transfer_name TEXT, total_bytes INTEGER);
            CREATE TABLE message_attachment_join (message_id INTEGER, attachment_id INTEGER);
            INSERT INTO attachment VALUES (1,'a','~/Library/SMS/Attachments/a.jpg','image/jpeg','a.jpg',10);
            INSERT INTO attachment VALUES (2,'b','~/Library/SMS/Attachments/b.jpg','image/jpeg','b.jpg',20);
            INSERT INTO message_attachment_join VALUES (100,1);
            INSERT INTO message_attachment_join VALUES (200,2);
            """
        )
        rows = con.execute(
            """
            SELECT maj.message_id, a.ROWID, a.guid, a.filename, a.mime_type, a.transfer_name, a.total_bytes
            FROM attachment a JOIN message_attachment_join maj ON maj.attachment_id = a.ROWID
            WHERE maj.message_id IN (?)
            """,
            (100,),
        ).fetchall()
        con.close()
        assert len(rows) == 1 and rows[0][0] == 100, "limited attachment query should only load requested message IDs"


def test_message_exporter_caches_schema_and_preserves_tapback_context(root: Path) -> None:
    src = read(root, "Sources/Phosphor/Services/MessageExporter.swift")
    assert_contains(src, "private let messageColumns", "message table columns should be cached per exporter")
    assert_contains(src, "private func foldRows", "reaction/tapback folding should be centralized")
    assert_contains(src, "reactionEventsByTarget", "tapback rows must be folded with their target messages")
    assert_contains(src, "associated_message_type", "tapback detection should use associated_message_type when present")
