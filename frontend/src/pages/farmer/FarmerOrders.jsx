import { useEffect, useState } from "react";
import {
  ClipboardList,
  ChevronRight,
  MessageCircle,
  Image,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import {
  ORDER_FLOW,
  ORDER_STATUS,
  ORDER_STATUS_LABEL,
} from "../../lib/constants";
import StatusBadge from "../../components/ui/StatusBadge";
import OrderProgress from "../../components/ui/OrderProgress";
import EmptyState from "../../components/ui/EmptyState";
import PaymentStatusBadge from "../../components/ui/PaymentStatusBadge";
import ChatWindow from "../../components/ui/ChatWindow";
import ImageUpload, { ImageThumb } from "../../components/ui/ImageUpload";
import Avatar from "../../components/ui/Avatar";
import ConfirmationModal from "../../components/ui/ConfirmationModal";
import { ensureChat } from "../../services/chatService";
import { fmtDate, fmtPHP } from "../../lib/format";

export default function FarmerOrders() {
  const { user } = useAuth();
  const orders = useDb(() => db.listOrders({ farmerId: user.id }), [user.id]);
  const users = useDb(() => db.listUsers(), []);
  const [openId, setOpenId] = useState(orders[0]?.id || null);
  const [chatOpen, setChatOpen] = useState(false);
  const [activeChatId, setActiveChatId] = useState(null);
  const [statusNote, setStatusNote] = useState("");
  const [statusPhoto, setStatusPhoto] = useState(null);
  const [statusBusy, setStatusBusy] = useState(false);
  const [statusError, setStatusError] = useState("");
  const [statusWarning, setStatusWarning] = useState("");

  useEffect(() => {
    setStatusNote("");
    setStatusPhoto(null);
    setStatusError("");
    setStatusWarning("");
  }, [openId]);

  const openChat = async (order) => {
    const buyer = buyerOf(order.buyerId);
    if (!buyer) return;
    const cid = await ensureChat({
      buyerId: buyer.id,
      buyerName: buyer.name,
      farmerId: user.id,
      farmerName: user.farmName || user.name,
      orderId: order.id,
      orderCrop: order.crop,
    });
    setActiveChatId(cid);
    setChatOpen(true);
  };

  const buyerOf = (id) => users.find((u) => u.id === id);
  const open = orders.find((o) => o.id === openId) || orders[0];

  const advance = async (order) => {
    const idx = ORDER_FLOW.indexOf(order.status);
    const next = ORDER_FLOW[idx + 1];
    if (!next) return;
    // open confirm modal
    setConfirm({
      open: true,
      title: "Move order",
      message: `Move this order from ${ORDER_STATUS_LABEL[order.status] || order.status} to ${ORDER_STATUS_LABEL[next] || next}?`,
      onConfirm: async () => {
        setConfirm((c) => ({ ...c, open: false }));
        setStatusBusy(true);
        setStatusError("");
        setStatusWarning("");
        const note = statusNote.trim() || "Updated by farmer";
        try {
          try {
            await db.updateOrderStatus(order.id, next, note, {
              photo: statusPhoto,
            });
          } catch (photoErr) {
            // Fallback: advance status even if the photo payload is rejected.
            await db.updateOrderStatus(order.id, next, note);
            if (statusPhoto) {
              setStatusWarning(
                "Status updated, but photo was not saved. Try a smaller image.",
              );
            } else {
              throw photoErr;
            }
          }
          setStatusNote("");
          setStatusPhoto(null);
        } catch (e) {
          setStatusError(e?.message || "Failed to update status.");
        } finally {
          setStatusBusy(false);
        }
      },
    });
  };

  const cancel = async (order) => {
    setConfirm({
      open: true,
      title: "Cancel order",
      message: "Cancel this order? This will be visible to the buyer.",
      confirmLabel: "Yes, cancel",
      cancelLabel: "No",
      onConfirm: async () => {
        setConfirm((c) => ({ ...c, open: false }));
        setStatusBusy(true);
        setStatusError("");
        setStatusWarning("");
        const note = statusNote.trim() || "Cancelled by farmer";
        try {
          try {
            await db.updateOrderStatus(order.id, ORDER_STATUS.CANCELLED, note, {
              photo: statusPhoto,
            });
          } catch (photoErr) {
            await db.updateOrderStatus(order.id, ORDER_STATUS.CANCELLED, note);
            if (statusPhoto) {
              setStatusWarning(
                "Order cancelled, but photo was not saved. Try a smaller image.",
              );
            } else {
              throw photoErr;
            }
          }
          setStatusNote("");
          setStatusPhoto(null);
        } catch (e) {
          setStatusError(e?.message || "Failed to cancel order.");
        } finally {
          setStatusBusy(false);
        }
      },
    });
  };

  const [confirm, setConfirm] = useState({ open: false });

  if (orders.length === 0) {
    return (
      <EmptyState
        icon={ClipboardList}
        title="No orders yet"
        description="When buyers pre-order from your plantings, they'll show up here."
      />
    );
  }

  return (
    <div className="space-y-6">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">
          Order Management
        </h1>
        <p className="text-sm text-slate-500">
          Update each order's status. Buyers see your changes in real-time.
        </p>
      </div>

      <div className="flex-1 grid lg:grid-cols-3 gap-6">
        {/* Order list */}
        <aside className="card overflow-hidden lg:col-span-1 max-h-[70vh] overflow-y-auto">
          <div className="border-b-2 border-slate-100 px-4 py-3 bg-brand-50">
            <p className="text-xs font-bold uppercase tracking-widest text-brand-700">
              {orders.length} order{orders.length !== 1 ? "s" : ""}
            </p>
          </div>
          {orders.map((o) => {
            const buyer = buyerOf(o.buyerId);
            const isOpen = open?.id === o.id;
            return (
              <button
                key={o.id}
                onClick={() => setOpenId(o.id)}
                className={`w-full text-left px-4 py-3 transition flex items-center gap-3 border-b border-slate-100 ${
                  isOpen
                    ? "bg-brand-50 border-l-4 border-l-brand-600"
                    : "hover:bg-slate-50 border-l-4 border-l-transparent"
                }`}
              >
                <Avatar user={buyer} name={buyer?.name || "Buyer"} />
                <div className="min-w-0 flex-1">
                  <div className="font-semibold text-slate-900 truncate">
                    {buyer?.name || "Unknown buyer"}
                  </div>
                  <div className="text-xs text-slate-500">
                    {o.crop} · {o.quantityKg} kg
                  </div>
                </div>
                <div className="text-right space-y-1 shrink-0">
                  <StatusBadge status={o.status} />
                  <div className="text-xs font-semibold text-slate-700">
                    {fmtPHP(o.totalPHP)}
                  </div>
                </div>
              </button>
            );
          })}
        </aside>

        {/* Order detail */}
        <section className="card-accent lg:col-span-2 space-y-5 p-6">
          {open && (
            <>
              <div className="flex flex-wrap items-start justify-between gap-3 pb-4 border-b-2 border-slate-100">
                <div>
                  <div className="text-xs font-bold uppercase tracking-widest text-slate-400">
                    Order #{open.id.slice(-6)}
                  </div>
                  <h3 className="font-display text-2xl font-extrabold text-slate-900 mt-0.5">
                    {open.crop} · {open.quantityKg} kg
                  </h3>
                  <div className="text-sm text-slate-500 mt-0.5">
                    Buyer:{" "}
                    <span className="font-semibold text-slate-700">
                      {buyerOf(open.buyerId)?.name || "—"}
                    </span>{" "}
                    · Placed {fmtDate(open.placedAt)}
                  </div>
                </div>
                <div className="text-right">
                  <div className="font-display text-2xl font-extrabold text-slate-900">
                    {fmtPHP(open.totalPHP)}
                  </div>
                  <div className="flex flex-col items-end gap-1 mt-1">
                    <StatusBadge status={open.status} />
                    <PaymentStatusBadge status={open.paymentStatus} />
                  </div>
                </div>
              </div>

              <OrderProgress status={open.status} />

              <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
                <InfoRow label="Crop" value={open.crop} />
                <InfoRow label="Quantity" value={`${open.quantityKg} kg`} />
                <InfoRow label="Price / kg" value={fmtPHP(open.pricePerKg)} />
                <InfoRow
                  label="Harvest date"
                  value={fmtDate(open.expectedDate)}
                />
                <InfoRow label="Paid" value={fmtPHP(open.paidAmountPHP || 0)} />
                <InfoRow
                  label="Balance due"
                  value={fmtPHP(open.balanceDuePHP ?? open.totalPHP)}
                />
                <InfoRow label="Payment mode" value={open.paymentMode || "—"} />
                <InfoRow
                  label="Payment method"
                  value={open.paymentMethod || "—"}
                />
              </div>

              <div className="flex flex-wrap gap-2">
                <div className="w-full rounded-xl border border-slate-200 bg-slate-50 p-3 space-y-3">
                  <div>
                    <label className="label">Update note (optional)</label>
                    <textarea
                      rows={2}
                      className="input"
                      value={statusNote}
                      onChange={(e) => setStatusNote(e.target.value)}
                      placeholder="Add details for buyer (e.g. packed and ready for dispatch)"
                    />
                  </div>
                  {open.status === ORDER_STATUS.PREPARING && (
                    <ImageUpload
                      label="Preparing photo (optional)"
                      folder="order-updates"
                      aspect="aspect-[16/7]"
                      value={statusPhoto}
                      onChange={setStatusPhoto}
                    />
                  )}
                  {open.status !== ORDER_STATUS.PREPARING && (
                    <p className="text-xs text-slate-500">
                      Photos can only be added when moving to the Preparing
                      stage.
                    </p>
                  )}
                  {statusError && (
                    <p className="text-sm text-rose-600">{statusError}</p>
                  )}
                  {statusWarning && (
                    <p className="text-sm text-amber-700">{statusWarning}</p>
                  )}
                </div>
                {open.status !== ORDER_STATUS.DELIVERED &&
                  open.status !== ORDER_STATUS.CANCELLED && (
                    <button
                      className="btn-primary"
                      onClick={() => advance(open)}
                      disabled={statusBusy}
                    >
                      Move to next status <ChevronRight size={16} />
                    </button>
                  )}
                {open.status !== ORDER_STATUS.DELIVERED &&
                  open.status !== ORDER_STATUS.CANCELLED && (
                    <button
                      className="btn-danger"
                      onClick={() => cancel(open)}
                      disabled={statusBusy}
                    >
                      Cancel order
                    </button>
                  )}
                <button
                  className="inline-flex items-center gap-1.5 rounded-xl bg-brand-700 px-4 py-2 text-sm font-bold text-white hover:bg-brand-800 transition-colors"
                  onClick={() => openChat(open)}
                >
                  <MessageCircle size={15} /> Message Buyer
                </button>
              </div>

              {/* Timeline */}
              <div>
                <h4 className="font-extrabold text-slate-900 mb-3">
                  Status history
                </h4>
                <ol className="space-y-2 border-l-2 border-brand-200 pl-4">
                  {(open.timeline || [])
                    .slice()
                    .reverse()
                    .map((t, i) => (
                      <li key={i} className="relative">
                        <span className="absolute -left-[21px] top-1 h-3 w-3 rounded-full bg-brand-600 border-2 border-white" />
                        <div className="font-semibold text-slate-800 text-sm">
                          {ORDER_STATUS_LABEL[t.status] || t.status}
                        </div>
                        <div className="text-xs text-slate-500">
                          {fmtDate(t.at, "MMM d, yyyy h:mm a")}{" "}
                          {t.note && `· ${t.note}`}
                        </div>
                        {(() => {
                          const url =
                            typeof t.photo === "string"
                              ? t.photo
                              : t.photo?.url;
                          if (!url) return null;
                          // show image only at preparing stage
                          if (t.status === ORDER_STATUS.PREPARING) {
                            return (
                              <ImageThumb
                                image={
                                  typeof t.photo === "string"
                                    ? { url: t.photo }
                                    : t.photo
                                }
                                alt="Order stage update"
                                className="mt-2 h-24 w-36 rounded-lg border border-slate-200"
                              />
                            );
                          }
                          return null;
                        })()}
                      </li>
                    ))}
                </ol>
              </div>
            </>
          )}
        </section>
      </div>

      {/* Chat window */}
      {confirm?.open && (
        <ConfirmationModal
          open={confirm.open}
          title={confirm.title}
          message={confirm.message}
          confirmLabel={confirm.confirmLabel}
          cancelLabel={confirm.cancelLabel}
          onConfirm={confirm.onConfirm}
          onClose={() => setConfirm((c) => ({ ...c, open: false }))}
        />
      )}

      {chatOpen && activeChatId && open && (
        <ChatWindow
          chatId={activeChatId}
          currentUser={user}
          otherName={buyerOf(open.buyerId)?.name || "Buyer"}
          otherPhoto={buyerOf(open.buyerId)?.photo}
          onClose={() => setChatOpen(false)}
        />
      )}
    </div>
  );
}

function InfoRow({ label, value }) {
  return (
    <div className="rounded-xl border-2 border-slate-100 bg-slate-50 px-3 py-2.5">
      <div className="text-xs font-bold uppercase tracking-widest text-slate-400">
        {label}
      </div>
      <div className="mt-0.5 text-sm font-semibold text-slate-900">{value}</div>
    </div>
  );
}
