#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from typing import TypedDict

from matplotlib import pyplot as plt
from matplotlib.ticker import PercentFormatter
from matplotlib.typing import ColorType

from analyze.lib.constants import DATA_DIR, PLOT_DIR
from analyze.lib.plot import gray_shades, plot_bar, savefig, use_plot_style

SRC_PATH = DATA_DIR / "so-survey.csv"
OUT_PATH = PLOT_DIR / "so-survey"


class DataRow(TypedDict):
    technology: str
    popularity: float
    language: str


def main():
    use_plot_style()
    PLOT_DIR.mkdir(exist_ok=True, parents=True)
    with SRC_PATH.open() as file:
        reader = csv.DictReader(file)
        rows: list[DataRow] = list(reader)  # pyright: ignore[reportAssignmentType]

    labels = [row["technology"] for row in rows]
    popularities = [float(row["popularity"]) for row in rows]
    styles = [language_to_style(row["language"]) for row in rows]
    colors, hatch = zip(*styles)

    fig = plt.figure(figsize=(9, 4))
    ax = plot_bar(
        labels,
        popularities,
        colors=colors,
        hatch=hatch,
        barlabel_decimals=1,
        barlabel_fontscale=0.8,
        rotation=True,
        linewidth=1.5,
    )
    ax.yaxis.set_major_formatter(PercentFormatter())

    savefig(fig, OUT_PATH)
    plt.close(fig)


def language_to_style(language: str) -> tuple[ColorType, str]:
    white, gray, black = gray_shades(3, shades="dark")
    match language:
        case "c":
            return gray, ""
        case "":
            return white, "//"
        case _:
            return black, ""


if __name__ == "__main__":
    main()
