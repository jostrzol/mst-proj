from typing import TypedDict


class Experiment(TypedDict):
    slug: str
    name: str
    number: int
    is_bm: bool


EXPERIMENTS = {
    "1-blinky": {
        "slug": "1-blinky",
        "number": 1,
        "name": "blinky",
        "is_bm": False,
    },
    "1-blinky-bm": {
        "slug": "1-blinky-bm",
        "number": 1,
        "name": "blinky-bm",
        "is_bm": True,
    },
    "2-motor": {
        "slug": "2-motor",
        "number": 2,
        "name": "motor",
        "is_bm": False,
    },
    "2-motor-bm": {
        "slug": "2-motor-bm",
        "number": 2,
        "name": "motor-bm",
        "is_bm": True,
    },
    "3-pid": {
        "slug": "3-pid",
        "number": 3,
        "name": "pid",
        "is_bm": False,
    },
    "3-pid-bm": {
        "slug": "3-pid-bm",
        "number": 3,
        "name": "pid-bm",
        "is_bm": True,
    },
}
