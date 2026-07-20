// Crop catalog used in dropdowns and as the client-side fallback for AI forecasts.
// Day counts are average grow-to-harvest periods used widely in PH agronomy refs.

import { useEffect, useState } from "react";

const CUSTOM_CROPS_KEY = "agrilink:custom-crops:v1";

export const CROP_GROWTH_DAYS = {
  Tomato: 75,
  Eggplant: 90,
  Lettuce: 45,
  "Bell Pepper": 80,
  Cabbage: 70,
  Carrot: 90,
  Cucumber: 55,
  Onion: 120,
  Garlic: 150,
  Corn: 90,
  Rice: 120,
  Squash: 100,
  Okra: 55,
  "String Beans": 60,
  Spinach: 40,
  Pechay: 30,
  "Sweet Potato": 110,
  Cassava: 270,
  Ginger: 240,
  "Bitter Gourd (Ampalaya)": 70,
};

const readCustomCrops = () => {
  if (typeof window === "undefined") return {};
  try {
    const raw = JSON.parse(
      window.localStorage.getItem(CUSTOM_CROPS_KEY) || "{}",
    );
    return raw && typeof raw === "object" ? raw : {};
  } catch {
    return {};
  }
};

const writeCustomCrops = (next) => {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(CUSTOM_CROPS_KEY, JSON.stringify(next));
  window.dispatchEvent(new Event("agrilink:crops-updated"));
};

export const getCropCatalog = () => {
  const merged = { ...CROP_GROWTH_DAYS, ...readCustomCrops() };
  return Object.keys(merged).sort();
};

export const getCropGrowthDays = (crop) => {
  const custom = readCustomCrops();
  return custom[crop] ?? CROP_GROWTH_DAYS[crop] ?? 80;
};

export const addCustomCrop = (crop, avgDaysToHarvest) => {
  const name = String(crop || "").trim();
  if (!name) return getCropCatalog();

  const days = Math.max(1, Number(avgDaysToHarvest) || 80);
  const next = { ...readCustomCrops(), [name]: days };
  writeCustomCrops(next);
  return getCropCatalog();
};

export const useCropCatalog = () => {
  const [crops, setCrops] = useState(getCropCatalog());

  useEffect(() => {
    const update = () => setCrops(getCropCatalog());
    window.addEventListener("storage", update);
    window.addEventListener("agrilink:crops-updated", update);
    return () => {
      window.removeEventListener("storage", update);
      window.removeEventListener("agrilink:crops-updated", update);
    };
  }, []);

  return crops;
};
