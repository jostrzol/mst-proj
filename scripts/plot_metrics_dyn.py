#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

from __future__ import annotations

import csv
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from itertools import groupby
from typing import TYPE_CHECKING, Any, Callable, Literal

import numpy as np
from lib.constants import PERF_DIR, PLOT_DIR
from lib.language import LANGUAGES, Language
from lib.plot import savefig
from lib.types import Benchmark
from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.container import Container
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from matplotlib.typing import ColorType
from numpy.typing import NDArray

if TYPE_CHECKING:
    from _typeshed import SupportsRichComparison

EXPERIMENTS = [
    "1-blinky",
    # "1-blinky-bm",
    "2-motor",
    # "2-motor-bm",
    "3-pid",
    # "3-pid-bm",
]

# TODO: change to 10
WARMUP_REPORTS = 1

type Key = tuple[Literal["perf"] | Literal["mem"], str, str]


@dataclass
class LangResult:
    lang: Language
    time_us_per_loop: dict[str, Stat]
    mem_usage_per_task: dict[str, Stat]


@dataclass
class Stat:
    values: NDArray[Any]

    @classmethod
    def empty(cls) -> Stat:
        return cls(np.array([]))

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
        slug = f"{experiment}-{lang['slug']}"
        perf = read_reports(f"{slug}-perf-*.csv")
        mem = read_reports(f"{slug}-mem-*.csv")
        result = LangResult(
            lang=lang,
            time_us_per_loop=group_reports(perf),
            mem_usage_per_task=group_reports(mem),
        )
        results.append(result)

    fig, axes = plt.subplots(ncols=2, layout="tight", figsize=(8, 4))
    axes: Iterable[Axes]
    ax_perf, ax_mem = axes

    plot_perf(ax_perf, results)
    plot_mem(ax_mem, results)

    fig.subplots_adjust(top=0.8)

    out_path = PLOT_DIR / f"{experiment}-perf"
    savefig(fig, out_path)


def read_reports(
    pattern: str,
    profile: str = "fast",
    warmup_reports: int = WARMUP_REPORTS,
) -> Iterable[Benchmark]:
    paths = (PERF_DIR / profile).glob(pattern)
    for path in paths:
        with path.open() as file:
            reader = csv.DictReader(file)
            benchmarks = (Benchmark.from_dict(row) for row in reader)
            yield from (b for b in benchmarks if b.report_number >= warmup_reports)


def group_reports(
    benchmarks: Iterable[Benchmark],
) -> dict[str, Stat]:
    return {
        name: Stat(np.array([row.value for row in rows]).astype(np.float64))
        for name, rows in groupby2(benchmarks, lambda row: row.name)
    }


def groupby2[T, TK: SupportsRichComparison](lst: Iterable[T], key: Callable[[T], TK]):
    lst_sorted = sorted(lst, key=key)
    return groupby(lst_sorted, key=key)


def plot_perf(ax: Axes, results: list[LangResult]):
    if any(not result.time_us_per_loop for result in results):
        print("No perf series")
        return

    series_names = [f"faza {name}" for name in results[0].time_us_per_loop.keys()]
    series_stats: list[Sequence[Stat]] = list(
        zip(*(result.time_us_per_loop.values() for result in results))
    )

    plot(ax, series_names, series_stats, plottype="box")
    ax.set_ylabel(r"Czas wykonania $[\mu s]$")


def plot_mem(ax: Axes, results: list[LangResult]):
    stacks = [
        {k: v for k, v in result.mem_usage_per_task.items() if k != "Heap"}
        for result in results
    ]

    if any(not result.mem_usage_per_task for result in results):
        print("No mem series")
        return

    stacks_stats: list[Sequence[Stat]] = [*zip(*(stack.values() for stack in stacks))]
    heap_stats = [
        result.mem_usage_per_task.get("Heap", Stat.empty()) for result in results
    ]
    n_stacks = len(stacks_stats)

    series_stats: list[Sequence[Stat]] = [*stacks_stats, heap_stats]
    series_names = [*("stos" for _ in stacks[0].keys()), "sterta"]

    patterns = [*PATTERNS[:n_stacks], "o"]

    ax_stack = ax
    ax_heap = ax.twinx()
    axs = [ax_stack] * n_stacks + [ax_heap, ax_heap]

    plot(axs, series_names, series_stats, patterns, plottype="bar")
    ax_stack.set_ylabel(r"Zajętość stosu $[B]$")
    ax_heap.set_ylabel(r"Zajętość sterty $[B]$")


