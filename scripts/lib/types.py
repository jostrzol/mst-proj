from dataclasses import astuple, dataclass

import numpy as np


@dataclass
class Benchmark:
    report_number: int
    name: str
    value: int

    def __array__(self):
        return np.array(astuple(self)[1:])
