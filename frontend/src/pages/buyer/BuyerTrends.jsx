import { useEffect, useState } from "react";
import { LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";
import { TrendingUp, TrendingDown, Minus, Brain } from "lucide-react";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import { useCropCatalog } from "../../data/crops";
import { api } from "../../services/api";
import { fmtPHP } from "../../lib/format";

export default function BuyerTrends() {
  const allPrices = useDb(() => db.listMarketPrices(), []);
  const cropOptions = useCropCatalog();
  const cropsAvailable = Array.from(new Set(allPrices.map((p) => p.crop)));
  const initialCrop = cropsAvailable.includes("Tomato") ? "Tomato" : cropsAvailable[0] || cropOptions[0] || "Tomato";
  const [crop, setCrop] = useState(initialCrop);

  const history = allPrices.filter((p) => p.crop === crop).sort((a, b) => a.month.localeCompare(b.month));
  const [trend, setTrend] = useState(null);

  // Refit when the crop changes or new monthly entries are appended.
  // We key on history.length (and crop) instead of the array reference so
  // we don't refetch on every render.
  useEffect(() => {
    let active = true;
    api.priceTrend({ crop, history: history.map((h) => ({ month: h.month, price: h.price })) })
      .then((data) => { if (active) setTrend(data); });
    return () => { active = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [crop, history.length]);

  const Icon =
    trend?.trend === "rising" ? TrendingUp :
    trend?.trend === "falling" ? TrendingDown : Minus;
  const tone =
    trend?.trend === "rising" ? "text-brand-700 bg-brand-50" :
    trend?.trend === "falling" ? "text-rose-700 bg-rose-50" : "text-slate-700 bg-slate-100";

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div>
        <h1 className="font-display text-2xl font-bold text-slate-900">AI Price Trends</h1>
        <p className="text-sm text-slate-500">Historical prices and our model's forecast for next month.</p>
      </div>

      <section className="card p-6 flex-1 flex flex-col">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <label className="label">Crop</label>
            <select className="input min-w-[200px]" value={crop} onChange={(e) => setCrop(e.target.value)}>
              {(cropsAvailable.length ? cropsAvailable : cropOptions).map((c) => (
                <option key={c} value={c}>{c}</option>
              )) : <option>—</option>}
            </select>
          </div>

          {trend && (
            <div className="flex items-center gap-3">
              <div className={`grid h-12 w-12 place-items-center rounded-xl ${tone}`}>
                <Icon size={22} />
              </div>
              <div>
                <div className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                  Trend
                </div>
                <div className="font-display text-lg font-bold text-slate-900 capitalize">
                  {trend.trend} ({trend.change_pct >= 0 ? "+" : ""}{trend.change_pct}%)
                </div>
              </div>

              {trend.forecast_next != null && (
                <div className="ml-2 px-3 py-2 rounded-xl bg-brand-50 text-brand-700">
                  <div className="text-xs font-semibold uppercase tracking-wider flex items-center gap-1">
                    <Brain size={12} /> Forecast next month
                  </div>
                  <div className="font-display text-lg font-bold">{fmtPHP(trend.forecast_next)}/kg</div>
                </div>
              )}
            </div>
          )}
        </div>

        <div className="mt-6 flex-1 min-h-[300px]">
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={history.map((h) => ({ month: h.month, price: h.price }))}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="month" stroke="#94a3b8" tick={{ fontSize: 12 }} />
              <YAxis stroke="#94a3b8" tick={{ fontSize: 12 }} domain={["auto", "auto"]} />
              <Tooltip
                contentStyle={{ borderRadius: 12, border: "1px solid #e2e8f0", fontSize: 12 }}
                formatter={(v) => [fmtPHP(v), "PHP/kg"]}
              />
              <Line type="monotone" dataKey="price" stroke="#377c1f" strokeWidth={2.5} dot={{ r: 4, fill: "#377c1f" }} activeDot={{ r: 6 }} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </section>
    </div>
  );
}
