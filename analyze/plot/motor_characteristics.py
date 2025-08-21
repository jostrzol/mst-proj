#!/usr/bin/env python3

# pyright: reportUnusedCallResult=false

import csv

from matplotlib import pyplot as plt

from analyze.lib.constants import DATA_DIR, PLOT_DIR

MOTOR_CHARACTERISTICS_PATH = DATA_DIR / "motor-characteristics.csv"
OUT_PATH = PLOT_DIR / "motor-characteristics.pdf"


def main():
    with MOTOR_CHARACTERISTICS_PATH.open() as file:
        reader = csv.reader(file)
        points = [(float(x) / 100, float(y)) for x, y in reader]

    xs, ys = zip(*points)

    plt.figure()
    plt.title("Charakterystyka statyczna silnika")

    plt.plot(xs, ys, color="black")

    match points:
        case [(x_first, y_first), *_]:
            xs = [0, x_first, x_first]
            ys = [0, 0, y_first]
            plt.plot(xs, ys, color="black", linestyle="--")
        case _:
            pass

    plt.xlim(0, 1)
    plt.xlabel("Sterowanie")
    plt.ylim(0, None)
    plt.ylabel("Frequency $[Hz]$")

    plt.tight_layout()

    plt.savefig(OUT_PATH)
    plt.close()


if __name__ == "__main__":
    main()
