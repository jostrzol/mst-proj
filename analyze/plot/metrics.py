#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv
from collections.abc import Iterable
from dataclasses import dataclass
from functools import lru_cache
from typing import NamedTuple, final, override

from matplotlib import pyplot as plt
from matplotlib.figure import Figure

from analyze.lib.constants import ANALYSIS_DIR, ARTIFACTS_DIR, PLOT_DIR
from analyze.lib.language import LANGUAGES
from analyze.lib.plot import add_bar_texts, savefig

EXPERIMENTS = [
    "1-blinky",
    "1-blinky-bm",
    "2-motor",
    "2-motor-bm",
    "3-pid",
    "3-pid-bm",
]


class FunctionInfo(NamedTuple):
    nloc_count: int
    ccn: int
    token_count: int
    param_count: int
    loc_count: int
    location: str
    path: str
    function_name: str
    function_signature: str
    first_line: int
    last_line: int

    @classmethod
    def from_csv_row(cls, row: list[str]):
        [
            nloc_count,
            ccn,
            token_count,
            param_count,
            loc_count,
            location,
            path,
            function_name,
            function_signature,
            first_line,
            last_line,
        ] = row
        return cls(
            nloc_count=int(nloc_count),
            ccn=int(ccn),
            token_count=int(token_count),
            param_count=int(param_count),
            loc_count=int(loc_count),
            location=location,
            path=path,
            function_name=function_name,
            function_signature=function_signature,
            first_line=int(first_line),
            last_line=int(last_line),
        )


@final
class FunctionInfos:
    def __init__(self, infos: list[FunctionInfo]):
        self.infos = infos

    @property
    @lru_cache
    def nloc_count(self) -> int:
        return sum(info.nloc_count for info in self.infos)

    @property
    @lru_cache
    def ccn(self) -> int:
        return sum(info.ccn for info in self.infos)

    @property
    @lru_cache
    def ccn_prim(self) -> int:
        return sum(info.ccn - 1 for info in self.infos)

    @property
    @lru_cache
    def token_count(self) -> int:
        return sum(info.token_count for info in self.infos)

    @property
    @lru_cache
    def loc_count(self) -> int:
        return sum(info.loc_count for info in self.infos)

    def __len__(self) -> int:
        return len(self.infos)

    def __iter__(self):
        return iter(self.infos)

    @override
    def __repr__(self) -> str:
        return "\n".join(
            [
                "FunctionInfos([",
                *("  " + repr(info) + "," for info in self.infos),
                "])",
            ]
        )

    @classmethod
    def from_csv(cls, file: Iterable[str]):
        reader = csv.reader(file)
        infos = [FunctionInfo.from_csv_row(row) for row in reader]
        return cls(infos)


@dataclass
class ExperimentData:
    langs_to_infos: dict[str, FunctionInfos]
    sizes: list[float]

    @classmethod
    def from_fs(cls, experiment: str):
        langs_to_infos: dict[str, FunctionInfos] = {}
        for lang in LANGUAGES.values():
            path = ANALYSIS_DIR / f"{experiment}-{lang['slug']}.csv"
            with path.open() as file:
                infos = FunctionInfos.from_csv(file)
            langs_to_infos[lang["slug"]] = infos

        execs = [
            ARTIFACTS_DIR / "small" / f"{experiment}-{lang['slug']}"
            for lang in LANGUAGES.values()
        ]
        sizes = [exec.stat().st_size / 1000 for exec in execs]

        return cls(langs_to_infos=langs_to_infos, sizes=sizes)


def plot_experiment(
    figure: Figure, experiment: str, data: ExperimentData, suffix: str = ""
):
    labels = [lang["name"] for lang in LANGUAGES.values()]
    colors = [lang["color"] for lang in LANGUAGES.values()]

    ax = plt.subplot(2, 2, 1)
    plt.bar(labels, data.sizes, edgecolor="black", facecolor=colors)
    texts = [f"{s:.0f}" for s in data.sizes]
    add_bar_texts(ax, data.sizes, texts, bg_color=colors)
    plt.title("Rozmiar pliku binarnego")
    plt.ylabel("Rozmiar $[kB]$")

    titles = ["CCN'", "NLOC", "Liczba tokenów"]
    fields = ["ccn_prim", "nloc_count", "token_count"]
    for i, (title, field) in enumerate(zip(titles, fields)):
        values = [getattr(infos, field) for infos in data.langs_to_infos.values()]

        ax = plt.subplot(2, 2, i + 2)
        plt.bar(labels, values, edgecolor="black", facecolor=colors)
        add_bar_texts(ax, values, values, bg_color=colors)
        plt.title(title)

    plt.tight_layout()

    out_path = PLOT_DIR / f"{experiment}{suffix}"
    savefig(figure, out_path)
    plt.close(figure)


def main():
    for experiment in EXPERIMENTS:
        data = ExperimentData.from_fs(experiment)

        figure = plt.figure()
        plot_experiment(figure=figure, experiment=experiment, data=data)

        figure = plt.figure(figsize=(4.8, 4.8))
        plot_experiment(figure=figure, experiment=experiment, data=data, suffix="-doc")


if __name__ == "__main__":
    main()