PATTERNS = ["/", "x", "-", "|", "\\", "+", "o", "O", ".", "*"]


def plot(
    axs: list[Axes] | Axes,
    series_names: list[str],
    series_stats: list[Sequence[Stat]],
    patterns: list[str] | None = None,
    width: float | None = None,
    plottype: Literal["box"] | Literal["bar"] = "bar",
):
    n_series = len(series_names)
    if isinstance(axs, Axes):
        axs = [axs] * n_series
    if not patterns:
        patterns = PATTERNS
    if not width:
        width = 1 / (n_series + 1)

    names = [lang["name"] for lang in LANGUAGES.values()]
    colors = [lang["color"] for lang in LANGUAGES.values()]
    positions_init = np.arange(len(names))

    ax = axs[0]
    box = ax.get_position()
    ax.set_position((box.x0, box.y0, box.width, box.height * 0.9))

    match plottype:
        case "box":
            plot_boxplot(
                axs=axs,
                series_stats=series_stats,
                patterns=patterns,
                positions_init=positions_init,
                colors=colors,
                width=width,
            )
        case "bar":
            plot_bar(
                axs=axs,
                series_stats=series_stats,
                patterns=patterns,
                positions_init=positions_init,
                colors=colors,
                width=width,
            )

    ax = axs[0]
    ax.set_xticks(positions_init + width * (n_series - 1) / 2, names)

    legend_stubs = [
        Rectangle(
            (0, 0),
            1,
            1,
            facecolor="none",
            edgecolor="black",
            hatch=pattern * 2,
        )
        for pattern in patterns
    ]

    names = [name for name, stats in zip(series_names, series_stats) if stats]
    legend = ax.legend(
        legend_stubs,
        names,
        loc="lower center",
        bbox_to_anchor=(0.5, 1.01),
        ncol=len(names),
    )
    leg_handles: Sequence[Rectangle] = legend.legend_handles  # pyright: ignore[reportAssignmentType]
    for leg in leg_handles:
        leg.set_fill(False)


def plot_boxplot(
    axs: Sequence[Axes],
    series_stats: list[Sequence[Stat]],
    patterns: list[str],
    positions_init: NDArray[Any],
    colors: Sequence[ColorType],
    width: float,
):
    containers: list[Container] = []
    for multiplier, (stats, pattern, ax) in enumerate(zip(series_stats, patterns, axs)):
        if len(stats) == 0:
            continue

        offset = width * multiplier
        positions = positions_init + offset
        xs = [stat.values for stat in stats]

        boxplot = ax.boxplot(
            xs,
            positions=positions,
            widths=width,
            patch_artist=True,
            showfliers=False,
        )
        patches: Sequence[Patch] = boxplot["boxes"]
        for patch, color in zip(patches, colors):
            patch.set_facecolor(color)
            patch.set_edgecolor("black")
            patch.set_hatch(pattern * 2)
        medians: Sequence[Line2D] = boxplot["medians"]
        for median in medians:
            median.remove()

        containers.append(Container(patches))
    return containers


def plot_bar(
    axs: Sequence[Axes],
    series_stats: list[Sequence[Stat]],
    patterns: list[str],
    positions_init: NDArray[Any],
    colors: Sequence[ColorType],
    width: float,
):
    containers: list[Container] = []
    for multiplier, (stats, pattern, ax) in enumerate(zip(series_stats, patterns, axs)):
        if len(stats) == 0:
            continue

        offset = width * multiplier
        xs = positions_init + offset
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

        containers.append(bar)
    return containers


def main():
    for experiment in EXPERIMENTS:
        plot_experiment(experiment)


if __name__ == "__main__":
    main()
