import { Link } from "react-router-dom";
import { Sprout, ClipboardList, Coins, CalendarClock, ArrowRight, TrendingUp } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import Stat from "../../components/ui/Stat";
import StatusBadge from "../../components/ui/StatusBadge";
import { fmtDate, fmtPHP, daysUntil } from "../../lib/format";

export default function FarmerDashboard() {
  const { user } = useAuth();
  const plantings = useDb(() => db.listPlantings({ farmerId: user.id }), [user.id]);
  const orders    = useDb(() => db.listOrders({ farmerId: user.id }), [user.id]);

  const expectedRevenue = orders.reduce((sum, o) => sum + (o.totalPHP || 0), 0);
  const upcoming = [...plantings].sort((a, b) =>
    new Date(a.estimatedHarvest) - new Date(b.estimatedHarvest),
  );

  return (
    <div className="flex-1 flex flex-col space-y-6">
      {/* Page header */}
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Farm Dashboard</h1>
        <p className="text-sm text-slate-500">Overview of your crop listings and incoming orders.</p>
      </div>

      {/* Stats row */}
      <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <Stat icon={Sprout}        label="Crop listings"  value={plantings.length}          tone="brand" />
        <Stat icon={ClipboardList} label="Open orders"       value={orders.length}             tone="harvest" />
        <Stat icon={Coins}         label="Expected revenue"  value={fmtPHP(expectedRevenue)}   tone="blue" />
        <Stat
          icon={CalendarClock}
          label="Next harvest in"
          value={upcoming.length ? `${Math.max(0, daysUntil(upcoming[0].estimatedHarvest) ?? 0)} days` : "—"}
          sublabel={upcoming[0] ? `${upcoming[0].crop} · ${fmtDate(upcoming[0].estimatedHarvest)}` : "No listings yet"}
          tone="rose"
        />
      </div>

      <div className="flex-1 grid lg:grid-cols-3 gap-6">
        {/* Plantings table */}
        <section className="card-accent lg:col-span-2 flex flex-col">
          <div className="flex items-center justify-between border-b-2 border-slate-100 px-6 py-4">
            <div>
              <h2 className="font-display text-lg font-extrabold text-slate-900">Your crop listings</h2>
              <p className="text-xs text-slate-500">Automatically predicted harvest schedule.</p>
            </div>
            <Link to="/farmer/plant" className="btn-primary text-sm px-4 py-2">
              <Sprout size={15} /> List crop
            </Link>
          </div>

          <div className="overflow-x-auto">
            {plantings.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 text-center">
                <div className="grid h-14 w-14 place-items-center rounded-2xl bg-brand-50 text-brand-600 mb-3">
                  <TrendingUp size={24} />
                </div>
                <p className="font-semibold text-slate-700">No crop listings yet</p>
                <p className="mt-1 text-sm text-slate-400">Add your first crop listing for buyers to pre-order.</p>
                <Link to="/farmer/plant" className="btn-primary mt-4 px-5 py-2">
                  <Sprout size={15} /> List crop
                </Link>
              </div>
            ) : (
              <table className="min-w-full text-sm">
                <thead className="bg-brand-800 text-white">
                  <tr>
                    <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Crop</th>
                    <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Planted</th>
                    <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Harvest</th>
                    <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Yield (kg)</th>
                    <th className="text-right py-3 px-4 text-xs font-bold uppercase tracking-wider">Days left</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100">
                  {upcoming.map((p) => {
                    const left = daysUntil(p.estimatedHarvest) ?? 0;
                    return (
                      <tr key={p.id} className="hover:bg-brand-50/40 transition-colors">
                        <td className="py-3 px-4">
                          <div className="font-bold text-slate-900">{p.crop}</div>
                          <div className="text-xs text-slate-500">{p.variety || "—"}</div>
                        </td>
                        <td className="py-3 px-4 text-slate-600">{fmtDate(p.datePlanted)}</td>
                        <td className="py-3 px-4 text-slate-600">{fmtDate(p.estimatedHarvest)}</td>
                        <td className="py-3 px-4 text-slate-600">{p.expectedYieldKg}</td>
                        <td className="py-3 px-4 text-right">
                          <span className={`badge font-semibold ${left < 0 ? "badge-rose" : left < 14 ? "badge-amber" : "badge-gray"}`}>
                            {left < 0 ? `${-left}d late` : `${left} days`}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        </section>

        {/* Recent orders */}
        <section className="card flex flex-col">
          <div className="flex items-center justify-between border-b-2 border-slate-100 px-5 py-4">
            <h2 className="font-display text-lg font-extrabold text-slate-900">Recent orders</h2>
            <Link to="/farmer/orders" className="inline-flex items-center gap-1 text-sm font-bold text-brand-700 hover:underline">
              View all <ArrowRight size={13} />
            </Link>
          </div>

          <ul className="flex-1 divide-y divide-slate-100">
            {orders.length === 0 && (
              <li className="py-8 text-center text-sm text-slate-500">No orders yet.</li>
            )}
            {orders.slice(0, 5).map((o) => (
              <li key={o.id} className="px-5 py-3">
                <div className="flex items-center justify-between gap-3">
                  <div className="min-w-0">
                    <div className="font-semibold text-slate-900 truncate">
                      {o.crop} · {o.quantityKg} kg
                    </div>
                    <div className="text-xs text-slate-500">{fmtDate(o.placedAt)}</div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="text-sm font-bold text-slate-900">{fmtPHP(o.totalPHP)}</div>
                    <StatusBadge status={o.status} />
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}

