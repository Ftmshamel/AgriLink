import { useMemo } from "react";
import { BarChart, Bar, CartesianGrid, LineChart, Line, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { BarChart3, ClipboardList, Coins, Package, CalendarClock } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import Stat from "../../components/ui/Stat";
import { fmtDate, fmtPHP, daysUntil } from "../../lib/format";

const monthKey = (iso) => {
  if (!iso) return "Unknown";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "Unknown";
  return d.toLocaleString("en-US", { month: "short", year: "numeric" });
};

export default function FarmerAnalytics() {
  const { user } = useAuth();
  const plantings = useDb(() => db.listPlantings({ farmerId: user.id }), [user.id]);
  const orders = useDb(() => db.listOrders({ farmerId: user.id }), [user.id]);

  const totals = useMemo(() => {
    const totalRevenue = orders.reduce((s, o) => s + (o.totalPHP || 0), 0);
    const delivered = orders.filter((o) => o.status === "delivered");
    const completionRate = orders.length ? Math.round((delivered.length / orders.length) * 100) : 0;
    const totalVolume = orders.reduce((s, o) => s + (o.quantityKg || 0), 0);
    const avgOrderValue = orders.length ? Math.round(totalRevenue / orders.length) : 0;
    return { totalRevenue, completionRate, totalVolume, avgOrderValue };
  }, [orders]);

  const monthlySales = useMemo(() => {
    const map = new Map();
    orders.forEach((o) => {
      const key = monthKey(o.placedAt);
      const current = map.get(key) || { month: key, sales: 0, orders: 0 };
      map.set(key, {
        ...current,
        sales: current.sales + (o.totalPHP || 0),
        orders: current.orders + 1,
      });
    });
    return Array.from(map.values()).slice(-6);
  }, [orders]);

  const cropPerformance = useMemo(() => {
    const map = new Map();
    orders.forEach((o) => {
      const key = o.crop || "Unknown";
      const current = map.get(key) || { crop: key, quantity: 0, revenue: 0 };
      map.set(key, {
        ...current,
        quantity: current.quantity + (o.quantityKg || 0),
        revenue: current.revenue + (o.totalPHP || 0),
      });
    });
    return Array.from(map.values()).sort((a, b) => b.revenue - a.revenue).slice(0, 6);
  }, [orders]);

  const nextHarvest = useMemo(() => {
    const sorted = [...plantings].sort((a, b) => new Date(a.estimatedHarvest) - new Date(b.estimatedHarvest));
    return sorted[0] || null;
  }, [plantings]);

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Farm Analytics & Reports</h1>
        <p className="text-sm text-slate-500">Track sales, crop performance, and farm progress in one place.</p>
      </div>

      <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Stat icon={Coins} label="Total sales" value={fmtPHP(totals.totalRevenue)} tone="brand" />
        <Stat icon={ClipboardList} label="Total orders" value={orders.length} tone="harvest" />
        <Stat icon={Package} label="Sold volume" value={`${totals.totalVolume} kg`} tone="blue" />
        <Stat icon={BarChart3} label="Completion rate" value={`${totals.completionRate}%`} tone="rose" />
      </div>

      <div className="grid lg:grid-cols-3 gap-6 flex-1 items-start">
        <section className="card-accent lg:col-span-2 p-5">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-display text-lg font-extrabold text-slate-900">Monthly Sales</h2>
            <span className="text-xs font-semibold text-slate-500">Last 6 months</span>
          </div>
          <div className="h-72">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={monthlySales}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                <XAxis dataKey="month" stroke="#94a3b8" tick={{ fontSize: 12 }} />
                <YAxis stroke="#94a3b8" tick={{ fontSize: 12 }} />
                <Tooltip formatter={(v, n) => [n === "sales" ? fmtPHP(v) : v, n === "sales" ? "Sales" : "Orders"]} />
                <Line type="monotone" dataKey="sales" stroke="#1f6f2d" strokeWidth={3} dot={{ r: 4 }} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </section>

        <section className="card p-5">
          <h2 className="font-display text-lg font-extrabold text-slate-900">Quick Report</h2>
          <div className="mt-4 space-y-3 text-sm">
            <div className="rounded-xl bg-brand-50 border border-brand-100 p-3">
              <p className="text-xs uppercase tracking-wider text-brand-700 font-bold">Average order value</p>
              <p className="font-display text-xl font-extrabold text-brand-800">{fmtPHP(totals.avgOrderValue)}</p>
            </div>
            <div className="rounded-xl bg-slate-50 border border-slate-200 p-3">
              <p className="text-xs uppercase tracking-wider text-slate-500 font-bold">Active plantings</p>
              <p className="font-display text-xl font-extrabold text-slate-900">{plantings.length}</p>
            </div>
            <div className="rounded-xl bg-harvest-50 border border-harvest-100 p-3">
              <p className="text-xs uppercase tracking-wider text-harvest-700 font-bold flex items-center gap-1">
                <CalendarClock size={12} /> Next harvest
              </p>
              <p className="font-semibold text-slate-900 mt-1">
                {nextHarvest ? `${nextHarvest.crop} in ${Math.max(0, daysUntil(nextHarvest.estimatedHarvest) ?? 0)} days` : "No scheduled harvest"}
              </p>
              {nextHarvest && (
                <p className="text-xs text-slate-500 mt-0.5">{fmtDate(nextHarvest.estimatedHarvest)}</p>
              )}
            </div>
          </div>
        </section>
      </div>

      <section className="card p-5">
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-display text-lg font-extrabold text-slate-900">Top Crop Performance</h2>
          <span className="text-xs text-slate-500">Based on order revenue</span>
        </div>
        <div className="h-72">
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={cropPerformance}>
              <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
              <XAxis dataKey="crop" stroke="#94a3b8" tick={{ fontSize: 12 }} />
              <YAxis stroke="#94a3b8" tick={{ fontSize: 12 }} />
              <Tooltip formatter={(v, n) => [n === "revenue" ? fmtPHP(v) : `${v} kg`, n === "revenue" ? "Revenue" : "Quantity sold"]} />
              <Bar dataKey="revenue" fill="#f08c00" radius={[6, 6, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </section>
    </div>
  );
}
