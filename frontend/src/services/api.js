// HTTP client for the AgriLink Python backend (FastAPI).
// All endpoints have a graceful fallback to local mock logic so the
// frontend works even when the backend is offline.

import axios from "axios";
import { API_URL } from "../lib/constants";
import { CROP_GROWTH_DAYS } from "../data/crops";

const http = axios.create({
  baseURL: API_URL,
  timeout: 8000,
});

const fallbackForecast = (crop, datePlanted, region) => {
  const days = CROP_GROWTH_DAYS[crop] ?? 80;
  const planted = new Date(datePlanted);
  const harvest = new Date(planted);
  harvest.setDate(planted.getDate() + days);
  return {
    crop,
    region: region || "Luzon-Central",
    date_planted: datePlanted,
    growth_days: days,
    estimated_harvest_date: harvest.toISOString().slice(0, 10),
    confidence: 0.7,
    source: "client-fallback",
  };
};

const fallbackPriceTrend = (crop, history) => {
  if (!history || history.length < 2) {
    return {
      crop,
      trend: "stable",
      change_pct: 0,
      forecast_next: null,
      source: "client-fallback",
    };
  }
  const sorted = [...history].sort((a, b) => a.month.localeCompare(b.month));
  const first = sorted[0].price;
  const last = sorted[sorted.length - 1].price;
  const changePct = ((last - first) / first) * 100;
  const next = last + (last - sorted[sorted.length - 2].price);
  return {
    crop,
    trend: changePct > 2 ? "rising" : changePct < -2 ? "falling" : "stable",
    change_pct: Number(changePct.toFixed(2)),
    forecast_next: Number(next.toFixed(2)),
    source: "client-fallback",
  };
};

export const api = {
  async forecastHarvest({ crop, datePlanted, region }) {
    try {
      const { data } = await http.post("/forecast", {
        crop,
        date_planted: datePlanted,
        region: region || "Luzon-Central",
      });
      return data;
    } catch {
      return fallbackForecast(crop, datePlanted, region);
    }
  },

  async priceTrend({ crop, history }) {
    try {
      const { data } = await http.post("/price-trend", { crop, history });
      return data;
    } catch {
      return fallbackPriceTrend(crop, history);
    }
  },

  async health() {
    try {
      const { data } = await http.get("/health");
      return { ok: true, ...data };
    } catch {
      return { ok: false };
    }
  },

  async addCrop({ name, avgDaysToHarvest }) {
    const { data } = await http.post("/crops", {
      name,
      avg_days_to_harvest: avgDaysToHarvest,
    });
    return data;
  },
};
