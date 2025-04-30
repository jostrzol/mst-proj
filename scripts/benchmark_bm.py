#!/usr/bin/env python3

# pyright: reportAny=false
import csv
import dataclasses
import math
import os
import re
import subprocess
import sys
from argparse import ArgumentParser
from datetime import datetime, timedelta
from pathlib import Path
from time import sleep
from typing import IO, TYPE_CHECKING, Callable, Protocol

from lib.constants import PERF_DIR
from lib.types import MemReport, PerformanceReport

if TYPE_CHECKING:
    from _typeshed import DataclassInstance

from rich.progress import Progress

CONNECTING = re.compile(rb"Connecting...")
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


class Args(Protocol):
    files: list[str]
    reports: int
    retries: int
    iters: int
    reset: bool


args: Args


def main():
    parser = ArgumentParser()
    _ = parser.add_argument("files", type=str, nargs="*")
    _ = parser.add_argument("--reset", type=bool, const=True, nargs="?", default=False)
    _ = parser.add_argument("--iters", type=int, default=5)
    _ = parser.add_argument("--reports", type=int, default=100)
    _ = parser.add_argument("--retries", type=int, default=10)

    global args
    args = parser.parse_args()  # pyright: ignore[reportAssignmentType]

    PERF_DIR.mkdir(exist_ok=True, parents=True)

    for elf_path_str in args.files:
        elf_path = Path(elf_path_str)
        benchmark(elf_path)


def benchmark(elf_path: Path):
    print(f"Benchmarking: {elf_path}")

    name, *_ = elf_path.name.split(".")
    perf_outs = [PERF_DIR / f"{name}-perf-{i}.csv" for i in range(args.iters)]
    mem_outs = [PERF_DIR / f"{name}-mem-{i}.csv" for i in range(args.iters)]

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
            _ = reset_usb()
            sleep(2)
            # with monitor() if is_init else flash(elf_path) as proc:
            with flash(elf_path) as proc:
                wait_for_connected(proc)
                if not is_init:
                    wait_for_flash_finish(proc)
                    is_init = True
                return gather_results(proc)

        def on_error():
            sleep(1)

        result = retry(iteration, times=args.retries, on_error=on_error)
        if not result:
            print(f"Failed to benchmark: {elf_path}, iteration {i}")
        else:
            perf, mem = result
            write_report(PerformanceReport, perf, perf_outs[i])
            write_report(MemReport, mem, mem_outs[i])


def flash(elf_path: Path):
    return launch(["espflash", "flash", "--monitor", str(elf_path)])


def monitor():
    return launch(["espflash", "monitor", "--non-interactive"])


def launch(command: list[str]):
    return subprocess.Popen(command, stderr=subprocess.PIPE, stdout=subprocess.PIPE)


def reset_usb():
    print("Resetting usb device")
    vendor = os.environ["USB_VENDOR"]
    product = os.environ["USB_PRODUCT"]
    command = ["usb_modeswitch", "-v", vendor, "-p", product, "--reset-usb"]
    print(f"Running: {command}")
    return subprocess.run(
        ["usb_modeswitch", "-v", vendor, "-p", product, "--reset-usb"], check=True
    )


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
        except Exception as e:
            print(e)
            try_count += 1
            if on_error:
                on_error()
            print(f"Retry number: {try_count + 1}/{times}")
    return None


def wait_for_connected(proc: subprocess.Popen[bytes]):
    if proc.stderr is None:
        raise Exception("stderr not opened")

    is_connecting = False
    while proc.poll() is None:
        line = readline_non_blocking(proc.stderr, timeout=5)
        _ = sys.stderr.buffer.write(line)
        _ = sys.stderr.flush()
        if is_connecting:
            break
        if CONNECTING.search(line):
            is_connecting = True
    if proc.returncode is not None:
        raise Exception(f"Unexpected process finish, ret: {proc.returncode}")


def wait_for_flash_finish(proc: subprocess.Popen[bytes]):
    if proc.stderr is None:
        raise Exception("stderr not opened")

    while proc.poll() is None:
        line = readline_non_blocking(proc.stderr, timeout=15)
        _ = sys.stderr.buffer.write(line)
        _ = sys.stderr.flush()
        if FLASH_FINISHED.search(line):
            break
    if proc.returncode is not None:
        raise Exception(f"Unexpected process finish, ret: {proc.returncode}")


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


def gather_results(proc: subprocess.Popen[bytes]):
    perf: list[PerformanceReport] = []
    stack: list[MemReport] = []
    heap: list[MemReport] = []

    patterns = [PERFORMANCE, MEM_STACK, MEM_HEAP]
    types = [PerformanceReport, MemReport, MemReport]
    report_sets = [perf, stack, heap]

    with Progress() as progress:
        task = progress.add_task("Collecting reports", total=args.reports)

        while (
            proc.poll() is None and proc.stdout is not None and len(perf) < args.reports
        ):
            line = readline_non_blocking(proc.stdout, timeout=15)
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
