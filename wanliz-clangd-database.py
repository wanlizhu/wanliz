#!/usr/bin/env python3
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from multiprocessing import get_context
from pathlib import Path


class Arguments:
    def __init__(self, args: list[str]):
        self.args = args

    def index(self, flag):
        for token_index, token in enumerate(self.args):
            if token == flag:
                return token_index
        return -1
    
    def values_of(self, flag, can_be_joined, remove, required):
        values = []
        for token_index, token in enumerate(self.args):
            if token.startswith(flag):
                if token == flag:
                    if token_index + 1 < len(self.args):
                        values.append(self.args[token_index + 1])
                    else:
                        print(f"Error: missing value of flag {token}")
                        exit(1)
                elif can_be_joined:
                    values.append(token.removeprefix(flag))
                continue 
        if len(values) > 0 and remove:
            self.remove_flag_and_value(flag, can_be_joined)
        if len(values) == 0 and required:
            print(f"Error: cannot find value of flag: {flag}")
            exit(1)

        return values 
    
    def remove_flag_and_value(self, flag, can_be_joined):
        remove_list = []
        for token_index, token in enumerate(self.args):
            if token.startswith(flag):
                if token == flag:
                    remove_list.append(token_index)
                    remove_list.append(token_index + 1)
                elif can_be_joined:
                    remove_list.append(token_index)
        if len(remove_list) > 0:
            temp = []
            for token_index, token in enumerate(self.args):
                if not token_index in remove_list:
                    temp.append(token)
            self.args = temp 


class Clang_CMD:
    def __init__(self, gcc_cmdline, cwd):
        tokens = shlex.split(gcc_cmdline)

        # Locate the begin of subshell
        subshell_index = -1
        for token_index, token in enumerate(tokens):
            if token == "(": 
                subshell_index = token_index
                break 

        # Locate the begin of compile command 
        compiler_index = -1
        for token_index, token in enumerate(tokens):
            if token_index <= subshell_index:
                continue 
            if  os.path.basename(token) in {"gcc", "g++"} or \
                os.path.basename(token).endswith(("-gcc", "-g++")):
                compiler_index = token_index
                break
        if compiler_index < 0:
            print("Error: cannot find compiler token")
            exit(1)

        # Find optional cd command
        working_dir = cwd 
        for token_index in range(subshell_index + 1, compiler_index):
            if tokens[token_index].lstrip("(") == "cd":
                working_dir = Path(tokens[token_index + 1])
                if not working_dir.is_absolute():
                    working_dir = Path(cwd) / working_dir
                working_dir = str(working_dir.resolve(strict=False))

        # Locate the end of compile command 
        compiler_end_index = -1
        for token_index, token in enumerate(tokens):
            if token_index <= compiler_index:
                continue 
            if token == ";":
                compiler_end_index = token_index
                break 
        if compiler_end_index < 0:
            print("Error: cannot find the end of compiler")
            exit(1)

        compiler_and_args = tokens[compiler_index:compiler_end_index]
        self.working_dir = str(working_dir)
        self.gcc_args = Arguments(compiler_and_args[1:])
        self.clang = {
            "directory": "",
            "file": "", 
            "command": ""
        }

    def convert_to_clang_cmdline(self):
        input_file = self.gcc_args.values_of("-c", can_be_joined=False, remove=True, required=True)[0]
        self.clang["directory"] = self.working_dir
        self.clang["file"] = input_file
        if self.clang["file"].endswith(".cpp"):
            if shutil.which("clang++"):
                self.clang["command"] = shutil.which("clang++")
            else:
                print("Error: clang++ is not installed")
                exit(1)
        elif self.clang["file"].endswith(".c"):
            if shutil.which("clang"):
                self.clang["command"] = shutil.which("clang")
            else:
                print("Error: clang is not installed")
                exit(1)
        else:
            print(f"Error: unknown source file \"{self.clang['file']}\"")
            exit(1)

        defines_strs = self.gcc_args.values_of("-D", can_be_joined=True, remove=True, required=False)
        for macro in defines_strs:
            self.clang["command"] += f" -D{macro}"

        self.convert_include_dirs()
        self.convert_compiler_flags()

    def convert_include_dirs(self):
        include_files = self.gcc_args.values_of("-include", can_be_joined=False, remove=True, required=False)
        isystem_dirs = self.gcc_args.values_of("-isystem", can_be_joined=True, remove=True, required=False)
        include_dirs = self.gcc_args.values_of("-I", can_be_joined=True, remove=True, required=False)
        cmdline_substr = ""

        for flag, path, is_dir in (
            *((("-include", value, False) for value in include_files)),
            *((("-isystem", value, True) for value in isystem_dirs)),
            *((("-I", value, True) for value in include_dirs))
        ):
            fullpath = self.resolve_relative_path(self.working_dir, path, required=False)
            if os.path.exists(fullpath):
                cmdline_substr += f" {flag} {fullpath}"
            else:
                if os.path.exists(str(fullpath) + ".gch.cmd"):
                    # Clang cannot parse gcc's .gch file
                    pch_flags = self.extract_pch_flags(str(fullpath) + ".gch.cmd")
                    cmdline_substr += f" {pch_flags}"
                else:
                    print(f"Error: {fullpath} doesn't exist")
                    exit(1)
        self.clang["command"] += cmdline_substr

    def extract_pch_flags(self, pch_path):
        pch_text = Path(pch_path).read_text(encoding="utf-8")
        pch_tokens = shlex.split(pch_text)
        pch_args = Arguments(pch_tokens)
        include_files = pch_args.values_of("-include", can_be_joined=False, remove=True, required=False)
        isystem_dirs = pch_args.values_of("-isystem", can_be_joined=True, remove=True, required=False)
        include_dirs = pch_args.values_of("-I", can_be_joined=True, remove=True, required=False)
        defines_strs = pch_args.values_of("-D", can_be_joined=True, remove=True, required=False)
        cmdline_substr = ""

        for flag, path, is_dir in (
            *((("-include", value, False) for value in include_files)),
            *((("-isystem", value, True) for value in isystem_dirs)),
            *((("-I", value, True) for value in include_dirs))
        ):
            # pch_args.args[0] should be the working dir when the *.gch.cmd generated
            pch_root = pch_args.args[0]
            if not os.path.exists(pch_root) or not os.path.isdir(pch_root):
                print(f"Error: the first word of {Path(pch_root).name} is not a dir")
                exit(1)
            fullpath = self.resolve_relative_path(pch_root, path, required=False)
            if os.path.exists(fullpath):
                cmdline_substr += f" {flag} {fullpath}"
            elif is_dir:
                cmdline_substr += f" {flag} {fullpath}"
        for macro in defines_strs:
            cmdline_substr += f" -D{macro}"
        return cmdline_substr
            
    def resolve_relative_path(self, root, path, required):
        fullpath = Path(path)
        if not fullpath.is_absolute():
            fullpath = Path(root) / Path(path)
        if not fullpath.exists():
            if required:
                print(f"Error: {fullpath} doesn't exist")
                exit(1)
        return str(fullpath)

    def convert_compiler_flags(self):
        bad_flags_with_value = {
            "-MF", "-MT", "-MQ", "-o","-gcc-toolchain",
            "-isysroot", "--sysroot", "-target", "-mllvm",
            "-Xclang", "-Xlinker", "-Xassembler", "-Xpreprocessor",
            "-L", "-l","-fplugin", "-specs"
        }
        bad_flags_no_value = {
            "-M", "-MM", "-MD", "-MMD", "-MG", "-MP","-S", "-E",
            "-shared", "-Winvalid-pch","-fno-reorder-functions", "-fcallgraph-info"
        }
        bad_flags_prefix = {
            "-Wl,", "-Wa,", "-Wp,"
        }

        # Mark bad flags 
        for token_index, token in enumerate(self.gcc_args.args):
            if self.gcc_args.args[token_index].endswith("[to-be-removed]"):
                continue 
            if any(token.startswith(flag) for flag in bad_flags_prefix):
                self.gcc_args.args[token_index] += "[to-be-removed]"
                continue 
            if token in bad_flags_no_value:
                self.gcc_args.args[token_index] += "[to-be-removed]"
                continue 
            for flag in bad_flags_with_value:
                if token == flag:
                    self.gcc_args.args[token_index] += "[to-be-removed]"
                    if (token_index + 1 < len(self.gcc_args.args)):
                        self.gcc_args.args[token_index + 1] += "[to-be-removed]"
                    token += "[to-be-removed]"
                    break 
                elif token.startswith(flag):
                    self.gcc_args.args[token_index] += "[to-be-removed]"
                    token += "[to-be-removed]"
                    break 
            if token.endswith("[to-be-removed]"):
                continue 
        
        # Remove all marked bad flags 
        self.gcc_args.args[:] = [x for x in self.gcc_args.args if not x.endswith("[to-be-removed]")]
        quoted_args = [(f'"{x}"' if " " in x else x) for x in self.gcc_args.args]
        self.clang["command"] += " " + " ".join(quoted_args)


