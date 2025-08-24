#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false
# pyright: reportUninitializedInstanceVariable=false


import pandas as pd
import pandera.pandas as pa
from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.figure import Figure
from pandas.api.typing import SeriesGroupBy
from pandera.typing import DataFrame, Series

from analyze.lib.constants import ARTIFACTS_DIR, LIZARD_DIR, PLOT_DIR
from analyze.lib.experiments import EXPERIMENTS
from analyze.lib.language import LANGUAGES, Language
from analyze.lib.plot import plot_bar, savefig, use_plot_style

OUT_DIR = PLOT_DIR / "metrics"

COLUMNS = [
    "nloc",
    "ccn",
    "n_tokens",
    "n_params",
    "length",
    "location",
    "file",
    "name",
    "signature",
    "line_start",
    "line_end",
]


class Schema(pa.DataFrameModel):
    nloc: Series[int]
    ccn: Series[int]
    n_tokens: Series[int]
    n_params: Series[int]
    length: Series[int]
    location: Series[str]
    file: Series[str]
    name: Series[str]
    signature: Series[str]
    line_start: Series[int]
    line_end: Series[int]
    lang: Series[str]
    experiment: Series[str]
    bin_size: Series[float]


def load_data() -> DataFrame[Schema]:
    df = pd.DataFrame()
    for experiment in EXPERIMENTS.values():
        for lang in LANGUAGES.values():
            slug = f"{experiment['slug']}-{lang['slug']}"
            path = LIZARD_DIR / f"{slug}.csv"
            df_part = pd.read_csv(path, names=COLUMNS)
            df_part["lang"] = lang["slug"]
            df_part["experiment"] = experiment["slug"]

            exec = ARTIFACTS_DIR / "small" / slug
            df_part["bin_size"] = exec.stat().st_size / 1000

            df = pd.concat([df, df_part])
    return Schema.validate(df)


def plot_param(fig: Figure, series: pd.Series, is_bm: bool) -> list[Axes]:
    experiments = [
        experiment
        for experiment in EXPERIMENTS.values()
        if experiment["is_bm"] == is_bm
    ]

    axs = fig.subplots(1, len(experiments))
    for experiment, ax in zip(experiments, axs):
        values: pd.Series = series[experiment["slug"]]
        values = values.reindex([*LANGUAGES.keys()])

        lang_slugs = values.index.get_level_values("lang")
        langs: list[Language] = lang_slugs.map(LANGUAGES.get).to_list()
        names = [lang["name"] for lang in langs]
        colors = [lang["color"] for lang in langs]
        plot_bar(
            names,
            values.to_list(),
            ax=ax,
            colors=colors,
            linewidth=1.5,
        )
        ax.set_title(f"Scenariusz {experiment['number']}")

    return axs


def main():
    OUT_DIR.mkdir(exist_ok=True, parents=True)
    use_plot_style()

    df = load_data()
    ccn = df["ccn"]

    ccnp = ccn - 1
    ccnp.name = "ccnp"

    cols = [
        df["bin_size"],
        ccnp,
        df["nloc"],
        df["n_tokens"],
    ]
    aggregations = [
        SeriesGroupBy.min,
        SeriesGroupBy.sum,
        SeriesGroupBy.sum,
        SeriesGroupBy.sum,
    ]

    for col, aggregate in zip(cols, aggregations):
        assert col.name is not None
        name = str(col.name)

        col_df = pd.concat([col, df["lang"], df["experiment"]], axis=1)
        groupped = col_df.groupby(["experiment", "lang"])[name]
        to_plot = aggregate(groupped)

        for is_bm in [True, False]:
            fig = plt.figure()
            axs = plot_param(fig, to_plot, is_bm=is_bm)

            if name == "bin_size":
                axs[0].set_ylabel("Rozmiar $[kB]$")

            platform = "bm" if is_bm else "os"
            savefig(fig, OUT_DIR / f"{name}-{platform}")
            plt.close(fig)


if __name__ == "__main__":
    main()
