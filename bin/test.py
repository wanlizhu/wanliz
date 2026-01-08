#!/usr/bin/env python3

from pathlib import Path

def find_non_utf8_txt(root_dir: str | Path) -> list[Path]:
    root = Path(root_dir)
    for path in root.rglob("*.txt"):
        if not path.is_file():
            continue
        try:
            path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            print(path)

if __name__ == "__main__":
    find_non_utf8_txt
