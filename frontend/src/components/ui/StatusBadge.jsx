import { ORDER_STATUS, ORDER_STATUS_LABEL } from "../../lib/constants";

const TONE = {
  [ORDER_STATUS.PENDING]:    "badge-amber",
  [ORDER_STATUS.GROWING]:    "badge-green",
  [ORDER_STATUS.PREPARING]:  "badge-blue",
  [ORDER_STATUS.HARVESTED]:  "badge-green",
  [ORDER_STATUS.READY]:      "badge-blue",
  [ORDER_STATUS.IN_TRANSIT]: "badge-amber",
  [ORDER_STATUS.DELIVERED]:  "badge-green",
  [ORDER_STATUS.CANCELLED]:  "badge-rose",
};

export default function StatusBadge({ status }) {
  const cls = TONE[status] || "badge-gray";
  return <span className={cls}>{ORDER_STATUS_LABEL[status] || status}</span>;
}
