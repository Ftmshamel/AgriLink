import { format, formatDistanceToNowStrict, differenceInDays, parseISO, isValid } from "date-fns";

const toDate = (value) => {
  if (!value) return null;
  if (value instanceof Date) return value;
  const parsed = typeof value === "string" ? parseISO(value) : new Date(value);
  return isValid(parsed) ? parsed : null;
};

export const fmtDate = (value, pattern = "MMM d, yyyy") => {
  const d = toDate(value);
  return d ? format(d, pattern) : "—";
};

export const fmtRelative = (value) => {
  const d = toDate(value);
  if (!d) return "—";
  return formatDistanceToNowStrict(d, { addSuffix: true });
};

export const daysUntil = (value) => {
  const d = toDate(value);
  if (!d) return null;
  return differenceInDays(d, new Date());
};

export const fmtPHP = (n) =>
  new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
    maximumFractionDigits: 0,
  }).format(Number(n) || 0);

export const fmtNumber = (n) =>
  new Intl.NumberFormat("en-PH").format(Number(n) || 0);
