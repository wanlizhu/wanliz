#!/usr/bin/env python3
"""
Script to process pushbuffer dump from __GL_ac12fedf=./frame%03d.xml __GL_ac12fede=0x10183

Features:
- Merge consecutive identical lines with repetition count
- Remove dummy NULL data blocks
- Resolve DSO+offset addresses in FRAME nodes using addr2line
- Demangle C++ function names
"""

import sys
import os
import re
import subprocess
import tempfile
from collections import defaultdict


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


def process_frame_content(content):
    pattern = re.compile(r'^([^\s]+)\+0x([0-9a-fA-F]+)$')
    match = pattern.match(content)
    if match:
        dso_path = match.group(1)
        offset = "0x" + match.group(2)
        resolved = resolve_address(dso_path, offset)
        if resolved:
            return resolved
    return content


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


def process_frame_nodes(content):
    pattern = re.compile(r'(<FRAME\s+PC="[^"]*">)([^<]+)(</FRAME>)')
    
    def replacer(match):
        open_tag = match.group(1)
        body = match.group(2)
        close_tag = match.group(3)
        new_body = process_frame_content(body.strip())
        return f"{open_tag}{new_body}{close_tag}"
    
    return pattern.sub(replacer, content)


def process_file(input_path):
    with open(input_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    content = process_frame_nodes(content)
    
    lines = content.splitlines(keepends=True)
    if lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    
    lines = remove_dummy_null_blocks(lines)
    lines = merge_consecutive_lines(lines)
    
    return ''.join(lines)


import glob


def process_single_file(input_path):
    try:
        result = process_file(input_path)
        with open(input_path, 'w', encoding='utf-8') as f:
            f.write(result)
        print(f"Processed: {input_path}")
        return True
    except Exception as e:
        temp_fd, temp_path = tempfile.mkstemp(suffix='.xml', prefix='pushbuffer_partial_')
        try:
            with os.fdopen(temp_fd, 'w', encoding='utf-8') as f:
                if 'result' in dir():
                    f.write(result)
                else:
                    f.write("")
            print(f"Error: Processing failed for {input_path}: {e}", file=sys.stderr)
            print(f"Incomplete data written to: {temp_path}", file=sys.stderr)
        except Exception as write_err:
            print(f"Error: Failed to write temp file: {write_err}", file=sys.stderr)
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
        
        success_count = 0
        fail_count = 0
        for f in files:
            if process_single_file(f):
                success_count += 1
            else:
                fail_count += 1
        
        print(f"Done: {success_count} succeeded, {fail_count} failed")
        if fail_count > 0:
            sys.exit(1)
    else:
        if not process_single_file(input_path):
            sys.exit(1)


if __name__ == "__main__":
    main()
