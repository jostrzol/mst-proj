#!/usr/bin/env python3

import csv
import dataclasses
import math
import os
import re
import subprocess
from argparse import ArgumentParser
from datetime import datetime, timedelta
from pathlib import Path
from signal import SIGINT
from typing import IO, Callable, Protocol

from lib.constants import PERF_DIR
from lib.types import Benchmark
from rich.progress import Progress

REPORT = re.compile(rb"# REPORT (?P<report_number>\d+)")
PERFORMANCE = re.compile(
    rb"Performance counter "  # pyright: ignore[reportImplicitStringConcatenation]
    rb"(?P<name>[^:]+)"
    rb": \[(?P<samples>[0-9,]+)\] us"
)
MEM_STACK = re.compile(rb"(?P<name>\w+) stack usage: (?P<sample>\d+) B")
MEM_HEAP = re.compile(rb"(?P<name>Heap) usage: (?P<sample>\d+) B")


class Args(Protocol):
    files: list[str]
    remote: str
    remote_app_dir: Path
    reports: int
    retries: int
    iters: int
    reset: bool


args: Args


def main():
    parser = ArgumentParser()
    _ = parser.add_argument("files", type=str, nargs="*")
    _ = parser.add_argument("--remote", type=str, default="raspberrypi.local")
    _ = parser.add_argument("--remote-app-dir", type=Path, default="~/app/")
    _ = parser.add_argument("--reset", type=bool, const=True, nargs="?", default=False)
    _ = parser.add_argument("--iters", type=int, default=5)
    _ = parser.add_argument("--reports", type=int, default=100)
    _ = parser.add_argument("--retries", type=int, default=10)

    global args
    args = parser.parse_args()  # pyright: ignore[reportAssignmentType]

    try:
        for binary_path_str in args.files:
            binary_path = Path(binary_path_str)
            benchmark(binary_path)
    except KeyboardInterrupt:
        print("Benchmark stopped")


def benchmark(binary_path: Path):
    print(f"Benchmarking: {binary_path}")

    name, *_ = binary_path.name.split(".")
    profile = binary_path.parent.name
    perf_profile_dir = PERF_DIR / profile
    perf_profile_dir.mkdir(exist_ok=True, parents=True)

    perf_outs = [perf_profile_dir / f"{name}-perf-{i}.csv" for i in range(args.iters)]
    mem_outs = [perf_profile_dir / f"{name}-mem-{i}.csv" for i in range(args.iters)]

    found: list[int] = []
    to_do: list[int] = []
    for i, (perf_out, mem_out) in enumerate(zip(perf_outs, mem_outs)):
        if perf_out.exists() and mem_out.exists():
            found.append(i)
        else:
            to_do.append(i)
    print(f"Found results for iterations: {found}")

    if args.reset:
        print("Resetting found results")
        for i in found:
            perf_outs[i].unlink()
            mem_outs[i].unlink()
        to_do = list(range(args.iters))

    print(f"Executing iterations: {to_do}")

    is_init = False
    for i in to_do:

        def iteration():
            nonlocal is_init
            if not is_init:
                upload_binary(binary_path)
                is_init = True

            with start_binary(binary_path) as proc:
                try:
                    return gather_results(proc)
                finally:
                    proc.send_signal(SIGINT)

        def on_error():
            kill_all()

        result = retry(iteration, times=args.retries, on_error=on_error)
        if not result:
            print(f"Failed to benchmark: {binary_path}, iteration {i}")
        else:
            perf, mem = result
            write_report(perf, perf_outs[i])
            write_report(mem, mem_outs[i])


def upload_binary(binary: Path):
    print(f"Uploading binary {binary.name}")
    _ = subprocess.run(["ssh", args.remote, "mkdir", "-p", str(args.remote_app_dir)])
    _ = subprocess.run(["scp", str(binary), f"{args.remote}:{args.remote_app_dir}"])


def kill_all():
    print("Killing all running app binaries")
    query = args.remote_app_dir.name + "/"
    cmd1 = ["sudo", "pkill", "--full", query]
    cmd2 = ["sudo", "pkill", "-9", "--full", query]
    cmd = cmd1 + ["&&", "sleep", "1", "&&"] + cmd2
    _ = subprocess.run(["ssh", args.remote] + cmd)


def start_binary(binary: Path):
    target_binary = args.remote_app_dir / binary.name
    return launch(["ssh", "-t", args.remote, "sudo", str(target_binary)])


def launch(command: list[str]):
    return subprocess.Popen(command, stderr=subprocess.PIPE, stdout=subprocess.PIPE)


def retry[T](
    function: Callable[[], T],
    times: int,
    on_error: Callable[[], None] | None = None,
) -> T | None:
    try_count = 0
    is_done = False
    while try_count < times and not is_done:
        try:
            return function()
        except KeyboardInterrupt:
            raise
        except Exception as e:
            print(e)
            try_count += 1
            if on_error:
                on_error()
            print(f"Retry number: {try_count + 1}/{times}")
    return None


def gather_results(proc: subprocess.Popen[bytes]):
    perf: list[Benchmark] = []
    stack: list[Benchmark] = []
    heap: list[Benchmark] = []

    patterns = [PERFORMANCE, MEM_STACK, MEM_HEAP]
    report_sets = [perf, stack, heap]
    are_combined = [True, False, False]

    report_number = 0
    with Progress() as progress:
        task = progress.add_task("Collecting reports", total=args.reports)

        while (
            proc.poll() is None
            and proc.stdout is not None
            and report_number < args.reports
        ):
            line = readline_non_blocking(proc.stdout, timeout=15)

            match = REPORT.search(line)
            if match is not None:
                new_report_number = int(match.group("report_number"))
                diff = new_report_number - report_number
                progress.update(task, advance=diff)
                report_number = new_report_number
                continue

            for pattern, report_set, is_combined in zip(
                patterns, report_sets, are_combined
            ):
                match = pattern.search(line)
                if match is None:
                    continue

                groups = match.groupdict()
                if is_combined:
                    values = [int(sample) for sample in groups["samples"].split(b",")]
                    benchmarks = [
                        Benchmark(
                            report_number=report_number,
                            name=groups["name"].decode(),
                            value=value,
                        )
                        for value in values
                    ]
                    pass
                else:
                    benchmark = Benchmark(
                        report_number=report_number,
                        name=groups["name"].decode(),
                        value=int(groups["sample"]),
                    )
                    benchmarks = [benchmark]

                report_set.extend(benchmarks)

    if proc.returncode is not None:
        raise Exception(f"Unexpected process finish, ret: {proc.returncode}")

    return perf, stack + heap


def readline_non_blocking(file: IO[bytes], timeout: float = math.inf):
    tout = timedelta(seconds=timeout)
    last_byte_at = datetime.now()
    bytes = b""

    def is_line_complete():
        nonlocal bytes
        return len(bytes) != 0 and bytes[-1:] == b"\n"

    while (
        datetime.now() < last_byte_at + tout
        and not is_line_complete()
        and not file.closed
    ):
        byte = os.read(file.fileno(), 1)
        if byte != b"":
            last_byte_at = datetime.now()
        bytes += byte

    if is_line_complete():
        return bytes
    else:
        raise Exception("Timeout")


def write_report(reports: list[Benchmark], path: Path):
    with path.open("w") as file:
        fields = [field.name for field in dataclasses.fields(Benchmark)]
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        rows = (dataclasses.asdict(row) for row in reports)
        writer.writerows(rows)


if __name__ == "__main__":
    main()
