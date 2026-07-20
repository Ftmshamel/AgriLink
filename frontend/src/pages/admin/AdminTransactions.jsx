import { useState } from "react";
import { Search } from "lucide-react";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import StatusBadge from "../../components/ui/StatusBadge";
import PaymentStatusBadge from "../../components/ui/PaymentStatusBadge";
import { ORDER_STATUS_LABEL } from "../../lib/constants";
import { fmtDate, fmtPHP } from "../../lib/format";

export default function AdminTransactions() {
  const orders = useDb(() => db.listOrders(), []);
  const users  = useDb(() => db.listUsers(), []);
  const [query, setQuery] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  const filtered = orders.filter((o) => {
    const buyer  = users.find((u) => u.id === o.buyerId);
    const farmer = users.find((u) => u.id === o.farmerId);
    const matchesQuery = query
      ? `${o.crop} ${buyer?.name || ""} ${farmer?.name || ""}`.toLowerCase().includes(query.toLowerCase())
      : true;
    const matchesStatus = statusFilter ? o.status === statusFilter : true;
    return matchesQuery && matchesStatus;
  });

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Transaction Monitoring</h1>
        <p className="text-sm text-slate-500">All pre-orders and deliveries in the system.</p>
      </div>

      <section className="card p-4 flex flex-col md:flex-row gap-3">
        <div className="relative flex-1">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input className="input pl-9" placeholder="Search crop, buyer, or farmer…" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <select className="input md:w-56" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          {Object.entries(ORDER_STATUS_LABEL).map(([k, v]) => (
            <option key={k} value={k}>{v}</option>
          ))}
        </select>
      </section>

      <section className="card overflow-hidden flex-1">
        <div className="overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-brand-800 text-white">
              <tr>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Order</th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Crop</th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Buyer</th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Farmer</th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Placed</th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Status</th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">Payment</th>
                <th className="text-right py-3 px-4 text-xs font-bold uppercase tracking-wider">Total</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtered.length === 0 && (
                <tr><td colSpan={8} className="py-10 text-center text-slate-500">No transactions match.</td></tr>
              )}
              {filtered.map((o) => {
                const buyer  = users.find((u) => u.id === o.buyerId);
                const farmer = users.find((u) => u.id === o.farmerId);
                return (
                  <tr key={o.id} className="hover:bg-brand-50/40 transition-colors">
                    <td className="py-3 px-4">
                      <div className="font-bold text-slate-900">#{o.id.slice(-6)}</div>
                    </td>
                    <td className="py-3 px-4 font-medium text-slate-700">{o.crop} · {o.quantityKg} kg</td>
                    <td className="py-3 px-4 text-slate-600">{buyer?.name || "—"}</td>
                    <td className="py-3 px-4 text-slate-600">{farmer?.farmName || farmer?.name || "—"}</td>
                    <td className="py-3 px-4 text-slate-600">{fmtDate(o.placedAt)}</td>
                    <td className="py-3 px-4"><StatusBadge status={o.status} /></td>
                    <td className="py-3 px-4">
                      <PaymentStatusBadge status={o.paymentStatus} />
                      <div className="text-xs text-slate-500 mt-0.5">
                        {fmtPHP(o.paidAmountPHP || 0)} / {fmtPHP(o.totalPHP)}
                      </div>
                    </td>
                    <td className="py-3 px-4 text-right font-extrabold text-slate-900">{fmtPHP(o.totalPHP)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
