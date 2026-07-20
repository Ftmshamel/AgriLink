export function getPlantingAvailability(planting, orders = [], buyerId = null) {
  const stockKg = Number(
    planting?.preOrderStockKg ?? planting?.expectedYieldKg ?? 0,
  );
  const activeOrders = orders.filter(
    (order) => order.plantingId === planting?.id && order.status !== "cancelled",
  );
  const reservedKg = activeOrders.reduce(
    (sum, order) => sum + Number(order.quantityKg || 0),
    0,
  );
  const availableKg = Math.max(0, stockKg - reservedKg);

  const allowBulk = planting?.allowBulkPreorder !== false;
  if (allowBulk || !buyerId) {
    return {
      stockKg,
      reservedKg,
      availableKg,
      maxForBuyerKg: availableKg,
      soldOut: availableKg <= 0,
    };
  }

  const limitPerAccount = Number(planting.maxPerAccountKg || 0);
  const alreadyOrderedByBuyer = activeOrders
    .filter((order) => order.buyerId === buyerId)
    .reduce((sum, order) => sum + Number(order.quantityKg || 0), 0);
  const buyerRemainingKg = Math.max(0, limitPerAccount - alreadyOrderedByBuyer);

  return {
    stockKg,
    reservedKg,
    availableKg,
    maxForBuyerKg: Math.max(0, Math.min(availableKg, buyerRemainingKg)),
    soldOut: availableKg <= 0,
  };
}
