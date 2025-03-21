#!/usr/bin/env python3

import csv
from pathlib import Path

from matplotlib import pyplot as plt

ANALYSIS_DIR = Path("./analysis/")
ANALYSIS_SRC_DIR = Path("./analysis-src/")

MOTOR_CHARACTERISTICS_PATH = ANALYSIS_SRC_DIR / "motor-characteristics.csv"
OUT_PATH = ANALYSIS_DIR / "motor-characteristics.svg"


def main():
    with MOTOR_CHARACTERISTICS_PATH.open() as file:
        reader = csv.reader(file)
        points = [(float(x) / 100, float(y)) for x, y in reader]

    xs, ys = zip(*points)

    _ = plt.figure()
    _ = plt.title("Charakterystyka statyczna silnika")

    _ = plt.plot(xs, ys, color="black")

    match points:
        case [(x_first, y_first), *_]:
            xs = [0, x_first, x_first]
            ys = [0, 0, y_first]
            _ = plt.plot(xs, ys, color="black", linestyle="--")
        case _:
            pass

    _ = plt.xlim(0, 1)
    _ = plt.xlabel("Sterowanie")
    _ = plt.ylim(0, None)
    _ = plt.ylabel("Frequency $[Hz]$")

    _ = plt.tight_layout()

    _ = plt.savefig(OUT_PATH)


if __name__ == "__main__":
    main()
