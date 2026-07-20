import { PAYMENT_STATUS, PAYMENT_STATUS_LABEL } from "../../lib/constants";

const TONE = {
  [PAYMENT_STATUS.PENDING]: "badge-amber",
  [PAYMENT_STATUS.PARTIAL]: "badge-blue",
  [PAYMENT_STATUS.PAID]:    "badge-green",
};

export default function PaymentStatusBadge({ status }) {
  const cls = TONE[status] || "badge-gray";
  return <span className={cls}>{PAYMENT_STATUS_LABEL[status] || "—"}</span>;
}
