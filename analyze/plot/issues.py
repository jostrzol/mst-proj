#!/usr/bin/env python3

# pyright: reportAny=false
# pyright: reportUnusedCallResult=false

import csv
from collections.abc import Iterable
from itertools import groupby

from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.ticker import PercentFormatter

from analyze.lib.constants import ANALYSIS_SRC_DIR, PLOT_DIR
from analyze.lib.plot import add_bar_texts, savefig

ISSUES_PATH = ANALYSIS_SRC_DIR / "issues.csv"
OUT_PATH = PLOT_DIR / "issues"


def main():
    with ISSUES_PATH.open() as file:
        reader = csv.reader(file)
        it = iter(reader)
        head = next(it)
        rows = [[tag, *map(int, values)] for [tag, *values] in it]

    langs = [lang.split("-") for lang in head[2:]]
    names, colors = [*zip(*langs)]  # pyright: ignore[reportAssignmentType]
    names: list[str]
    colors: list[str]

    totals = rows[0][2:]  # pyright: ignore[reportAssignmentType]
    totals: list[int]
    tags, groups, *n_questions = zip(*rows[1:])
    tags: Iterable[str]

    n_questions_per_tag = [*zip(*n_questions)]
    n_questions_per_tag: list[Iterable[int]]

    fig, ax = plt.subplots(layout="tight")
    ax.bar(names, totals, facecolor=colors, edgecolor="black")
    add_bar_texts(ax, totals, totals)
    ax.set_ylabel("Liczba pytań")
    savefig(fig, OUT_PATH.with_name(f"{OUT_PATH.name}-0-totals"))
    plt.close(fig)

    i = 0
    for group, members in groupby(groups):
        n_group = len([*members])
        group_tags = tags[i : i + n_group]
        group_n_questions_per_tag = n_questions_per_tag[i : i + n_group]
        i += n_group

        ncols = n_group if n_group != 4 else 2
        nrows = 1 if n_group != 4 else 2
        width = 4.8 + 2.8 * (ncols - 1)
        height = 3.6 + 1.8 * (nrows - 1)
        figsize = (width, height)
        fig, axs = plt.subplots(
            nrows=nrows, ncols=ncols, layout="tight", figsize=figsize
        )
        axs_flat: Iterable[Axes] = (
            [ax for row in axs for ax in row] if nrows > 1 else axs
        )

        for tag, ys, ax in zip(group_tags, group_n_questions_per_tag, axs_flat):
            ax.set_title(f"Tag: {tag}")

            ys_percent = [y / total * 100 for y, total in zip(ys, totals)]
            ax.bar(names, ys_percent, facecolor=colors, edgecolor="black")
            add_bar_texts(ax, ys_percent, ys)

            ax.set_ylabel("Część")
            ax.yaxis.set_major_formatter(PercentFormatter(decimals=2))

        savefig(fig, OUT_PATH.with_name(f"{OUT_PATH.name}-{group}"))
        plt.close(fig)


if __name__ == "__main__":
    main()
