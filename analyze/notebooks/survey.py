from pathlib import Path
from subprocess import run

QMD = Path(__file__).parent / "survey.qmd"


def render():
    _ = run(
        [
            "quarto",
            "render",
            QMD,
            "--to",
            "pdf",
            "--toc",
            "--output-dir",
            "../out/notebooks",
        ],
        check=True,
    )


def preview():
    _ = run(
        ["quarto", "preview", QMD, "--port", "5218"],
        check=True,
    )
