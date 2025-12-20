import os

__all__ = ["__version__"]

try:
    with open(os.path.join(os.path.dirname(__file__), "VERSION.txt"), "r") as f:
        __version__ = f.read().strip()
except FileNotFoundError:
    __version__ = "0.0.0"
