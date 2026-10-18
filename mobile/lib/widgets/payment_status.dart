import 'package:flutter/material.dart';

import '../models/agri_models.dart';
import '../services/geo.dart';
import '../utils/app_colors.dart';

/// Every order is paid before it is created, so the buyer, farm and rider
/// should all see that plainly instead of guessing from a reference number.
enum PaymentState { paid, refunded, checking }

PaymentState paymentStateOf(AgriOrder order) {
  if (order.isRefunded) return PaymentState.refunded;
  if (order.isPaymentSecured) return PaymentState.paid;
  return PaymentState.checking;
}

/// The short label used on order cards: "PAID", "REFUNDED", or "CHECKING".
String paymentBadgeText(AgriOrder order) => switch (paymentStateOf(order)) {
      PaymentState.paid => 'PAID',
      PaymentState.refunded => 'REFUNDED',
      PaymentState.checking => 'CHECKING PAYMENT',
    };

Color paymentColor(AgriOrder order) => switch (paymentStateOf(order)) {
      PaymentState.paid => green,
      PaymentState.refunded => muted,
      PaymentState.checking => orange,
    };

IconData paymentIcon(AgriOrder order) => switch (paymentStateOf(order)) {
      PaymentState.paid => Icons.verified,
      PaymentState.refunded => Icons.replay,
      PaymentState.checking => Icons.hourglass_top,
    };

/// A line under an order's total: whether it is paid, how, and the reference.
class PaymentStatusLine extends StatelessWidget {
  const PaymentStatusLine({super.key, required this.order});

  final AgriOrder order;

  @override
  Widget build(BuildContext context) {
    final state = paymentStateOf(order);
    final color = paymentColor(order);
    final title = switch (state) {
      PaymentState.paid => 'Fully paid',
      PaymentState.refunded =>
        'Refunded ${formatPeso(order.refundedAmount)} to the wallet',
      PaymentState.checking => 'Payment sent, waiting for the farm to check it',
    };
    final how = [
      if (order.paymentMethod.isNotEmpty) order.paymentMethod,
      if (order.paymentReference.isNotEmpty) order.paymentReference,
    ].join(' • ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(paymentIcon(order), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                if (how.isNotEmpty)
                  Text(how, style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
