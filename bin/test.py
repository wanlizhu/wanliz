#!/usr/bin/env python3

from pathlib import Path

text_exts = {
    ".txt", ".text", ".log", ".md", ".rst", ".csv", ".tsv",
    ".json", ".yaml", ".yml", ".xml", ".ini", ".cfg", ".conf",
    ".toml", ".properties", ".env",
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".hxx",
    ".py", ".pyi", ".sh", ".bash", ".zsh", ".fish",
    ".ps1", ".bat", ".cmd",
    ".js", ".jsx", ".ts", ".tsx",
    ".java", ".kt", ".go", ".rs", ".swift",
    ".html", ".htm", ".css", ".scss", ".less",
    ".sql", ".proto",
}

def find_non_utf8_txt(root_dir: str | Path):
    root = Path(root_dir)
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in text_exts:
            continue
        try:
            path.read_bytes().decode("utf-8")
        except UnicodeDecodeError:
            print(path)

if __name__ == "__main__":
    find_non_utf8_txt("/root/SinglePassCapture")

# ./SinglePassCapture/pic-x --clean=0 --check_clocks=0 --present=0 --sleep=3 --time=1 --api=vk --exe=./vulkanbench --arg="-p img"