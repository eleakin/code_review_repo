"""URL slug generation utilities."""

import re
import unicodedata

_NON_WORD = re.compile(r"[^\w\s-]")
_WHITESPACE = re.compile(r"[\s_-]+")


def slugify(text: str, max_length: int = 80) -> str:
    """Convert arbitrary text into a URL-safe slug.

    Normalizes unicode to ASCII, lowercases, strips punctuation, and
    collapses whitespace/underscores/hyphens into single hyphens.

    >>> slugify("Hello, World!")
    'hello-world'
    >>> slugify("Déjà Vu — Again")
    'deja-vu-again'
    """
    if max_length < 1:
        raise ValueError("max_length must be at least 1")

    ascii_text = (
        unicodedata.normalize("NFKD", text)
        .encode("ascii", "ignore")
        .decode("ascii")
    )
    cleaned = _NON_WORD.sub("", ascii_text.lower())
    slug = _WHITESPACE.sub("-", cleaned).strip("-")

    if len(slug) <= max_length:
        return slug
    # Truncate on a hyphen boundary where possible so words stay intact.
    truncated = slug[:max_length]
    if "-" in truncated and slug[max_length] != "-":
        truncated = truncated.rsplit("-", 1)[0]
    return truncated.rstrip("-")
