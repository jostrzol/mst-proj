#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from collections.abc import Iterable
from math import ceil
from pathlib import Path
from typing import TypedDict

from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.ticker import PercentFormatter

ANALYSIS_DIR = Path("./analysis/")
ANALYSIS_SRC_DIR = Path("./analysis-src/")


class Language(TypedDict):
    name: str
    slug: str
    color: str


LANGUAGES: list[Language] = [
    {"name": "C", "slug": "c", "color": "cornflowerblue"},
    {"name": "Zig", "slug": "zig", "color": "orange"},
    {"name": "Rust", "slug": "rust", "color": "indianred"},
]


def main():
    for language in LANGUAGES:
        data_path = ANALYSIS_SRC_DIR / f"top-tags-{language['slug']}.csv"
        with data_path.open() as file:
            reader = csv.DictReader(file)
            rows = list(reader)

        tags = [row["TagName"] for row in rows]
        counts = [int(row["Count"]) for row in rows]

        fig = plt.figure(figsize=(10, 4))

        ax = fig.subplots()
        ax.bar(tags, counts, width=0.65, facecolor="black")
        ax.set_xticks(
            ax.get_xticks(),  # pyright: ignore[reportUnknownArgumentType]
            ax.get_xticklabels(),  # pyright: ignore[reportArgumentType]
            rotation=45,
            ha="right",
        )
        ax.set_title(f"Najpopularniejsze tagi dla języka {language['name']}")

        fig.tight_layout()
        out_path = ANALYSIS_DIR / f"top-tags-{language['slug']}.svg"
        fig.savefig(out_path)


def add_bar_texts(ax: Axes, ys: Iterable[float], texts: Iterable[object]) -> None:
    _, ymax = ax.get_ylim()
    margin = ymax / 50
    for i, (y, text) in enumerate(zip(ys, texts)):
        if y < 0.9 * ymax:
            ax.text(i, y + margin, str(text), ha="center")
        else:
            ax.text(i, y - margin, str(text), ha="center", va="top", color="white")


if __name__ == "__main__":
    main()