class Clang_CCDB:
    def __init__(self, cwd):
        self.working_dir = cwd 
        self.gcc_cmds = []
        self.commands = []

    def load_gcc_commands(self, path):
        if not Path(path).is_absolute():
            path = str(Path(self.working_dir) / path)
        if not os.path.exists(path):
            print(f"{path} doesn't exist")
            exit(1)

        self.gcc_cmds = []
        with open(path, "r") as file:
            for line in file.readlines():
                line = line.strip()
                if len(line) == 0 or line.startswith("#"):
                    continue 
                self.gcc_cmds.append(line)
        print(f"Found {len(self.gcc_cmds)} gcc commands")
        if len(self.gcc_cmds) == 0:
            exit(1)
        
    def convert_to_clang_commands(self):
        for gcc_cmd in self.gcc_cmds:
            clang_cmd = Clang_CMD(gcc_cmd, self.working_dir)
            clang_cmd.convert_to_clang_cmdline()
            self.commands.append(clang_cmd)

    def save_to_ccdb_json(self):
        entries = []
        for cmd in self.commands:
            entries.append(cmd.clang)
        
        with open("compile_commands.json", "w", encoding="utf-8") as file:
            json.dump(entries, file, indent=4)
        print("Generated compile_commands.json for clangd")


if __name__ == "__main__":
    ccdb = Clang_CCDB(str(Path.cwd()))
    ccdb.load_gcc_commands(sys.argv[1])
    ccdb.convert_to_clang_commands()
    ccdb.save_to_ccdb_json()