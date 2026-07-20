// Lightweight localStorage-backed "database" used in demo mode.
// Models the collections we'd otherwise have in Firestore:
//   users, plantings, orders, marketPrices.
//
// All writes notify in-memory subscribers so the UI feels real-time.
// Mutating methods return promises so the call sites are interchangeable
// with the Firestore-backed implementation in `firestoreDb.js`.

const STORAGE_KEY = "agrilink:db:v2";

const seed = () => ({
  users: [],
  plantings: [],
  orders: [],
  reports: [],

  marketPrices: [
    { crop: "Tomato", month: "2025-12", price: 50 },
    { crop: "Tomato", month: "2026-01", price: 55 },
    { crop: "Tomato", month: "2026-02", price: 58 },
    { crop: "Tomato", month: "2026-03", price: 62 },
    { crop: "Tomato", month: "2026-04", price: 60 },
    { crop: "Eggplant", month: "2025-12", price: 38 },
    { crop: "Eggplant", month: "2026-01", price: 40 },
    { crop: "Eggplant", month: "2026-02", price: 44 },
    { crop: "Eggplant", month: "2026-03", price: 46 },
    { crop: "Eggplant", month: "2026-04", price: 45 },
    { crop: "Lettuce", month: "2025-12", price: 70 },
    { crop: "Lettuce", month: "2026-01", price: 72 },
    { crop: "Lettuce", month: "2026-02", price: 75 },
    { crop: "Lettuce", month: "2026-03", price: 78 },
    { crop: "Lettuce", month: "2026-04", price: 80 },
  ],
});

const load = () => {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      const initial = seed();
      localStorage.setItem(STORAGE_KEY, JSON.stringify(initial));
      return initial;
    }
    return JSON.parse(raw);
  } catch {
    return seed();
  }
};

const save = (state) => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  notify();
};

const subscribers = new Set();
const notify = () => subscribers.forEach((cb) => cb());

const uid = (prefix = "id") =>
  `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;

const nowIso = () => new Date().toISOString();

export const mockDb = {
  isFirestore: false,

  // Mock backend is "ready" immediately.
  ready() {
    return Promise.resolve();
  },

  subscribe(cb) {
    subscribers.add(cb);
    return () => subscribers.delete(cb);
  },

  async reset() {
    localStorage.removeItem(STORAGE_KEY);
    notify();
  },

  // --- users ---
  listUsers() {
    return load().users;
  },
  findUserByEmail(email) {
    return (
      load().users.find(
        (u) => u.email.toLowerCase() === (email || "").toLowerCase(),
      ) || null
    );
  },
  async findUserByEmailRemote(email) {
    return this.findUserByEmail(email);
  },
  findUserById(id) {
    return load().users.find((u) => u.id === id) || null;
  },

  async createUser(data) {
    const state = load();
    const user = {
      id: uid("u"),
      createdAt: nowIso(),
      verified: false,
      photo: null,
      ...data,
    };
    state.users.push(user);
    save(state);
    return user;
  },
  async updateUser(id, patch) {
    const state = load();
    const idx = state.users.findIndex((u) => u.id === id);
    if (idx >= 0) {
      state.users[idx] = { ...state.users[idx], ...patch };
      save(state);
      return state.users[idx];
    }
    return null;
  },
  async deleteUser(id) {
    const state = load();
    state.users = state.users.filter((u) => u.id !== id);
    save(state);
  },

  // --- plantings ---
  listPlantings(filter = {}) {
    let list = load().plantings;
    if (filter.farmerId)
      list = list.filter((p) => p.farmerId === filter.farmerId);
    return list;
  },
  async createPlanting(data) {
    const state = load();
    const planting = {
      id: uid("plant"),
      createdAt: nowIso(),
      status: "growing",
      photo: null,
      ...data,
    };
    state.plantings.push(planting);
    save(state);
    return planting;
  },
  async updatePlanting(id, patch) {
    const state = load();
    const idx = state.plantings.findIndex((p) => p.id === id);
    if (idx >= 0) {
      state.plantings[idx] = { ...state.plantings[idx], ...patch };
      save(state);
      return state.plantings[idx];
    }
    return null;
  },
  async deletePlanting(id) {
    const state = load();
    state.plantings = state.plantings.filter((p) => p.id !== id);
    save(state);
  },

  // --- orders ---
  listOrders(filter = {}) {
    let list = load().orders;
    if (filter.buyerId) list = list.filter((o) => o.buyerId === filter.buyerId);
    if (filter.farmerId)
      list = list.filter((o) => o.farmerId === filter.farmerId);
    return list;
  },
  async createOrder(data) {
    const state = load();
    const now = nowIso();
    const order = {
      id: uid("ord"),
      placedAt: now,
      status: "pending",
      timeline: [{ status: "pending", at: now, note: "Pre-order placed" }],
      paymentHistory: [],
      paidAmountPHP: 0,
      balanceDuePHP: data.totalPHP || 0,
      paymentStatus: "pending",
      ...data,
    };
    state.orders.push(order);
    save(state);
    return order;
  },
  async updateOrderStatus(id, nextStatus, note = "", meta = {}) {
    const state = load();
    const idx = state.orders.findIndex((o) => o.id === id);
    if (idx < 0) return null;
    const order = state.orders[idx];
    order.status = nextStatus;
    order.timeline = [
      ...(order.timeline || []),
      {
        status: nextStatus,
        at: nowIso(),
        note,
        ...(meta.photo ? { photo: meta.photo } : {}),
      },
    ];
    save(state);
    return order;
  },
  async addPaymentToOrder(id, payment) {
    const state = load();
    const idx = state.orders.findIndex((o) => o.id === id);
    if (idx < 0) return null;
    const order = state.orders[idx];
    if (order.status === "cancelled") {
      throw new Error("Cancelled orders cannot be paid.");
    }
    const history = [
      ...(order.paymentHistory || []),
      { ...payment, at: nowIso() },
    ];
    const paid = history.reduce((s, p) => s + (p.amount || 0), 0);
    const balance = Math.max(0, (order.totalPHP || 0) - paid);
    order.paymentHistory = history;
    order.paidAmountPHP = paid;
    order.balanceDuePHP = balance;
    order.paymentStatus =
      balance === 0 ? "paid" : paid > 0 ? "partial" : "pending";
    save(state);
    return order;
  },

  // --- reports ---
  listReports(filter = {}) {
    let list = load().reports || [];
    if (filter.reportedUserId)
      list = list.filter((r) => r.reportedUserId === filter.reportedUserId);
    if (filter.reporterId)
      list = list.filter((r) => r.reporterId === filter.reporterId);
    return list;
  },
  async createReport(data) {
    const state = load();
    const report = {
      id: uid("rep"),
      createdAt: nowIso(),
      status: "open",
      ...data,
    };
    state.reports = [...(state.reports || []), report];
    save(state);
    return report;
  },

  // --- market prices ---
  listMarketPrices(crop) {
    const list = load().marketPrices;
    return crop ? list.filter((m) => m.crop === crop) : list;
  },
  async addMarketPrice(entry) {
    const state = load();
    state.marketPrices.push(entry);
    save(state);
  },
};
