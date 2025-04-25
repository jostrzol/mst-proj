#!/usr/bin/env python3

import csv
from collections.abc import Iterable
from functools import lru_cache
from pathlib import Path
from typing import NamedTuple, TypedDict, final, override

from matplotlib import pyplot as plt


class Language(TypedDict):
    name: str
    slug: str
    color: str


ANALYSIS_DIR = Path("./analysis/")
ARTIFACTS_DIR = Path("./artifacts/")
EXPERIMENTS = [
    "1-blinky",
    "1-blinky-bm",
    "2-motor",
    "2-motor-bm",
    "3-pid",
    "3-pid-bm",
]
LANGUAGES: list[Language] = [
    {"name": "C", "slug": "c", "color": "cornflowerblue"},
    {"name": "Zig", "slug": "zig", "color": "orange"},
    {"name": "Rust", "slug": "rust", "color": "indianred"},
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


def plot_experiment(experiment: str):
    langs_to_infos: dict[str, FunctionInfos] = {}
    for lang in LANGUAGES:
        path = ANALYSIS_DIR / f"{experiment}-{lang['slug']}.csv"
        with path.open() as file:
            infos = FunctionInfos.from_csv(file)
        langs_to_infos[lang["slug"]] = infos

    plt.figure()

    titles = ["CCN'", "NLOC", "Liczba tokenów"]
    fields = ["ccn_prim", "nloc_count", "token_count"]
    labels = [lang["name"] for lang in LANGUAGES]
    colors = [lang["color"] for lang in LANGUAGES]
    for i, (title, field) in enumerate(zip(titles, fields)):
        values = [getattr(infos, field) for infos in langs_to_infos.values()]
        plt.subplot(2, 2, i + 1)
        plt.bar(labels, values, edgecolor="black", facecolor=colors)
        plt.title(title)

    execs = [ARTIFACTS_DIR / f"{experiment}-{lang['slug']}" for lang in LANGUAGES]
    sizes = [exec.stat().st_size / 1000 for exec in execs]
    plt.subplot(2, 2, 4)
    plt.bar(labels, sizes, edgecolor="black", facecolor=colors)
    plt.title("Rozmiar [KB]")

    plt.tight_layout()

    out_path = ANALYSIS_DIR / f"{experiment}.svg"
    plt.savefig(out_path)


def main():
    for experiment in EXPERIMENTS:
        plot_experiment(experiment)


if __name__ == "__main__":
    main()
