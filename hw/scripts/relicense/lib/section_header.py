# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import re
from itertools import takewhile
from typing import Iterable, Any
from .header import Header, UnmatchedHeader, License, register_header

def group_delim(i: Iterable[Any], delim: 'f(x) -> bool'):
    i = iter(i)
    lst = []
    try:
        while True:
            nxt = next(i)
            if delim(nxt):
                yield lst
                lst = []
            else:
                lst.append(nxt)
    except StopIteration:
        if len(lst):
            yield lst

@register_header
class SecHeader(Header):
    start = "==============================================================================================\n"
    end   = "\n==============================================================================================\n"
    delim = "\n----------------------------------------------------------------------------------------------\n"
    # A sectioned header matches if something resembling a separator is found
    header_re = re.compile(r'(^|\n)\s*([#=-])\2{2,}[\/#*\s]*(\n|$)')
    delim_re = re.compile(r'^\s*[=\-\/\*\s#]+\s*$')

    def __init__(self, args, sections: Iterable[str]):
        self._args = args
        self._sections = list(sections)
        self._license = License(args.removable_re)

        try:
            idx, self.license = next(filter(lambda x: args.license_re.search(x[1]) is not None,
                                            enumerate(self._sections)))
            self._sections[idx] = self._license
        except StopIteration:
            self._sections.insert(0, self._license)

    @classmethod
    def _iter_sections(cls, txt):
        return map(lambda x: "\n".join(x), 
                   group_delim(txt.splitlines(), lambda x: cls.delim_re.match(x)))

    @classmethod
    def read(cls, args, txt) -> 'SecHeader':
        if cls.header_re.search(txt) is None:
            raise UnmatchedHeader()
        return SecHeader(args, cls._iter_sections(txt))

    @staticmethod
    def valid_section(s):
        return s is not None and len(s)

    def __str__(self) -> str:
        parts = (
            self.start, 
            self.delim.join(filter(self.valid_section, map(str, self._sections))),
            self.end
        )
        return "".join(filter(lambda x: x is not None, parts))
