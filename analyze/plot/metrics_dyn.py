#!/usr/bin/env python3

# pyright: reportUninitializedInstanceVariable=false
# pyright: reportUnusedCallResult=false

from __future__ import annotations

import locale
from collections.abc import Sequence
from typing import Any, Literal

import numpy as np
import pandas as pd
import pandera.pandas as pa
from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.container import BarContainer, Container
from matplotlib.figure import Figure
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from matplotlib.typing import ColorType
from numpy.typing import NDArray
from pandera.typing import DataFrame, Series

from analyze.lib.constants import PERF_DIR, PLOT_DIR
from analyze.lib.experiments import EXPERIMENTS
from analyze.lib.language import LANGUAGES
from analyze.lib.plot import figsize_rel, fmt
from analyze.lib.plot import plot_bar as plot_bar_
from analyze.lib.plot import savefig, set_locale, use_plot_style

type PlotType = Literal["box"] | Literal["bar"] | Literal["stack"]

OUT_DIR = PLOT_DIR / "metrics-dyn"

WARMUP_REPORTS = 10

MEM_NAME_TRANSLATIONS = {
    "Heap": "sterta",
    "CONTROLLER_LOOP": "stos",
    "MAIN": "stos",
    "main": "stos",
}

BEST_MEM_PROFILE = {
    "c": {e: "fast" for e in EXPERIMENTS.keys()},
    "zig": {e: "fast" for e in EXPERIMENTS.keys()}
    | {
        "1-blinky": "debug",
        "3-pid": "debug",
    },
    "rust": {e: "fast" for e in EXPERIMENTS.keys()},
}


type Stats = NDArray[Any]


def main():
    use_plot_style()
    OUT_DIR.mkdir(exist_ok=True, parents=True)

    perf, mem = load_data()
    mem["value"] = mem["value"] / 1000  # to kB

    for is_bm in [True, False]:
        platform = "bm" if is_bm else "os"

        fig = plt.figure(figsize=figsize_rel(w=1.2, h=1.2))
        set_locale()  # for some reason have to call it here to make mpl respect the decimal separator
        ax, *_ = plot_perf(fig, perf, is_bm=is_bm)
        ax.set_ylabel(r"Czas wykonania $[\mu s]$")
        savefig(fig, OUT_DIR / f"perf-{platform}")
        plt.close(fig)

        fig = plt.figure()
        ax, *_ = plot_mem(fig, mem, is_bm=is_bm)
        ax.set_ylabel(r"Zajętość pamięci $[kB]$")
        savefig(fig, OUT_DIR / f"mem-{platform}")
        plt.close(fig)

    return


class Schema(pa.DataFrameModel):
    report_number: Series[int]
    name: Series[str]
    value: Series[float]
    lang: Series[str]
    experiment: Series[str]


def load_data() -> tuple[DataFrame[Schema], DataFrame[Schema]]:
    perf = pd.DataFrame()
    mem = pd.DataFrame()
    for experiment in EXPERIMENTS.values():
        for lang in LANGUAGES.values():
            slug = f"{experiment['slug']}-{lang['slug']}"

            perf_part = read_reports(f"{slug}-perf-*.csv")

            mem_profile = BEST_MEM_PROFILE[lang["slug"]][experiment["slug"]]
            mem_part = read_reports(f"{slug}-mem-*.csv", profile=mem_profile)

            for part in perf_part, mem_part:
                part["lang"] = lang["slug"]
                part["experiment"] = experiment["slug"]

            perf = pd.concat([perf, perf_part])
            mem = pd.concat([mem, mem_part])

    return Schema.validate(perf), Schema.validate(mem)


def read_reports(
    pattern: str,
    profile: str = "fast",
    warmup_reports: int = WARMUP_REPORTS,
) -> pd.DataFrame:
    result = pd.DataFrame()
    paths = (PERF_DIR / profile).glob(pattern)
    for path in paths:
        with path.open() as file:
            part_df = pd.read_csv(file)
            part_df = part_df[part_df["report_number"] >= warmup_reports]
            result = pd.concat([result, part_df])
    return result


def plot_perf(fig: Figure, df: DataFrame[Schema], is_bm: bool) -> list[Axes]:
    experiments = [
        experiment
        for experiment in EXPERIMENTS.values()
        if experiment["is_bm"] == is_bm
    ]

    axs: list[Axes] = fig.subplots(1, len(experiments), width_ratios=[1, 1, 2])
    for experiment, ax in zip(experiments, axs):
        values = df[df["experiment"] == experiment["slug"]]

        series_names = []
        series_stats = []
        for name, stats in values.groupby("name"):
            res = stats.groupby("lang")["value"].apply(np.array)
            res = res.reindex([*LANGUAGES.keys()])
            series_names.append(name)
            series_stats.append(res.to_list())

        patterns = [""] + PATTERNS
        if len(series_stats) <= 1:
            series_names = None
            patterns = [""]

        plot(
            axs=ax,
            series_names=series_names,
            series_stats=series_stats,
            patterns=patterns,
            plottype="bar" if is_bm else "box",
        )
        ax.set_title(f"Scenariusz {experiment["number"]}")
    return axs


