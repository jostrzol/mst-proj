#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from typing import TypedDict

from lib.constants import ANALYSIS_SRC_DIR, PLOT_DIR
from lib.language import LANGUAGES
from lib.plot import add_bar_texts, lighten_color, savefig
from matplotlib import pyplot as plt
from matplotlib.ticker import PercentFormatter
from matplotlib.typing import ColorType

SRC_PATH = ANALYSIS_SRC_DIR / "so-survey.csv"
OUT_PATH = PLOT_DIR / "so-survey"


class DataRow(TypedDict):
    technology: str
    popularity: float
    language: str


def main():
    with SRC_PATH.open() as file:
        reader = csv.DictReader(file)
        rows: list[DataRow] = list(reader)  # pyright: ignore[reportAssignmentType]

    labels = [row["technology"] for row in rows]
    popularities = [float(row["popularity"]) for row in rows]
    colors = [language_to_color(row["language"]) for row in rows]

    fig = plt.figure(figsize=(9, 4))

    ax = fig.subplots()
    ax.bar(labels, popularities, facecolor=colors)
    ax.set_xticks(
        ax.get_xticks(),  # pyright: ignore[reportUnknownArgumentType]
        ax.get_xticklabels(),  # pyright: ignore[reportArgumentType]
        rotation=45,
        ha="right",
    )
    ax.yaxis.set_major_formatter(PercentFormatter())

    texts = [f"{popularity}" for popularity in popularities]
    add_bar_texts(ax, popularities, texts, below_color="black", size="small")

    fig.tight_layout()
    savefig(fig, OUT_PATH)


def language_to_color(language: str) -> ColorType:
    match language:
        case "c":
            return LANGUAGES["c"]["color"]
        case "":
            return lighten_color(LANGUAGES["c"]["color"], 0.5)
        case _:
            return "crimson"


if __name__ == "__main__":
    main()
