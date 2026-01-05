#!/usr/bin/env python3
"""
Process pushbuffer XML dumps: resolve symbols, simplify callstacks, remove noise, format output.
Usage: process-pushbuffer-dump.py <file.xml or directory>
"""

import sys, os, re, subprocess, tempfile, glob
import multiprocessing as mp
from multiprocessing import Pool, Manager
from xml.etree import ElementTree as ET

VK_ENTRY_POINTS = [
    "vkCreateDevice", "vkDestroyDevice", "vkCreateInstance", "vkDestroyInstance",
    "vkEnumerateInstanceExtensionProperties", "vkEnumerateInstanceLayerProperties",
]

class PushbufferProcessor:
    def __init__(self, filepath):
        self.filepath = filepath
        self.content = ""
        self.resolved_symbols = {}

    def run(self):
        print(f"  Reading file...")
        with open(self.filepath, 'r', encoding='utf-8', errors='replace') as f:
            self.content = f.read()
        self._resolve_symbols_parallel()
        self._apply_resolved_symbols()
        self._simplify_gpfifo_entries()
        self._remove_dummy_null_blocks()
        self._merge_consecutive_lines()
        self._format_xml_indent()
        print(f"  Writing output...")
        with open(self.filepath, 'w', encoding='utf-8') as f:
            f.write(self.content)

    def _resolve_symbols_parallel(self):
        print(f"  Extracting FRAME bodies...")
        pattern = re.compile(r'<FRAME\s+PC="[^"]*">([^<]+)</FRAME>')
        unique_bodies = {m.group(1).strip() for m in pattern.finditer(self.content) if '+0x' in m.group(1)}
        if not unique_bodies:
            print(f"  No symbols to resolve")
            return
        num_cpus = mp.cpu_count()
        total = len(unique_bodies)
        print(f"  Resolving {total} unique symbols using {num_cpus} processes...")
        manager = Manager()
        counter, lock = manager.Value('i', 0), manager.Lock()
        args_list = [(body, counter, lock) for body in unique_bodies]
        with Pool(processes=num_cpus) as pool:
            async_result = pool.map_async(_resolve_single_frame, args_list)
            while not async_result.ready():
                async_result.wait(timeout=0.5)
                with lock:
                    done = counter.value
                print(f"\r  Symbol resolution progress: {done}/{total} ({done*100//total}%)", end="", flush=True)
            print(f"\r  Symbol resolution progress: {total}/{total} (100%)")
            self.resolved_symbols = {body: resolved for body, resolved in async_result.get() if resolved}

    def _apply_resolved_symbols(self):
        if not self.resolved_symbols:
            return
        print(f"  Applying {len(self.resolved_symbols)} resolved symbols...")
        def replacer(m):
            body = m.group(2).strip()
            resolved = self.resolved_symbols.get(body, body)
            return f'{m.group(1)}{resolved}{m.group(3)}'
        self.content = re.sub(r'(<FRAME\s+PC="[^"]*">)([^<]+)(</FRAME>)', replacer, self.content)

    def _simplify_gpfifo_entries(self):
        print(f"  Simplifying GPFIFOENTRY nodes...")
        pattern = re.compile(r'(<GPFIFOENTRY[^>]*>)(.*?)(</GPFIFOENTRY>)', re.DOTALL)
        def replacer(m):
            open_tag, body, close_tag = m.group(1), m.group(2), m.group(3)
            callstack_match = re.search(r'<CALLSTACK[^>]*>(.*?)</CALLSTACK>', body, re.DOTALL)
            if callstack_match:
                callstack_content = callstack_match.group(1)
                for vk_func in VK_ENTRY_POINTS:
                    if vk_func in callstack_content:
                        return f'{open_tag}\n Ignored calls from {vk_func}\n{close_tag}'
            return m.group(0)
        self.content = pattern.sub(replacer, self.content)

    def _remove_dummy_null_blocks(self):
        print(f"  Removing dummy NULL data blocks...")
        lines, result, i = self.content.splitlines(keepends=True), [], 0
        if lines and not lines[-1].endswith('\n'):
            lines[-1] += '\n'
        while i < len(lines):
            if lines[i].strip() == "// dummy NULL data":
                j = i + 1
                while j < len(lines) and lines[j].strip() == "0x00000000\t//\t\tLoadInlineData(0x0)":
                    j += 1
                if j > i + 1:
                    i = j
                    continue
            result.append(lines[i])
            i += 1
        self.content = ''.join(result)

    def _merge_consecutive_lines(self):
        print(f"  Merging consecutive lines...")
        lines, result, i = self.content.splitlines(keepends=True), [], 0
        while i < len(lines):
            current, count = lines[i], 1
            while i + count < len(lines) and lines[i + count] == current:
                count += 1
            if count > 1:
                result.append(f"{current.rstrip()}  // x{count}\n")
            else:
                result.append(current)
            i += count
        self.content = ''.join(result)

    def _format_xml_indent(self):
        print(f"  Formatting XML indentation...")
        lines, result, indent_level = self.content.splitlines(), [], 0
        open_tag = re.compile(r'^<(\w+)(?:\s[^>]*)?>(?!.*</\1>)')
        close_tag = re.compile(r'^</(\w+)>')
        self_close = re.compile(r'^<[^>]+/>')
        full_tag = re.compile(r'^<(\w+)[^>]*>.*</\1>$')
        for line in lines:
            stripped = line.strip()
            if not stripped:
                result.append("")
                continue
            if close_tag.match(stripped):
                indent_level = max(0, indent_level - 1)
            result.append("    " * indent_level + stripped)
            if open_tag.match(stripped) and not self_close.match(stripped) and not full_tag.match(stripped):
                indent_level += 1
        self.content = '\n'.join(result) + '\n'


