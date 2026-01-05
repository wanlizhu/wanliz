#!/usr/bin/env python3
"""
Script to process pushbuffer dump from __GL_ac12fedf=./frame%03d.xml __GL_ac12fede=0x10183

Features:
- Merge consecutive identical lines with repetition count
- Remove dummy NULL data blocks
- Resolve DSO+offset addresses in FRAME nodes using addr2line (multiprocessing)
- Demangle C++ function names
"""

import sys
import os
import re
import subprocess
import tempfile
import glob
import multiprocessing as mp
from multiprocessing import Pool, Manager


def demangle_symbol(symbol):
    if not symbol or symbol == "??":
        return symbol
    if not symbol.startswith("_Z"):
        return symbol
    try:
        result = subprocess.run(
            ["c++filt", symbol],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return symbol


def resolve_address(dso_path, offset):
    if not os.path.exists(dso_path):
        return None
    try:
        result = subprocess.run(
            ["addr2line", "-f", "-e", dso_path, offset],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            lines = result.stdout.strip().split("\n")
            if len(lines) >= 1:
                func_name = lines[0].strip()
                if func_name and func_name != "??":
                    return demangle_symbol(func_name)
    except Exception:
        pass
    return None


def resolve_single_frame(args):
    body, counter, lock = args
    pattern = re.compile(r'^([^\s]+)\+0x([0-9a-fA-F]+)$')
    match = pattern.match(body)
    result = None
    if match:
        dso_path = match.group(1)
        offset = "0x" + match.group(2)
        resolved = resolve_address(dso_path, offset)
        if resolved:
            result = resolved
    with lock:
        counter.value += 1
    return (body, result)


def resolve_frames_parallel(unique_bodies):
    if not unique_bodies:
        return {}

    num_cpus = mp.cpu_count()
    total = len(unique_bodies)

    print(f"  Resolving {total} unique symbols using {num_cpus} processes...")

    manager = Manager()
    counter = manager.Value('i', 0)
    lock = manager.Lock()

    args_list = [(body, counter, lock) for body in unique_bodies]

    results = {}
    with Pool(processes=num_cpus) as pool:
        async_result = pool.map_async(resolve_single_frame, args_list)

        while not async_result.ready():
            async_result.wait(timeout=0.5)
            with lock:
                done = counter.value
            pct = (done * 100) // total if total > 0 else 100
            print(f"\r  Symbol resolution progress: {done}/{total} ({pct}%)", end="", flush=True)

        print(f"\r  Symbol resolution progress: {total}/{total} (100%)")

        for body, resolved in async_result.get():
            if resolved:
                results[body] = resolved

    return results


def extract_frame_bodies(content):
    pattern = re.compile(r'<FRAME\s+PC="[^"]*">([^<]+)</FRAME>')
    bodies = set()
    for match in pattern.finditer(content):
        body = match.group(1).strip()
        if '+0x' in body:
            bodies.add(body)
    return bodies


def apply_resolved_symbols(content, resolved_map):
    pattern = re.compile(r'(<FRAME\s+PC="[^"]*">)([^<]+)(</FRAME>)')

    def replacer(match):
        open_tag = match.group(1)
        body = match.group(2).strip()
        close_tag = match.group(3)
        if body in resolved_map:
            return f"{open_tag}{resolved_map[body]}{close_tag}"
        return match.group(0)

    return pattern.sub(replacer, content)


def is_dummy_null_line(line):
    stripped = line.strip()
    return stripped == "0x00000000\t//\t\tLoadInlineData(0x0)"


def is_dummy_null_comment(line):
    stripped = line.strip()
    return stripped == "// dummy NULL data"


def merge_consecutive_lines(lines):
    if not lines:
        return []

    result = []
    i = 0

    while i < len(lines):
        current_line = lines[i]
        count = 1

        while i + count < len(lines) and lines[i + count] == current_line:
            count += 1

        if count > 1:
            stripped = current_line.rstrip('\n')
            result.append(f"{stripped}  // x{count}\n")
        else:
            result.append(current_line)

        i += count

    return result


def remove_dummy_null_blocks(lines):
    result = []
    i = 0

    while i < len(lines):
        if is_dummy_null_comment(lines[i]):
            j = i + 1
            while j < len(lines) and is_dummy_null_line(lines[j]):
                j += 1
            if j > i + 1:
                i = j
                continue
        result.append(lines[i])
        i += 1

    return result


def process_file(input_path):
    print(f"  Reading file...")
    with open(input_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    print(f"  Extracting FRAME bodies...")
    unique_bodies = extract_frame_bodies(content)

    resolved_map = resolve_frames_parallel(unique_bodies)

    print(f"  Applying resolved symbols...")
    content = apply_resolved_symbols(content, resolved_map)

    print(f"  Removing dummy NULL data blocks...")
    lines = content.splitlines(keepends=True)
    if lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'

    lines = remove_dummy_null_blocks(lines)

    print(f"  Merging consecutive lines...")
    lines = merge_consecutive_lines(lines)

    return ''.join(lines)


def process_single_file(input_path, file_idx=None, total_files=None):
    if file_idx is not None and total_files is not None:
        print(f"[{file_idx}/{total_files}] Processing: {input_path}")
    else:
        print(f"Processing: {input_path}")

    try:
        result = process_file(input_path)
        print(f"  Writing output...")
        with open(input_path, 'w', encoding='utf-8') as f:
            f.write(result)
        print(f"  Done: {input_path}")
        return True
    except Exception as e:
        temp_fd, temp_path = tempfile.mkstemp(suffix='.xml', prefix='pushbuffer_partial_')
        try:
            with os.fdopen(temp_fd, 'w', encoding='utf-8') as f:
                if 'result' in dir():
                    f.write(result)
                else:
                    f.write("")
            print(f"  Error: Processing failed: {e}", file=sys.stderr)
            print(f"  Incomplete data written to: {temp_path}", file=sys.stderr)
        except Exception as write_err:
            print(f"  Error: Failed to write temp file: {write_err}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <pushbuffer_dump.xml or directory>", file=sys.stderr)
        sys.exit(1)

    input_path = sys.argv[1]

    if not os.path.exists(input_path):
        print(f"Error: Path not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    if os.path.isdir(input_path):
        pattern = os.path.join(input_path, "frame*.xml")
        files = sorted(glob.glob(pattern))
        if not files:
            print(f"No frame*.xml files found in: {input_path}", file=sys.stderr)
            sys.exit(1)

        total_files = len(files)
        print(f"Found {total_files} dump file(s) to process")
        print()

        success_count = 0
        fail_count = 0
        for idx, f in enumerate(files, 1):
            if process_single_file(f, idx, total_files):
                success_count += 1
            else:
                fail_count += 1
            print()

        print(f"All done: {success_count} succeeded, {fail_count} failed")
        if fail_count > 0:
            sys.exit(1)
    else:
        if not process_single_file(input_path):
            sys.exit(1)


if __name__ == "__main__":
    main()
