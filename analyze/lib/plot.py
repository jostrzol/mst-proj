import colorsys
import locale
from collections.abc import Iterable, Sequence
from datetime import datetime
from itertools import cycle
from pathlib import Path
from typing import Any, Literal

import matplotlib.colors as mc
import numpy as np
import pandas as pd
import scienceplots as _  # pyright: ignore[reportMissingTypeStubs]
from matplotlib import pyplot as plt
from matplotlib import rcParams
from matplotlib.axes import Axes
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.colors import to_rgb
from matplotlib.container import BarContainer
from matplotlib.figure import Figure
from matplotlib.ticker import PercentFormatter
from matplotlib.typing import ColorType

# To make the pdfs identical if nothing changes
PDF_DATE = datetime(2025, 8, 23)


def plot_bar(
    xs: Sequence[Any] | np.ndarray,
    ys: Sequence[Any] | np.ndarray,
    *,
    widths: Sequence[Any] | float | None = None,
    colors: Sequence[ColorType] | None = None,
    hatch: Sequence[str] | None = None,
    bottom: Sequence[Any] | np.ndarray | float | None = None,
    barlabels: Sequence[Any] | bool | None = None,
    barlabel_decimals: int = 0,
    barlabel_fontscale: float = 1,
    linewidth: float = 0,
    ax: Axes | None = None,
    rotation: bool | float = False,
    fontsize: int | None = None,
    ymax: float | None | Literal[False] = None,
    ymargin: float | None = None,
    xticks: bool = True,
) -> BarContainer:
    ax = ax or plt.axes()
    bar = ax.bar(
        xs,
        ys,
        width=widths or 0.5,
        color=colors,
        hatch=hatch,
        bottom=bottom,
        edgecolor="black",
        linewidth=linewidth,
    )

    fontsize_val = fontsize or rcParams["font.size"] or 12
    if barlabels == True or barlabels == None:
        barlabels = [fmt(f"%.{barlabel_decimals}f", y) for y in ys]
    if barlabels == False:
        barlabels = [""] * len(ys)
    fontsize_barlabel = fontsize_val * barlabel_fontscale
    barlabel_padding = 2
    _ = ax.bar_label(
        bar,
        barlabels,
        fontsize=fontsize_barlabel,
        padding=barlabel_padding,
    )

    _ = ax.margins(x=0.5 / len(ys))

    if ymax != False:
        if ymax is None:
            _, ymax = ax.get_ylim()
        ymargin = ymargin or (0.2 if any(barlabels) else 0.05)
        _ = ax.set_ylim(ymax=ymax * (1 + ymargin))

    if xticks:
        if rotation == True:
            rotation = 45
        elif rotation == False:
            rotation = 0
        _ = ax.set_xticks(
            xs,
            xs,
            fontsize=fontsize,
            ha="right" if rotation != 0 else "center",
            va="top",
            multialignment="right",
            rotation=rotation,
            rotation_mode="anchor",
        )
        ax.tick_params(axis="x", length=0)
        ax.tick_params(axis="x", which="minor", length=0)

    return bar


def plot_hist(
    labels: Sequence[Any],
    *,
    ax: Axes | None = None,
    total: float | None = None,
    xrange: Iterable[Any] | None = None,
    rotation: bool | float = False,
    sort_by_index: bool = False,
    fontsize: int | None = None,
    ymax: float | None = None,
    ymargin: float | None = None,
    bottom: Sequence[Any] | np.ndarray | float | None = None,
    barlabels: Sequence[Any] | bool | None = None,
    colors: Sequence[ColorType] | None = None,
    widths: Sequence[Any] | float | None = None,
) -> BarContainer:
    series = pd.Series(labels)
    total = total if total else len(series)

    values = series.explode().value_counts()
    for label in xrange or []:
        if label not in values:
            values[label] = 0
    if sort_by_index:
        values = values.sort_index()

    ys = values / total * 100

    ax = ax or plt.axes()
    bar = plot_bar(
        xs=values.index.to_list(),
        ys=ys.to_list(),
        barlabels=barlabels or values.to_list(),
        ax=ax,
        rotation=rotation,
        fontsize=fontsize,
        ymax=ymax / total * 100 if ymax else None,
        ymargin=ymargin,
        bottom=bottom,
        colors=colors,
        widths=widths,
    )
    ax.yaxis.set_major_formatter(PercentFormatter(decimals=0))

    return bar


