from __future__ import annotations

import os
import re
import shutil
import sys
from collections import deque
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
BOOKS = [
    {
        "name": "tspl4",
        "title": "The Scheme Programming Language, 4th Edition",
        "start": "https://www.scheme.com/tspl4/",
        "allowed_prefixes": ["https://www.scheme.com/tspl4/"],
        "target": ROOT / "tspl4",
    },
    {
        "name": "csug",
        "title": "Chez Scheme User's Guide",
        "start": "https://cisco.github.io/ChezScheme/csug/csug.html",
        "allowed_prefixes": ["https://cisco.github.io/ChezScheme/csug/"],
        "target": ROOT / "csug",
    },
]

USER_AGENT = "Mozilla/5.0 (MacScheme docs downloader)"
CSS_URL_RE = re.compile(r"url\(([^)]+)\)")
ABSOLUTE_URL_RE = re.compile(r'https?://[^\s"\'<>)]+' )


class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = dict(attrs)
        for key in ("href", "src"):
            value = attr_map.get(key)
            if value:
                self.links.append(value)


def normalize_url(url: str) -> str:
    parsed = urlparse(url)
    return urlunparse(parsed._replace(fragment=""))


def is_allowed(url: str, allowed_prefixes: list[str]) -> bool:
    if not url.startswith(("http://", "https://")):
        return False
    return any(url.startswith(prefix) for prefix in allowed_prefixes)


def local_path_for(url: str, target_root: Path, allowed_prefixes: list[str]) -> Path:
    suffix = None
    for prefix in allowed_prefixes:
        if url.startswith(prefix):
            suffix = url[len(prefix):]
            break
    if suffix is None:
        raise ValueError(f"URL outside allowed prefixes: {url}")
    if not suffix or suffix.endswith("/"):
        suffix = (suffix or "") + "index.html"
    local_path = target_root / suffix
    local_path.parent.mkdir(parents=True, exist_ok=True)
    return local_path


def relative_link(from_path: Path, to_path: Path) -> str:
    return os.path.relpath(to_path, start=from_path.parent).replace(os.sep, "/")


def rewrite_absolute_links(
    content: str,
    current_path: Path,
    allowed_prefixes: list[str],
    target_root: Path,
) -> str:
    def replacer(match: re.Match[str]) -> str:
        raw_url = match.group(0)
        if not is_allowed(raw_url, allowed_prefixes):
            return raw_url
        parsed = urlparse(raw_url)
        local_target = local_path_for(
            urlunparse(parsed._replace(fragment="")),
            target_root,
            allowed_prefixes,
        )
        rewritten = relative_link(current_path, local_target)
        if parsed.fragment:
            rewritten += f"#{parsed.fragment}"
        return rewritten

    return ABSOLUTE_URL_RE.sub(replacer, content)


def fetch(url: str) -> tuple[bytes, str, str]:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request) as response:
        data = response.read()
        content_type = response.headers.get_content_type()
        charset = response.headers.get_content_charset() or "utf-8"
    return data, content_type, charset


def clear_target(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def crawl_book(book: dict[str, object]) -> tuple[int, Path]:
    target_root = book["target"]
    assert isinstance(target_root, Path)
    clear_target(target_root)

    queue: deque[str] = deque([book["start"]])
    seen: set[str] = set()
    downloaded = 0

    allowed_prefixes = book["allowed_prefixes"]
    assert isinstance(allowed_prefixes, list)

    while queue:
        url = normalize_url(queue.popleft())
        if url in seen or not is_allowed(url, allowed_prefixes):
            continue

        seen.add(url)
        data, content_type, charset = fetch(url)
        output_path = local_path_for(url, target_root, allowed_prefixes)

        if content_type in {"text/html", "application/xhtml+xml"} or output_path.suffix.lower() in {"", ".html", ".htm"}:
            try:
                text = data.decode(charset, errors="replace")
            except LookupError:
                text = data.decode("utf-8", errors="replace")

            parser = LinkParser()
            parser.feed(text)
            for link in parser.links:
                full_url = normalize_url(urljoin(url, link))
                if is_allowed(full_url, allowed_prefixes):
                    queue.append(full_url)

            text = rewrite_absolute_links(text, output_path, allowed_prefixes, target_root)
            output_path.write_text(text, encoding="utf-8")
        elif content_type == "text/css" or output_path.suffix.lower() == ".css":
            text = data.decode(charset, errors="replace")
            for item in CSS_URL_RE.findall(text):
                asset_url = normalize_url(urljoin(url, item.strip().strip('"\'')))
                if is_allowed(asset_url, allowed_prefixes):
                    queue.append(asset_url)
            text = rewrite_absolute_links(text, output_path, allowed_prefixes, target_root)
            output_path.write_text(text, encoding="utf-8")
        else:
            output_path.write_bytes(data)

        downloaded += 1

    return downloaded, target_root


def main() -> None:
    selected = set(sys.argv[1:])
    if selected:
        books = [book for book in BOOKS if book["name"] in selected]
    else:
        books = BOOKS

    if not books:
        available = ", ".join(book["name"] for book in BOOKS)
        raise SystemExit(f"No matching books requested. Available: {available}")

    print(f"Downloading Scheme books into {ROOT}")
    for book in books:
        try:
            downloaded, target = crawl_book(book)
        except Exception as error:
            print(f"- {book['title']}: FAILED ({error})")
            raise
        print(f"- {book['title']}: {downloaded} files -> {target}")


if __name__ == "__main__":
    main()
