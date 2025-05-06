# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

from typing import Tuple

class License:
    def __init__(self, removable_re, value = None):
        self._value = value
        self._removable_re = removable_re

    @property
    def removable(self):
        if self._value is None:
            return True
        else:
            return any(self._removable_re.search(x) is not None for x in self._value.splitlines())

    def set(self, value):
        self._value = value

    def defined(self):
        return self._value is not None

    def __str__(self):
        return str(self._value) if self._value is not None else ""

"""
The default empty header
"""
class Header:
    start = None
    end   = None
    delim = ""

    def __init__(self, args, txt):
        self._license = License(args.removable_re)
        if args.license_re.search(txt) is not None:
            self.license = txt
            self.header = None
        else:
            self.header = txt

    """
    Get and set the license
    """
    @property
    def license(self):
        return self._license

    @license.setter
    def license(self, value):
        self._license.set(value)

    """
    Tries to match this particular header against the given file contents.
    Raises an exception if the header does not match.
    """
    @classmethod
    def read(cls, args, txt) -> 'Self':
        pass

    """
    Renders the header
    """
    def __str__(self) -> str:
        lic = (str(self.license), self.delim) if self.license.defined() else ()
        parts = (
            self.start,
            *lic,
            self.header,
            self.end
        )
        return "\n".join(filter(lambda x: x is not None, parts))

class UnmatchedHeader(Exception):
    pass

class HeaderReader:
    headers = []

    @classmethod
    def read(cls, args, txt) -> 'Header':
        from .section_header import SecHeader
        for h in cls.headers:
            try:
                return h.read(args, txt)
            except UnmatchedHeader:
                pass
        raise UnmatchedHeader()

# The main idea here is to allow for multiple header types to be registered in independent modules.
# Turns out we only got two registered, but who knows the future.

def register_header(cls):
    HeaderReader.headers.append(cls)
    return cls
