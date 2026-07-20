import { useMemo } from "react";
import { Link } from "react-router-dom";
import {
  Sprout,
  ArrowRight,
  CheckCircle2,
  MapPin,
  Truck,
  TrendingUp,
  ShoppingCart,
  BadgeCheck,
  Brain,
  Leaf,
  Star,
  ShieldCheck,
  Package,
  Wheat,
  Apple,
  Carrot,
} from "lucide-react";
import Logo from "../components/ui/Logo";
import FarmsMap from "../components/map/FarmsMap";
import { useDb } from "../contexts/useDb";
import { db } from "../services/db";
import { isFirebaseConfigured } from "../services/firebase";
import { daysUntil } from "../lib/format";

const getCropIcon = (cropName = "") => {
  const n = cropName.toLowerCase();
  if (n.includes("rice") || n.includes("corn") || n.includes("wheat"))
    return Wheat;
  if (n.includes("carrot") || n.includes("tomato") || n.includes("eggplant"))
    return Carrot;
  if (n.includes("apple") || n.includes("mango") || n.includes("fruit"))
    return Apple;
  return Leaf;
};

const FARMER_BENEFITS = [
  {
    icon: TrendingUp,
    title: "Fair Market Prices",
    desc: "Sell directly to buyers — zero middlemen, maximum earnings.",
  },
  {
    icon: Brain,
    title: "AI Harvest Forecast",
    desc: "Predict your harvest dates using ML trained on real PH farm data.",
  },
  {
    icon: Package,
    title: "Order Management",
    desc: "Track every order from Growing to Delivered in one clean dashboard.",
  },
  {
    icon: MapPin,
    title: "Pin Your Farm",
    desc: "Buyers see your exact pickup hub on an interactive map.",
  },
];

const BUYER_BENEFITS = [
  {
    icon: ShoppingCart,
    title: "Pre-Order Harvests",
    desc: "Reserve fresh crops weeks ahead — secure your supply before market.",
  },
  {
    icon: TrendingUp,
    title: "Live Price Trends",
    desc: "AI charts show whether crop prices are rising or falling.",
  },
  {
    icon: Truck,
    title: "Real-Time Tracking",
    desc: "Follow your order from the farm all the way to your door.",
  },
  {
    icon: ShieldCheck,
    title: "Verified Sellers Only",
    desc: "Every farmer is reviewed by the AgriLink team before listing.",
  },
];

const STEPS = [
  {
    step: 1,
    Icon: Leaf,
    title: "Browse Harvests",
    desc: "See what crops are available and when they'll be ready to pick.",
  },
  {
    step: 2,
    Icon: ShoppingCart,
    title: "Reserve Your Order",
    desc: "Pre-order the quantity you need and choose GCash, Maya, or COD.",
  },
  {
    step: 3,
    Icon: Truck,
    title: "Track to Delivery",
    desc: "Watch your order move from farm to your door in real-time.",
  },
];

