import { Users, Sprout, ShoppingBasket, Coins, ShieldCheck, Database, Brain } from "lucide-react";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import Stat from "../../components/ui/Stat";
import StatusBadge from "../../components/ui/StatusBadge";
import { fmtDate, fmtPHP } from "../../lib/format";
import { ROLES } from "../../lib/constants";

export default function AdminOverview() {
  const users     = useDb(() => db.listUsers(),     []);
  const plantings = useDb(() => db.listPlantings(), []);
  const orders    = useDb(() => db.listOrders(),    []);

  const farmers  = users.filter((u) => u.role === ROLES.FARMER);
  const buyers   = users.filter((u) => u.role === ROLES.BUYER);
  const pending  = users.filter((u) => !u.verified && u.role !== ROLES.ADMIN);
  const totalGMV = orders.reduce((s, o) => s + (o.totalPHP || 0), 0);

  const cropCounts = plantings.reduce((acc, p) => {
    acc[p.crop] = (acc[p.crop] || 0) + 1;
    return acc;
  }, {});
  const chartData = Object.entries(cropCounts).map(([crop, count]) => ({ crop, count }));

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Admin Overview</h1>
        <p className="text-sm text-slate-500">System-wide metrics and platform health.</p>
      </div>

      <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Stat icon={Sprout}         label="Farmers"          value={farmers.length}    sublabel={`${pending.length} pending`} tone="brand" />
        <Stat icon={ShoppingBasket} label="Buyers"           value={buyers.length}     tone="harvest" />
        <Stat icon={Users}          label="Active plantings" value={plantings.length}  tone="blue" />
        <Stat icon={Coins}          label="Gross volume"     value={fmtPHP(totalGMV)}  tone="rose" />
      </div>

      <div className="flex-1 grid lg:grid-cols-3 gap-6">
        {/* Chart */}
        <section className="card-accent lg:col-span-2 flex flex-col">
          <div className="border-b-2 border-slate-100 px-6 py-4">
            <h2 className="font-display text-lg font-extrabold text-slate-900">Plantings by crop</h2>
            <p className="text-xs text-slate-500">Number of active listings per crop type.</p>
          </div>
          <div className="flex-1 p-6 min-h-[260px]">
            {chartData.length === 0 ? (
              <div className="flex h-full items-center justify-center text-sm text-slate-500">
                No plantings recorded yet.
              </div>
            ) : (
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
                  <XAxis dataKey="crop" stroke="#94a3b8" tick={{ fontSize: 12 }} />
                  <YAxis stroke="#94a3b8" tick={{ fontSize: 12 }} allowDecimals={false} />
                  <Tooltip
                    contentStyle={{ borderRadius: 12, border: "2px solid #e2e8f0", fontSize: 12, fontWeight: 600 }}
                  />
                  <Bar dataKey="count" fill="#2d7a10" radius={[8, 8, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            )}
          </div>
        </section>

        {/* System health */}
        <section className="card">
          <div className="border-b-2 border-slate-100 px-5 py-4">
            <h2 className="font-display text-lg font-extrabold text-slate-900">System health</h2>
          </div>
          <ul className="divide-y divide-slate-100">
            <HealthRow icon={Database}    label="Firebase Firestore"  value="Operational" tone="ok" />
            <HealthRow icon={Brain}       label="AI Forecast Service" value="Healthy"     tone="ok" />
            <HealthRow icon={ShieldCheck} label="Auth Provider"       value="Operational" tone="ok" />
          </ul>
        </section>
      </div>

      {/* Latest orders */}
      <section className="card overflow-hidden">
        <div className="border-b-2 border-slate-100 px-6 py-4 bg-brand-50">
          <h2 className="font-display text-lg font-extrabold text-slate-900">Latest orders</h2>
        </div>
        <div className="overflow-x-auto">
          {orders.length === 0 ? (
            <div className="py-10 text-center text-sm text-slate-500">No orders yet.</div>
          ) : (
            <table className="min-w-full text-sm">
              <thead className="bg-brand-800 text-white">
                <tr>
                  <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Order</th>
                  <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Crop</th>
                  <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Buyer</th>
                  <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Farmer</th>
                  <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Status</th>
                  <th className="text-right py-3 px-4 text-xs font-bold uppercase tracking-wider">Total</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {orders.slice(0, 8).map((o) => {
                  const buyer  = users.find((u) => u.id === o.buyerId);
                  const farmer = users.find((u) => u.id === o.farmerId);
                  return (
                    <tr key={o.id} className="hover:bg-brand-50/40 transition-colors">
                      <td className="py-3 px-4">
                        <div className="font-bold text-slate-900">#{o.id.slice(-6)}</div>
                        <div className="text-xs text-slate-500">{fmtDate(o.placedAt)}</div>
                      </td>
                      <td className="py-3 px-4 text-slate-700 font-medium">{o.crop} · {o.quantityKg} kg</td>
                      <td className="py-3 px-4 text-slate-600">{buyer?.name || "—"}</td>
                      <td className="py-3 px-4 text-slate-600">{farmer?.farmName || farmer?.name || "—"}</td>
                      <td className="py-3 px-4"><StatusBadge status={o.status} /></td>
                      <td className="py-3 px-4 text-right font-extrabold text-slate-900">{fmtPHP(o.totalPHP)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </div>
      </section>
    </div>
  );
}

function HealthRow({ icon: Icon, label, value, tone }) {
  const cls = tone === "ok" ? "badge-green" : tone === "warn" ? "badge-amber" : "badge-rose";
  return (
    <li className="flex items-center justify-between gap-3 px-5 py-3.5">
      <div className="flex items-center gap-2.5 text-slate-700">
        <div className="grid h-8 w-8 place-items-center rounded-lg bg-brand-50 text-brand-600">
          <Icon size={15} />
        </div>
        <span className="text-sm font-medium">{label}</span>
      </div>
      <span className={cls}>{value}</span>
    </li>
  );
}