def plot_mem(fig: Figure, df: DataFrame[Schema], is_bm: bool) -> list[Axes]:
    experiments = [
        experiment
        for experiment in EXPERIMENTS.values()
        if experiment["is_bm"] == is_bm
    ]

    axs: list[Axes] = fig.subplots(1, len(experiments))
    for experiment, ax in zip(experiments, axs):
        values = df[df["experiment"] == experiment["slug"]]

        series_names = []
        series_stats = []
        for name, stats in values.groupby("name"):
            name = str(name)
            res = stats.groupby("lang")["value"].apply(np.array)
            res = res.reindex([*LANGUAGES.keys()])
            series_names.append(MEM_NAME_TRANSLATIONS.get(name, name))
            series_stats.append(res.to_list())

        idx = np.argsort(series_names)
        series_names = [series_names[i] for i in idx]
        series_stats = [series_stats[i] for i in idx]

        patterns = ["."] + PATTERNS
        if len(series_stats) <= 1:
            series_names = None
            patterns = [""]
        if experiment["number"] != 3:
            series_names = None

        plot(
            axs=ax,
            series_names=series_names,
            series_stats=series_stats,
            patterns=patterns,
            plottype="stack",
        )
        ax.set_title(f"Scenariusz {experiment["number"]}")
    return axs


PATTERNS = ["/", "x", "-", "|", "\\", "+", "o", "O", ".", "*"]


def plot(
    axs: list[Axes] | Axes,
    series_names: list[str] | None,
    series_stats: list[Sequence[Stats]],
    patterns: list[str] | None = None,
    width: float | None = None,
    plottype: PlotType = "bar",
    errors: bool = False,
):
    n_series = len(series_stats)
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
                errors=errors,
            )
        case "stack":
            plot_stack(
                axs=axs,
                series_stats=series_stats,
                patterns=patterns,
                positions_init=positions_init,
                colors=colors,
                width=width,
            )

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

    if series_names:
        names = [name for name, stats in zip(series_names, series_stats) if stats]
        legend = ax.legend(
            legend_stubs,
            names,
            loc="upper center",
            bbox_to_anchor=(0.5, -0.05),
            ncol=len(names),
        )
        leg_handles: Sequence[Rectangle] = (
            legend.legend_handles
        )  # pyright: ignore[reportAssignmentType]
        for leg in leg_handles:
            leg.set_fill(False)


def plot_boxplot(
    axs: Sequence[Axes],
    series_stats: list[Sequence[Stats]],
    patterns: list[str],
    positions_init: Stats,
    colors: Sequence[ColorType],
    width: float,
):
    containers: list[Container] = []
    for multiplier, (stats, pattern, ax) in enumerate(zip(series_stats, patterns, axs)):
        if len(stats) == 0:
            continue

        offset = width * multiplier
        positions = positions_init + offset
        xs = [stat for stat in stats]

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
            patch.set_hatch(pattern * 3)
        medians: Sequence[Line2D] = boxplot["medians"]
        for median in medians:
            median.set_color("black")
            # median.remove()

        ax.margins(0.05)
        containers.append(Container(patches))
    return containers


def plot_bar(
    axs: Sequence[Axes],
    series_stats: list[Sequence[Stats]],
    patterns: list[str],
    positions_init: Stats,
    colors: Sequence[ColorType],
    width: float,
    errors: bool = False,
):
    containers: list[Container] = []
    print(series_stats)
    series_means = [np.array([*map(np.mean, stats)]) for stats in series_stats]
    series_yerrs = [np.array([*map(sem, stats)]) for stats in series_stats]
    print(series_means)

    max_mean = np.max(np.concatenate(series_means))
    max_yerr = np.max(np.concatenate(series_yerrs))
    ymax = +max_mean + max_yerr

    for multiplier, (ys, yerr, pattern, ax) in enumerate(
        zip(series_means, series_yerrs, patterns, axs)
    ):
        if len(ys) == 0:
            continue

        offset = width * multiplier
        xs = positions_init + offset

        bar = plot_bar_(
            xs,
            ys,
            ax=ax,
            widths=width,
            colors=colors,
            linewidth=1.2,
            hatch=pattern * 2,
            barlabel_decimals=2,
            barlabel_fontscale=0.8,
            ymax=ymax,
        )

        if errors:
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

        ax.margins(x=0.1 / len(series_stats), y=0.15)
        containers.append(bar)
    return containers


def plot_stack(
    axs: Sequence[Axes],
    series_stats: list[Sequence[Stats]],
    patterns: list[str],
    positions_init: Stats,
    colors: Sequence[ColorType],
    width: float,
):
    containers: list[BarContainer] = []
    bottom = np.zeros_like(positions_init, dtype=np.float64)
    are_last = [False] * (len(series_stats) - 1) + [True]

    for stats, pattern, ax, is_last in zip(series_stats, patterns, axs, are_last):
        if len(stats) == 0:
            continue

        xs = positions_init + width / 2
        ys = np.array([stat.mean() for stat in stats])

        if is_last:
            barlabels = [fmt("%.1f", y) for y in bottom + ys]
        else:
            barlabels = [""] * len(xs)

        bar = plot_bar_(
            xs,
            ys,
            ax=ax,
            linewidth=1.2,
            colors=colors,
            widths=width,
            hatch=pattern * 2,
            bottom=bottom,
            barlabels=barlabels,
            barlabel_fontscale=0.8,
        )

        ax.margins(x=0.2 / len(series_stats), y=0.15)
        bottom += ys
        containers.append(bar)

    return containers


def sem(values: NDArray[Any]) -> float:
    return values.std() / np.sqrt(len(values))


if __name__ == "__main__":
    main()
