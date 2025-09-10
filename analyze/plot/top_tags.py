#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from typing import TypedDict

from matplotlib import pyplot as plt
from matplotlib.typing import ColorType

from analyze.lib.constants import DATA_DIR, PLOT_DIR
from analyze.lib.language import LANGUAGES
from analyze.lib.plot import gray_shades, plot_bar, savefig

OUT_DIR = PLOT_DIR / "top-tags"


class DataRow(TypedDict):
    TagName: str
    Count: str


GRAY, BLACK = gray_shades(2, start=0.6)

TAG_SUBSTITUTIONS = {
    "segmentation-fault": "seg-fault",
    "memory-management": "mem-manag.",
    "command-line-arguments": "cmd-line-args",
    "metaprogramming": "metaprog.",
}

HIGHLIGHTED_TAGS = {
    "c": {
        BLACK: {
            "arrays",
            "pointers",
            "malloc",
            "seg-fault",
            "memory",
            "mem-manag.",
        }
    },
    "zig": {
        BLACK: {
            "compiler-errors",
            "compilation",
            "metaprog.",
            "compile-time",
        },
        "green": {"arrays", "pointers", "malloc", "seg-fault", "memory", "mem-manag."},
    },
    "rust": {
        BLACK: {"lifetime", "borrow-checker", "reference", "ownership"},
    },
}


def main():
    OUT_DIR.mkdir(exist_ok=True, parents=True)
    for language in LANGUAGES.values():
        data_path = DATA_DIR / f"top-tags-{language['slug']}.csv"
        with data_path.open() as file:
            reader = csv.DictReader(file)
            rows: list[DataRow] = list(reader)  # pyright: ignore[reportAssignmentType]

        tags = [substitute(row["TagName"]) for row in rows]
        counts = [int(row["Count"]) for row in rows]

        fig = plt.figure(figsize=(8, 4))

        plot_bar(
            tags,
            counts,
            colors=colors(language["slug"], tags),
            barlabels=[""] * len(tags),
            rotation=True,
            linewidth=1,
        )
        #
        # ax.set_title(f"Najpopularniejsze tagi dla języka {language['name']}")

        fig.tight_layout()
        out_path = OUT_DIR / f"top-tags-{language['slug']}"
        savefig(fig, out_path)
        plt.close(fig)


def substitute(tag: str) -> str:
    return TAG_SUBSTITUTIONS.get(tag, tag)


def colors(language: str, tags: list[str]) -> list[ColorType]:
    result: list[ColorType] = []
    highlights = HIGHLIGHTED_TAGS[language]
    for tag in tags:
        color = GRAY
        for hcolor, htags in highlights.items():
            if tag in htags:
                color = hcolor
                break
        result.append(color)
    return result


if __name__ == "__main__":
    main()
