from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from importlib.resources import files as _res_files
except Exception:  # pragma: no cover
    _res_files = None  # type: ignore


def _run(cmd: list[str]) -> int:
    completed = subprocess.run(cmd)
    return int(completed.returncode)


def _which(name: str) -> str | None:
    return shutil.which(name)


def _windows_path_to_wsl(p: Path) -> str | None:
    # Convert like C:\Users\me\x -> /mnt/c/Users/me/x
    drive = p.drive
    if not drive or len(drive) < 2 or drive[1] != ":":
        return None
    drive_letter = drive[0].lower()
    rest = str(p)[2:].lstrip("\\/")
    return f"/mnt/{drive_letter}/" + rest.replace("\\", "/")


def _cygpath(mode: str, p: str) -> str | None:
    cygpath = _which("cygpath")
    if not cygpath:
        return None
    res = subprocess.run([cygpath, mode, p], capture_output=True, text=True)
    if res.returncode != 0:
        return None
    return (res.stdout or "").strip()


def main() -> None:
    # Simple package-manager install: provide aws-lambda-layer command.
    # This runs the bundled bash script (same behavior as the repo script).
    if _res_files is not None:
        assets_dir = Path(_res_files("aws_lambda_layer_cli").joinpath("assets"))
    else:
        assets_dir = Path(__file__).resolve().parent / "assets"

    script_path = assets_dir / "aws-lambda-layer"
    if not script_path.exists():
        raise SystemExit(f"Packaged script missing: {script_path}")

    args = sys.argv[1:]

    # POSIX
    if os.name != "nt":
        raise SystemExit(_run(["bash", str(script_path), *args]))

    # Windows
    # 1) Git Bash / MSYS / Cygwin: use cygpath -u and run bash
    posix = _cygpath("-u", str(script_path))
    if posix and _which("bash"):
        raise SystemExit(_run(["bash", posix, *args]))

    # 2) WSL
    wsl = _which("wsl.exe") or _which("wsl")
    if wsl:
        wsl_path = _windows_path_to_wsl(script_path)
        if not wsl_path:
            raise SystemExit(f"Unable to convert path for WSL: {script_path}")

        def q(s: str) -> str:
            return "'" + s.replace("'", "'\\''") + "'"

        cmd = "bash " + q(wsl_path) + (" " + " ".join(q(a) for a in args) if args else "")
        raise SystemExit(_run([wsl, "bash", "-lc", cmd]))

    raise SystemExit(
        "No compatible bash found on Windows. Install WSL (recommended) or Git Bash and ensure bash is on PATH."
    )
