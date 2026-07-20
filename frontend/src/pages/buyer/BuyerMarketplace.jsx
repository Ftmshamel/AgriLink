import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Search,
  MapPin,
  Sprout,
  ShoppingCart,
  X,
  Calendar,
  BadgeCheck,
  Leaf,
  CheckCircle2,
  ArrowRight,
  Info,
  Trash2,
  UserCircle2,
  Flag,
} from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import FarmsMap from "../../components/map/FarmsMap";
import EmptyState from "../../components/ui/EmptyState";
import { ImageThumb } from "../../components/ui/ImageUpload";
import PaymentDialog from "../../components/ui/PaymentDialog";
import ConfirmationModal from "../../components/ui/ConfirmationModal";
import { fmtDate, fmtPHP, daysUntil } from "../../lib/format";
import { getPlantingAvailability } from "../../lib/stock";
import { useCropCatalog } from "../../data/crops";

const CART_KEY = "agrilink:buyer:cart:v1";

export default function BuyerMarketplace() {
  const { user } = useAuth();
  const cropOptions = useCropCatalog();

  const plantings = useDb(() => db.listPlantings(), []);
  const users = useDb(() => db.listUsers(), []);
  const orders = useDb(() => db.listOrders(), []);

  const [query, setQuery] = useState("");
  const [crop, setCrop] = useState("");
  const [showOrder, setShowOrder] = useState(null);
  const [showDetails, setShowDetails] = useState(null);
  const [showFarmerProfile, setShowFarmerProfile] = useState(null);
  const [showReport, setShowReport] = useState(null);
  const [cart, setCart] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem(CART_KEY) || "[]");
    } catch {
      return [];
    }
  });
  const [showCartPay, setShowCartPay] = useState(false);
  const [cartDone, setCartDone] = useState(false);
  const [notice, setNotice] = useState({ open: false, title: "", message: "" });
  const [removeKey, setRemoveKey] = useState(null);

  const items = useMemo(() => {
    return plantings
      .map((p) => ({
        planting: p,
        farmer: users.find((u) => u.id === p.farmerId),
      }))
      .filter((x) => x.farmer && x.farmer.verified)
      .filter(
        (x) =>
          getPlantingAvailability(x.planting, orders, user.id).availableKg > 0,
      )
      .filter((x) => (crop ? x.planting.crop === crop : true))
      .filter((x) =>
        query
          ? `${x.planting.crop} ${x.farmer.name} ${x.farmer.farmName}`
              .toLowerCase()
              .includes(query.toLowerCase())
          : true,
      )
      .sort(
        (a, b) =>
          new Date(a.planting.estimatedHarvest) -
          new Date(b.planting.estimatedHarvest),
      );
  }, [plantings, users, orders, user.id, query, crop]);

  const farmMarkers = useMemo(() => {
    return users
      .filter((u) => u.role === "farmer")
      .filter((u) => u.location?.lat != null && u.location?.lng != null)
      .map((farmer) => {
        const farmerPlantings = plantings.filter(
          (p) => p.farmerId === farmer.id,
        );
        const crops = [
          ...new Set(farmerPlantings.map((p) => p.crop).filter(Boolean)),
        ];
        return {
          id: farmer.id,
          lat: farmer.location.lat,
          lng: farmer.location.lng,
          title: farmer.farmName || farmer.name || "Farm",
          subtitle: `${farmer.municipality || farmer.barangay || "Pinned farm"}${farmer.province ? `, ${farmer.province}` : ""}`,
          body:
            crops.length > 0
              ? `${farmer.location.approximate ? "Approximate pin. " : ""}${farmerPlantings.length} listing${farmerPlantings.length !== 1 ? "s" : ""}: ${crops.slice(0, 3).join(", ")}`
              : `${farmer.location.approximate ? "Approximate pin. " : ""}No active crop listings yet.`,
        };
      });
  }, [users, plantings]);

  const persistCart = (next) => {
    setCart(next);
    localStorage.setItem(CART_KEY, JSON.stringify(next));
  };

  const getPlantingCaps = (planting) => {
    return getPlantingAvailability(planting, orders, user.id);
  };

  const addToCart = ({ planting, farmer }) => {
    const { maxForBuyerKg } = getPlantingCaps(planting);
    if (maxForBuyerKg < 10) {
      setNotice({
        open: true,
        title: "Unavailable",
        message: "This listing is currently unavailable for your account.",
      });
      return;
    }

    const key = planting.id;
    const existing = cart.find((c) => c.key === key);
    if (existing) {
      const next = cart.map((c) =>
        c.key === key
          ? {
              ...c,
              qty: Math.min(c.qty + 10, maxForBuyerKg || c.qty + 10),
              maxQty: maxForBuyerKg,
            }
          : c,
      );
      persistCart(next);
      return;
    }
    const next = [
      ...cart,
      {
        key,
        plantingId: planting.id,
        crop: planting.crop,
        qty: Math.min(10, maxForBuyerKg),
        maxQty: maxForBuyerKg,
        pricePerKg: planting.pricePerKg || 0,
        farmerId: farmer.id,
        farmerName: farmer.farmName || farmer.name || "Farmer",
        expectedDate: planting.estimatedHarvest || "",
      },
    ];
    persistCart(next);
  };

  const updateCartQty = (key, qty) => {
    const next = cart.map((c) =>
      c.key === key
        ? (() => {
            const planting = plantings.find((p) => p.id === c.plantingId);
            const dynamicMax = planting
              ? getPlantingCaps(planting).maxForBuyerKg
              : c.maxQty || 999999;
            return {
              ...c,
              maxQty: dynamicMax,
              qty: Math.max(
                10,
                Math.min(Number(qty) || 10, dynamicMax || 999999),
              ),
            };
          })()
        : c,
    );
    persistCart(next);
  };

  const removeFromCart = (key) => {
    setRemoveKey(key);
  };

  const cartTotal = cart.reduce((s, c) => s + c.qty * c.pricePerKg, 0);

  return (
    <div className="flex-1 flex flex-col space-y-6">
      {/* Page header */}
      <div className="border-l-4 border-harvest-500 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">
          Upcoming Harvest Marketplace
        </h1>
        <p className="text-sm text-slate-500">
          Reserve crops before they're harvested — straight from verified
          Filipino farmers.
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
            placeholder="Search crop, farm or farmer…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <select
          className="input md:w-56"
          value={crop}
          onChange={(e) => setCrop(e.target.value)}
        >
          <option value="">All crops</option>
          {cropOptions.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </section>

      <div className="flex-1 grid lg:grid-cols-3 gap-6 items-start">
        {/* Listings */}
        <section className="lg:col-span-2 space-y-4">
          {items.length === 0 ? (
            <EmptyState
              icon={Sprout}
              title="No matching listings"
              description="Try a different crop or search term."
            />
          ) : (
            items.map(({ planting, farmer }) => {
              const left = daysUntil(planting.estimatedHarvest) ?? 0;
              const availability = getPlantingAvailability(
                planting,
                orders,
                user.id,
              );
              const urgencyBar =
                left <= 14
                  ? "bg-red-500"
                  : left <= 30
                    ? "bg-harvest-500"
                    : "bg-slate-300";
              return (
                <article
                  key={planting.id}
                  className="card overflow-hidden hover:shadow-strong hover:-translate-y-0.5 transition-all duration-200"
                >
                  {/* Urgency bar */}
                  <div className={`h-1.5 w-full ${urgencyBar}`} />

                  <div className="flex flex-col sm:flex-row">
                    {/* Image */}
                    <div className="sm:w-48 sm:shrink-0 h-44 sm:h-auto bg-brand-50 relative">
                      <ImageThumb
                        image={planting.photo}
                        alt={planting.crop}
                        className="absolute inset-0 h-full w-full"
                      />
                      {/* Fallback icon */}
                      {!planting.photo?.url && (
                        <div className="absolute inset-0 flex items-center justify-center">
                          <Leaf size={40} className="text-brand-200" />
                        </div>
                      )}
                    </div>

                    {/* Info */}
                    <div className="flex-1 p-5">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="min-w-0">
                          <h3 className="font-display text-xl font-extrabold text-slate-900">
                            {planting.crop}
                          </h3>
                          <div className="text-sm text-slate-500 mt-0.5">
                            {planting.variety && <>{planting.variety} · </>}
                            {availability.availableKg} kg available for
                            pre-order
                          </div>
                        </div>
                        <div className="rounded-xl bg-brand-800 px-4 py-2 text-right">
                          <div className="font-display text-xl font-extrabold text-white">
                            {fmtPHP(planting.pricePerKg)}
                            <span className="text-xs font-normal text-brand-200">
                              /kg
                            </span>
                          </div>
                          <div className="text-xs text-brand-300">
                            Min. order 10 kg
                          </div>
                        </div>
                      </div>

                      <div className="mt-4 grid sm:grid-cols-3 gap-2">
                        <div className="flex items-center gap-2 rounded-lg bg-slate-50 border border-slate-100 px-3 py-2 text-sm text-slate-700">
                          <Calendar
                            size={14}
                            className="text-brand-600 shrink-0"
                          />
                          <span>
                            In <strong>{Math.max(0, left)}</strong> days
                          </span>
                        </div>
                        <div className="flex items-center gap-2 rounded-lg bg-slate-50 border border-slate-100 px-3 py-2 text-sm text-slate-700">
                          <Sprout
                            size={14}
                            className="text-brand-600 shrink-0"
                          />
                          <span>Planted {fmtDate(planting.datePlanted)}</span>
                        </div>
                        <div className="flex items-center gap-2 rounded-lg bg-slate-50 border border-slate-100 px-3 py-2 text-sm text-slate-700">
                          <MapPin
                            size={14}
                            className="text-brand-600 shrink-0"
                          />
                          <span className="truncate">
                            {farmer.municipality || farmer.barangay || "PH"}
                          </span>
                        </div>
                      </div>

                      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 pt-4 border-t-2 border-slate-100">
                        <div className="flex items-center gap-2.5">
                          {farmer.photo?.url ? (
                            <img
                              src={farmer.photo.url}
                              alt=""
                              className="h-9 w-9 rounded-xl object-cover border-2 border-brand-100"
                            />
                          ) : (
                            <div className="grid h-9 w-9 place-items-center rounded-xl bg-brand-700 text-white font-bold text-sm">
                              {(farmer.name || "?").charAt(0)}
                            </div>
                          )}
                          <div>
                            <div className="font-semibold text-slate-900 flex items-center gap-1 text-sm">
                              {farmer.farmName || farmer.name}
                              {farmer.verified && (
                                <BadgeCheck
                                  size={13}
                                  className="text-brand-600"
                                />
                              )}
                            </div>
                            <div className="text-xs text-slate-500">
                              by {farmer.name}
                            </div>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <button
                            className="inline-flex items-center gap-1.5 rounded-xl border-2 border-brand-200 bg-brand-50 px-4 py-2 text-sm font-bold text-brand-700 hover:bg-brand-100 transition-colors"
                            onClick={() => setShowDetails({ planting, farmer })}
                          >
                            <Info size={14} /> View details
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                </article>
              );
            })
          )}
        </section>

        {/* Map + Cart */}
        <aside className="lg:col-span-1 lg:sticky lg:top-20 self-start">
          <div className="flex flex-col gap-4">
            <section className="card overflow-hidden">
              <div className="border-b-2 border-slate-100 px-4 py-3 bg-brand-50">
                <div className="font-extrabold text-slate-900">Farm map</div>
                <div className="text-xs text-slate-500">
                  Pinned locations of verified farmers
                </div>
              </div>
              <div className="p-4">
                <FarmsMap markers={farmMarkers} height={280} />
              </div>
            </section>

            <section className="card overflow-hidden">
              <div className="border-b-2 border-slate-100 px-4 py-3 bg-harvest-50 flex items-center justify-between">
                <div>
                  <div className="font-extrabold text-slate-900">Cart</div>
                  <div className="text-xs text-slate-500">
                    {cart.length} item{cart.length !== 1 ? "s" : ""}
                  </div>
                </div>
                <ShoppingCart size={16} className="text-harvest-600" />
              </div>
              <div className="p-4 space-y-3 max-h-[52vh] overflow-y-auto">
                {cart.length === 0 && (
                  <p className="text-sm text-slate-400">
                    No items yet. Add crops to cart first.
                  </p>
                )}
                {cart.map((c) => (
                  <div
                    key={c.key}
                    className="rounded-xl border border-slate-200 bg-white p-3"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="font-bold text-slate-800 text-sm truncate">
                          {c.crop}
                        </p>
                        <p className="text-xs text-slate-500 truncate">
                          from {c.farmerName}
                        </p>
                      </div>
                      <button
                        onClick={() => removeFromCart(c.key)}
                        className="text-slate-400 hover:text-rose-600 transition-colors"
                        title="Remove"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                    <div className="mt-2 flex items-center justify-between gap-2">
                      <input
                        type="number"
                        min={10}
                        max={c.maxQty}
                        value={c.qty}
                        onChange={(e) => updateCartQty(c.key, e.target.value)}
                        className="input !w-24 !py-1.5 !px-2 text-xs"
                      />
                      <p className="text-sm font-bold text-brand-700">
                        {fmtPHP(c.qty * c.pricePerKg)}
                      </p>
                    </div>
                  </div>
                ))}
                {cart.length > 0 && (
                  <>
                    <div className="pt-2 border-t border-slate-200 flex items-center justify-between">
                      <span className="text-sm font-semibold text-slate-600">
                        Total
                      </span>
                      <span className="font-display text-xl font-extrabold text-slate-900">
                        {fmtPHP(cartTotal)}
                      </span>
                    </div>
                    <button
                      className="btn-harvest w-full py-2.5"
                      onClick={() => setShowCartPay(true)}
                    >
                      <ShoppingCart size={15} /> Checkout all
                    </button>
                  </>
                )}
              </div>
            </section>
          </div>
        </aside>
      </div>

      {showOrder && (
        <PreOrderModal
          farmer={showOrder.farmer}
          planting={showOrder.planting}
          buyerId={user.id}
          onClose={() => setShowOrder(null)}
        />
      )}

      {showDetails && (
        <CropDetailsModal
          planting={showDetails.planting}
          farmer={showDetails.farmer}
          onClose={() => setShowDetails(null)}
          onViewProfile={() => {
            setShowFarmerProfile(showDetails.farmer);
            setShowDetails(null);
          }}
          onAddToCart={() => {
            addToCart(showDetails);
            setShowDetails(null);
          }}
          onPreOrder={() => {
            setShowOrder(showDetails);
            setShowDetails(null);
          }}
        />
      )}
      {showFarmerProfile && (
        <FarmerProfileModal
          farmer={showFarmerProfile}
          plantings={plantings}
          orders={orders}
          buyerId={user.id}
          onClose={() => setShowFarmerProfile(null)}
          onPreOrder={(planting) => {
            setShowFarmerProfile(null);
            setShowOrder({ planting, farmer: showFarmerProfile });
          }}
          onReport={(farmer) => {
            setShowFarmerProfile(null);
            setShowReport(farmer);
          }}
        />
      )}
      {showReport && (
        <ReportFarmerModal
          farmer={showReport}
          buyer={user}
          onClose={() => setShowReport(null)}
          onDone={() => setShowReport(null)}
        />
      )}

      {/* Cart single checkout modal */}
      <PaymentDialog
        open={showCartPay}
        onClose={() => setShowCartPay(false)}
        title="Checkout cart"
        subtitle={`${cart.length} item${cart.length !== 1 ? "s" : ""} from multiple farms`}
        total={cartTotal}
        amountDue={cartTotal}
        submitLabel="Pay & place all orders"
        onConfirm={async ({
          mode,
          method,
          amount,
          downpaymentPct,
          reference,
        }) => {
          if (!cart.length) return;
          const now = new Date().toISOString();
          const simulatedNewOrders = [];
          // Create one order per cart line; split paid amount proportionally
          for (const line of cart) {
            const planting = plantings.find((p) => p.id === line.plantingId);
            if (!planting) continue;

            const baseOrders = orders
              .filter(
                (o) =>
                  o.plantingId === line.plantingId && o.status !== "cancelled",
              )
              .concat(
                simulatedNewOrders.filter(
                  (o) => o.plantingId === line.plantingId,
                ),
              );
            const stock = Number(
              planting.preOrderStockKg ?? planting.expectedYieldKg ?? 0,
            );
            const reserved = baseOrders.reduce(
              (sum, o) => sum + Number(o.quantityKg || 0),
              0,
            );
            const available = Math.max(0, stock - reserved);

            const allowBulk = planting.allowBulkPreorder !== false;
            const alreadyForBuyer = baseOrders
              .filter((o) => o.buyerId === user.id)
              .reduce((sum, o) => sum + Number(o.quantityKg || 0), 0);
            const perAccountRemaining = allowBulk
              ? available
              : Math.max(
                  0,
                  Number(planting.maxPerAccountKg || 0) - alreadyForBuyer,
                );
            const allowedNow = Math.max(
              0,
              Math.min(available, perAccountRemaining),
            );

            if (Number(line.qty) > allowedNow) {
              setNotice({
                open: true,
                title: "Quantity limit",
                message: `${line.crop}: max allowed right now is ${allowedNow} kg.`,
              });
              return;
            }

            const lineTotal = line.qty * line.pricePerKg;
            const linePaid =
              cartTotal > 0 ? Math.round((lineTotal / cartTotal) * amount) : 0;
            const newOrder = {
              buyerId: user.id,
              farmerId: line.farmerId,
              plantingId: line.plantingId,
              crop: line.crop,
              quantityKg: Number(line.qty),
              pricePerKg: Number(line.pricePerKg),
              totalPHP: Number(lineTotal),
              status: "growing",
              expectedDate: line.expectedDate,
              paymentMode: mode,
              paymentMethod: method,
              downpaymentPct,
              paidAmountPHP: linePaid,
              balanceDuePHP: Math.max(0, lineTotal - linePaid),
              paymentStatus:
                linePaid === 0
                  ? "pending"
                  : linePaid >= lineTotal
                    ? "paid"
                    : "partial",
              paymentHistory:
                linePaid > 0
                  ? [
                      {
                        amount: linePaid,
                        method,
                        reference,
                        note:
                          downpaymentPct === 100
                            ? "Full payment"
                            : "Downpayment",
                        at: now,
                      },
                    ]
                  : [],
              timeline: [
                {
                  status: "pending",
                  at: now,
                  note: "Pre-order placed via cart checkout",
                },
                { status: "growing", at: now, note: "Awaiting harvest" },
              ],
            };
            await db.createOrder(newOrder);
            simulatedNewOrders.push(newOrder);
          }
          persistCart([]);
          setShowCartPay(false);
          setCartDone(true);
        }}
      />
      {cartDone && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-sm bg-white rounded-2xl border-2 border-brand-100 shadow-strong p-8 text-center">
            <div className="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-2xl bg-brand-600">
              <CheckCircle2 size={38} className="text-white" />
            </div>
            <h3 className="font-display text-2xl font-extrabold text-slate-900">
              Checkout successful!
            </h3>
            <p className="mt-2 text-slate-500 text-sm">
              All cart items were converted into orders.
            </p>
            <div className="mt-6 flex flex-col gap-3">
              <button
                className="btn-primary w-full py-3 text-base"
                onClick={() => {
                  setCartDone(false);
                  navigate("/buyer/orders");
                }}
              >
                View My Orders <ArrowRight size={16} />
              </button>
              <button
                className="btn-ghost w-full py-2.5 text-sm"
                onClick={() => setCartDone(false)}
              >
                Continue browsing
              </button>
            </div>
          </div>
        </div>
      )}

      <ConfirmationModal
        open={notice.open}
        title={notice.title}
        message={notice.message}
        confirmLabel="OK"
        showCancel={false}
        onClose={() => setNotice({ open: false, title: "", message: "" })}
        onConfirm={() => setNotice({ open: false, title: "", message: "" })}
      />

      <ConfirmationModal
        open={removeKey != null}
        title="Remove item"
        message="Remove this item from your cart?"
        confirmLabel="Remove"
        cancelLabel="Keep"
        onClose={() => setRemoveKey(null)}
        onConfirm={() => {
          if (removeKey != null) {
            persistCart(cart.filter((c) => c.key !== removeKey));
          }
          setRemoveKey(null);
        }}
      />
    </div>
  );
}

