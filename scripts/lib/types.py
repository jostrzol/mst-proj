from dataclasses import astuple, dataclass, fields

import numpy as np


@dataclass
class PerformanceReport:
    name: str
    time_us: float
    cycles: int
    samples: int

    @classmethod
    def from_dict(cls, d: dict[str, bytes]):
        return cls(
            name=d["name"].decode(),
            time_us=float(d["time_us"]),
            cycles=int(d["cycles"]),
            samples=int(d["samples"]),
        )

    @classmethod
    def stats(cls):
        return [field.name for field in fields(cls)[1:]]

    def __array__(self):
        return np.array(astuple(self)[1:])


@dataclass
class MemReport:
    name: str
    usage: int

    @classmethod
    def from_dict(cls, d: dict[str, bytes]):
        return cls(
            name=d["name"].decode(),
            usage=int(d["usage"]),
        )

    @classmethod
    def stats(cls):
        return [field.name for field in fields(cls)[1:]]

    def __array__(self):
        return np.array(astuple(self)[1:])
