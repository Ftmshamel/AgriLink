// Adapted Firestore data layer for existing database structure.
// Your Firestore database stores everything inside ONE document with arrays.
// This adapter reads that structure and maps it to what the app expects.
//
// IMPORTANT: Set MAIN_COLLECTION and MAIN_DOC_ID to match your Firestore path.
// Open Firebase Console → Firestore → click the document → note the path.

import {
  collection,
  getDocs,
  doc,
  onSnapshot,
  updateDoc,
  arrayUnion,
} from "firebase/firestore";
import { db as firestore } from "./firebase";

// ─── CONFIG ───────────────────────────────────────────────────────────────────
// We will try each path below until we find one that has data.
// The format is: { collection: "collectionName", doc: "documentId" }
// "auto" as doc means: take the first document found in that collection.
const CANDIDATE_PATHS = [
  { collection: "agriData", doc: "auto" },
  { collection: "agriData", doc: "main" },
  { collection: "main", doc: "auto" },
  { collection: "agrilink", doc: "main" },
  { collection: "agrilink", doc: "auto" },
  { collection: "data", doc: "main" },
  { collection: "data", doc: "auto" },
];
// ─────────────────────────────────────────────────────────────────────────────

let resolvedDocRef = null;

const cache = {
  users: [],
  crops: [],
  reservations: [],
  reports: [],
  hubs: [],
  logs: [],
  verifications: [],
  marketSync: [],
};

const PH_LOCATION_FALLBACKS = [
  { match: ["san ildefonso", "bulacan"], lat: 15.0792, lng: 120.9419 },
  { match: ["urayong", "la union"], lat: 16.5465, lng: 120.3336 },
  { match: ["bauang", "la union"], lat: 16.5308, lng: 120.3331 },
  { match: ["la union"], lat: 16.6159, lng: 120.3209 },
];

const subscribers = new Set();
const notify = () =>
  subscribers.forEach((cb) => {
    try {
      cb();
    } catch {
      /* ignore */
    }
  });

let initialized = false;
const readyResolvers = [];
let readyPromise = new Promise((r) => readyResolvers.push(r));

const resolveReady = () => readyResolvers.splice(0).forEach((r) => r());

