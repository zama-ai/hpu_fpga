# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import re
from .comment import CLineComment, ShComment
from .header import HeaderReader, Header, UnmatchedHeader
from .section_header import SecHeader

class SplitFile:
    def __init__(self, shebang, header, contents):
        self.shebang = shebang
        self.header = header
        self.contents = contents

    def __str__(self):
        header = () if self.header is None else \
                (str(self.header),"")
        parts = (self.shebang, *header, self.contents.lstrip())
        return "\n".join(filter(lambda x: x is not None, parts))

class FileType:
    def __init__(self, args, comment_style):
        self._args = args
        self._comstyle = comment_style

    def comment(self, txt) -> str:
        return self._comstyle.comment(txt)

    def uncomment(self, txt) -> str:
        return self._comstyle.uncomment(txt)

    def split(self, txt) -> 'SplitFile':
        pass

    def DefaultHeader(self, args, lic):
        return self.commented_header(SecHeader(args, [lic]))

    def commented_header(self, header):
        comment = self.comment
        class _Header(Header):
            def __init__(self, header):
                self.__dict__.update(header.__dict__)
                self.__str__ = Header.__str__

            def __str__(self):
                # Take the chance to remove spaces at eol
                lines = comment(str(header)).splitlines()
                return "\n".join(map(lambda x: x.rstrip(), lines))
        return _Header(header)


class SHStyle(FileType):
    header_re = re.compile(
        r"(?P<header>((((\s*#[^\n]*)+)|\s*)\n?)+)"
    )

    def __init__(self, args):
        super().__init__(args, ShComment)

    def split(self, fd) -> 'SplitFile':
        # Read the wholefile
        txt = fd.read()

        shebang = None
        header = None
        contents = None

        try:
            # Extract the shebang, if any
            first, left = txt.split("\n", maxsplit=1)
            if first.startswith("#!"):
                shebang = first
                txt = left
            else:
                shebang = None

            match = self.header_re.match(txt)
            if match is not None and match.groupdict()['header'] is not None:
                header = match.groupdict()['header']
                uncommented = self.uncomment(header)
                header = self.commented_header(HeaderReader.read(self._args, uncommented))
                contents = txt[match.end():]
            else:
                header = None
                contents = txt
        except ValueError:
            header = None
            contents = txt
        except UnmatchedHeader:
            header = None
            contents = txt

        return SplitFile(shebang, header, contents)

class CStyle(SHStyle):
    header_re = re.compile(
        r"\s*(?P<header>((\/\*([*](?!\/)|[^*])*\*\/)|((\/\/[^\n]*\n?))|(\s*\n?))+)"
    )

    def __init__(self, args):
        FileType.__init__(self, args, CLineComment)