function CropDetailsModal({
  planting,
  farmer,
  onClose,
  onViewProfile,
  onAddToCart,
  onPreOrder,
}) {
  const days = Math.max(0, daysUntil(planting.estimatedHarvest) ?? 0);
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
      <div className="w-full max-w-3xl overflow-hidden rounded-3xl border-2 border-slate-100 bg-white shadow-strong">
        <div className="flex items-center justify-between border-b-2 border-slate-100 px-6 py-4">
          <h3 className="font-display text-xl font-extrabold text-slate-900">
            Listing Details
          </h3>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-700 transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        <div className="grid gap-0 md:grid-cols-2">
          <div className="relative h-64 md:h-full min-h-[320px] bg-brand-50">
            <ImageThumb
              image={planting.photo}
              alt={planting.crop}
              className="absolute inset-0 h-full w-full"
            />
            {!planting.photo?.url && (
              <div className="absolute inset-0 flex items-center justify-center">
                <Leaf size={40} className="text-brand-200" />
              </div>
            )}
          </div>

          <div className="p-6 space-y-4">
            <div>
              <p className="font-display text-2xl font-extrabold text-slate-900">
                {planting.crop}
              </p>
              <p className="text-sm text-slate-500">
                {planting.variety || "Standard variety"} ·{" "}
                {planting.preOrderStockKg ?? planting.expectedYieldKg} kg
                pre-order stock
              </p>
            </div>

            <div className="rounded-2xl bg-brand-800 px-4 py-2.5 inline-block shadow-pop">
              <div className="font-display text-xl font-extrabold text-white">
                {fmtPHP(planting.pricePerKg)}
                <span className="text-xs font-normal text-brand-200">/kg</span>
              </div>
            </div>

            <div className="grid gap-2">
              <div className="flex items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-700">
                <Calendar size={14} className="text-brand-600" />
                Harvest in <strong>{days} days</strong>
              </div>
              <div className="flex items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-700">
                <Sprout size={14} className="text-brand-600" />
                Planted {fmtDate(planting.datePlanted)}
              </div>
              <div className="flex items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm text-slate-700">
                <MapPin size={14} className="text-brand-600" />
                {farmer?.municipality || farmer?.barangay || "PH"}
                {farmer?.province ? `, ${farmer.province}` : ""}
              </div>
            </div>

            {planting.notes && (
              <div className="rounded-xl border border-slate-200 bg-slate-50 p-3">
                <p className="text-xs font-bold uppercase tracking-widest text-slate-400">
                  Farmer notes
                </p>
                <p className="mt-1 text-sm text-slate-600">{planting.notes}</p>
              </div>
            )}

            <div className="pt-2 border-t border-slate-100 space-y-2">
              <button
                onClick={onViewProfile}
                className="inline-flex w-full items-center justify-center gap-1.5 rounded-xl border-2 border-slate-200 bg-white px-4 py-2.5 text-sm font-bold text-slate-700 hover:bg-slate-50 transition-colors"
              >
                <UserCircle2 size={14} /> View farmer profile
              </button>
              <div className="grid grid-cols-2 gap-2">
                <button
                  onClick={onAddToCart}
                  className="inline-flex items-center justify-center gap-1.5 rounded-xl border-2 border-harvest-200 bg-harvest-50 px-4 py-2.5 text-sm font-bold text-harvest-700 hover:bg-harvest-100 transition-colors"
                >
                  <ShoppingCart size={14} /> Add to cart
                </button>
                <button
                  onClick={onPreOrder}
                  className="btn-harvest px-4 py-2.5"
                >
                  <ShoppingCart size={15} /> Pre-order
                </button>
              </div>
              <button
                onClick={onClose}
                className="btn-ghost w-full px-5 py-3 text-base"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function FarmerProfileModal({
  farmer,
  plantings,
  orders,
  buyerId,
  onClose,
  onPreOrder,
  onReport,
}) {
  const farmerPlantings = useMemo(
    () =>
      plantings
        .filter((p) => p.farmerId === farmer.id)
        .filter(
          (p) => getPlantingAvailability(p, orders, buyerId).availableKg > 0,
        ),
    [plantings, orders, buyerId, farmer.id],
  );

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
      <div className="w-full max-w-4xl overflow-hidden rounded-2xl border-2 border-slate-100 bg-white shadow-strong">
        <div className="flex items-center justify-between border-b-2 border-slate-100 px-5 py-3">
          <h3 className="font-display text-xl font-extrabold text-slate-900">
            Farmer Profile
          </h3>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-700 transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        <div className="grid gap-5 p-5 md:grid-cols-3">
          <section className="md:col-span-1 rounded-2xl border border-slate-200 bg-slate-50 p-4">
            <div className="flex items-center gap-3">
              {farmer.photo?.url ? (
                <img
                  src={farmer.photo.url}
                  alt=""
                  className="h-14 w-14 rounded-xl object-cover border-2 border-brand-100"
                />
              ) : (
                <div className="grid h-14 w-14 place-items-center rounded-xl bg-brand-700 text-white font-bold text-xl">
                  {(farmer.name || "?").charAt(0)}
                </div>
              )}
              <div>
                <p className="font-bold text-slate-900">
                  {farmer.farmName || farmer.name}
                </p>
                <p className="text-xs text-slate-500">by {farmer.name}</p>
              </div>
            </div>
            <div className="mt-4 space-y-2 text-sm">
              <p className="text-slate-700">
                <strong>Location:</strong>{" "}
                {farmer.municipality || farmer.barangay || "PH"}
                {farmer.province ? `, ${farmer.province}` : ""}
              </p>
              <p className="text-slate-700">
                <strong>Phone:</strong> {farmer.phone || "N/A"}
              </p>
              <p className="text-slate-700">
                <strong>Status:</strong>{" "}
                {farmer.verified ? "Verified" : "Pending verification"}
              </p>
            </div>
            <button
              onClick={() => onReport(farmer)}
              className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl border-2 border-rose-200 bg-rose-50 px-4 py-2 text-sm font-bold text-rose-700 hover:bg-rose-100 transition-colors"
            >
              <Flag size={14} /> Report this farmer
            </button>
          </section>

          <section className="md:col-span-2">
            <div className="mb-3 flex items-center justify-between">
              <h4 className="font-bold text-slate-900">Farmer Crop Listings</h4>
              <span className="badge-green">
                {farmerPlantings.length} listing
                {farmerPlantings.length !== 1 ? "s" : ""}
              </span>
            </div>

            {farmerPlantings.length === 0 ? (
              <div className="rounded-xl border border-slate-200 bg-white p-4 text-sm text-slate-500">
                No active crop listings from this farmer yet.
              </div>
            ) : (
              <div className="space-y-3 max-h-[420px] overflow-y-auto pr-1">
                {farmerPlantings.map((p) => (
                  <div
                    key={p.id}
                    className="rounded-xl border border-slate-200 bg-white p-3"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div>
                        <p className="font-bold text-slate-900">{p.crop}</p>
                        <p className="text-xs text-slate-500">
                          {p.variety || "Standard variety"} ·{" "}
                          {p.preOrderStockKg ?? p.expectedYieldKg} kg pre-order
                          stock · harvest {fmtDate(p.estimatedHarvest)}
                        </p>
                      </div>
                      <div className="text-right">
                        <p className="font-extrabold text-brand-700">
                          {fmtPHP(p.pricePerKg)}/kg
                        </p>
                        <button
                          className="btn-harvest mt-1 px-3 py-1.5 text-xs"
                          onClick={() => onPreOrder(p)}
                        >
                          Pre-order
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}

function ReportFarmerModal({ farmer, buyer, onClose, onDone }) {
  const [reason, setReason] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const canSubmit = reason.trim().length >= 10;

  const submit = async () => {
    if (!canSubmit || submitting) return;
    setSubmitting(true);
    try {
      await db.createReport({
        type: "farmer",
        reporterId: buyer.id,
        reporterName: buyer.name || buyer.email || "Buyer",
        reportedUserId: farmer.id,
        reportedUserName: farmer.name || farmer.farmName || "Farmer",
        reason: reason.trim(),
      });
      onDone();
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
      <div className="w-full max-w-md rounded-2xl border-2 border-rose-100 bg-white shadow-strong p-6">
        <div className="flex items-center justify-between">
          <h3 className="font-display text-xl font-extrabold text-slate-900">
            Report Farmer
          </h3>
          <button
            onClick={onClose}
            className="text-slate-400 hover:text-slate-700 transition-colors"
          >
            <X size={18} />
          </button>
        </div>
        <p className="mt-2 text-sm text-slate-500">
          You are reporting <strong>{farmer.farmName || farmer.name}</strong>.
          Please provide details.
        </p>
        <textarea
          className="input mt-4 min-h-28 resize-y"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Reason for report (minimum 10 characters)"
        />
        <div className="mt-4 flex items-center justify-end gap-2">
          <button onClick={onClose} className="btn-ghost">
            Cancel
          </button>
          <button
            onClick={submit}
            disabled={!canSubmit || submitting}
            className="inline-flex items-center gap-2 rounded-xl bg-rose-600 px-4 py-2 text-sm font-bold text-white hover:bg-rose-700 disabled:opacity-50"
          >
            <Flag size={14} /> {submitting ? "Submitting..." : "Submit report"}
          </button>
        </div>
      </div>
    </div>
  );
}

function PreOrderModal({ farmer, planting, buyerId, onClose }) {
  const navigate = useNavigate();
  const orders = useDb(() => db.listOrders(), []);
  const [qty, setQty] = useState(10);
  const [showPay, setShowPay] = useState(false);
  const [done, setDone] = useState(false);

  const { availableKg, maxForBuyerKg: maxAllowedKg } = getPlantingAvailability(
    planting,
    orders,
    buyerId,
  );

  const total = Number(qty || 0) * planting.pricePerKg;
  const valid = Number(qty) >= 10 && Number(qty) <= maxAllowedKg;

  const handleConfirm = async ({
    mode,
    method,
    amount,
    downpaymentPct,
    reference,
  }) => {
    setDone(true);
    const now = new Date().toISOString();
    const payment =
      amount > 0
        ? [
            {
              amount,
              method,
              reference,
              note: downpaymentPct === 100 ? "Full payment" : "Downpayment",
              at: now,
            },
          ]
        : [];

    await db.createOrder({
      buyerId,
      farmerId: farmer.id,
      plantingId: planting.id,
      crop: planting.crop,
      quantityKg: Number(qty),
      pricePerKg: planting.pricePerKg,
      totalPHP: total,
      status: "growing",
      expectedDate: planting.estimatedHarvest,
      paymentMode: mode,
      paymentMethod: method,
      downpaymentPct,
      paidAmountPHP: amount,
      balanceDuePHP: total - amount,
      paymentStatus:
        amount === 0 ? "pending" : amount === total ? "paid" : "partial",
      paymentHistory: payment,
      timeline: [
        { status: "pending", at: now, note: "Pre-order placed" },
        { status: "growing", at: now, note: "Awaiting harvest" },
      ],
    });
  };

  // ── Success screen after payment confirmed ──
  if (done) {
    return (
      <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
        <div className="w-full max-w-sm bg-white rounded-2xl border-2 border-brand-100 shadow-strong p-8 text-center">
          <div className="mx-auto mb-5 flex h-20 w-20 items-center justify-center rounded-2xl bg-brand-600">
            <CheckCircle2 size={38} className="text-white" />
          </div>
          <h3 className="font-display text-2xl font-extrabold text-slate-900">
            Order placed!
          </h3>
          <p className="mt-2 text-slate-500 text-sm">
            Your pre-order for <strong>{planting.crop}</strong> ({qty} kg) from{" "}
            <strong>{farmer.farmName || farmer.name}</strong> has been
            confirmed.
          </p>
          <div className="mt-6 flex flex-col gap-3">
            <button
              className="btn-primary w-full py-3 text-base"
              onClick={() => {
                onClose();
                navigate("/buyer/orders");
              }}
            >
              View My Orders <ArrowRight size={16} />
            </button>
            <button
              className="btn-ghost w-full py-2.5 text-sm"
              onClick={onClose}
            >
              Continue browsing
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <>
      {!showPay && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-slate-900/60 p-4 backdrop-blur-sm animate-fade-in">
          <div className="w-full max-w-md bg-white rounded-2xl border-2 border-slate-100 shadow-strong p-6 relative">
            <div className="absolute top-0 left-0 right-0 h-1.5 bg-harvest-500 rounded-t-2xl" />

            <button
              onClick={onClose}
              className="absolute top-4 right-4 text-slate-400 hover:text-slate-700 transition-colors"
            >
              <X size={20} />
            </button>

            <h3 className="font-display text-xl font-extrabold text-slate-900 mt-2">
              Pre-order {planting.crop}
            </h3>
            <p className="text-sm text-slate-500 mt-1">
              From <strong>{farmer.farmName || farmer.name}</strong>. Estimated
              harvest {fmtDate(planting.estimatedHarvest)}.
            </p>

            <div className="mt-5 space-y-4">
              <div>
                <label className="label">Quantity (kg)</label>
                <input
                  type="number"
                  min={10}
                  max={maxAllowedKg}
                  className="input"
                  value={qty}
                  onChange={(e) => setQty(e.target.value)}
                  required
                />
                <p className="text-xs text-slate-500 mt-1">
                  Available now: up to {availableKg} kg · min. order 10 kg
                </p>
                {!allowBulkPreorder && (
                  <p className="text-xs text-slate-500 mt-1">
                    Max per account: {limitPerAccount} kg · You already ordered{" "}
                    {alreadyOrderedByBuyer} kg
                  </p>
                )}
                {maxAllowedKg < 10 && (
                  <p className="text-xs text-rose-600 mt-1">
                    This listing is currently unavailable for your account.
                  </p>
                )}
              </div>

              <div className="rounded-xl bg-brand-50 border-2 border-brand-100 p-4 flex items-center justify-between">
                <span className="text-sm font-semibold text-slate-700">
                  Total reservation
                </span>
                <span className="font-display text-2xl font-extrabold text-brand-800">
                  {fmtPHP(total)}
                </span>
              </div>

              <button
                type="button"
                className="btn-harvest w-full py-3 text-base"
                disabled={!valid}
                onClick={() => setShowPay(true)}
              >
                <ShoppingCart size={16} /> Continue to payment
              </button>
            </div>
          </div>
        </div>
      )}

      <PaymentDialog
        open={showPay}
        title={`Pay for your ${planting.crop} pre-order`}
        subtitle={`${qty} kg × ${fmtPHP(planting.pricePerKg)} from ${farmer.farmName || farmer.name}`}
        total={total}
        amountDue={total}
        onConfirm={handleConfirm}
        onClose={() => setShowPay(false)}
        submitLabel="Place pre-order &amp; pay"
      />
    </>
  );
}
