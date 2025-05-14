#!/usr/bin/env python3
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import os
import re
import sys
import time
import argparse
from pathlib import Path
from functools import cached_property
from jinja2 import Environment, FileSystemLoader, select_autoescape

from lib.ftype import CStyle, SHStyle

"""
Used to relicense a list of files
"""
class Relicense:
    LICENSE = "license.j2"

    FILE_TABLE = {
        ".sv"      : CStyle,
        ".v"       : CStyle,
        ".c"       : CStyle,
        ".h"       : CStyle,
        ".ron"     : CStyle,
        ".tcl"     : SHStyle,
        ".py"      : SHStyle,
        ".sh"      : SHStyle,
        ".xdc"     : SHStyle,
        ".sage"    : SHStyle,
        ".csv"     : SHStyle,
        "justfile" : SHStyle,
    }

    # Add jinja template filetypes
    for (k,v) in list(FILE_TABLE.items()):
        FILE_TABLE[k + '.j2'] = v

    def __init__(self):
        self.args = self.parse_args()

    @classmethod
    def parse_args(cls):
        parser = argparse.ArgumentParser(prog='relicense', description='Re-licenses files')

        parser.add_argument('-r', '--license_re', dest='license_re',
            default=r"((\b(BSD|MIT|GPL)\b.*license)|(\bCopyright\b))",
            type=lambda x: re.compile(x, flags=re.IGNORECASE),
            help="A regex expression to match for to detect an old license")
        parser.add_argument('-z', '--removable_re', dest='removable_re',
            default=r"\bCopyright\b.*\bZama\b",
            type=lambda x: re.compile(x, flags=re.IGNORECASE),
            help="A regex expression to match for to detect an old license removable license")
        parser.add_argument('-d', '--directory', dest='directory', default=[Path(".")], type=Path,
            nargs="*", help="The search directory to start the search from")
        parser.add_argument('-t', '--template', dest='template', default="relicense",
            help="""
            The jinja2 template package to use. The package must contain a \"header\" template.
            """)
        parser.add_argument('-g', '--glob', nargs="*", dest='pattern',
            default=[f"*{x}" for x in cls.FILE_TABLE.keys()],
            help="A glob pattern to find files to re-license.")
        parser.add_argument('-y', '--year', dest='year', default=time.gmtime().tm_year,
            help="The year to use to expand the header. Defaults to the current year.")
        parser.add_argument('-o', '--owner', dest='owner', default="ZAMA",
            help="The owner name to license the files to.")
        parser.add_argument('files', nargs="*",
            help="""
            Optional filelist of files to relicense. Can be - to read the file list from stdin.
            """)

        return parser.parse_args()

    """
    Finds and expands the license using the supplied arguments
    """
    @cached_property
    def license(self):
        env = Environment(
            loader=FileSystemLoader(self.args.template),
            autoescape=select_autoescape()
        )
        return env.get_template(self.LICENSE).render(year=self.args.year,
                                                     owner=self.args.owner)

    """
    Finds all the selected files to re-license
    """
    @cached_property
    def files(self):
        files = [Path(x) for x in self.args.files]
        return files + [x for g in self.args.pattern \
                for d in self.args.directory \
                for x in d.rglob(g)]

    def relicense(self, path: 'Path'):
        suffix = "".join(path.suffixes) if len(path.suffixes) else path.stem
        # Do not license a file if we don't know how to
        if not suffix in self.FILE_TABLE:
            return

        ftype = self.FILE_TABLE[suffix](self.args)

        with open(path, 'r') as fd:
            split = ftype.split(fd)

            # If the file is not licensed, add the license in
            if split.header is None:
                split.header = ftype.DefaultHeader(self.args, self.license)
            elif split.header.license.removable:
                split.header.license = self.license
            else: # If we cannot remove a license do nothing
                split = None

        if split is not None:
            with open(path, 'w') as fd:
                print(split, file=fd, end="")

if __name__ == "__main__":
    prog = Relicense()
    for file in prog.files:
        prog.relicense(file)
