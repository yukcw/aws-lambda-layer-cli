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

    script_path = assets_dir / "aws-lambda-layer-cli"
    if not script_path.exists():
        raise SystemExit(f"Packaged script missing: {script_path}")

    args = sys.argv[1:]

    # Handle uninstall command
    if args and args[0] == "uninstall":
        if "--help" in args or "-h" in args:
            GREEN = '\033[0;32m'
            BLUE = '\033[0;34m'
            NC = '\033[0m'
            
            print(f"{BLUE}Usage:{NC}")
            print(f"  aws-lambda-layer-cli {GREEN}uninstall{NC}")
            print("")
            print(f"{BLUE}Description:{NC}")
            print("  Uninstalls the AWS Lambda Layer CLI tool and removes all associated files.")
            print("  This includes:")
            print("  - The CLI executable and symlinks")
            print("  - The installation directory")
            print("  - Shell completion scripts")
            raise SystemExit(0)

        uninstall_script = assets_dir / "uninstall.sh"
        if not uninstall_script.exists():
            raise SystemExit(f"Uninstall script missing: {uninstall_script}")
        
        # Use the same execution logic as the main script, but pointing to uninstall.sh
        script_path = uninstall_script
        # Remove 'uninstall' from args
        args = args[1:]

    # Handle completion command
    if args and args[0] == "completion":
        has_zsh = "--zsh" in args
        has_bash = "--bash" in args
        
        if "--help" in args or "-h" in args or (not has_zsh and not has_bash):
            GREEN = '\033[0;32m'
            YELLOW = '\033[0;33m'
            BLUE = '\033[0;34m'
            MAGENTA = '\033[0;35m'
            NC = '\033[0m'
            UNDERLINE = '\033[4m'

            print(f"{BLUE}Usage:{NC}")
            print(f"  aws-lambda-layer-cli {GREEN}completion{NC} [options]")
            print("")
            print(f"{BLUE}Options:{NC}")
            print(f"  {YELLOW}--zsh{NC}     Output zsh completion script")
            print(f"  {YELLOW}--bash{NC}    Output bash completion script")
            print("")
            print(f"{MAGENTA}{UNDERLINE}Examples:{NC}")
            print("  # Load completion in current shell")
            print(f"  source <(aws-lambda-layer-cli {GREEN}completion{NC} {YELLOW}--bash{NC})")
            print("")
            print("  # Add to .zshrc")
            print(f"  aws-lambda-layer-cli {GREEN}completion{NC} {YELLOW}--zsh{NC} >> ~/.zshrc")
            raise SystemExit(0)

        completion_dir = assets_dir.parent / "completion"
        shell = ""
        
        if has_zsh:
            shell = "zsh"
        elif has_bash:
            shell = "bash"
            
        if shell == "zsh":
            file = completion_dir / "aws-lambda-layer-completion.zsh"
            if file.exists():
                content = file.read_text(encoding="utf-8")
                # Remove the auto-execution line if present
                import re
                content = re.sub(r'_aws-lambda-layer-cli "\$@"\s*$', "", content)
                print(content)
                print("\n# Register completion")
                print("if type compdef &>/dev/null; then")
                print("  compdef _aws-lambda-layer-cli aws-lambda-layer-cli")
                print("fi")
            else:
                print("Completion script not found for zsh", file=sys.stderr)
                raise SystemExit(1)
        else:
            # bash
            file = completion_dir / "aws-lambda-layer-completion.bash"
            if file.exists():
                print(file.read_text(encoding="utf-8"))
            else:
                print("Completion script not found for bash", file=sys.stderr)
                raise SystemExit(1)
        raise SystemExit(0)

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
