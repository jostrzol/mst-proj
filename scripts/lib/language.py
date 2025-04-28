from typing import TypedDict


class Language(TypedDict):
    name: str
    slug: str
    color: str


LANGUAGES: dict[str, Language] = {
    "c": {"name": "C", "slug": "c", "color": "cornflowerblue"},
    "zig": {"name": "Zig", "slug": "zig", "color": "orange"},
    "rust": {"name": "Rust", "slug": "rust", "color": "indianred"},
}