def _demangle(symbol):
    if not symbol or symbol == "??" or not symbol.startswith("_Z"):
        return symbol
    try:
        r = subprocess.run(["c++filt", symbol], capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else symbol
    except:
        return symbol

def _resolve_single_frame(args):
    body, counter, lock = args
    result = None
    m = re.match(r'^([^\s]+)\+0x([0-9a-fA-F]+)$', body)
    if m:
        dso_path, offset = m.group(1), "0x" + m.group(2)
        if os.path.exists(dso_path):
            try:
                r = subprocess.run(["addr2line", "-f", "-e", dso_path, offset],
                                   capture_output=True, text=True, timeout=10)
                if r.returncode == 0:
                    func = r.stdout.strip().split("\n")[0].strip()
                    if func and func != "??":
                        result = _demangle(func)
            except:
                pass
    with lock:
        counter.value += 1
    return (body, result)

def process_single_file(filepath, file_idx=None, total_files=None):
    prefix = f"[{file_idx}/{total_files}] " if file_idx else ""
    print(f"{prefix}Processing: {filepath}")
    try:
        PushbufferProcessor(filepath).run()
        print(f"  Done: {filepath}")
        return True
    except Exception as e:
        fd, tmp = tempfile.mkstemp(suffix='.xml', prefix='pushbuffer_partial_')
        os.close(fd)
        print(f"  Error: {e}", file=sys.stderr)
        print(f"  Partial output: {tmp}", file=sys.stderr)
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
        files = sorted(glob.glob(os.path.join(input_path, "frame*.xml")))
        if not files:
            print(f"No frame*.xml files found in: {input_path}", file=sys.stderr)
            sys.exit(1)
        print(f"Found {len(files)} dump file(s) to process\n")
        results = [process_single_file(f, i+1, len(files)) for i, f in enumerate(files)]
        print()
        success, fail = sum(results), len(results) - sum(results)
        print(f"All done: {success} succeeded, {fail} failed")
        if fail > 0:
            sys.exit(1)
    else:
        if not process_single_file(input_path):
            sys.exit(1)

if __name__ == "__main__":
    main()
