import { useEffect, useMemo, useState } from "react";
import {
  Bell,
  Package,
  MessageCircle,
  BadgeCheck,
  ShoppingCart,
  CheckCircle2,
  Eye,
  Trash2,
  X,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import { subscribeUserChats } from "../../services/chatService";
import StatusBadge from "../../components/ui/StatusBadge";
import ConfirmationModal from "../../components/ui/ConfirmationModal";
import { fmtDate, fmtPHP } from "../../lib/format";

const NOTIF_STORAGE_KEY = "agrilink:notifications:v1";
const NOTIF_HIDDEN_KEY = "agrilink:notifications:hidden:v1";

function buildNotifications(orders, chats, userId) {
  const notifs = [];

  // From orders — status changes become notifications
  orders.forEach((o) => {
    (o.timeline || []).forEach((t, i) => {
      notifs.push({
        id: `order-${o.id}-${i}`,
        type: "order",
        title: `Order ${t.status.replace(/_/g, " ")}`,
        body: `${o.crop} · ${o.quantityKg} kg — ${fmtPHP(o.totalPHP)}`,
        at: t.at,
        status: t.status,
        orderId: o.id,
      });
    });
  });

  // From chats — last messages
  chats.forEach((c) => {
    if (c.lastMessage && c.lastAt) {
      const otherName = userId === c.buyerId ? c.farmerName : c.buyerName;
      notifs.push({
        id: `chat-${c.id}`,
        type: "message",
        title: `New message from ${otherName}`,
        body: c.lastMessage,
        at: c.lastAt?.toDate ? c.lastAt.toDate().toISOString() : null,
      });
    }
  });

  return notifs.sort((a, b) => new Date(b.at || 0) - new Date(a.at || 0));
}

const ICONS = {
  order: { icon: Package, bg: "bg-brand-100", text: "text-brand-700" },
  message: { icon: MessageCircle, bg: "bg-blue-100", text: "text-blue-700" },
  verify: { icon: BadgeCheck, bg: "bg-green-100", text: "text-green-700" },
  payment: {
    icon: ShoppingCart,
    bg: "bg-harvest-100",
    text: "text-harvest-700",
  },
};

export default function NotificationsPage() {
  const { user } = useAuth();
  const orders = useDb(
    () =>
      db.listOrders(
        user.role === "farmer" ? { farmerId: user.id } : { buyerId: user.id },
      ),
    [user.id, user.role],
  );

  const [chats, setChats] = useState([]);
  const [readIds, setReadIds] = useState(
    () => new Set(JSON.parse(localStorage.getItem(NOTIF_STORAGE_KEY) || "[]")),
  );
  const [hiddenIds, setHiddenIds] = useState(
    () => new Set(JSON.parse(localStorage.getItem(NOTIF_HIDDEN_KEY) || "[]")),
  );
  const [viewing, setViewing] = useState(null);
  const [confirm, setConfirm] = useState({
    open: false,
    title: "",
    message: "",
    onConfirm: null,
  });

  useEffect(() => {
    const unsub = subscribeUserChats(user.id, setChats);
    return unsub;
  }, [user.id]);

  const allNotifs = buildNotifications(orders, chats, user.id);
  const notifs = useMemo(
    () => allNotifs.filter((n) => !hiddenIds.has(n.id)),
    [allNotifs, hiddenIds],
  );

  const markRead = (id) => {
    setReadIds((prev) => {
      const next = new Set(prev);
      next.add(id);
      localStorage.setItem(NOTIF_STORAGE_KEY, JSON.stringify([...next]));
      return next;
    });
  };

  const markAllRead = () => {
    setConfirm({
      open: true,
      title: "Mark all as read",
      message: "Mark all notifications as read?",
      onConfirm: () => {
        const all = notifs.map((n) => n.id);
        setReadIds(new Set(all));
        localStorage.setItem(NOTIF_STORAGE_KEY, JSON.stringify(all));
      },
    });
  };

  const deleteNotif = (id) => {
    setConfirm({
      open: true,
      title: "Delete notification",
      message: "Delete this notification?",
      onConfirm: () => {
        setHiddenIds((prev) => {
          const next = new Set(prev);
          next.add(id);
          localStorage.setItem(NOTIF_HIDDEN_KEY, JSON.stringify([...next]));
          return next;
        });
        setViewing((v) => (v?.id === id ? null : v));
      },
    });
  };

  const unread = notifs.filter((n) => !readIds.has(n.id)).length;

  return (
    <div className="flex-1 flex flex-col space-y-4">
      <div className="flex items-end justify-between">
        <div className="border-l-4 border-brand-600 pl-4">
          <h1 className="font-display text-2xl font-extrabold text-slate-900 flex items-center gap-2">
            Notifications
            {unread > 0 && (
              <span className="inline-flex h-6 min-w-[24px] items-center justify-center rounded-full bg-harvest-500 px-1.5 text-xs font-extrabold text-white">
                {unread}
              </span>
            )}
          </h1>
          <p className="text-sm text-slate-500">
            Your recent activity and updates.
          </p>
        </div>
        {unread > 0 && (
          <button
            onClick={markAllRead}
            className="inline-flex items-center gap-1.5 rounded-xl border-2 border-brand-200 bg-brand-50 px-4 py-2 text-sm font-bold text-brand-700 hover:bg-brand-100 transition-colors"
          >
            <CheckCircle2 size={14} /> Mark all as read
          </button>
        )}
      </div>

      <div className="flex-1 card overflow-hidden flex flex-col">
        {notifs.length === 0 ? (
          <div className="flex-1 flex flex-col items-center justify-center text-center p-10">
            <div className="grid h-20 w-20 place-items-center rounded-2xl bg-brand-50 text-brand-300 mb-4">
              <Bell size={36} />
            </div>
            <p className="font-bold text-slate-700">No notifications yet</p>
            <p className="text-sm text-slate-400 mt-1">
              Order updates and messages will appear here.
            </p>
          </div>
        ) : (
          <ul className="flex-1 overflow-y-auto divide-y divide-slate-100">
            {notifs.map((n) => {
              const isRead = readIds.has(n.id);
              const meta = ICONS[n.type] || ICONS.order;
              const Icon = meta.icon;
              return (
                <li
                  key={n.id}
                  className={`flex items-start gap-4 px-5 py-4 cursor-pointer transition-colors ${
                    isRead
                      ? "opacity-60 hover:bg-slate-50"
                      : "bg-brand-50/60 hover:bg-brand-50"
                  }`}
                >
                  {/* Icon */}
                  <div
                    className={`grid h-10 w-10 shrink-0 place-items-center rounded-xl ${meta.bg} ${meta.text}`}
                  >
                    <Icon size={18} />
                  </div>

                  {/* Content */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-3">
                      <p
                        className={`text-sm font-bold ${isRead ? "text-slate-600" : "text-slate-900"}`}
                      >
                        {n.title}
                      </p>
                      {!isRead && (
                        <span className="h-2 w-2 shrink-0 rounded-full bg-harvest-500 mt-1.5" />
                      )}
                    </div>
                    <p className="text-xs text-slate-500 truncate mt-0.5">
                      {n.body}
                    </p>
                    {n.status && (
                      <div className="mt-1.5">
                        <StatusBadge status={n.status} />
                      </div>
                    )}
                    <p className="text-xs text-slate-400 mt-1">
                      {fmtDate(n.at, "MMM d, yyyy h:mm a")}
                    </p>
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        markRead(n.id);
                        setViewing(n);
                      }}
                      className="grid h-8 w-8 place-items-center rounded-lg text-slate-400 hover:bg-brand-100 hover:text-brand-700 transition-colors"
                      title="View notification"
                    >
                      <Eye size={14} />
                    </button>
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        deleteNotif(n.id);
                      }}
                      className="grid h-8 w-8 place-items-center rounded-lg text-slate-400 hover:bg-rose-100 hover:text-rose-700 transition-colors"
                      title="Delete notification"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {viewing && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/50 p-4 backdrop-blur-sm">
          <div className="w-full max-w-md rounded-2xl border-2 border-brand-100 bg-white p-5 shadow-strong">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-xs font-bold uppercase tracking-widest text-brand-600">
                  Notification
                </p>
                <h3 className="mt-1 font-display text-xl font-extrabold text-slate-900">
                  {viewing.title}
                </h3>
              </div>
              <button
                onClick={() => setViewing(null)}
                className="text-slate-400 hover:text-slate-700 transition-colors"
              >
                <X size={18} />
              </button>
            </div>
            <p className="mt-3 text-sm text-slate-600 leading-relaxed">
              {viewing.body}
            </p>
            {viewing.status && (
              <div className="mt-3">
                <StatusBadge status={viewing.status} />
              </div>
            )}
            <p className="mt-3 text-xs text-slate-400">
              {fmtDate(viewing.at, "MMM d, yyyy h:mm a")}
            </p>
            <div className="mt-5 flex items-center justify-end gap-2">
              <button
                onClick={() => {
                  deleteNotif(viewing.id);
                }}
                className="inline-flex items-center gap-1.5 rounded-xl border border-rose-200 bg-rose-50 px-3 py-1.5 text-xs font-bold text-rose-700 hover:bg-rose-100 transition-colors"
              >
                <Trash2 size={13} /> Delete
              </button>
              <button
                onClick={() => setViewing(null)}
                className="btn-primary !px-4 !py-2 text-sm"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}

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
