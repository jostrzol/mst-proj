#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from math import ceil

from lib.constants import ANALYSIS_SRC_DIR, PLOT_DIR
from lib.plot import add_bar_texts
from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.ticker import PercentFormatter

ISSUES_PATH = ANALYSIS_SRC_DIR / "issues.csv"
OUT_PATH = PLOT_DIR / "issues.svg"


def main():
    with ISSUES_PATH.open() as file:
        reader = csv.reader(file)
        it = iter(reader)
        head = next(it)
        rows = [(tag, *map(int, values)) for [tag, *values] in it]

    langs = [lang.split("-") for lang in head[1:]]
    names, colors = zip(*langs)  # pyright: ignore[reportAssignmentType]
    names: list[str]
    colors: list[str]

    totals = rows[0][1:]
    tags, *n_questions = zip(*rows[1:])  # pyright: ignore[reportAssignmentType]
    tags: list[str]

    n_questions_per_tag = zip(*n_questions)  # pyright: ignore[reportAssignmentType]
    n_questions_per_tag: list[list[int]]

    fig = plt.figure(figsize=(10, 9))
    fig.suptitle("Liczba pytań na forum")

    ncols = 3
    nrows = ceil((1 + len(tags)) / ncols)
    axs = fig.subplots(nrows=nrows, ncols=ncols)
    axs: list[list[Axes]]
    ax1, *rest_axs = [ax for row in axs for ax in row]

    ax1.bar(names, totals, facecolor=colors, edgecolor="black")
    add_bar_texts(ax1, totals, totals)
    ax1.set_ylabel("Liczba pytań")
    ax1.set_title("Łącznie")

    ax_it = iter(rest_axs)
    for tag, ys, ax in zip(tags, n_questions_per_tag, ax_it):
        ax.set_title(f"Tag: {tag}")

        ys_percent = [y / total * 100 for y, total in zip(ys, totals)]
        ax.bar(names, ys_percent, facecolor=colors, edgecolor="black")
        add_bar_texts(ax, ys_percent, ys)

        ax.set_ylabel("Część")
        ax.yaxis.set_major_formatter(PercentFormatter(decimals=2))

    for ax in ax_it:
        ax.remove()

    fig.tight_layout()
    fig.savefig(OUT_PATH)


if __name__ == "__main__":
    main()
