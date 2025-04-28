#!/usr/bin/env python3

# pyright: reportAny=false
import csv
import dataclasses
import re
import subprocess
import sys
from argparse import ArgumentParser
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Protocol

if TYPE_CHECKING:
    from _typeshed import DataclassInstance

from rich.progress import Progress

ANALYSIS_DIR = Path("./analysis/perf/")

FLASH_FINISHED = re.compile(rb"Flashing has completed")
PERFORMANCE = re.compile(
    rb"Performance counter "  # pyright: ignore[reportImplicitStringConcatenation]
    rb"(?P<name>[^:]+)"
    rb": (?P<time_us>[0-9.]+) us = "
    rb"(?P<cycles>[0-9]+) cycles "
    rb"\((?P<samples>[0-9]+) sampl.\)"
)
MEM_STACK = re.compile(rb"(?P<name>\w+) stack usage: (?P<usage>\d+) B")
MEM_HEAP = re.compile(rb"(?P<name>Heap) usage: (?P<usage>\d+) B")


@dataclass
class PerformanceReport:
    name: str
    time_us: float
    cycles: int
    samples: int

    @classmethod
    def from_dict(cls, d: dict[str, bytes]):
        return cls(
            name=d["name"].decode(),
            time_us=float(d["time_us"]),
            cycles=int(d["cycles"]),
            samples=int(d["samples"]),
        )


@dataclass
class MemReport:
    name: str
    usage: int

    @classmethod
    def from_dict(cls, d: dict[str, bytes]):
        return cls(
            name=d["name"].decode(),
            usage=int(d["usage"]),
        )


type Report = PerformanceReport | MemReport


class Args(Protocol):
    files: list[str]
    reports: int
    retries: int


args: Args


def main():
    parser = ArgumentParser()
    _ = parser.add_argument("files", type=str, nargs="*")
    _ = parser.add_argument("--reports", type=int, default=100)
    _ = parser.add_argument("--retries", type=int, default=10)

    global args
    args = parser.parse_args()  # pyright: ignore[reportAssignmentType]

    ANALYSIS_DIR.mkdir(exist_ok=True, parents=True)

    for elf_path_str in args.files:
        elf_path = Path(elf_path_str)
        benchmark(elf_path)


def benchmark(elf_path: Path):
    print(f"Benchmarking: {elf_path}")
    name, *_ = elf_path.name.split(".")

    try_count = 0
    is_done = False
    while try_count < args.retries and not is_done:
        try:
            with subprocess.Popen(
                ["espflash", "flash", "--monitor", str(elf_path)],
                stderr=subprocess.PIPE,
                stdout=subprocess.PIPE,
            ) as proc:
                perf, mem = gather_results(proc)
            is_done = True
        except Exception as e:
            print(e)
            try_count += 1
            print(f"Retry number: {try_count + 1}/{args.retries}")
    if not is_done:
        print(f"Failed to benchmark: {elf_path}")
        return

    perf = perf  # pyright: ignore[reportPossiblyUnboundVariable]
    mem = mem  # pyright: ignore[reportPossiblyUnboundVariable]

    write_report(PerformanceReport, perf, ANALYSIS_DIR / f"{name}-perf.csv")
    write_report(MemReport, mem, ANALYSIS_DIR / f"{name}-mem.csv")


def gather_results(proc: subprocess.Popen[bytes]):
    perf: list[PerformanceReport] = []
    stack: list[MemReport] = []
    heap: list[MemReport] = []

    while proc.poll() is None and proc.stderr is not None:
        line = proc.stderr.readline()
        _ = sys.stderr.buffer.write(line)
        _ = sys.stderr.flush()
        if FLASH_FINISHED.search(line):
            break
    if proc.returncode is not None:
        raise Exception(f"Unexpected process finish, ret: {proc.returncode}")

    patterns = [PERFORMANCE, MEM_STACK, MEM_HEAP]
    types = [PerformanceReport, MemReport, MemReport]
    report_sets = [perf, stack, heap]

    with Progress() as progress:
        task = progress.add_task("Collecting reports", total=args.reports)

        while (
            proc.poll() is None and proc.stdout is not None and len(perf) < args.reports
        ):
            line = proc.stdout.readline()
            for pattern, ty, report_set in zip(patterns, types, report_sets):
                match = pattern.search(line)
                if match is None:
                    continue

                report = ty.from_dict(match.groupdict())
                report_set.append(report)  # pyright: ignore[reportArgumentType]

                if report_set == perf:
                    progress.update(task, advance=1)

    if proc.returncode is not None:
        raise Exception(f"Unexpected process finish, ret: {proc.returncode}")

    return perf, stack + heap


def write_report[T: DataclassInstance](t: type[T], reports: list[T], path: Path):
    with path.open("w") as file:
        fields = [field.name for field in dataclasses.fields(t)]
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        rows = (dataclasses.asdict(row) for row in reports)
        writer.writerows(rows)


if __name__ == "__main__":
    main()
