#!/usr/bin/env python3

# pyright: reportAny=false
# pyright: reportExplicitAny=false
# pyright: reportUnusedCallResult=false

from __future__ import annotations

import csv
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from itertools import groupby
from pathlib import Path
from typing import TYPE_CHECKING, Any, Callable, Literal

import numpy as np
from lib.constants import ANALYSIS_DIR, PLOT_DIR
from lib.language import LANGUAGES, Language
from lib.types import MemReport, PerformanceReport
from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.container import BarContainer
from numpy.typing import NDArray

if TYPE_CHECKING:
    from _typeshed import SupportsRichComparison

EXPERIMENTS = [
    # "1-blinky",
    "1-blinky-bm",
    # "2-motor",
    "2-motor-bm",
    # "3-pid",
    "3-pid-bm",
]

SKIP_REPORTS = 10

type Key = tuple[Literal["perf"] | Literal["mem"], str, str]


@dataclass
class LangResult:
    lang: Language
    time_us_per_loop: dict[str, Stat]
    mem_usage_per_task: dict[str, Stat]


@dataclass
class Stat:
    values: NDArray[Any]

    @property
    def sum(self) -> float:
        return self.values.sum()

    @property
    def mean(self) -> float:
        return self.values.mean()

    @property
    def sem(self) -> float:
        return self.values.std() / np.sqrt(len(self.values))


def plot_experiment(experiment: str):
    results: list[LangResult] = []
    for lang in LANGUAGES.values():
        perf = read_report(
            PerformanceReport,
            ANALYSIS_DIR / "perf" / f"{experiment}-{lang['slug']}-perf.csv",
        )
        mem = read_report(
            MemReport,
            ANALYSIS_DIR / "perf" / f"{experiment}-{lang['slug']}-mem.csv",
        )
        time_us_per_loop = {
            name: Stat(np.array([row.time_us for row in rows]).astype(np.float64))
            for name, rows in groupby2(perf, lambda row: row.name)
        }
        mem_usage_per_task = {
            name: Stat(np.array([row.usage for row in rows]).astype(np.int64))
            for name, rows in groupby2(mem, lambda row: row.name)
        }
        results.append(
            LangResult(
                lang=lang,
                time_us_per_loop=time_us_per_loop,
                mem_usage_per_task=mem_usage_per_task,
            )
        )

    fig, axes = plt.subplots(nrows=2, layout="tight", figsize=(6.4, 8))
    axes: Iterable[Axes]
    ax_perf, ax_mem = axes

    series_names_perf = [f"pętla {name}" for name in results[0].time_us_per_loop.keys()]
    series_stats_perf: list[Sequence[Stat]] = list(
        zip(*(result.time_us_per_loop.values() for result in results))
    )

    plot(ax_perf, series_names_perf, series_stats_perf)
    ax_perf.set_ylabel(r"Czas wykonania $[\mu s]$")

    stacks = [
        {k: v for k, v in result.mem_usage_per_task.items() if k != "Heap"}
        for result in results
    ]

    stacks_stats: list[Sequence[Stat]] = [*zip(*(stack.values() for stack in stacks))]
    heap_stats = [result.mem_usage_per_task["Heap"] for result in results]
    n_stacks = len(stacks_stats)

    series_stats_mem: list[Sequence[Stat]] = [*stacks_stats, heap_stats]
    series_names_mem = [*("stos" for _ in stacks[0].keys()), "sterta"]

    patterns_mem = [*PATTERNS[:n_stacks], "o"]

    ax_stack = ax_mem
    ax_heap = ax_mem.twinx()
    axs = [ax_stack] * n_stacks + [ax_heap, ax_heap]

    plot(axs, series_names_mem, series_stats_mem, patterns_mem)
    ax_stack.set_ylabel(r"Zajętość stosu $[B]$")
    ax_heap.set_ylabel(r"Zajętość sterty $[B]$")

    fig.subplots_adjust(top=0.8)

    out_path = PLOT_DIR / f"{experiment}-perf.svg"
    fig.savefig(out_path)


def read_report[T](t: type[T], path: Path):
    with path.open() as file:
        reader = csv.DictReader(file)
        return [t(**row) for row in reader][SKIP_REPORTS:]


def groupby2[T, TK: SupportsRichComparison](lst: Iterable[T], key: Callable[[T], TK]):
    lst_sorted = sorted(lst, key=key)
    return groupby(lst_sorted, key=key)


PATTERNS = ["/", "x", "-", "|", "\\", "+", "o", "O", ".", "*"]


def plot(
    axs: list[Axes] | Axes,
    series_names: list[str],
    series_stats: list[Sequence[Stat]],
    patterns: list[str] | None = None,
    width: float | None = None,
):
    n_series = len(series_names)
    if isinstance(axs, Axes):
        axs = [axs] * n_series
    if not patterns:
        patterns = PATTERNS
    if not width:
        width = 0.8 / (n_series + 1)

    names = [lang["name"] for lang in LANGUAGES.values()]
    colors = [lang["color"] for lang in LANGUAGES.values()]
    xs_init = np.arange(len(names))

    ax = axs[0]
    box = ax.get_position()
    ax.set_position((box.x0, box.y0, box.width, box.height * 0.9))

    bars: list[BarContainer] = []
    for stats, pattern, multiplier, ax in zip(
        series_stats, patterns, range(n_series), axs
    ):
        if len(stats) == 0:
            continue

        offset = width * multiplier
        xs = xs_init + offset
        ys = np.array([stat.mean for stat in stats])
        yerr = [stat.sem * 10 for stat in stats]

        bar = ax.bar(
            xs,
            ys,
            width,
            edgecolor="black",
            facecolor=colors,
            hatch=pattern * 2,
        )
        bars.append(bar)
        ax.hlines(
            ys - yerr,
            xs - width / 4,
            xs + width / 4,
            color="black",
        )
        ax.hlines(
            ys + yerr,
            xs - width / 4,
            xs + width / 4,
            color="black",
        )
        ax.vlines(
            xs,
            ys - yerr,
            ys + yerr,
            color="black",
        )

    ax = axs[0]
    ax.set_xticks(xs_init + width * (n_series - 1) / 2, names)

    names = [name for name, stats in zip(series_names, series_stats) if stats]
    legend = ax.legend(
        bars,
        names,
        loc="lower center",
        bbox_to_anchor=(0.5, 1.01),
        ncol=len(names),
    )
    for leg in legend.legend_handles:
        leg: Any
        leg.set_facecolor("white")


def main():
    for experiment in EXPERIMENTS:
        plot_experiment(experiment)


if __name__ == "__main__":
    main()
