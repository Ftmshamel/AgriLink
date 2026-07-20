import { useState } from "react";
import {
  BadgeCheck,
  Trash2,
  Search,
  ShieldCheck,
  Sprout,
  Ban,
  CheckCircle2,
} from "lucide-react";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import { ROLES, ROLE_LABELS } from "../../lib/constants";
import { fmtDate } from "../../lib/format";
import ConfirmationModal from "../../components/ui/ConfirmationModal";

export default function AdminUsers() {
  const users = useDb(() => db.listUsers(), []);
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [confirm, setConfirm] = useState({
    open: false,
    title: "",
    message: "",
    onConfirm: null,
  });

  const filtered = users
    .filter((u) => u.role !== ROLES.ADMIN)
    .filter((u) => {
      if (filter === "pending") return !u.verified && !u.blocked;
      if (filter === "verified") return u.verified && !u.blocked;
      if (filter === "blocked") return u.blocked;
      return true; // "all"
    })
    .filter((u) =>
      query
        ? `${u.name} ${u.email} ${u.farmName || ""}`
            .toLowerCase()
            .includes(query.toLowerCase())
        : true,
    );

  const askConfirm = (title, message, onConfirm) =>
    setConfirm({ open: true, title, message, onConfirm });

  const verify = (u) =>
    askConfirm(
      `Verify ${u.name}?`,
      "This will mark the account as verified.",
      () => db.updateUser(u.id, { verified: true, blocked: false }),
    );
  const unverify = (u) =>
    askConfirm(
      `Revoke verification for ${u.name}?`,
      "This will remove the verified badge.",
      () => db.updateUser(u.id, { verified: false }),
    );
  const block = (u) =>
    askConfirm(`Block ${u.name}?`, "They won't be able to log in.", () =>
      db.updateUser(u.id, { blocked: true, verified: false }),
    );
  const unblock = (u) =>
    askConfirm(`Unblock ${u.name}?`, "They will be able to log in again.", () =>
      db.updateUser(u.id, { blocked: false }),
    );
  const remove = (u) =>
    askConfirm(`Permanently delete ${u.name}?`, "This cannot be undone.", () =>
      db.deleteUser(u.id),
    );

  const counts = {
    pending: users.filter(
      (u) => u.role !== ROLES.ADMIN && !u.verified && !u.blocked,
    ).length,
    verified: users.filter(
      (u) => u.role !== ROLES.ADMIN && u.verified && !u.blocked,
    ).length,
    blocked: users.filter((u) => u.role !== ROLES.ADMIN && u.blocked).length,
    all: users.filter((u) => u.role !== ROLES.ADMIN).length,
  };

  const TABS = [
    { id: "pending", label: "Pending", count: counts.pending },
    { id: "verified", label: "Verified", count: counts.verified },
    { id: "blocked", label: "Blocked", count: counts.blocked },
    { id: "all", label: "All", count: counts.all },
  ];

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900 flex items-center gap-2">
          <ShieldCheck size={22} className="text-brand-600" /> User Management
        </h1>
        <p className="text-sm text-slate-500">
          Verify farmers and buyers, or block accounts that violate platform
          rules.
        </p>
      </div>

      {/* Filter bar */}
      <section className="card p-4 flex flex-col md:flex-row gap-3">
        <div className="relative flex-1">
          <Search
            size={16}
            className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"
          />
          <input
            className="input pl-9"
            placeholder="Search by name, email, or farm…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="flex gap-2 flex-wrap">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setFilter(tab.id)}
              className={`inline-flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-bold transition-colors ${
                filter === tab.id
                  ? tab.id === "blocked"
                    ? "bg-rose-600 text-white"
                    : "bg-brand-700 text-white"
                  : "bg-slate-100 text-slate-600 hover:bg-slate-200"
              }`}
            >
              {tab.label}
              <span
                className={`rounded-full px-1.5 py-0.5 text-xs font-extrabold ${
                  filter === tab.id
                    ? "bg-white/25"
                    : "bg-slate-200 text-slate-700"
                }`}
              >
                {tab.count}
              </span>
            </button>
          ))}
        </div>
      </section>

      {/* Table */}
      <section className="card overflow-hidden flex-1">
        <div className="overflow-x-auto h-full">
          <table className="min-w-full text-sm">
            <thead className="bg-brand-800 text-white">
              <tr>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">
                  User
                </th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">
                  Role
                </th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">
                  Joined
                </th>
                <th className="text-left py-3 px-4 text-xs font-bold uppercase tracking-wider">
                  Status
                </th>
                <th className="text-right py-3 px-4 text-xs font-bold uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {filtered.length === 0 && (
                <tr>
                  <td colSpan={5} className="py-14 text-center text-slate-400">
                    No users match this filter.
                  </td>
                </tr>
              )}
              {filtered.map((u) => (
                <tr
                  key={u.id}
                  className={`transition-colors ${
                    u.blocked
                      ? "bg-rose-50/60 hover:bg-rose-50"
                      : "hover:bg-brand-50/40"
                  }`}
                >
                  {/* User info */}
                  <td className="py-3 px-4">
                    <div className="flex items-center gap-3">
                      <div
                        className={`grid h-10 w-10 shrink-0 place-items-center rounded-xl font-bold text-sm ${
                          u.blocked
                            ? "bg-rose-200 text-rose-700"
                            : "bg-brand-700 text-white"
                        }`}
                      >
                        {u.name.charAt(0).toUpperCase()}
                      </div>
                      <div className="min-w-0">
                        <div
                          className={`font-bold truncate ${u.blocked ? "text-rose-700 line-through" : "text-slate-900"}`}
                        >
                          {u.name}
                        </div>
                        <div className="text-xs text-slate-500 truncate">
                          {u.email}
                        </div>
                        {u.farmName && (
                          <div className="flex items-center gap-1 text-xs text-brand-700 mt-0.5">
                            <Sprout size={10} /> {u.farmName}
                          </div>
                        )}
                      </div>
                    </div>
                  </td>

                  {/* Role */}
                  <td className="py-3 px-4">
                    <span
                      className={`badge font-bold ${u.role === ROLES.FARMER ? "badge-green" : "badge-amber"}`}
                    >
                      {ROLE_LABELS[u.role]}
                    </span>
                  </td>

                  {/* Joined */}
                  <td className="py-3 px-4 text-slate-600">
                    {fmtDate(u.createdAt)}
                  </td>

                  {/* Status */}
                  <td className="py-3 px-4">
                    {u.blocked ? (
                      <span className="badge badge-rose font-bold flex items-center gap-1 w-fit">
                        <Ban size={12} /> Blocked
                      </span>
                    ) : u.verified ? (
                      <span className="badge-green font-bold flex items-center gap-1 w-fit">
                        <BadgeCheck size={12} /> Verified
                      </span>
                    ) : (
                      <span className="badge-amber font-bold">Pending</span>
                    )}
                  </td>

                  {/* Actions */}
                  <td className="py-3 px-4 text-right">
                    <div className="inline-flex items-center gap-2">
                      {u.blocked ? (
                        /* Unblock */
                        <button
                          className="inline-flex items-center gap-1.5 rounded-xl bg-brand-50 border border-brand-200 px-3 py-1.5 text-xs font-bold text-brand-700 hover:bg-brand-100 transition-colors"
                          onClick={() => unblock(u)}
                          title="Unblock user"
                        >
                          <CheckCircle2 size={13} /> Unblock
                        </button>
                      ) : (
                        <>
                          {/* Verify / Revoke */}
                          {!u.verified ? (
                            <button
                              className="btn-primary !py-1.5 !px-3 text-xs"
                              onClick={() => verify(u)}
                            >
                              <BadgeCheck size={13} /> Verify
                            </button>
                          ) : (
                            <button
                              className="btn-secondary !py-1.5 !px-3 text-xs"
                              onClick={() => unverify(u)}
                            >
                              Revoke
                            </button>
                          )}

                          {/* Block */}
                          <button
                            className="inline-flex items-center gap-1 rounded-xl bg-rose-50 border border-rose-200 px-3 py-1.5 text-xs font-bold text-rose-700 hover:bg-rose-100 transition-colors"
                            onClick={() => block(u)}
                            title="Block user"
                          >
                            <Ban size={13} /> Block
                          </button>
                        </>
                      )}

                      {/* Delete */}
                      <button
                        className="grid h-8 w-8 place-items-center rounded-xl text-slate-400 hover:bg-rose-50 hover:text-rose-600 transition-colors"
                        onClick={() => remove(u)}
                        title="Delete account"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <ConfirmationModal
        open={confirm.open}
        title={confirm.title}
        message={confirm.message}
        confirmLabel="Continue"
        cancelLabel="Cancel"
        onClose={() =>
          setConfirm({ open: false, title: "", message: "", onConfirm: null })
        }
        onConfirm={() => {
          confirm.onConfirm?.();
          setConfirm({ open: false, title: "", message: "", onConfirm: null });
        }}
      />
    </div>
  );
}
