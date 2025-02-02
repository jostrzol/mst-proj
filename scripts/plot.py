#!/usr/bin/env python3

import csv
from argparse import ArgumentParser
from collections.abc import Iterable
from dataclasses import dataclass
from functools import lru_cache
from typing import NamedTuple, final, override

from matplotlib import pyplot as plt


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
        return "\n".join([
            "FunctionInfos([",
            *("  " + repr(info) + "," for info in self.infos),
            "])",
        ])

    @classmethod
    def from_csv(cls, file: Iterable[str]):
        reader = csv.reader(file)
        infos = [FunctionInfo.from_csv_row(row) for row in reader]
        return cls(infos)


@dataclass
class Args:
    files: list[str]
    out: str | None


def main():
    parser = ArgumentParser(description="generates plots for lizard outputs")
    _ = parser.add_argument(
        "files",
        nargs="*",
        type=str,
        help="CSV output from lizard, in format <lang>:<path>, e.g. zig:lizard-zig.csv",
    )
    _ = parser.add_argument(
        "--out",
        nargs="?",
        type=str,
        help="output file; will show the plot if not given",
    )
    args: Args = parser.parse_args()  # pyright: ignore[reportAssignmentType]

    langs_to_infos: dict[str, FunctionInfos] = {}
    for lang_path_pair in args.files:
        [lang, path] = lang_path_pair.split(":")
        with open(path) as file:
            infos = FunctionInfos.from_csv(file)
        langs_to_infos[lang] = infos

    titles = ["CCN", "NLOC", "LOC", "Liczba tokenów"]
    fields = ["ccn", "nloc_count", "loc_count", "token_count"]
    labels = list(langs_to_infos.keys())
    for i, (title, field) in enumerate(zip(titles, fields)):
        values = [getattr(infos, field) for infos in langs_to_infos.values()]
        _ = plt.subplot(2, 2, i + 1)
        _ = plt.bar(labels, values, edgecolor="black", facecolor="dimgray")
        _ = plt.title(title)

    _ = plt.tight_layout()

    if args.out is not None:
        _ = plt.savefig(args.out)
    else:
        _ = plt.show()


if __name__ == "__main__":
    main()
