"""Crop catalog with average days-to-harvest used for synthetic training data.

Numbers reflect typical Philippine agronomy references for common vegetables
and grains. They are *averages* — the AI model learns variation around them
based on month-of-year (a rough proxy for weather effects).

Custom crops added through the API are persisted in ``backend/data/custom_crops.json``
and merged into this catalog at runtime.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Dict


BACKEND_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = BACKEND_ROOT / "data"
CUSTOM_CROPS_PATH = DATA_DIR / "custom_crops.json"

CROP_DAYS_TO_HARVEST: Dict[str, int] = {
    "Tomato": 75,
    "Eggplant": 90,
    "Lettuce": 45,
    "Bell Pepper": 80,
    "Cabbage": 70,
    "Carrot": 90,
    "Cucumber": 55,
    "Onion": 120,
    "Garlic": 150,
    "Corn": 90,
    "Rice": 120,
    "Squash": 100,
    "Okra": 55,
    "String Beans": 60,
    "Spinach": 40,
    "Pechay": 30,
    "Sweet Potato": 110,
    "Cassava": 270,
    "Ginger": 240,
    "Bitter Gourd (Ampalaya)": 70,
}


def _load_custom_crops() -> Dict[str, int]:
    if not CUSTOM_CROPS_PATH.exists():
        return {}

    try:
        raw = json.loads(CUSTOM_CROPS_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}

    crops: Dict[str, int] = {}
    for item in raw if isinstance(raw, list) else []:
        name = str(item.get("name", "")).strip()
        days = item.get("avg_days_to_harvest")
        if not name:
            continue
        try:
            crops[name] = max(1, int(days))
        except (TypeError, ValueError):
            continue
    return crops


def get_crop_days_to_harvest() -> Dict[str, int]:
    catalog = dict(CROP_DAYS_TO_HARVEST)
    catalog.update(_load_custom_crops())
    return catalog


def add_custom_crop(name: str, avg_days_to_harvest: int) -> Dict[str, int]:
    name = name.strip()
    if not name:
        raise ValueError("Crop name is required")

    DATA_DIR.mkdir(exist_ok=True)
    catalog = get_crop_days_to_harvest()
    catalog[name] = max(1, int(avg_days_to_harvest))

    custom_rows = [
        {"name": crop_name, "avg_days_to_harvest": days}
        for crop_name, days in sorted(catalog.items())
        if crop_name not in CROP_DAYS_TO_HARVEST
    ]
    CUSTOM_CROPS_PATH.write_text(json.dumps(custom_rows, indent=2, ensure_ascii=False), encoding="utf-8")
    return catalog
