# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import re
from itertools import takewhile
from typing import Iterable, Any
from .header import Header, UnmatchedHeader, License, register_header
from .section_header import SecHeader

@register_header
class SimpleHeader(SecHeader):
    start = None
    end   = None
    delim = "\n\n"
    # This is the fallback header, matches everything
    header_re = re.compile(r'.*')
    delim_re = re.compile(r'^\s*$')

    @classmethod
    def read(cls, args, txt) -> 'SecHeader':
        return SimpleHeader(args, cls._iter_sections(txt))
