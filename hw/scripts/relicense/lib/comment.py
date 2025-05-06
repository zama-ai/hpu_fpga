# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.

import re
from functools import reduce

class CommentStyle:
    @classmethod
    def comment(cls, txt) -> str:
        pass

    @classmethod
    def uncomment(cls, txt) -> str:
        pass

class CLineComment(CommentStyle):
    comment_re = re.compile(
        r"\s*((\/\/(?P<line>[^\n]*\n?))|(\/(?P<block>\*([*](?!\/)|[^*])*)\*\/))"
    )
    indent_re = re.compile(r"[\s\*#]*")

    @classmethod
    def comment(cls, txt) -> str:
        return "\n".join(f"// {x}" for x in txt.splitlines())

    @classmethod
    def unindent(cls, txt) -> str:
        lines = txt.splitlines()
        ind = reduce(lambda acc, x: min(acc, len(cls.indent_re.match(x)[0])), 
                     filter(len, map(lambda x: x.rstrip(), txt.splitlines())),
                     len(txt))
        return "\n".join(x[ind:] for x in lines)

    """
    Uncomments any kind of C comment
    """
    @classmethod
    def uncomment(cls, txt) -> str:
        return cls.unindent(cls.comment_re.sub(r'\g<line>\g<block>', txt))

class CBlockComment(CLineComment):
    @classmethod
    def comment(cls, txt) -> str:
        txt = "/* " + txt + "*/"
        return "\n   ".join(txt.splitlines())

class ShComment(CLineComment):
    comment_re = re.compile(r"\s*#([^\n]*\n?)")

    @classmethod
    def comment(cls, txt) -> str:
        return "\n".join(f"# {x}" for x in txt.splitlines())

    """
    Uncomments any kind of C comment
    """
    @classmethod
    def uncomment(cls, txt) -> str:
        return cls.unindent(cls.comment_re.sub(r'\1', txt))
