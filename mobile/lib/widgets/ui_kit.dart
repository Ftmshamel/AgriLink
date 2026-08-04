import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
        child: Column(
          children: [
            Icon(icon, size: 48, color: green),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.45)),
          ],
        ),
      ),
    );
  }
}
class MetricCard extends StatelessWidget {
  const MetricCard(
      {super.key,
       required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: green),
          const SizedBox(height: 12),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

class ActionCard extends StatelessWidget {
  const ActionCard(
      {super.key,
       required this.icon,
      required this.title,
      required this.subtitle,
      required this.badge});
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: lightGreen, child: Icon(icon, color: green)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: Text(badge,
            style: const TextStyle(
                color: orange, fontSize: 10, fontWeight: FontWeight.w900)),
      ),
    );
  }
}
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: green,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: muted, height: 1.4)),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    required this.action,
    this.onAction,
  });
  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        InkWell(
          onTap: onAction,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              action,
              style:
                  const TextStyle(color: green, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.icon,
    required this.text,
    this.color = muted,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip({
    super.key,
    required this.emoji,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? lightGreen : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? green : const Color(0xFFE6EAE2),
            ),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? darkGreen : ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LineItem extends StatelessWidget {
  const LineItem({
    super.key,
    required this.emoji,
    required this.name,
    required this.detail,
    required this.price,
  });
  final String emoji;
  final String name;
  final String detail;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: lightGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 27)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(detail, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        Text(price, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class MoneyRow extends StatelessWidget {
  const MoneyRow({super.key, required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? ink : muted,
                fontWeight: strong ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 19 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class PastOrderCard extends StatelessWidget {
  const PastOrderCard({
    super.key,
    required this.id,
    required this.name,
    required this.detail,
    required this.price,
    required this.emoji,
    this.statusText = 'DELIVERED',
    this.statusIcon = Icons.check_circle,
    this.statusColor = green,
    this.onTap,
  });
  final String id;
  final String name;
  final String detail;
  final String price;
  final String emoji;
  final String statusText;
  final IconData statusIcon;
  final Color statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LineItem(emoji: emoji, name: name, detail: detail, price: price),
              const Divider(height: 26),
              Row(
                children: [
                  Pill(
                    icon: statusIcon,
                    text: statusText,
                    color: statusColor,
                  ),
                  const Spacer(),
                  Text(id, style: const TextStyle(color: muted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.title,
    required this.subtitle,
    required this.done,
    this.active = false,
    this.last = false,
  });
  final String title;
  final String subtitle;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: active ? 18 : 14,
                  height: active ? 18 : 14,
                  decoration: BoxDecoration(
                    color: done ? green : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: done ? green : Colors.grey),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? green : const Color(0xFFD0D5DD),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: active ? green : muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: lightGreen,
          child: Icon(icon, color: green),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: tint,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class RouteRow extends StatelessWidget {
  const RouteRow({
    super.key,
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class RouteLine extends StatelessWidget {
  const RouteLine({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      margin: const EdgeInsets.only(left: 6),
      alignment: Alignment.centerLeft,
      child: Container(width: 2, color: const Color(0xFFD0D5DD)),
    );
  }
}

class MiniOpportunity extends StatelessWidget {
  const MiniOpportunity({
    super.key,
    required this.area,
    required this.orders,
    required this.distance,
    required this.pay,
    this.onTap,
  });
  final String area;
  final String orders;
  final String distance;
  final String pay;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFFFF1DD),
                child: Icon(Icons.route, color: orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(area,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      '$orders • $distance',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                pay,
                style:
                    const TextStyle(color: green, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? green : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? green : const Color(0xFFD0D5DD)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class PoolCard extends StatelessWidget {
  const PoolCard({
    super.key,
    required this.route,
    required this.badge,
    required this.orders,
    required this.farms,
    required this.distance,
    required this.pay,
    required this.capacity,
    required this.onTap,
  });
  final String route;
  final String badge;
  final int orders;
  final int farms;
  final String distance;
  final String pay;
  final double capacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Pill(icon: Icons.auto_awesome, text: badge, color: orange),
                  const Spacer(),
                  Text(
                    pay,
                    style: const TextStyle(
                      color: green,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                route,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                '$orders orders • $farms farms • $distance',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Vehicle capacity',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${(capacity * 100).round()}%',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: capacity,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripHistoryTile extends StatelessWidget {
  const TripHistoryTile({
    super.key,
    required this.route,
    required this.date,
    required this.orders,
    required this.amount,
  });
  final String route;
  final String date;
  final String orders;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(
          backgroundColor: lightGreen,
          child: Icon(Icons.check, color: green),
        ),
        title: Text(route, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('$date\n$orders'),
        isThreeLine: true,
        trailing: Text(
          amount,
          style: const TextStyle(color: green, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
