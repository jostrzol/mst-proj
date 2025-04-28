#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from typing import TypedDict

from lib.constants import ANALYSIS_SRC_DIR, PLOT_DIR
from lib.language import LANGUAGES
from matplotlib import pyplot as plt


class DataRow(TypedDict):
    TagName: str
    Count: str


TAG_SUBSTITUTIONS = {
    "segmentation-fault": "seg-fault",
    "memory-management": "mem-manag.",
    "command-line-arguments": "cmd-line-args",
    "metaprogramming": "metaprog.",
}


def main():
    for language in LANGUAGES.values():
        data_path = ANALYSIS_SRC_DIR / f"top-tags-{language['slug']}.csv"
        with data_path.open() as file:
            reader = csv.DictReader(file)
            rows: list[DataRow] = list(reader)  # pyright: ignore[reportAssignmentType]

        tags = [substitute(row["TagName"]) for row in rows]
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
        out_path = PLOT_DIR / f"top-tags-{language['slug']}.svg"
        fig.savefig(out_path)


def substitute(tag: str) -> str:
    return TAG_SUBSTITUTIONS.get(tag, tag)


if __name__ == "__main__":
    main()