export default function Landing() {
  const allPlantings = useDb(() => db.listPlantings(), []);
  const allUsers = useDb(() => db.listUsers(), []);

  const verifiedFarmers = useMemo(
    () => allUsers.filter((u) => u.role === "farmer" && u.verified),
    [allUsers],
  );

  const farmerMap = useMemo(
    () => Object.fromEntries(verifiedFarmers.map((f) => [f.id, f])),
    [verifiedFarmers],
  );

  const upcomingHarvests = useMemo(() => {
    const now = new Date();
    return allPlantings
      .filter(
        (p) => farmerMap[p.farmerId] && new Date(p.estimatedHarvest) > now,
      )
      .sort(
        (a, b) => new Date(a.estimatedHarvest) - new Date(b.estimatedHarvest),
      )
      .slice(0, 6);
  }, [allPlantings, farmerMap]);

  const farmerCropsMap = useMemo(() => {
    const map = {};
    allPlantings.forEach((p) => {
      if (!map[p.farmerId]) map[p.farmerId] = new Set();
      map[p.farmerId].add(p.crop);
    });
    return map;
  }, [allPlantings]);

  const featuredFarms = useMemo(
    () => verifiedFarmers.slice(0, 6),
    [verifiedFarmers],
  );

  return (
    <div className="w-full bg-white">
      {/* ── NAVBAR ── */}
      <header className="sticky top-0 z-40 w-full border-b-2 border-slate-100 bg-white">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-3 lg:px-10">
          {/* Logo + Admin icon */}
          <div className="flex items-center gap-3">
            <Logo />
            <Link
              to="/login"
              title="Admin login"
              className="grid h-8 w-8 place-items-center rounded-lg text-slate-300 hover:bg-brand-50 hover:text-brand-600 transition-colors"
            >
              <ShieldCheck size={16} />
            </Link>
          </div>
          {/* Debug: show data source */}
          <div className="absolute top-6 right-6 rounded-full px-3 py-1 text-xs font-semibold bg-white/90 text-slate-700 shadow-sm">
            {isFirebaseConfigured ? "Data: Firestore" : "Data: Demo (mock)"}
          </div>

          {/* Right nav — always right-aligned */}
          <nav className="flex items-center gap-2">
            <Link
              to="/login"
              className="hidden sm:inline-flex items-center text-sm font-semibold text-slate-600 hover:text-brand-700 transition-colors px-3 py-2"
            >
              Sign in
            </Link>
            <Link to="/register" className="btn-primary text-sm px-5 py-2.5">
              Get started <ArrowRight size={15} />
            </Link>
          </nav>
        </div>
      </header>

      {/* ── HERO ─── solid brand-800 background ── */}
      <section className="w-full min-h-screen flex items-center justify-center bg-brand-800 px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-5xl text-center">
          {/* Eyebrow */}
          <span className="inline-flex items-center gap-2 rounded-full bg-brand-700 border border-brand-600 px-4 py-1.5 text-sm font-semibold text-brand-200">
            <Sprout size={14} />
            Philippines' Fresh Produce Marketplace
          </span>

          {/* Heading */}
          <h1 className="mt-7 font-display text-5xl font-extrabold leading-tight text-white sm:text-6xl lg:text-7xl">
            Fresh crops, direct
            <br />
            <span className="text-harvest-400">from Filipino farms</span>
          </h1>

          <p className="mx-auto mt-6 max-w-2xl text-lg text-brand-200 sm:text-xl">
            AgriLink connects restaurants, hotels, and wholesalers directly to
            verified local farmers — reserve fresh produce before it's even
            harvested.
          </p>

          {/* CTAs */}
          <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
            <Link
              to="/register"
              className="btn-harvest px-9 py-3.5 text-base font-bold"
            >
              Start buying fresh <ArrowRight size={18} />
            </Link>
            <Link
              to="/register"
              className="inline-flex items-center gap-2 rounded-xl border-2 border-white/30 px-9 py-3.5 text-base font-bold text-white hover:bg-white/10 transition-colors"
            >
              List my crops
            </Link>
          </div>

          {/* Trust pills */}
          <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
            {[
              "100% verified farmers",
              "Pre-order before harvest",
              "GCash & Maya",
              "Zero hidden fees",
            ].map((t) => (
              <span
                key={t}
                className="flex items-center gap-1.5 text-sm text-brand-300"
              >
                <CheckCircle2 size={13} className="text-brand-400 shrink-0" />{" "}
                {t}
              </span>
            ))}
          </div>
        </div>
      </section>

      {/* ── UPCOMING HARVESTS ── */}
      <section className="w-full min-h-screen flex flex-col justify-center bg-white px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-7xl">
          {/* Section header with left accent */}
          <div className="mb-10 flex items-end justify-between">
            <div className="border-l-4 border-brand-500 pl-4">
              <p className="text-xs font-bold uppercase tracking-widest text-brand-600 mb-0.5">
                Live Listings
              </p>
              <h2 className="font-display text-3xl font-extrabold text-slate-900 sm:text-4xl">
                Upcoming Harvests
              </h2>
              <p className="mt-1 text-slate-500 text-sm">
                Reserve fresh crops before they reach the market.
              </p>
            </div>
            <Link
              to="/register"
              className="hidden text-sm font-bold text-brand-700 hover:underline sm:inline"
            >
              View all →
            </Link>
          </div>

          {upcomingHarvests.length === 0 ? (
            <div className="flex flex-col items-center justify-center rounded-2xl border-2 border-dashed border-slate-200 py-24 text-center">
              <div className="grid h-16 w-16 place-items-center rounded-2xl bg-brand-50 text-brand-600 mb-4">
                <Leaf size={28} />
              </div>
              <p className="font-semibold text-slate-700">No listings yet</p>
              <p className="mt-1 text-sm text-slate-400">
                Be the first farmer to list your upcoming harvest.
              </p>
              <Link to="/register" className="btn-primary mt-5 px-6 py-2.5">
                Register as a farmer <ArrowRight size={16} />
              </Link>
            </div>
          ) : (
            <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {upcomingHarvests.map((p) => {
                const farmer = farmerMap[p.farmerId];
                const days = Math.max(0, daysUntil(p.estimatedHarvest) ?? 0);
                const urgencyColor =
                  days <= 14
                    ? "bg-red-500"
                    : days <= 30
                      ? "bg-harvest-500"
                      : "bg-slate-400";
                const urgencyText =
                  days <= 14
                    ? "text-red-700 bg-red-50"
                    : days <= 30
                      ? "text-harvest-700 bg-harvest-50"
                      : "text-slate-600 bg-slate-100";
                const photoUrl = p.photo?.url || null;
                const CropIcon = getCropIcon(p.crop);

                return (
                  <div
                    key={p.id}
                    className="group card overflow-hidden hover:-translate-y-1 hover:shadow-strong transition-all duration-200"
                  >
                    {/* Top urgency bar */}
                    <div className={`h-1.5 w-full ${urgencyColor}`} />

                    {/* Image */}
                    <div className="relative h-44 w-full bg-brand-50 overflow-hidden">
                      {photoUrl ? (
                        <img
                          src={photoUrl}
                          alt={p.crop}
                          className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
                        />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center">
                          <CropIcon size={52} className="text-brand-200" />
                        </div>
                      )}
                      {/* Price chip */}
                      <div className="absolute bottom-3 left-3 rounded-lg bg-brand-800 px-3 py-1">
                        <span className="font-bold text-white text-sm">
                          ₱{(p.pricePerKg || 0).toLocaleString()}
                          <span className="text-xs font-normal text-brand-200 ml-1">
                            /kg
                          </span>
                        </span>
                      </div>
                    </div>

                    {/* Card body */}
                    <div className="p-4">
                      <p className="font-extrabold text-slate-900 text-base">
                        {p.crop}
                      </p>
                      <p className="truncate text-xs text-slate-500 mt-0.5">
                        {farmer?.farmName || farmer?.name || "Unknown Farm"}
                      </p>
                      <div className="mt-2 flex items-center gap-1 text-xs text-slate-500">
                        <MapPin size={11} className="shrink-0" />
                        {farmer?.municipality ||
                          farmer?.barangay ||
                          "Philippines"}
                        {farmer?.province ? `, ${farmer.province}` : ""}
                      </div>
                      <div
                        className={`mt-3 inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold ${urgencyText}`}
                      >
                        <Leaf size={11} />
                        Harvest in {days} days ·{" "}
                        {(p.expectedYieldKg || 0).toLocaleString()} kg
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </section>

      {/* ── FEATURED FARMS ─── bg-brand-50 ── */}
      <section className="w-full min-h-screen flex flex-col justify-center bg-brand-50 px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-7xl">
          {/* Section header */}
          <div className="mb-10 flex items-end justify-between">
            <div className="border-l-4 border-brand-500 pl-4">
              <p className="text-xs font-bold uppercase tracking-widest text-brand-600 mb-0.5">
                Trusted Partners
              </p>
              <h2 className="font-display text-3xl font-extrabold text-slate-900 sm:text-4xl">
                Farms You Can Trust
              </h2>
              <p className="mt-1 text-sm text-slate-500">
                Every farm is reviewed and verified before listing on AgriLink.
              </p>
            </div>
            <Link
              to="/register"
              className="hidden text-sm font-bold text-brand-700 hover:underline sm:inline"
            >
              Join as farmer →
            </Link>
          </div>

          {featuredFarms.length === 0 ? (
            <div className="flex flex-col items-center justify-center rounded-2xl border-2 border-dashed border-brand-200 py-24 text-center">
              <div className="grid h-16 w-16 place-items-center rounded-2xl bg-white text-brand-600 mb-4">
                <Sprout size={28} />
              </div>
              <p className="font-semibold text-slate-700">
                No verified farms yet
              </p>
              <p className="mt-1 text-sm text-slate-500">
                Farmers are pending verification by the admin team.
              </p>
              <Link to="/register" className="btn-primary mt-5 px-6 py-2.5">
                Register your farm <ArrowRight size={16} />
              </Link>
            </div>
          ) : (
            <div className="grid gap-6 lg:grid-cols-5">
              {/* Farm cards — left 3 cols */}
              <div className="lg:col-span-3 grid gap-4 sm:grid-cols-2 content-start">
                {featuredFarms.map((f) => {
                  const crops = [...(farmerCropsMap[f.id] || [])];
                  const hasPin = f.location?.lat && f.location?.lng;
                  return (
                    <div
                      key={f.id}
                      className="group bg-white rounded-2xl border-2 border-brand-100 p-5 hover:-translate-y-1 hover:shadow-strong hover:border-brand-400 transition-all duration-200"
                    >
                      <div className="flex items-start gap-3">
                        {f.photo?.url ? (
                          <img
                            src={f.photo.url}
                            alt=""
                            className="h-12 w-12 rounded-xl object-cover shrink-0 border-2 border-brand-100"
                          />
                        ) : (
                          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-brand-700 text-white font-bold text-lg">
                            {(f.farmName || f.name || "F").charAt(0)}
                          </div>
                        )}
                        <div className="min-w-0 flex-1">
                          <div className="flex items-start justify-between gap-2">
                            <p className="font-extrabold text-slate-900 leading-snug text-sm">
                              {f.farmName || f.name}
                            </p>
                            <span className="badge-green shrink-0 flex items-center gap-1 text-xs">
                              <BadgeCheck size={10} /> Verified
                            </span>
                          </div>
                          <p className="mt-1 flex items-center gap-1 text-xs text-slate-500">
                            <MapPin
                              size={10}
                              className="shrink-0 text-brand-500"
                            />
                            <span className="truncate">
                              {f.municipality || f.barangay || "—"}
                              {f.province ? `, ${f.province}` : ""}
                            </span>
                          </p>
                        </div>
                      </div>

                      {crops.length > 0 && (
                        <div className="mt-3 flex flex-wrap gap-1">
                          {crops.slice(0, 4).map((cr) => (
                            <span key={cr} className="badge-gray text-xs">
                              {cr}
                            </span>
                          ))}
                          {crops.length > 4 && (
                            <span className="badge-gray text-xs">
                              +{crops.length - 4}
                            </span>
                          )}
                        </div>
                      )}

                      {hasPin && (
                        <div className="mt-3 flex items-center gap-1.5 text-xs text-brand-600 font-semibold">
                          <MapPin size={11} className="text-brand-500" />
                          {f.location.lat.toFixed(4)},{" "}
                          {f.location.lng.toFixed(4)}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>

              {/* Map — right 2 cols */}
              <div className="lg:col-span-2">
                <div className="sticky top-20 rounded-2xl overflow-hidden border-2 border-brand-200 shadow-strong">
                  {/* Map header */}
                  <div className="bg-brand-800 px-4 py-3 flex items-center gap-2">
                    <MapPin size={15} className="text-brand-300" />
                    <span className="text-sm font-bold text-white">
                      Farm Locations
                    </span>
                    <span className="ml-auto text-xs text-brand-300">
                      {featuredFarms.filter((f) => f.location?.lat).length}{" "}
                      pinned
                    </span>
                  </div>
                  <FarmsMap
                    height={420}
                    markers={featuredFarms
                      .filter((f) => f.location?.lat && f.location?.lng)
                      .map((f) => ({
                        id: f.id,
                        lat: f.location.lat,
                        lng: f.location.lng,
                        title: f.farmName || f.name,
                        subtitle: `${f.municipality || f.barangay || ""}, ${f.province || ""}`,
                        body: [...(farmerCropsMap[f.id] || [])]
                          .slice(0, 3)
                          .join(" · "),
                      }))}
                  />
                  <div className="bg-brand-50 border-t-2 border-brand-100 px-4 py-3">
                    <p className="text-xs text-brand-700 font-medium">
                      Click a pin to see farm details and available crops.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </section>

      {/* ── BENEFITS SPLIT ─── two solid-color panels ── */}
      <section className="w-full min-h-screen flex flex-col justify-center bg-white px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-7xl">
          <div className="mb-12 text-center">
            <p className="eyebrow mb-1">Who It's For</p>
            <h2 className="font-display text-3xl font-extrabold text-slate-900 sm:text-4xl lg:text-5xl">
              Built for buyers <span className="text-brand-600">&</span> farmers
            </h2>
          </div>

          <div className="grid gap-6 lg:grid-cols-2">
            {/* Buyers — harvest orange */}
            <div className="rounded-3xl bg-harvest-500 p-8 text-white">
              <div className="mb-6 flex items-center gap-3">
                <div className="grid h-12 w-12 place-items-center rounded-2xl bg-white/20">
                  <ShoppingCart size={22} />
                </div>
                <div>
                  <p className="text-xl font-extrabold">For Buyers</p>
                  <p className="text-sm text-harvest-200">
                    Restaurants · Hotels · Wholesalers
                  </p>
                </div>
              </div>
              <ul className="space-y-4 mb-8">
                {BUYER_BENEFITS.map((b) => (
                  <li key={b.title} className="flex gap-3">
                    <div className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-xl bg-white/20">
                      <b.icon size={16} />
                    </div>
                    <div>
                      <p className="font-bold text-sm">{b.title}</p>
                      <p className="text-xs text-harvest-100 mt-0.5">
                        {b.desc}
                      </p>
                    </div>
                  </li>
                ))}
              </ul>
              <Link
                to="/register"
                className="inline-flex items-center gap-2 rounded-xl bg-white px-6 py-3 text-sm font-bold text-harvest-700 hover:bg-harvest-50 transition-colors"
              >
                Start buying <ArrowRight size={15} />
              </Link>
            </div>

            {/* Farmers — deep green */}
            <div className="rounded-3xl bg-brand-800 p-8 text-white">
              <div className="mb-6 flex items-center gap-3">
                <div className="grid h-12 w-12 place-items-center rounded-2xl bg-white/20">
                  <Sprout size={22} />
                </div>
                <div>
                  <p className="text-xl font-extrabold">For Farmers</p>
                  <p className="text-sm text-brand-300">
                    Individual farms · Cooperatives
                  </p>
                </div>
              </div>
              <ul className="space-y-4 mb-8">
                {FARMER_BENEFITS.map((b) => (
                  <li key={b.title} className="flex gap-3">
                    <div className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-xl bg-white/20">
                      <b.icon size={16} />
                    </div>
                    <div>
                      <p className="font-bold text-sm">{b.title}</p>
                      <p className="text-xs text-brand-300 mt-0.5">{b.desc}</p>
                    </div>
                  </li>
                ))}
              </ul>
              <Link
                to="/register"
                className="inline-flex items-center gap-2 rounded-xl bg-white px-6 py-3 text-sm font-bold text-brand-800 hover:bg-brand-50 transition-colors"
              >
                List my crops <ArrowRight size={15} />
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* ── HOW IT WORKS ─── slate-900 dark section ── */}
      <section className="w-full min-h-screen flex flex-col items-center justify-center bg-slate-900 px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-7xl text-center">
          <p className="text-xs font-bold uppercase tracking-widest text-harvest-400 mb-2">
            Simple Process
          </p>
          <h2 className="font-display text-3xl font-extrabold text-white sm:text-4xl lg:text-5xl">
            How it works
          </h2>
          <p className="mt-3 text-slate-400 sm:text-lg max-w-xl mx-auto">
            From farm to order in three simple steps.
          </p>

          <div className="mt-14 grid gap-6 sm:grid-cols-3">
            {STEPS.map((s) => (
              <div
                key={s.step}
                className="rounded-2xl bg-slate-800 border-2 border-slate-700 p-7 hover:border-brand-500 hover:-translate-y-1 hover:shadow-strong transition-all duration-200"
              >
                {/* Number circle */}
                <div className="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-2xl bg-brand-600">
                  <s.Icon size={28} className="text-white" />
                </div>
                <div className="mb-2 font-bold text-2xl text-brand-400">
                  0{s.step}
                </div>
                <h3 className="text-lg font-extrabold text-white mb-2">
                  {s.title}
                </h3>
                <p className="text-sm text-slate-400 leading-relaxed">
                  {s.desc}
                </p>
              </div>
            ))}
          </div>

          <Link
            to="/register"
            className="btn-primary mt-12 px-8 py-3.5 text-base"
          >
            Get started for free <ArrowRight size={18} />
          </Link>
        </div>
      </section>

      {/* ── STATS ─── solid brand-700 ── */}
      <section className="w-full min-h-screen flex items-center justify-center bg-brand-700 px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-7xl text-center text-white">
          <p className="text-xs font-bold uppercase tracking-widest text-brand-300 mb-3">
            Growing Together
          </p>
          <h2 className="font-display text-3xl font-extrabold sm:text-4xl lg:text-5xl">
            Connecting Filipino Agriculture
          </h2>
          <p className="mt-4 text-brand-200 text-lg max-w-xl mx-auto">
            From farm to table, with full transparency and zero middlemen.
          </p>

          <div className="mt-12 grid grid-cols-2 gap-4 sm:grid-cols-4">
            {[
              {
                value: verifiedFarmers.length || "—",
                label: "Verified Farms",
                Icon: Sprout,
              },
              {
                value: allPlantings.length || "—",
                label: "Active Listings",
                Icon: Package,
              },
              { value: "₱0", label: "Hidden Fees", Icon: ShieldCheck },
              { value: "100%", label: "Filipino Grown", Icon: CheckCircle2 },
            ].map((s) => (
              <div
                key={s.label}
                className="rounded-2xl bg-brand-800 border-2 border-brand-600 px-5 py-7"
              >
                <div className="mb-3 mx-auto flex h-12 w-12 items-center justify-center rounded-xl bg-brand-600">
                  <s.Icon size={20} className="text-white" />
                </div>
                <div className="font-display text-4xl font-extrabold text-white">
                  {s.value}
                </div>
                <div className="mt-1.5 text-sm text-brand-300">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── TESTIMONIALS ─── white ── */}
      <section className="w-full min-h-screen flex flex-col justify-center bg-white px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-7xl">
          <div className="mb-12 text-center">
            <p className="eyebrow mb-1">Community</p>
            <h2 className="font-display text-3xl font-extrabold text-slate-900 sm:text-4xl lg:text-5xl">
              What our users say
            </h2>
          </div>

          <div className="grid gap-5 sm:grid-cols-3">
            {[
              {
                name: "Juan dela Cruz",
                role: "Farmer, Tagaytay",
                text: "Naibenta ko na agad ang harvest ko bago pa man mag-ani. Mas malaki ang kita ko ngayon dahil direkta na.",
              },
              {
                name: "Manila Fresh Bistro",
                role: "Buyer, Makati",
                text: "We pre-order veggies two weeks ahead. No more supply shortages, and deliveries stay consistently fresh.",
              },
              {
                name: "Rosa Mendoza",
                role: "Farmer, Nueva Ecija",
                text: "Ang daling gamitin. Inupload ko lang yung planting ko tapos may order na agad. Grabe ang convenience.",
              },
            ].map((t) => (
              <div
                key={t.name}
                className="card-accent p-6 hover:-translate-y-1 hover:shadow-strong transition-all duration-200"
              >
                <div className="mb-4 flex gap-0.5 text-harvest-500">
                  {[...Array(5)].map((_, i) => (
                    <Star key={i} size={14} fill="currentColor" />
                  ))}
                </div>
                <p className="text-sm leading-relaxed text-slate-700 italic">
                  "{t.text}"
                </p>
                <div className="mt-5 flex items-center gap-3">
                  <div className="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-brand-700 text-sm font-bold text-white">
                    {t.name.charAt(0)}
                  </div>
                  <div>
                    <p className="text-sm font-extrabold text-slate-900">
                      {t.name}
                    </p>
                    <p className="text-xs text-slate-400">{t.role}</p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── CTA ─── harvest orange ── */}
      <section className="w-full min-h-screen flex items-center justify-center bg-harvest-500 px-6 py-16 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto w-full max-w-3xl text-center text-white">
          <div className="mb-6 mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-white/20">
            <Sprout size={30} />
          </div>
          <h2 className="font-display text-4xl font-extrabold sm:text-5xl">
            Ready to join AgriLink?
          </h2>
          <p className="mt-5 text-lg text-harvest-100 max-w-xl mx-auto">
            Free to join for farmers and buyers. No subscription, no hidden
            fees.
          </p>
          <div className="mt-10 flex flex-wrap items-center justify-center gap-4">
            <Link
              to="/register"
              className="inline-flex items-center gap-2 rounded-xl bg-white px-10 py-4 text-lg font-extrabold text-harvest-700 hover:bg-harvest-50 shadow-strong transition-colors"
            >
              Create free account <ArrowRight size={20} />
            </Link>
            <Link
              to="/login"
              className="inline-flex items-center gap-2 rounded-xl border-2 border-white/40 px-10 py-4 text-lg font-bold text-white hover:bg-white/10 transition-colors"
            >
              Sign in
            </Link>
          </div>
          {verifiedFarmers.length > 0 && (
            <p className="mt-6 text-sm text-harvest-200">
              Join {verifiedFarmers.length} verified farmer
              {verifiedFarmers.length !== 1 ? "s" : ""} already on the platform.
            </p>
          )}
        </div>
      </section>

      {/* ── FOOTER ─── dark ── */}
      <footer className="w-full bg-brand-900 px-6 py-8 sm:px-10 lg:px-16 xl:px-24">
        <div className="mx-auto flex max-w-7xl flex-col items-center gap-4 sm:flex-row sm:justify-between">
          <Logo light />
          <p className="text-xs text-brand-400">
            © {new Date().getFullYear()} AgriLink — Smart Agriculture for the
            Philippines.
          </p>
          <div className="flex items-center gap-5 text-xs text-brand-400">
            <Link to="/login" className="hover:text-white transition-colors">
              Sign in
            </Link>
            <Link to="/register" className="hover:text-white transition-colors">
              Register
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
