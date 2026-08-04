"""Fail on relative documentation links that resolve to a page which does not exist.

This site emits relative ``href`` values verbatim into the HTML, so the browser
resolves them against the **page URL**, not against the source file path. That
makes ``./target/`` correct only on an *index* page, whose URL already ends at
the directory. On a non-index page such as ``customer-edge/lifecycle.mdx``,
whose URL is ``/en/customer-edge/lifecycle/``, a link written ``./access/ssh/``
resolves to ``/en/customer-edge/lifecycle/access/ssh/`` and returns 404.

Nothing else catches this. The prose linter does not resolve links, the
translation audit only compares hashes, and the site build does not fail on a
dangling relative link — so the first report is a reader hitting a 404 in
published documentation. Three such links reached production before this check
existed (issue #828).

Only ``docs/en`` is checked, because it is the authored source of truth. Locale
trees are generated from it by the translation pipeline and link paths are not
translated, so a corrected English link propagates on the next regeneration.

Absolute paths, external URLs, ``mailto:`` and pure fragments are out of scope:
they do not depend on the page URL. Fenced code blocks are stripped first, so a
link inside an example is documentation rather than a link to verify.

Exit 0 means every relative link resolves, 1 means findings, and 2 means the
check could not run.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import urljoin

if TYPE_CHECKING:
    from collections.abc import Iterator

EXIT_OK = 0
EXIT_FINDINGS = 1
EXIT_ERROR = 2

DOCS_ROOT = Path("docs")
SOURCE_LOCALE = "en"

FENCE_RE = re.compile(r"(?ms)^(?:```|~~~).*?^(?:```|~~~)[ \t]*$")
MARKDOWN_LINK_RE = re.compile(r"\]\(([^)\s]+)\)")
HREF_RE = re.compile(r"""href=['"]([^'"]+)['"]""")
NOT_PAGE_RELATIVE_RE = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//|/|#)")


def page_url(path: Path, root: Path) -> str:
    """Return the published URL path for a documentation source file."""
    parts = path.relative_to(root).with_suffix("").parts
    if parts[-1] == "index":
        parts = parts[:-1]
    return "/" + "".join(f"{part}/" for part in parts)


def link_targets(raw: str) -> Iterator[str]:
    """Yield every page-relative link target in a document."""
    body = FENCE_RE.sub("", raw)
    for pattern in (MARKDOWN_LINK_RE, HREF_RE):
        for match in pattern.finditer(body):
            target = match.group(1)
            if not NOT_PAGE_RELATIVE_RE.match(target):
                yield target


def normalize(url: str) -> str:
    """Compare on directory URLs; a trailing slash is not a meaningful difference."""
    base, _, fragment = url.partition("#")
    del fragment
    base, _, query = base.partition("?")
    del query
    return base if base.endswith("/") else base + "/"


def main() -> int:
    """Check English pages' relative links and report the ones that resolve nowhere."""
    root = DOCS_ROOT
    if not root.is_dir():
        sys.stderr.write(f"{root}/ not found — run from the repository root\n")
        return EXIT_ERROR

    pages = {page_url(f, root): f for f in sorted(root.rglob("*.mdx"))}
    if not pages:
        sys.stderr.write(f"no .mdx pages found under {root}/\n")
        return EXIT_ERROR

    prefix = f"/{SOURCE_LOCALE}/"
    sources = {url: f for url, f in pages.items() if url.startswith(prefix)}
    if not sources:
        sys.stderr.write(f"no pages found under {root}/{SOURCE_LOCALE}/\n")
        return EXIT_ERROR

    findings = 0
    checked = 0
    for url, path in sorted(sources.items(), key=lambda item: str(item[1])):
        for target in link_targets(path.read_text(encoding="utf-8")):
            checked += 1
            resolved = normalize(urljoin(url, target))
            if resolved not in pages:
                findings += 1
                sys.stderr.write(
                    f"{path}: {target!r} resolves to {resolved} which is not a page\n"
                )

    if findings:
        sys.stderr.write(
            f"\n{findings} unresolved relative link(s) in {len(sources)} page(s).\n"
            "Relative links resolve against the page URL: a non-index page needs "
            "'../' where an index page needs './'.\n"
        )
        return EXIT_FINDINGS

    print(f"{checked} relative link(s) across {len(sources)} pages resolve")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
