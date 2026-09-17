"""Procedural painters: code that fills a recipe's cells instead of a model."""

from __future__ import annotations

from importlib import import_module


def get_painter(name: str):
    """Return `paint(recipe) -> PIL.Image` for the painter called `name`."""
    return import_module(f"{__name__}.{name}").paint
