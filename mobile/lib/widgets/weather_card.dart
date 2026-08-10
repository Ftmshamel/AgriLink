import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../screens/weather_screens.dart';
import '../services/session.dart';
import '../services/weather_service.dart';
import '../utils/app_colors.dart';
import 'live_data.dart';

/// Who is reading the forecast, which decides the advisory line.
enum WeatherAudience { farmer, rider }

final weatherService = WeatherService();

/// Default pin used when an account never finished pinning its location:
/// Cabanatuan, in the Nueva Ecija rice belt AgriLink serves.
const _fallbackLatitude = 15.4865;
const _fallbackLongitude = 120.9734;

/// Live weather for the signed-in account's pinned location.
///
/// Dropped into the farmer and rider dashboards. It reuses [LiveBuilder], so
/// the data refreshes on its own timer and on pull-to-refresh without the
/// screen being rebuilt from scratch.
class WeatherPanel extends StatelessWidget {
  const WeatherPanel({
    super.key,
    required this.session,
    required this.audience,
  });

  final AppSession session;
  final WeatherAudience audience;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final latitude = user.latitude ?? _fallbackLatitude;
    final longitude = user.longitude ?? _fallbackLongitude;
    final place = user.location.isEmpty
        ? 'Cabanatuan, Nueva Ecija'
        : user.location.split(',').take(2).join(',').trim();

    return LiveBuilder<FarmWeather>(
      session: session,
      // Conditions move slowly, so this polls far less often than order data.
      interval: const Duration(minutes: 10),
      placeholder: const _WeatherSkeleton(),
      load: () => weatherService.loadForecast(
        latitude: latitude,
        longitude: longitude,
        placeName: place,
      ),
      builder: (context, data) {
        final weather = data.value;
        if (weather == null) {
          return _WeatherError(
            message: data.errorMessage,
            onRetry: data.reload,
          );
        }
        return WeatherCard(
          weather: weather,
          audience: audience,
          refreshing: data.loading,
          onRefresh: () {
            // Tapping refresh should mean "go and ask", not "re-read the cache".
            weatherService.clearCache();
            data.reload();
          },
        );
      },
    );
  }
}

/// The card itself — pure presentation so it can be reused and tested.
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    required this.weather,
    required this.audience,
    this.refreshing = false,
    this.onRefresh,
    this.showForecastLink = true,
  });

  final FarmWeather weather;
  final WeatherAudience audience;
  final bool refreshing;
  final VoidCallback? onRefresh;
  final bool showForecastLink;

  String get _advice => audience == WeatherAudience.farmer
      ? weather.harvestAdvice
      : weather.deliveryAdvice;

  @override
  Widget build(BuildContext context) {
    final condition = weather.condition;
    final alert = condition.severe || weather.rainChanceSoon >= 60;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(condition.emoji, style: const TextStyle(fontSize: 42)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${weather.temperature.round()}°C',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      Text(
                        condition.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRefresh != null)
                  IconButton(
                    onPressed: refreshing ? null : onRefresh,
                    tooltip: 'Refresh weather',
                    icon: refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, color: green),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 15, color: muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    weather.placeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _WeatherStat(
                    icon: Icons.water_drop_outlined,
                    label: 'Humidity',
                    value: '${weather.humidity}%',
                  ),
                ),
                Expanded(
                  child: _WeatherStat(
                    icon: Icons.air,
                    label: 'Wind',
                    value: '${weather.windKph.round()} km/h',
                  ),
                ),
                Expanded(
                  child: _WeatherStat(
                    icon: Icons.umbrella_outlined,
                    label: 'Rain',
                    value: '${weather.rainChanceSoon}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: alert ? const Color(0xFFFFF7E8) : lightGreen,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: alert ? const Color(0xFFFFD99A) : const Color(0xFFCFE5C5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    alert ? Icons.warning_amber_rounded : Icons.eco_outlined,
                    size: 19,
                    color: alert ? orange : green,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _advice,
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            if (weather.daily.length > 1) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final day in weather.daily.take(4))
                    Expanded(child: _DayChip(day: day)),
                ],
              ),
            ],
            if (showForecastLink) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WeatherPage(
                        weather: weather,
                        audience: audience,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_outlined, size: 17),
                  label: const Text('7-day outlook & other towns'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WeatherStat extends StatelessWidget {
  const _WeatherStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 19, color: green),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final DailyForecast day;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          day.label(DateTime.now()),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: muted,
          ),
        ),
        const SizedBox(height: 5),
        Text(day.condition.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 5),
        Text(
          '${day.maxTemperature.round()}°',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
        Text(
          '${day.rainChance}%',
          style: const TextStyle(color: muted, fontSize: 10),
        ),
      ],
    );
  }
}

class _WeatherSkeleton extends StatelessWidget {
  const _WeatherSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 34),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 14),
            Text(
              'Checking today’s weather…',
              style: TextStyle(color: muted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the API is unreachable, rate limited, or returns something the
/// app cannot read — the forecast is a bonus, so the dashboard stays usable.
class _WeatherError extends StatelessWidget {
  const _WeatherError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: orange, size: 26),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Weather unavailable',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.isEmpty
                        ? 'Could not reach the weather service.'
                        : message,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onRetry,
              tooltip: 'Try again',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}
