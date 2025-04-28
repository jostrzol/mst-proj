from collections.abc import Iterable

from matplotlib.axes import Axes
from matplotlib.typing import ColorType


def add_bar_texts(
    ax: Axes,
    ys: Iterable[float],
    texts: Iterable[object],
    *,
    above_color: str | None = None,
    below_color: str | None = "white",
    size: str | float | None = None,
):
    _, ymax = ax.get_ylim()
    margin = ymax / 50
    for i, (y, text) in enumerate(zip(ys, texts)):
        if y < 0.9 * ymax:
            _ = ax.text(
                i,
                y + margin,
                str(text),
                ha="center",
                color=above_color,
                size=size,
            )
        else:
            _ = ax.text(
                i,
                y - margin,
                str(text),
                ha="center",
                va="top",
                color=below_color,
                size=size,
            )


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
    import colorsys

    import matplotlib.colors as mc

    try:
        c = mc.cnames[color]  # pyright:ignore[reportArgumentType]
    except Exception:
        c = color
    c = colorsys.rgb_to_hls(*mc.to_rgb(c))
    return colorsys.hls_to_rgb(c[0], 1 - (1 - amount) * (1 - c[1]), c[2])
