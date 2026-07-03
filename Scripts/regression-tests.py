#!/usr/bin/env python3
"""Compatibility entrypoint for Phosphor regression checks.

The focused checks live under Scripts/regression/checks so each stability area
can grow independently. Keep this top-level script as a stable local/CI command
for older workflows and contributor muscle memory.
"""
from __future__ import annotations

import runpy
from pathlib import Path


if __name__ == "__main__":
    runpy.run_path(str(Path(__file__).with_name("regression") / "run.py"), run_name="__main__")
