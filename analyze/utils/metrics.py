# pyright: reportUnknownArgumentType=false
# pyright: reportUnknownLambdaType=false
# pyright: reportUnknownVariableType=false

from pathlib import Path

import pandas as pd

EXPERIMENT = "3-pid-bm"
LANGUAGES = ["c", "zig"]


def read_metrics(path: str):
    df = pd.read_csv(
        path,
        names=[
            "nloc_count",
            "ccn",
            "token_count",
            "param_count",
            "loc_count",
            "location",
            "path",
            "function_name",
            "function_signature",
            "first_line",
            "last_line",
        ],
    )
    df["ccn"] = df["ccn"] - 1
    df["path"] = df["path"].apply(lambda p: Path(p).stem.replace("_", "").lower())
    return df


if __name__ == "__main__":
    lang_metrics = [
        read_metrics(f"./analysis/{EXPERIMENT}-{lang}.csv") for lang in LANGUAGES
    ]

    for metrics, lang in zip(lang_metrics, LANGUAGES):
        print(f"{lang.upper()}:")
        print(metrics.loc[:, ["path", "function_name", "ccn"]].to_markdown())
        print()

    ccns = []
    for metrics, lang in zip(lang_metrics, LANGUAGES):
        print(f"{lang.upper()}:")
        group = metrics.groupby(["path"])
        ccn = group["ccn"].sum()
        print(ccn.to_markdown())
        print()

        ccns.append(ccn)

    if len(LANGUAGES) == 2:
        print(f"{LANGUAGES[1].upper()} - {LANGUAGES[0].upper()}:")
        print((ccns[1] - ccns[0]).to_markdown())
