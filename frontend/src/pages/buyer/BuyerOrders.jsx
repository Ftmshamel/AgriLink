import { useEffect, useState } from "react";
import {
  ClipboardList,
  MapPin,
  Wallet,
  Receipt,
  MessageCircle,
  Star,
  Image,
} from "lucide-react";
import { ORDER_STATUS } from "../../lib/constants";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import StatusBadge from "../../components/ui/StatusBadge";
import OrderProgress from "../../components/ui/OrderProgress";
import EmptyState from "../../components/ui/EmptyState";
import FarmsMap from "../../components/map/FarmsMap";
import { ImageThumb } from "../../components/ui/ImageUpload";
import PaymentStatusBadge from "../../components/ui/PaymentStatusBadge";
import PaymentDialog from "../../components/ui/PaymentDialog";
import ChatWindow from "../../components/ui/ChatWindow";
import { ensureChat } from "../../services/chatService";
import { fmtDate, fmtPHP } from "../../lib/format";

export default function BuyerOrders() {
  const { user } = useAuth();
  const orders = useDb(() => db.listOrders({ buyerId: user.id }), [user.id]);
  const users = useDb(() => db.listUsers(), []);
  const plantings = useDb(() => db.listPlantings(), []);
  const [openId, setOpenId] = useState(orders[0]?.id || null);
  const [payOpen, setPayOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [activeChatId, setActiveChatId] = useState(null);

  const open = orders.find((o) => o.id === openId) || orders[0];

  useEffect(() => {
    if (open?.status === ORDER_STATUS.CANCELLED) {
      setPayOpen(false);
    }
  }, [open?.status]);

  const openChat = async (order) => {
    const farmer = farmerOf(order.farmerId);
    if (!farmer) return;
    const cid = await ensureChat({
      buyerId: user.id,
      buyerName: user.name,
      farmerId: farmer.id,
      farmerName: farmer.farmName || farmer.name,
      orderId: order.id,
      orderCrop: order.crop,
    });
    setActiveChatId(cid);
    setChatOpen(true);
  };

  const farmerOf = (id) => users.find((u) => u.id === id);
  const plantOf = (id) => plantings.find((p) => p.id === id);

  const onPayBalance = async ({ method, amount, reference }) => {
    if (!open) return;
    if (open.status === ORDER_STATUS.CANCELLED) {
      throw new Error("Cancelled orders cannot be paid.");
    }
    await db.addPaymentToOrder(open.id, {
      amount,
      method,
      reference,
      note: "Balance payment",
    });
  };

  if (orders.length === 0) {
    return (
      <EmptyState
        icon={ClipboardList}
        title="No orders yet"
        description="Browse the marketplace to pre-order from upcoming harvests."
      />
    );
  }

  return (
    <div className="flex-1 flex flex-col space-y-6">
      <div className="border-l-4 border-harvest-500 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">
          My Orders
        </h1>
        <p className="text-sm text-slate-500">
          Real-time tracking — updates from the farmer appear instantly.
        </p>
      </div>

      <div className="flex-1 grid lg:grid-cols-3 gap-6">
        <aside className="card overflow-hidden lg:col-span-1 max-h-[70vh] overflow-y-auto">
          <div className="border-b-2 border-slate-100 px-4 py-3 bg-harvest-50">
            <p className="text-xs font-bold uppercase tracking-widest text-harvest-700">
              {orders.length} order{orders.length !== 1 ? "s" : ""}
            </p>
          </div>
          {orders.map((o) => {
            const farmer = farmerOf(o.farmerId);
            const planting = plantOf(o.plantingId);
            const isOpen = open?.id === o.id;
            return (
              <button
                key={o.id}
                onClick={() => setOpenId(o.id)}
                className={`w-full text-left px-4 py-3 transition flex items-center gap-3 border-b border-slate-100 ${
                  isOpen
                    ? "bg-harvest-50 border-l-4 border-l-harvest-500"
                    : "hover:bg-slate-50 border-l-4 border-l-transparent"
                }`}
              >
                <ImageThumb
                  image={planting?.photo}
                  alt={o.crop}
                  className="h-10 w-10 rounded-lg"
                />
                <div className="min-w-0 flex-1">
                  <div className="font-medium text-slate-900 truncate">
                    {o.crop} • {o.quantityKg} kg
                  </div>
                  <div className="text-xs text-slate-500 truncate">
                    {farmer?.farmName || farmer?.name}
                  </div>
                </div>
                <div className="flex flex-col items-end gap-1">
                  <StatusBadge status={o.status} />
                  <PaymentStatusBadge status={o.paymentStatus} />
                </div>
              </button>
            );
          })}
        </aside>

        <section className="card-harvest lg:col-span-2 space-y-5 p-6">
          {open && (
            <>
              <header className="flex flex-wrap items-start justify-between gap-3">
                <div className="flex items-center gap-3">
                  <ImageThumb
                    image={plantOf(open.plantingId)?.photo}
                    alt={open.crop}
                    className="h-14 w-14 rounded-xl"
                  />
                  <div>
                    <div className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                      Order #{open.id.slice(-6)}
                    </div>
                    <h3 className="font-display text-xl font-bold text-slate-900 mt-0.5">
                      {open.crop} • {open.quantityKg} kg
                    </h3>
                    <div className="text-sm text-slate-500 mt-0.5">
                      From{" "}
                      {farmerOf(open.farmerId)?.farmName ||
                        farmerOf(open.farmerId)?.name}
                    </div>
                  </div>
                </div>
                <div className="text-right space-y-2">
                  <div className="font-display text-xl font-bold text-slate-900">
                    {fmtPHP(open.totalPHP)}
                  </div>
                  <div className="flex flex-col items-end gap-1">
                    <StatusBadge status={open.status} />
                    <PaymentStatusBadge status={open.paymentStatus} />
                  </div>
                  <button
                    onClick={() => openChat(open)}
                    className="inline-flex items-center gap-1.5 rounded-xl bg-brand-700 px-3 py-1.5 text-xs font-bold text-white hover:bg-brand-800 transition-colors"
                  >
                    <MessageCircle size={13} /> Message Farmer
                  </button>
                </div>
              </header>

              <OrderProgress status={open.status} />

              {/* Payment summary */}
              <PaymentSummary
                order={open}
                onPay={() => setPayOpen(true)}
                canPayBalance={open.status !== ORDER_STATUS.CANCELLED}
              />

              {farmerOf(open.farmerId)?.location && (
                <div className="space-y-2">
                  <h4 className="font-semibold text-slate-900 flex items-center gap-2">
                    <MapPin size={16} /> Pickup location
                  </h4>
                  <FarmsMap
                    height={260}
                    markers={[
                      {
                        id: open.id,
                        lat: farmerOf(open.farmerId).location.lat,
                        lng: farmerOf(open.farmerId).location.lng,
                        title:
                          farmerOf(open.farmerId).farmName ||
                          farmerOf(open.farmerId).name,
                        subtitle: `${farmerOf(open.farmerId).municipality || ""}, ${farmerOf(open.farmerId).province || ""}`,
                      },
                    ]}
                  />
                </div>
              )}

              {/* Rating — show only for delivered orders */}
              {open.status === "delivered" && <RatingPanel order={open} />}

              <div>
                <h4 className="font-semibold text-slate-900">Status history</h4>
                <ol className="mt-2 space-y-2">
                  {(open.timeline || [])
                    .slice()
                    .reverse()
                    .map((t, i) => (
                      <li key={i} className="flex items-start gap-3 text-sm">
                        <span className="mt-1 h-2 w-2 rounded-full bg-brand-500 shrink-0" />
                        <div>
                          <div className="font-medium text-slate-800 capitalize">
                            {t.status.replace(/_/g, " ")}
                          </div>
                          <div className="text-xs text-slate-500">
                            {fmtDate(t.at, "MMM d, yyyy h:mm a")}{" "}
                            {t.note && `• ${t.note}`}
                          </div>
                          {(() => {
                            const url =
                              typeof t.photo === "string"
                                ? t.photo
                                : t.photo?.url;
                            if (!url) return null;
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
                        </div>
                      </li>
                    ))}
                </ol>
              </div>
            </>
          )}
        </section>
      </div>

      {/* Chat window */}
      {chatOpen && activeChatId && open && (
        <ChatWindow
          chatId={activeChatId}
          currentUser={user}
          otherName={
            farmerOf(open.farmerId)?.farmName ||
            farmerOf(open.farmerId)?.name ||
            "Farmer"
          }
          otherPhoto={farmerOf(open.farmerId)?.photo}
          onClose={() => setChatOpen(false)}
        />
      )}

      {/* Pay-balance dialog */}
      {open && (
        <PaymentDialog
          open={payOpen}
          onClose={() => setPayOpen(false)}
          title="Pay remaining balance"
          subtitle={`${open.crop} • ${open.quantityKg} kg from ${farmerOf(open.farmerId)?.farmName || farmerOf(open.farmerId)?.name}`}
          total={open.totalPHP}
          amountDue={open.balanceDuePHP}
          forcedMode="balance"
          onConfirm={onPayBalance}
          submitLabel="Pay balance"
        />
      )}
    </div>
  );
}

function PaymentSummary({ order, onPay, canPayBalance = true }) {
  const paid = order.paidAmountPHP || 0;
  const total = order.totalPHP || 0;
  const balance = order.balanceDuePHP ?? Math.max(0, total - paid);
  const pct = total > 0 ? Math.min(100, Math.round((paid / total) * 100)) : 0;

  return (
    <div className="rounded-2xl border-2 border-slate-100 bg-slate-50 p-4 space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="font-semibold text-slate-900 flex items-center gap-2">
          <Receipt size={16} /> Payment
        </h4>
        <PaymentStatusBadge status={order.paymentStatus} />
      </div>

      <div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-slate-600">
            Paid {fmtPHP(paid)} of {fmtPHP(total)}
          </span>
          <span className="text-slate-500 text-xs">{pct}%</span>
        </div>
        <div className="mt-1.5 h-2 bg-white rounded-full overflow-hidden border border-slate-200">
          <div
            className="h-full bg-brand-500 transition-all"
            style={{ width: `${pct}%` }}
          />
        </div>
      </div>

      <div className="grid sm:grid-cols-3 gap-3 text-sm">
        <Cell label="Mode" value={order.paymentMode || "—"} />
        <Cell label="Method" value={order.paymentMethod || "—"} />
        <Cell label="Balance" value={fmtPHP(balance)} accent={balance > 0} />
      </div>

      {balance > 0 && canPayBalance && (
        <button className="btn-primary w-full sm:w-auto" onClick={onPay}>
          <Wallet size={16} /> Pay balance ({fmtPHP(balance)})
        </button>
      )}

      {balance > 0 && !canPayBalance && (
        <p className="text-sm text-slate-500">
          This order was cancelled, so balance payment is disabled.
        </p>
      )}

      {(order.paymentHistory || []).length > 0 && (
        <details className="text-sm">
          <summary className="cursor-pointer text-slate-600 hover:text-slate-900">
            Payment history ({order.paymentHistory.length})
          </summary>
          <ul className="mt-2 divide-y divide-slate-200">
            {order.paymentHistory.map((p, i) => (
              <li
                key={i}
                className="py-2 flex items-center justify-between text-slate-700"
              >
                <div>
                  <div className="font-medium">
                    {fmtPHP(p.amount)} via {p.method}
                  </div>
                  <div className="text-xs text-slate-500">
                    {fmtDate(p.at, "MMM d, yyyy h:mm a")} • Ref{" "}
                    {p.reference || "—"}
                    {p.note && ` • ${p.note}`}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}

function Cell({ label, value, accent }) {
  return (
    <div className="rounded-lg bg-white border border-slate-200 px-3 py-2">
      <div className="text-xs text-slate-500">{label}</div>
      <div
        className={`text-sm font-semibold ${accent ? "text-harvest-700" : "text-slate-900"}`}
      >
        {value}
      </div>
    </div>
  );
}

function RatingPanel({ order }) {
  const [rating, setRating] = useState(order.rating || 0);
  const [hover, setHover] = useState(0);
  const [comment, setComment] = useState(order.ratingComment || "");
  const [saved, setSaved] = useState(!!order.rating);

  const submit = async (e) => {
    e.preventDefault();
    await db
      .updateOrder?.(order.id, { rating, ratingComment: comment })
      .catch(() => {
        // fallback: use updateOrderStatus to piggyback patch
      });
    setSaved(true);
  };

  if (saved && order.rating) {
    return (
      <div className="rounded-2xl border-2 border-harvest-100 bg-harvest-50 p-4">
        <p className="text-xs font-bold uppercase tracking-widest text-harvest-700 mb-2">
          Your Rating
        </p>
        <div className="flex gap-0.5 mb-1">
          {[1, 2, 3, 4, 5].map((s) => (
            <Star
              key={s}
              size={18}
              className={
                s <= order.rating ? "text-harvest-500" : "text-slate-200"
              }
              fill={s <= order.rating ? "currentColor" : "none"}
            />
          ))}
        </div>
        {order.ratingComment && (
          <p className="text-sm text-slate-600 italic">
            "{order.ratingComment}"
          </p>
        )}
      </div>
    );
  }

  return (
    <form
      onSubmit={submit}
      className="rounded-2xl border-2 border-harvest-200 bg-harvest-50 p-4 space-y-3"
    >
      <p className="text-xs font-bold uppercase tracking-widest text-harvest-700">
        Rate this order
      </p>
      <p className="text-xs text-slate-500">
        How was your experience with this farmer?
      </p>

      {/* Star picker */}
      <div className="flex gap-1">
        {[1, 2, 3, 4, 5].map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => setRating(s)}
            onMouseEnter={() => setHover(s)}
            onMouseLeave={() => setHover(0)}
          >
            <Star
              size={28}
              className={
                s <= (hover || rating) ? "text-harvest-500" : "text-slate-300"
              }
              fill={s <= (hover || rating) ? "currentColor" : "none"}
            />
          </button>
        ))}
        {rating > 0 && (
          <span className="ml-2 text-sm font-bold text-harvest-700 self-center">
            {["", "Poor", "Fair", "Good", "Very Good", "Excellent"][rating]}
          </span>
        )}
      </div>

      <textarea
        className="input text-sm"
        rows={2}
        placeholder="Leave a comment (optional)…"
        value={comment}
        onChange={(e) => setComment(e.target.value)}
      />

      <button
        type="submit"
        disabled={!rating}
        className="btn-harvest px-5 py-2 text-sm disabled:opacity-40"
      >
        <Star size={14} /> Submit rating
      </button>
    </form>
  );
}
