#!/usr/bin/env python3
"""A tiny versioned registry — the spine of the mapping abstractions.

Every mapping the eval platform uses (SMPL->pose joints, coach-text->taxonomy
phrases, the tuning search space) is a *named, versioned* entry in one of these.
The point is isolation: iterating on one mapping (say, a better phrase map v2)
registers a new name and never mutates the frozen one the benchmark already
trusts. Nothing looks a mapping up by object identity or by editing a module
global — it asks the registry for a name, so two versions coexist without
interfering.

Contract
--------
- `register(name, value)` fails loudly on a duplicate name (no silent shadowing).
- `get(name)` fails loudly on an unknown name (no silent default).
- `names()` lists what is available, sorted, for CLIs and error messages.

stdlib only — importable under the bare interpreter (no numpy/torch).
"""
from __future__ import annotations

from typing import Generic, Iterator, TypeVar

_T = TypeVar("_T")


class Registry(Generic[_T]):
    """A frozen-by-convention name -> value map for one kind of mapping."""

    def __init__(self, kind: str) -> None:
        self._kind = kind
        self._items: dict[str, _T] = {}

    def register(self, name: str, value: _T) -> _T:
        """Add `value` under `name`. Raises if the name is already taken.

        Returns the value so it can be used as a decorator-ish one-liner:
        `FOO = REGISTRY.register("foo-v1", Foo(...))`.
        """
        if name in self._items:
            raise ValueError(
                f"{self._kind} mapping {name!r} already registered; "
                f"pick a new version name rather than overwriting a frozen one"
            )
        self._items[name] = value
        return value

    def get(self, name: str) -> _T:
        try:
            return self._items[name]
        except KeyError:
            raise KeyError(
                f"unknown {self._kind} mapping {name!r}; "
                f"available: {', '.join(self.names()) or '(none)'}"
            ) from None

    def names(self) -> list[str]:
        return sorted(self._items)

    def __contains__(self, name: object) -> bool:
        return name in self._items

    def __iter__(self) -> Iterator[str]:
        return iter(self.names())

    def __len__(self) -> int:
        return len(self._items)
