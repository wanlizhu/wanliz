#!/usr/bin/env python3
import os
from textwrap import wrap
from unittest import result
import uuid
import time
from functools import wraps
from pathlib import Path


class NVMake_referredDirs:
    def __init__(self):
        self.repo_root = "/home/wanliz/sw"
        self.root = Path(self.repo_root).resolve()
        self.min_size_mb = 10
        self.marker_file = "zzz-nvmake-referred-dir"
        self.exclude_names = [
            "_out", ".git", ".vscode", ".cursor", 
            "__pycache__", ".cache"
        ]
        self.elapsed_seconds = 0

    def track_elapsed_seconds(func):
        @wraps(func)
        def wrapper(self, *args, **kwargs):
            start = time.time()
            result = func(self, *args, *kwargs)
            self.elapsed_seconds = time.time() - start 
            return result 
        return wrapper

    def run(self):
        min_bytes = self.min_size_mb * 1024 * 1024
        dir_sizes = [(path, self._size(path)) for path in self._dirs(self.root)]
        candidates = [
            (path, size_bytes)
            for (path, size_bytes) in dir_sizes
            if size_bytes >= min_bytes
            and not self._excluded(path)
        ]
        candidates.sort(key=lambda item: item[1], reverse=True)
        num_dirs_total = len(candidates)
        num_dirs_not_tested = num_dirs_total
        num_dirs_referred = 0
        eta = "-"

        for dir_path, _size_bytes in candidates:
            print(f"To be tested: {num_dirs_not_tested} dirs (eta: {eta})\t[Found {num_dirs_referred} not-referred dirs]")
            if self._is_dir_referred(dir_path):
                num_dirs_referred += 1
            num_dirs_not_tested -= 1
            eta = self._update_eta(num_dirs_not_tested)
            
    def _update_eta(self, num_dirs_not_tested) -> str:
        eta_seconds = self.elapsed_seconds * num_dirs_not_tested
        if eta_seconds < 60:
            return f"{int(eta_seconds)}s"
        elif eta_seconds < 3600:
            minutes = int(eta_seconds / 60)
            secs = int(eta_seconds % 60)
            return f"{minutes}m {secs}s"
        else:
            hours = int(eta_seconds / 3600)
            minutes = int((eta_seconds % 3600) / 60)
            return f"{hours}h {minutes}m"

    def _dirs(self, start: Path):
        stack = [start]
        out = []
        while stack:
            try:
                current_dir = stack.pop()
                with os.scandir(current_dir) as it:
                    for entry in it:
                        if entry.is_dir(follow_symlinks=False) and entry.name not in self.exclude_names:
                            subdir_path = Path(entry.path)
                            out.append(subdir_path)
                            stack.append(subdir_path)
            except (PermissionError, OSError):
                continue
        return out

    def _size(self, dir_path: Path) -> int:
        total = 0
        stack = [dir_path]
        while stack:
            try:
                current_dir = stack.pop()
                with os.scandir(current_dir) as it:
                    for entry in it:
                        if entry.is_symlink():
                            continue
                        if entry.is_file(follow_symlinks=False):
                            total += entry.stat(follow_symlinks=False).st_size
                        elif entry.is_dir(follow_symlinks=False) and entry.name not in self.exclude_names:
                            stack.append(Path(entry.path))
            except (PermissionError, OSError):
                continue
        return total

    def _excluded(self, dir_path: Path) -> bool:
        if any(component in self.exclude_names for component in dir_path.parts):
            return True
        if dir_path.name.endswith("-not-referred"):
            return True
        if self._has_marker_file(dir_path):
            return True
        return False

    def _has_marker_file(self, dir_path: Path) -> bool:
        if (dir_path / self.marker_file).exists():
            return True
        stack = [dir_path]
        while stack:
            current_dir = stack.pop()
            try:
                with os.scandir(current_dir) as it:
                    for entry in it:
                        if entry.is_symlink():
                            continue
                        if entry.is_file(follow_symlinks=False) and entry.name == self.marker_file:
                            return True
                        elif entry.is_dir(follow_symlinks=False) and entry.name not in self.exclude_names:
                            stack.append(Path(entry.path))
            except (PermissionError, OSError):
                continue
        return False

    @track_elapsed_seconds
    def _is_dir_referred(self, original_dir: Path) -> bool:
        parent_dir = original_dir.parent
        base_name = original_dir.name
        tmp_dir = parent_dir / f"{base_name}-testing"
    
        os.rename(original_dir, tmp_dir)
        if self.build():
            os.rename(tmp_dir, original_dir)
            marker_file = original_dir / self.marker_file
            marker_file.touch()
            return False
        else:
            found_name = f"{base_name}-not-referred"
            found_dir = parent_dir / found_name
            os.rename(tmp_dir, found_dir)
            return True

    def build(self) -> bool:
        raise NotImplementedError


if __name__ == "__main__":
    NVMake_referredDirs().run()