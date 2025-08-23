import colorsys
from collections.abc import Iterable
from datetime import datetime
from itertools import cycle
from pathlib import Path

import matplotlib.colors as mc
from matplotlib import pyplot as plt
from matplotlib.axes import Axes
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.colors import to_rgb
from matplotlib.figure import Figure
from matplotlib.typing import ColorType

# To make the pdfs identical if nothing changes
PDF_DATE = datetime(2025, 8, 23)


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


def savefig(fig: Figure, path: Path):
    fig.savefig(path.with_suffix(".svg"))
    with PdfPages(path.with_suffix(".pdf")) as pdf:
        d = pdf.infodict()
        d["CreationDate"] = PDF_DATE
        d["ModDate"] = PDF_DATE
        pdf.savefig()


def use_plot_style():
    plt.style.use(["science", "ieee", "notebook", "./analyze/style.mplstyle"])


def figsize_rel(w: float = 1, h: float = 1) -> tuple[float, float]:
    size_abs = plt.rcParams.get("figure.figsize")
    assert size_abs
    w_abs, h_abs = size_abs
    return w_abs * w, h_abs * h
