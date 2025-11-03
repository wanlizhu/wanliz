#!/usr/bin/env python3
import io 
import os 
import sys 
import zipfile
import subprocess
import datetime
import re
import zipfile 
import xml.etree.ElementTree as ET 
import tkinter as tk
from pathlib import Path, PurePosixPath 
from tkinter import filedialog

class RAGDoc_docx:
    def __init__(self, path: Path):
        self.names = [
            "word/document.xml", 
            "word/comments.xml", 
            "word/footnotes.xml", 
            "word/endnotes.xml"
        ]
        self.path = path 

    def normalize(self):
        with zipfile.ZipFile(self.path) as zipfile:
            names = set(zipfile.namelist())
            parts = [p for p in self.names if p in names] 
            parts = parts + sorted(n for n in names 
                                if n.startswith("word/") 
                                and n.endswith(".xml") 
                                and ("/header" in n or "/footer" in n))
            sections = []
            for part in parts:
                text = self.__extract_text(zipfile, str(part))
                if text is None: continue 
                sections.append(f"## {PurePosixPath(part).name}\n{text}\n")
        
        with open(self.path + ".txt", mode="w") as output:
            output.writelines(sections)

    def __extract_text(self, zipfile: zipfile.ZipFile, part: str):
        root = ET.fromstring(zipfile.read(part)) 
        if root is None: return None 

        _is = lambda node, local: isinstance(node.tag, str) and (node.tag == local or node.endswith("}" + local))
        out = []
        for p in root.iter():
            if _is(p, "p"):  
                buf = []
                for node in p.iter():
                    if _is(node, "t") and node.text: buf.append(node.text)
                    elif _is(node, "tab"): buf.append("\t")
                    elif _is(node, "br"): buf.append("\n")
                line = "".join(buf).replace("\r\n", "\n").replace("\r", "\n")
                line = re.sub(r"[ \t\u00A0]+", " ", line)
                line = re.sub(r"\n{3,}", "\n\n", line)
                line = line.strip()
                out.append(line if line else "")
            elif _is(p, "tc") and not any(_is(c, "p") for c in p.iter()):
                text = "".join(p.itertext())
                out.append(text if text else "")
            
        return "\n".join(out).strip()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        folder = sys.argv[1]
    else:
        root = tk.Tk()
        root.withdraw()
        root.update_idletasks()
        folder = filedialog.askdirectory(
            title="Select Folder to Process",
            initialdir=os.getcwd(),
            mustexist=True
        )
        root.destroy()

    for root, dirs, files in os.walk(folder, topdown=True, followlinks=False):
        dirs[:] = [d for d in dirs if d not in [".git", "__pycache__"]]
        for file in files:
            try:
                if file.endswith(".docx"):
                    ok = RAGDoc_docx(Path(root) / file).normalize()
                else: raise RuntimeError(f"Ignore file {file}")
            except Exception as e:
                print(f"{type(e).__name__}: {e}", file=sys.stderr)
                continue 
            print(f"{file} \t {' [ OK ] ' if ok else ' [ FAILED ] '}")
