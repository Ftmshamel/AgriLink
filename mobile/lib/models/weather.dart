/// Weather models backing the Open-Meteo integration.
///
/// AgriLink is a farm-to-table platform, so weather is not decoration: rain
/// decides when a farmer should harvest and whether a rider can safely carry a
/// pooled load. Everything here is parsed from the JSON documented in
/// `docs/API_INTEGRATION.md`.
library;

/// A place returned by the Open-Meteo geocoding endpoint.
class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.region,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String region;
  final String country;
  final double latitude;
  final double longitude;

  /// "Cabanatuan, Nueva Ecija" — the region is dropped when it repeats the name.
  String get label => region.isEmpty || region == name
      ? name
      : '$name, $region';

  factory GeoPlace.fromJson(Map<String, dynamic> json) => GeoPlace(
        name: '${json['name'] ?? ''}',
        region: '${json['admin1'] ?? ''}',
        country: '${json['country'] ?? ''}',
        latitude: _toDouble(json['latitude']),
        longitude: _toDouble(json['longitude']),
      );
}

/// One day of the outlook strip.
class DailyForecast {
  const DailyForecast({
    required this.date,
    required this.code,
    required this.maxTemperature,
    required this.minTemperature,
    required this.rainChance,
    required this.rainfallMm,
  });

  final DateTime date;
  final int code;
  final double maxTemperature;
  final double minTemperature;

  /// Percentage chance of precipitation.
  final int rainChance;
  final double rainfallMm;

  WeatherCondition get condition => WeatherCondition.fromCode(code);

  /// "Today", then short weekday names.
  String label(DateTime today) {
    final sameDay = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    if (sameDay) return 'Today';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[date.weekday - 1];
  }
}

/// Current conditions plus a short outlook for one pinned location.
class FarmWeather {
  const FarmWeather({
    required this.placeName,
    required this.latitude,
    required this.longitude,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windKph,
    required this.rainfallMm,
    required this.code,
    required this.observedAt,
    required this.daily,
  });

  final String placeName;
  final double latitude;
  final double longitude;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windKph;
  final double rainfallMm;
  final int code;
  final DateTime observedAt;
  final List<DailyForecast> daily;

  WeatherCondition get condition => WeatherCondition.fromCode(code);

  DailyForecast? get today => daily.isEmpty ? null : daily.first;

  /// Highest rain chance across the next three days, used for the advisories.
  int get rainChanceSoon => daily
      .take(3)
      .fold<int>(0, (worst, day) => day.rainChance > worst ? day.rainChance : worst);

  /// What the weather means for a farmer deciding when to pick and pack.
  String get harvestAdvice {
    if (condition.severe) {
      return 'Storm conditions. Hold off on harvesting and secure your stored produce.';
    }
    if (condition.raining) {
      return 'Raining now. Harvest after it clears so produce is not packed wet.';
    }
    if (rainChanceSoon >= 60) {
      return 'Rain likely within three days. Harvest and list your crops early.';
    }
    if (temperature >= 34) {
      return 'Very hot. Harvest in the early morning and keep produce shaded.';
    }
    return 'Good harvest window. Clear enough to pick, pack, and list today.';
  }

  /// What it means for a rider carrying a pooled load.
  String get deliveryAdvice {
    if (condition.severe) {
      return 'Storm conditions. Avoid accepting trips until this passes.';
    }
    if (condition.raining) {
      return 'Wet roads. Cover the load and allow extra time on your route.';
    }
    if (rainChanceSoon >= 60) {
      return 'Rain expected soon. Bring a tarpaulin for the pooled orders.';
    }
    return 'Clear roads. Good conditions for pooled deliveries.';
  }

  factory FarmWeather.fromJson(
    Map<String, dynamic> json, {
    required String placeName,
  }) {
    final current = json['current'] as Map<String, dynamic>? ?? const {};
    final daily = json['daily'] as Map<String, dynamic>? ?? const {};
    final days = (daily['time'] as List<dynamic>? ?? const []);

    return FarmWeather(
      placeName: placeName,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      temperature: _toDouble(current['temperature_2m']),
      feelsLike: _toDouble(current['apparent_temperature']),
      humidity: _toInt(current['relative_humidity_2m']),
      windKph: _toDouble(current['wind_speed_10m']),
      rainfallMm: _toDouble(current['precipitation']),
      code: _toInt(current['weather_code']),
      observedAt:
          DateTime.tryParse('${current['time'] ?? ''}') ?? DateTime.now(),
      daily: [
        for (var i = 0; i < days.length; i++)
          DailyForecast(
            date: DateTime.tryParse('${days[i]}') ?? DateTime.now(),
            code: _toInt(_at(daily['weather_code'], i)),
            maxTemperature: _toDouble(_at(daily['temperature_2m_max'], i)),
            minTemperature: _toDouble(_at(daily['temperature_2m_min'], i)),
            rainChance: _toInt(_at(daily['precipitation_probability_max'], i)),
            rainfallMm: _toDouble(_at(daily['precipitation_sum'], i)),
          ),
      ],
    );
  }
}

/// A WMO weather code turned into something a farmer or rider can read.
class WeatherCondition {
  const WeatherCondition({
    required this.label,
    required this.emoji,
    this.raining = false,
    this.severe = false,
  });

  final String label;
  final String emoji;
  final bool raining;
  final bool severe;

  /// Open-Meteo reports WMO codes; this collapses them into the handful of
  /// outcomes that matter in the Philippines.
  static WeatherCondition fromCode(int code) => switch (code) {
        0 => const WeatherCondition(label: 'Clear sky', emoji: '☀️'),
        1 => const WeatherCondition(label: 'Mainly clear', emoji: '🌤️'),
        2 => const WeatherCondition(label: 'Partly cloudy', emoji: '⛅'),
        3 => const WeatherCondition(label: 'Overcast', emoji: '☁️'),
        45 || 48 => const WeatherCondition(label: 'Foggy', emoji: '🌫️'),
        51 || 53 || 55 => const WeatherCondition(
            label: 'Drizzle',
            emoji: '🌦️',
            raining: true,
          ),
        61 || 63 => const WeatherCondition(
            label: 'Rain',
            emoji: '🌧️',
            raining: true,
          ),
        65 => const WeatherCondition(
            label: 'Heavy rain',
            emoji: '🌧️',
            raining: true,
            severe: true,
          ),
        80 || 81 => const WeatherCondition(
            label: 'Rain showers',
            emoji: '🌦️',
            raining: true,
          ),
        82 => const WeatherCondition(
            label: 'Violent showers',
            emoji: '⛈️',
            raining: true,
            severe: true,
          ),
        95 => const WeatherCondition(
            label: 'Thunderstorm',
            emoji: '⛈️',
            raining: true,
            severe: true,
          ),
        96 || 99 => const WeatherCondition(
            label: 'Thunderstorm with hail',
            emoji: '⛈️',
            raining: true,
            severe: true,
          ),
        _ => const WeatherCondition(label: 'Unknown', emoji: '🌡️'),
      };
}

dynamic _at(dynamic list, int index) =>
    list is List && index < list.length ? list[index] : null;

double _toDouble(dynamic value) => switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value) ?? 0,
      _ => 0,
    };

int _toInt(dynamic value) => switch (value) {
      num() => value.round(),
      String() => int.tryParse(value) ?? 0,
      _ => 0,
    };
