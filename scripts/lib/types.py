from dataclasses import astuple, dataclass
from typing import Any

import numpy as np


@dataclass
class Benchmark:
    report_number: int
    name: str
    value: float

    def __array__(self):
        return np.array(astuple(self)[1:])

    @classmethod
    def from_dict(cls, dict: dict[str, Any]):
        return cls(
            report_number=int(dict["report_number"]),
            name=dict["name"],
            value=float(dict["value"]),
        )
