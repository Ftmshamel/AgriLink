// Centralized constants for AgriLink

export const ROLES = {
  FARMER: "farmer",
  BUYER: "buyer",
  ADMIN: "admin",
};

export const ROLE_LABELS = {
  [ROLES.FARMER]: "Farmer",
  [ROLES.BUYER]: "Buyer",
  [ROLES.ADMIN]: "Admin",
};

// Order status flow (Shopee-style)
export const ORDER_STATUS = {
  PENDING: "pending",
  GROWING: "growing",
  PREPARING: "preparing",
  HARVESTED: "harvested",
  READY: "ready_for_pickup",
  IN_TRANSIT: "in_transit",
  DELIVERED: "delivered",
  CANCELLED: "cancelled",
};

export const ORDER_STATUS_LABEL = {
  [ORDER_STATUS.PENDING]: "Pending",
  [ORDER_STATUS.GROWING]: "Growing",
  [ORDER_STATUS.PREPARING]: "Preparing",
  [ORDER_STATUS.HARVESTED]: "Harvested",
  [ORDER_STATUS.READY]: "Ready for Pickup",
  [ORDER_STATUS.IN_TRANSIT]: "In Transit",
  [ORDER_STATUS.DELIVERED]: "Delivered",
  [ORDER_STATUS.CANCELLED]: "Cancelled",
};

// Ordered progression for the progress tracker
export const ORDER_FLOW = [
  ORDER_STATUS.PENDING,
  ORDER_STATUS.GROWING,
  ORDER_STATUS.HARVESTED,
  ORDER_STATUS.PREPARING,
  ORDER_STATUS.READY,
  ORDER_STATUS.IN_TRANSIT,
  ORDER_STATUS.DELIVERED,
];

export const GRADES = ["A", "B", "C"];

// --- Payments ---

export const PAYMENT_MODE = {
  FULL: "full",
  DOWN_50: "down_50", // 50% downpayment, 50% on delivery
  DOWN_30: "down_30", // 30% downpayment, 70% on delivery
  COD: "cod", // 100% on delivery
};

export const PAYMENT_MODE_INFO = {
  [PAYMENT_MODE.FULL]: {
    label: "Pay in full now",
    downPct: 100,
    helper: "Lock in your reservation by paying the full amount up-front.",
  },
  [PAYMENT_MODE.DOWN_50]: {
    label: "50% downpayment",
    downPct: 50,
    helper: "Pay half now, half on pickup or delivery.",
  },
  [PAYMENT_MODE.DOWN_30]: {
    label: "30% downpayment",
    downPct: 30,
    helper: "Smaller upfront commitment, pay the rest on delivery.",
  },
  [PAYMENT_MODE.COD]: {
    label: "Cash on delivery (COD)",
    downPct: 0,
    helper:
      "No upfront payment. Pay the full amount when the crop is delivered.",
  },
};

export const PAYMENT_METHODS = [
  { id: "GCash", label: "GCash", tag: "E-wallet" },
  { id: "Maya", label: "Maya", tag: "E-wallet" },
  { id: "BPI", label: "BPI Online", tag: "Bank transfer" },
  { id: "BDO", label: "BDO Online", tag: "Bank transfer" },
  { id: "UnionBank", label: "UnionBank", tag: "Bank transfer" },
  { id: "Cash", label: "Cash on pickup", tag: "In-person" },
];

export const PAYMENT_STATUS = {
  PENDING: "pending",
  PARTIAL: "partial",
  PAID: "paid",
};

export const PAYMENT_STATUS_LABEL = {
  [PAYMENT_STATUS.PENDING]: "Awaiting payment",
  [PAYMENT_STATUS.PARTIAL]: "Partially paid",
  [PAYMENT_STATUS.PAID]: "Fully paid",
};

// Default map center: roughly central Philippines (between Manila and Cebu)
export const DEFAULT_MAP_CENTER = [12.8797, 121.774];
export const DEFAULT_MAP_ZOOM = 6;

// Backend URL for the AI service.
// Override in frontend/.env with VITE_API_URL=http://localhost:8000
export const API_URL =
  import.meta.env.VITE_API_URL ||
  (import.meta.env.DEV ? "http://localhost:8000" : "/api");