def plot_hist_horiz(
    labels: Sequence[Any],
    *,
    ax: Axes | None = None,
    total: float | None = None,
    yrange: Iterable[Any] | None = None,
    sort_by_index: bool = False,
    fontsize: int | None = None,
    xticks_side: Literal["left"] | Literal["right"] = "left",
) -> BarContainer:
    series = pd.Series(labels)
    total = total if total else len(series)

    values = series.explode().value_counts()
    for label in yrange or []:
        if label not in values:
            values[label] = 0
    if sort_by_index:
        values = values.sort_index()
    values = values[::-1]

    xs = values / total * 100
    ys = range(len(xs))

    ax = ax or plt.axes()
    bar = ax.barh(ys, xs, height=0.5)

    _ = ax.set_yticks(ys, values.index, fontsize=fontsize)
    ax.tick_params(axis="y", length=0)
    ax.tick_params(axis="y", which="minor", length=0)

    ax.xaxis.set_major_formatter(PercentFormatter(decimals=0))
    if xticks_side == "right":
        ax.tick_params(labelleft=False, labelright=True)
        ax.invert_xaxis()

    _ = ax.bar_label(bar, values, padding=3)
    _ = ax.margins(x=0.2, y=0.8 / len(ys))

    return bar


def savefig(fig: Figure, path: Path):
    fig.savefig(path.with_suffix(".svg"))
    with PdfPages(path.with_suffix(".pdf")) as pdf:
        d = pdf.infodict()
        d["CreationDate"] = PDF_DATE
        d["ModDate"] = PDF_DATE
        pdf.savefig()


def gray_shades(n: int, shades: Literal["light"] | Literal["dark"] = "dark"):
    start, end = (1.0, 0.6) if shades == "light" else (1.0, 0.0)
    return [f"{shade:.2f}" for shade in np.linspace(start, end, n)]


def add_bar_texts(
    ax: Axes,
    ys: Iterable[float],
    texts: Iterable[object],
    *,
    above_color: Iterable[ColorType] | ColorType | None = None,
    below_color: Iterable[ColorType] | ColorType | None = None,
    bg_color: Iterable[ColorType] | None = None,
    size: str | float | None = None,
):
    _, ymax = ax.get_ylim()
    margin = ymax / 50

    if isinstance(above_color, str | None):
        above_color = cycle([above_color if above_color else "black"])
    if isinstance(below_color, str | None):
        if bg_color is not None and below_color is None:
            below_color = map(fg_color_for_bg_color, bg_color)
        else:
            below_color = cycle([below_color if below_color else "white"])

    for i, (y, text, above, below) in enumerate(
        zip(ys, texts, above_color, below_color)
    ):
        if y < 0.9 * ymax:
            _ = ax.text(
                i,
                y + margin,
                str(text),
                ha="center",
                color=above,
                size=size,
            )
        else:
            _ = ax.text(
                i,
                y - margin,
                str(text),
                ha="center",
                va="top",
                color=below,
                size=size,
            )


def fg_color_for_bg_color(bg_color: ColorType) -> ColorType:
    """
    Source: https://stackoverflow.com/a/3943023/30363130
    """
    r, g, b = to_rgb(bg_color)
    value = r * 0.299 + g * 0.587 + b * 0.114
    return "black" if value > 170 / 255 else "white"
    # rp, gp, bp = [
    #     c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb
    # ]
    # L = 0.2126 * rp + 0.7152 * gp + 0.0722 * bp
    # return "black" if L > 0.179 else "white"


def lighten_color(color: ColorType | str, amount: float) -> ColorType:
    """
    Source: https://gist.github.com/ihincks/6a420b599f43fcd7dbd79d56798c4e5a

    Lightens the given color by multiplying (1-luminosity) by the given amount.
    Input can be matplotlib color string, hex string, or RGB tuple.

    Examples:
    >> lighten_color('g', 0.3)
    >> lighten_color('#F034A3', 0.6)
    >> lighten_color((.3,.55,.1), 0.5)
    """
    try:
        c = mc.cnames[color]  # pyright:ignore[reportArgumentType]
    except Exception:
        c = color
    c = colorsys.rgb_to_hls(*mc.to_rgb(c))
    return colorsys.hls_to_rgb(c[0], 1 - (1 - amount) * (1 - c[1]), c[2])


def use_plot_style():
    set_locale()
    plt.style.use(["science", "ieee", "notebook", "./analyze/style.mplstyle"])

def set_locale():
    try:
        _ = locale.setlocale(locale.LC_NUMERIC, "pl_PL.UTF-8")
    except Exception as e:
        msg = """
Could not set locale to pl_PL.UTF-8. Ensure that pl_PL.UTF-8 locale is installed
and that LC_ALL environment variable is NOT an empty string.

Falling back to the default locale.
        """
        print(msg, e)


def fmt(fmt: str, val: Any) -> str:
    return locale.format_string(fmt, val)


def figsize_rel(w: float = 1, h: float = 1) -> tuple[float, float]:
    size_abs = plt.rcParams.get("figure.figsize")
    assert size_abs
    w_abs, h_abs = size_abs
    return w_abs * w, h_abs * h
