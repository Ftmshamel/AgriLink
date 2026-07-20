import { useState } from "react";
import { Plus, TrendingUp, RefreshCw } from "lucide-react";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import { addCustomCrop, useCropCatalog } from "../../data/crops";
import { fmtPHP } from "../../lib/format";
import { api } from "../../services/api";
import ConfirmationModal from "../../components/ui/ConfirmationModal";

export default function AdminMarket() {
  const prices = useDb(() => db.listMarketPrices(), []);
  const cropOptions = useCropCatalog();

  const [crop, setCrop] = useState(() => cropOptions[0] || "Tomato");
  const [month, setMonth] = useState(new Date().toISOString().slice(0, 7));
  const [price, setPrice] = useState(50);
  const [newCropName, setNewCropName] = useState("");
  const [newCropDays, setNewCropDays] = useState(80);
  const [cropMessage, setCropMessage] = useState("");
  const [cropError, setCropError] = useState("");
  const [resetOpen, setResetOpen] = useState(false);

  const cropsTracked = Array.from(new Set(prices.map((p) => p.crop)));
  const [view, setView] = useState(cropsTracked[0] || crop);

  const history = prices
    .filter((p) => p.crop === view)
    .sort((a, b) => a.month.localeCompare(b.month));

  const submitCrop = async (e) => {
    e.preventDefault();
    setCropError("");
    setCropMessage("");
    const name = newCropName.trim();
    if (!name) {
      setCropError("Crop name is required.");
      return;
    }
    try {
      await api.addCrop({ name, avgDaysToHarvest: Number(newCropDays) });
      addCustomCrop(name, newCropDays);
      setCropMessage(`${name} added to the crop catalog.`);
      setCrop(name);
      setView(name);
      setNewCropName("");
      setNewCropDays(80);
    } catch (err) {
      setCropError(
        err?.response?.data?.detail || err?.message || "Failed to add crop.",
      );
    }
  };

  const submit = (e) => {
    e.preventDefault();
    db.addMarketPrice({ crop, month, price: Number(price) });
    setView(crop);
  };

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold text-slate-900 flex items-center gap-2">
          <TrendingUp className="text-brand-600" /> Market Data Control
        </h1>
        <p className="text-sm text-slate-500">
          Input global market prices that feed AgriLink's AI price-trend model.
        </p>
      </div>

      <div className="flex-1 grid lg:grid-cols-3 gap-6">
        <section className="card p-6 lg:col-span-1 space-y-6">
          <h2 className="font-semibold text-slate-900">Add price entry</h2>
          <form onSubmit={submit} className="mt-4 space-y-3">
            <div>
              <label className="label">Crop</label>
              <select
                className="input"
                value={crop}
                onChange={(e) => setCrop(e.target.value)}
              >
                {cropOptions.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="label">Month</label>
              <input
                type="month"
                className="input"
                value={month}
                onChange={(e) => setMonth(e.target.value)}
              />
            </div>
            <div>
              <label className="label">Price (PHP / kg)</label>
              <input
                type="number"
                min={0}
                className="input"
                value={price}
                onChange={(e) => setPrice(e.target.value)}
              />
            </div>
            <button type="submit" className="btn-primary w-full">
              <Plus size={16} /> Add entry
            </button>
            <button
              type="button"
              className="btn-ghost w-full text-rose-600"
              onClick={() => setResetOpen(true)}
            >
              <RefreshCw size={14} /> Reset local database
            </button>
          </form>

          <div className="border-t border-slate-200 pt-5">
            <h3 className="font-semibold text-slate-900">
              Add crop to catalog
            </h3>
            <p className="mt-1 text-xs text-slate-500">
              New crops will appear in all crop dropdowns after you add them.
            </p>
            <form onSubmit={submitCrop} className="mt-4 space-y-3">
              <div>
                <label className="label">Crop name</label>
                <input
                  className="input"
                  value={newCropName}
                  onChange={(e) => setNewCropName(e.target.value)}
                  placeholder="e.g. Kale"
                />
              </div>
              <div>
                <label className="label">Avg. days to harvest</label>
                <input
                  type="number"
                  min={1}
                  className="input"
                  value={newCropDays}
                  onChange={(e) => setNewCropDays(e.target.value)}
                />
              </div>
              {cropError && (
                <p className="text-sm text-rose-600">{cropError}</p>
              )}
              {cropMessage && (
                <p className="text-sm text-brand-700">{cropMessage}</p>
              )}
              <button type="submit" className="btn-primary w-full">
                <Plus size={16} /> Save crop
              </button>
            </form>
          </div>
        </section>

        <section className="card p-6 lg:col-span-2 flex flex-col">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <h2 className="font-semibold text-slate-900">Historical chart</h2>
            <select
              className="input max-w-[220px]"
              value={view}
              onChange={(e) => setView(e.target.value)}
            >
              {(cropsTracked.length ? cropsTracked : cropOptions).map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </div>

          <div className="mt-4 flex-1 min-h-[280px]">
            {history.length === 0 ? (
              <p className="text-sm text-slate-500">
                No data yet — add an entry to start.
              </p>
            ) : (
              <ResponsiveContainer width="100%" height="100%">
                <LineChart
                  data={history.map((h) => ({
                    month: h.month,
                    price: h.price,
                  }))}
                >
                  <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                  <XAxis
                    dataKey="month"
                    stroke="#94a3b8"
                    tick={{ fontSize: 12 }}
                  />
                  <YAxis stroke="#94a3b8" tick={{ fontSize: 12 }} />
                  <Tooltip
                    contentStyle={{
                      borderRadius: 12,
                      border: "1px solid #e2e8f0",
                      fontSize: 12,
                    }}
                    formatter={(v) => [fmtPHP(v), "PHP/kg"]}
                  />
                  <Line
                    type="monotone"
                    dataKey="price"
                    stroke="#dd5604"
                    strokeWidth={2.5}
                    dot={{ r: 4, fill: "#dd5604" }}
                  />
                </LineChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>
      </div>

      <ConfirmationModal
        open={resetOpen}
        title="Reset local database"
        message="All local users, plantings, orders, and prices will be wiped."
        confirmLabel="Reset"
        cancelLabel="Cancel"
        onClose={() => setResetOpen(false)}
        onConfirm={() => {
          db.reset();
          setResetOpen(false);
        }}
      />
    </div>
  );
}