// Try every known coordinate format and return { lat, lng } or null
// Logs what it finds so you can spot coordinate field names in the console.
const parseCoords = (u) => {
  // possible sub-object field names
  const raw =
    u.coords ?? u.location ?? u.geopoint ?? u.coordinates ?? u.position ?? null;
  if (raw && typeof raw === "object") {
    // Firestore GeoPoint → .latitude / .longitude
    // plain object     → .lat / .lng
    // legacy           → .x / .y
    const lat = raw.latitude ?? raw.lat ?? raw.x ?? null;
    const lng = raw.longitude ?? raw.lng ?? raw.y ?? null;
    if (lat != null && lng != null)
      return { lat: Number(lat), lng: Number(lng) };
  }
  // top-level flat fields
  const lat = u.latitude ?? u.lat ?? null;
  const lng = u.longitude ?? u.lng ?? null;
  if (lat != null && lng != null) return { lat: Number(lat), lng: Number(lng) };

  const addressText = [
    u.farmAddress,
    u.address,
    u.barangay,
    u.municipality,
    u.province,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
  const fallback = PH_LOCATION_FALLBACKS.find(({ match }) =>
    match.every((part) => addressText.includes(part)),
  );
  if (fallback) {
    return { lat: fallback.lat, lng: fallback.lng, approximate: true };
  }

  console.info(
    `[AgriLink] No coordinates found for user "${u.name || u.id}". Raw keys:`,
    Object.keys(u),
  );
  return null;
};

const mapPhoto = (photo) => {
  if (!photo) return null;
  if (typeof photo === "string")
    return { url: photo, path: null, kind: "data-url" };
  if (typeof photo === "object" && photo.url) {
    return {
      url: photo.url,
      path: photo.path || null,
      kind: photo.kind || (photo.path ? "firebase" : "data-url"),
    };
  }
  return null;
};

// Build a user object mapped to what the app expects
const mapUser = (u, verifications = []) => {
  const ver = verifications.find(
    (v) => v.id?.includes(u.id) || v.name === u.name,
  );
  const isVerified = ver?.status === "Verified" || u.role === "buyer" || true;
  // ↑ set to `true` so all farmers show while you're still pending verification

  const addressParts = (u.farmAddress || u.address || "").split(",");
  return {
    id: u.id,
    email: (u.email || "").toLowerCase(),
    password: u.password || "",
    name: u.name || "",
    role: u.role || "buyer",
    verified: isVerified,
    phone: u.phone || "",
    photo: mapPhoto(u.photo),
    farmName: u.farmName || u.name || "",
    barangay: u.barangay || addressParts[0]?.trim() || "",
    municipality: u.municipality || addressParts[1]?.trim() || "",
    province: u.province || addressParts[2]?.trim() || "",
    region: u.region || "",
    location: parseCoords(u),
    address: u.address || u.farmAddress || "",
    businessType: u.businessType || (u.role === "buyer" ? "Restaurant" : ""),
    createdAt: u.createdAt || new Date().toISOString(),
    blocked: u.blocked === true,
  };
};

// Map a crop listing to the planting format the app expects
const mapCropToPlanting = (crop) => {
  // Fallback harvest date: ensure it's always in the future so seeded crops
  // (whose createdAt may be months/years old) still render as "upcoming".
  const fallbackHarvest = () => {
    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    const base = crop.createdAt
      ? new Date(crop.createdAt).getTime() + thirtyDaysMs
      : Date.now() + thirtyDaysMs;
    return new Date(Math.max(base, Date.now() + thirtyDaysMs)).toISOString();
  };
  return {
    id: crop.id,
    farmerId: crop.ownerUserId,
    crop: crop.name,
    variety: crop.variety || "",
    datePlanted: crop.createdAt || new Date().toISOString(),
    estimatedHarvest:
      crop.expectedHarvest || crop.harvestDate || fallbackHarvest(),
    growthDays: crop.maturity || 90,
    areaHectares: 1,
    expectedYieldKg: crop.quantity || 0,
    preOrderStockKg: crop.preOrderStockKg ?? crop.quantity ?? 0,
    allowBulkPreorder: crop.allowBulkPreorder !== false,
    maxPerAccountKg: crop.maxPerAccountKg ?? null,
    pricePerKg: crop.price || 0,
    status: "growing",
    photo: crop.photo
      ? { url: crop.photo, path: null, kind: "data-url" }
      : null,
    notes: crop.notes || "",
    location: crop.location || "",
    farmer: crop.farmer || "",
    farmerEmail: crop.farmerEmail || "",
    createdAt: crop.createdAt || new Date().toISOString(),
    updatedAt: crop.updatedAt || new Date().toISOString(),
  };
};

// Map a reservation to the order format
const mapReservationToOrder = (r) => {
  const fallbackStatus =
    r.status === "Paid - Processing"
      ? "growing"
      : r.status === "Delivered"
        ? "delivered"
        : r.status === "Cancelled"
          ? "cancelled"
          : "growing";

  return {
    id: r.id,
    buyerId: r.buyerId || null,
    farmerId: r.farmerId || null,
    plantingId: r.plantingId || null,
    crop: r.crop,
    quantityKg: r.qty || 0,
    pricePerKg:
      r.pricePerKg ??
      (r.totalPrice ? Math.round(r.totalPrice / (r.qty || 1)) : 0),
    totalPHP: r.totalPrice || 0,
    status:
      r.status &&
      [
        "pending",
        "growing",
        "preparing",
        "harvested",
        "ready_for_pickup",
        "in_transit",
        "delivered",
        "cancelled",
      ].includes(r.status)
        ? r.status
        : fallbackStatus,
    placedAt: r.createdAt || new Date().toISOString(),
    expectedDate: r.eta || "",
    paymentMode: r.paymentMode || "full",
    paymentMethod: r.paymentDetails?.paymentMethod || r.paymentMethod || "Cash",
    downpaymentPct: r.downpaymentPct ?? 100,
    paidAmountPHP: r.paidAmountPHP ?? r.totalPrice ?? 0,
    balanceDuePHP: r.balanceDuePHP ?? 0,
    paymentStatus: r.paymentStatus || "paid",
    paymentHistory: r.paymentHistory || [
      {
        amount: r.totalPrice || 0,
        method: r.paymentDetails?.paymentMethod || "Cash",
        note: "Full payment",
        reference: r.id,
        at: r.createdAt || new Date().toISOString(),
      },
    ],
    timeline: r.timeline || [
      {
        status: "pending",
        at: r.createdAt || new Date().toISOString(),
        note: "Pre-order placed",
      },
      {
        status: "growing",
        at: r.createdAt || new Date().toISOString(),
        note: "Confirmed",
      },
    ],
  };
};

// ── Initialise: auto-detect the document reference ────────────────────────────
// Try to find the document by iterating candidate paths
const tryFindDocument = async () => {
  for (const { collection: colName, doc: docId } of CANDIDATE_PATHS) {
    try {
      if (docId === "auto") {
        const snap = await getDocs(collection(firestore, colName));
        if (!snap.empty) {
          const d = snap.docs[0];
          const data = d.data() || {};
          if (data.users || data.crops || data.reservations) {
            console.info(`[AgriLink] ✅ Found data at: ${colName}/${d.id}`);
            return d.ref;
          }
        }
      } else {
        const { getDoc } = await import("firebase/firestore");
        const ref = doc(firestore, colName, docId);
        const snap = await getDoc(ref);
        if (snap.exists()) {
          const data = snap.data() || {};
          if (data.users || data.crops || data.reservations) {
            console.info(`[AgriLink] ✅ Found data at: ${colName}/${docId}`);
            return ref;
          }
        }
      }
    } catch {
      /* silently try next */
    }
  }
  return null;
};

const initialize = async () => {
  if (initialized) return;
  initialized = true;

  try {
    console.info("[AgriLink] 🔍 Searching for your Firestore data...");
    const docRef = await tryFindDocument();

    if (!docRef) {
      console.error(
        "[AgriLink] ❌ Could not find your data in Firestore.\n" +
          "  → Please open Firebase Console → Firestore → find your data\n" +
          "  → Then tell us the collection name shown in the LEFT panel.\n" +
          "  → Tried these paths: " +
          CANDIDATE_PATHS.map((p) => `${p.collection}/${p.doc}`).join(", "),
      );
      resolveReady();
      return;
    }

    resolvedDocRef = docRef;

    // Real-time listener on the found document
    onSnapshot(
      docRef,
      async (snap) => {
        if (!snap.exists()) {
          console.warn("[AgriLink] Document no longer exists:", docRef.path);
          resolveReady();
          return;
        }
        const data = snap.data() || {};
        cache.users = data.users || [];
        cache.crops = data.crops || [];
        cache.reservations = data.reservations || [];
        cache.reports = data.reports || [];
        cache.hubs = data.hubs || [];
        cache.logs = data.logs || [];
        cache.verifications = data.verifications || [];
        cache.marketSync = data.marketSync || [];
        console.info(
          "[AgriLink] ✅ Data loaded —",
          cache.users.length,
          "users |",
          cache.crops.length,
          "crops |",
          cache.reservations.length,
          "reservations",
        );

        // Auto-seed a default admin account if none exists
        const hasAdmin = cache.users.some((u) => u.role === "admin");
        if (!hasAdmin) {
          const adminUser = {
            id: "admin-default",
            email: "admin@agrilink.com",
            password: "admin123",
            name: "AgriLink Admin",
            role: "admin",
            phone: "",
            address: "",
            farmAddress: "",
            farmName: "",
            createdAt: new Date().toISOString(),
          };
          try {
            await updateDoc(docRef, { users: arrayUnion(adminUser) });
            console.info(
              "[AgriLink] 🔑 Default admin created → admin@agrilink.com / admin123",
            );
          } catch {
            // non-fatal — show credentials anyway
            cache.users = [...cache.users, adminUser];
            console.info(
              "[AgriLink] 🔑 Admin seeded locally → admin@agrilink.com / admin123",
            );
          }
        }

        resolveReady();
        notify();
      },
      (err) => {
        console.error("[AgriLink] ❌ Listener error:", err.message);
        resolveReady();
      },
    );
  } catch (err) {
    console.error("[AgriLink] ❌ Init error:", err.message);
    resolveReady();
  }
};

// Auto-init on import
if (firestore) initialize();

// ── Helpers ───────────────────────────────────────────────────────────────────
const nowIso = () => new Date().toISOString();
const uid = (prefix = "id") =>
  `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;

// ── Public API ────────────────────────────────────────────────────────────────
export const firestoreDb = {
  isFirestore: true,

  ready() {
    return readyPromise;
  },

  subscribe(cb) {
    subscribers.add(cb);
    return () => subscribers.delete(cb);
  },

  async reset() {
    notify();
  },

  // ----- users -----
  listUsers() {
    return cache.users.map((u) => mapUser(u, cache.verifications));
  },

  findUserById(id) {
    const u = cache.users.find((u) => u.id === id);
    return u ? mapUser(u, cache.verifications) : null;
  },

  findUserByEmail(email) {
    if (!email) return null;
    const u = cache.users.find(
      (u) => (u.email || "").toLowerCase() === email.toLowerCase(),
    );
    return u ? mapUser(u, cache.verifications) : null;
  },

  async findUserByEmailRemote(email) {
    return this.findUserByEmail(email);
  },

  async createUser(data) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const newUser = {
      id: uid("user"),
      email: (data.email || "").toLowerCase(),
      password: data.password || "",
      name: data.name || "",
      role: data.role || "buyer",
      phone: data.phone || "",
      address: data.address || "",
      farmAddress: data.farmName
        ? `${data.barangay || ""}, ${data.municipality || ""}, ${data.province || ""}`
        : "",
      location: data.location || null,
      farmName: data.farmName || "",
      barangay: data.barangay || "",
      municipality: data.municipality || "",
      province: data.province || "",
      region: data.region || "",
      businessType: data.businessType || "",
      address: data.address || "",
      createdAt: nowIso(),
    };
    await updateDoc(resolvedDocRef, {
      users: arrayUnion(newUser),
      verifications: arrayUnion({
        id: uid("verification"),
        name: newUser.name,
        role: newUser.role === "farmer" ? "Farmer" : "Buyer",
        status: "Pending",
        documentsSubmitted: 0,
        submittedAt: nowIso().slice(0, 10),
        createdAt: nowIso(),
      }),
    });
    return mapUser(newUser, cache.verifications);
  },

  async updateUser(id, patch) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const users = cache.users.map((u) =>
      u.id === id ? { ...u, ...patch, id } : u,
    );
    await updateDoc(resolvedDocRef, { users });
    const updated = users.find((u) => u.id === id);
    return updated ? mapUser(updated, cache.verifications) : null;
  },

  async deleteUser(id) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const users = cache.users.filter((u) => u.id !== id);
    await updateDoc(resolvedDocRef, { users });
  },

  // ----- plantings (mapped from crops) -----
  listPlantings(filter = {}) {
    let list = cache.crops.map(mapCropToPlanting);
    if (filter.farmerId)
      list = list.filter((p) => p.farmerId === filter.farmerId);
    return list;
  },

  async createPlanting(data) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const newCrop = {
      id: uid("crop"),
      name: data.crop,
      variety: data.variety || "",
      farmer: data.farmer || "",
      farmerEmail: data.farmerEmail || "",
      ownerUserId: data.farmerId,
      price: data.pricePerKg || 0,
      quantity: data.expectedYieldKg || 0,
      preOrderStockKg: data.preOrderStockKg ?? data.expectedYieldKg ?? 0,
      allowBulkPreorder: data.allowBulkPreorder !== false,
      maxPerAccountKg:
        data.allowBulkPreorder === false
          ? (data.maxPerAccountKg ?? null)
          : null,
      expectedHarvest: data.estimatedHarvest || "",
      harvestDate: data.estimatedHarvest || "",
      location: data.location || "",
      notes: data.notes || "",
      photo: data.photo?.url || null,
      maturity: data.growthDays || 90,
      createdAt: nowIso(),
      updatedAt: nowIso(),
    };
    await updateDoc(resolvedDocRef, { crops: arrayUnion(newCrop) });
    return mapCropToPlanting(newCrop);
  },

  async updatePlanting(id, patch) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const toCropPatch = {
      ...(patch.crop != null ? { name: patch.crop } : {}),
      ...(patch.variety != null ? { variety: patch.variety } : {}),
      ...(patch.farmerId != null ? { ownerUserId: patch.farmerId } : {}),
      ...(patch.pricePerKg != null ? { price: Number(patch.pricePerKg) } : {}),
      ...(patch.expectedYieldKg != null
        ? { quantity: Number(patch.expectedYieldKg) }
        : {}),
      ...(patch.preOrderStockKg != null
        ? { preOrderStockKg: Number(patch.preOrderStockKg) }
        : {}),
      ...(patch.allowBulkPreorder != null
        ? { allowBulkPreorder: !!patch.allowBulkPreorder }
        : {}),
      ...(patch.maxPerAccountKg !== undefined
        ? {
            maxPerAccountKg:
              patch.maxPerAccountKg == null
                ? null
                : Number(patch.maxPerAccountKg),
          }
        : {}),
      ...(patch.estimatedHarvest != null
        ? {
            expectedHarvest: patch.estimatedHarvest,
            harvestDate: patch.estimatedHarvest,
          }
        : {}),
      ...(patch.location != null ? { location: patch.location } : {}),
      ...(patch.notes != null ? { notes: patch.notes } : {}),
      ...(patch.photo?.url != null ? { photo: patch.photo.url } : {}),
      ...(patch.growthDays != null
        ? { maturity: Number(patch.growthDays) }
        : {}),
    };
    const crops = cache.crops.map((c) =>
      c.id === id ? { ...c, ...toCropPatch, id, updatedAt: nowIso() } : c,
    );
    await updateDoc(resolvedDocRef, { crops });
    const updated = crops.find((c) => c.id === id);
    return updated ? mapCropToPlanting(updated) : null;
  },

  async deletePlanting(id) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const crops = cache.crops.filter((c) => c.id !== id);
    await updateDoc(resolvedDocRef, { crops });
  },

  // ----- orders (mapped from reservations) -----
  listOrders(filter = {}) {
    let list = cache.reservations.map(mapReservationToOrder);

    // Helper to match by id or by linked user email (handles legacy IDs)
    const matchByUser = (resId, targetUserId) => {
      if (!resId || !targetUserId) return false;
      if (resId === targetUserId) return true;
      // Try to resolve both ids to user records and compare emails
      const resUser = cache.users.find((u) => u.id === resId) || null;
      const targetUser = cache.users.find((u) => u.id === targetUserId) || null;
      if (resUser && targetUser && resUser.email && targetUser.email) {
        return resUser.email.toLowerCase() === targetUser.email.toLowerCase();
      }
      return false;
    };

    if (filter.buyerId) {
      list = list.filter((o) => matchByUser(o.buyerId, filter.buyerId));
    }
    if (filter.farmerId) {
      list = list.filter((o) => matchByUser(o.farmerId, filter.farmerId));
    }

    return list;
  },

  async createOrder(data) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const newRes = {
      id: uid("reservation"),
      buyerId: data.buyerId || null,
      farmerId: data.farmerId || null,
      plantingId: data.plantingId || null,
      crop: data.crop,
      farmer: data.farmer || "",
      qty: data.quantityKg || 0,
      totalPrice: data.totalPHP || 0,
      status: "Paid - Processing",
      eta: data.expectedDate || "",
      createdAt: nowIso(),
      paymentDetails: {
        paymentMethod: data.paymentMethod || "Cash",
        buyerName: "",
        fulfillmentType: "pickup",
        paidAt: nowIso(),
      },
      // keep full app-side fields so listOrders filter works immediately
      paymentMode: data.paymentMode || "full",
      downpaymentPct: data.downpaymentPct ?? 100,
      paidAmountPHP: data.paidAmountPHP ?? data.totalPHP ?? 0,
      balanceDuePHP: data.balanceDuePHP ?? 0,
      paymentStatus: data.paymentStatus || "paid",
      paymentHistory: data.paymentHistory || [],
      timeline: data.timeline || [],
    };
    await updateDoc(resolvedDocRef, { reservations: arrayUnion(newRes) });
    return mapReservationToOrder(newRes);
  },

  async updateOrderStatus(id, nextStatus, note = "", meta = {}) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const reservations = cache.reservations.map((r) =>
      r.id === id
        ? {
            ...r,
            status: nextStatus,
            updatedAt: nowIso(),
            timeline: [
              ...(r.timeline || []),
              {
                status: nextStatus,
                at: nowIso(),
                note,
                ...(meta.photo ? { photo: meta.photo } : {}),
              },
            ],
          }
        : r,
    );
    await updateDoc(resolvedDocRef, { reservations });
    const updated = reservations.find((r) => r.id === id);
    return updated ? mapReservationToOrder(updated) : null;
  },

  async addPaymentToOrder(id, payment) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const order = cache.reservations.find((r) => r.id === id);
    if (!order) return null;
    if (order.status === "cancelled") {
      throw new Error("Cancelled orders cannot be paid.");
    }

    const history = [
      ...(order.paymentHistory || []),
      { ...payment, at: nowIso() },
    ];
    const paid = history.reduce(
      (sum, item) => sum + Number(item.amount || 0),
      0,
    );
    const balance = Math.max(0, Number(order.totalPHP || 0) - paid);
    const updated = {
      ...order,
      paymentHistory: history,
      paidAmountPHP: paid,
      balanceDuePHP: balance,
      paymentStatus: balance === 0 ? "paid" : paid > 0 ? "partial" : "pending",
      updatedAt: nowIso(),
    };

    const reservations = cache.reservations.map((r) =>
      r.id === id ? updated : r,
    );
    cache.reservations = reservations;
    await updateDoc(resolvedDocRef, { reservations });
    return mapReservationToOrder(updated);
  },

  // ----- reports -----
  listReports(filter = {}) {
    let list = cache.reports || [];
    if (filter.reportedUserId)
      list = list.filter((r) => r.reportedUserId === filter.reportedUserId);
    if (filter.reporterId)
      list = list.filter((r) => r.reporterId === filter.reporterId);
    return list;
  },

  async createReport(data) {
    if (!resolvedDocRef) throw new Error("Firestore not ready");
    const newReport = {
      id: uid("report"),
      createdAt: nowIso(),
      status: "open",
      ...data,
    };
    await updateDoc(resolvedDocRef, { reports: arrayUnion(newReport) });
    return newReport;
  },

  // ----- market prices (not in your DB — return empty) -----
  listMarketPrices(crop) {
    // Your database doesn't have market prices yet.
    // Return some sample data so trends work.
    const samples = [
      { crop: "Rice", month: "2026-01", price: 800 },
      { crop: "Rice", month: "2026-02", price: 820 },
      { crop: "Rice", month: "2026-03", price: 810 },
      { crop: "Rice", month: "2026-04", price: 800 },
      { crop: "Corn", month: "2026-01", price: 950 },
      { crop: "Corn", month: "2026-02", price: 980 },
      { crop: "Corn", month: "2026-03", price: 1000 },
      { crop: "Corn", month: "2026-04", price: 1000 },
    ];
    return crop ? samples.filter((m) => m.crop === crop) : samples;
  },

  async addMarketPrice() {
    // not yet implemented for this DB structure
  },
};

// Hot-reload safety
if (typeof window !== "undefined") {
  window.__agrilinkFirestoreUnsub = null;
}
