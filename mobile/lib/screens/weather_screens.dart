import 'dart:async';

import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../utils/app_colors.dart';
import '../widgets/ui_kit.dart';
import '../widgets/weather_card.dart';

/// Full outlook for the pinned location, plus a search over any other town.
///
/// The search calls the Open-Meteo geocoding endpoint, then feeds the chosen
/// coordinates back into the forecast endpoint — so a farmer can check the
/// weather over a buyer's municipality before committing to a delivery date.
class WeatherPage extends StatefulWidget {
  const WeatherPage({
    super.key,
    required this.weather,
    required this.audience,
  });

  final FarmWeather weather;
  final WeatherAudience audience;

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  late FarmWeather _weather = widget.weather;
  List<GeoPlace> _results = const [];
  bool _searching = false;
  bool _loadingPlace = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Waits for a pause in typing so one lookup does not fire per keystroke.
  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    try {
      final places = await weatherService.searchPlaces(query);
      if (!mounted) return;
      setState(() {
        _results = places;
        _searching = false;
        _error = places.isEmpty ? 'No town matched “${query.trim()}”.' : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = const [];
        _error = '$error';
      });
    }
  }

  Future<void> _openPlace(GeoPlace place) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loadingPlace = true;
      _error = null;
    });
    try {
      final weather = await weatherService.loadForecast(
        latitude: place.latitude,
        longitude: place.longitude,
        placeName: place.label,
      );
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _results = const [];
        _search.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loadingPlace = false);
    }
  }

  Future<void> _refresh() async {
    weatherService.clearCache();
    try {
      final weather = await weatherService.loadForecast(
        latitude: _weather.latitude,
        longitude: _weather.longitude,
        placeName: _weather.placeName,
      );
      if (mounted) setState(() => _weather = weather);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weather outlook')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _search,
              onChanged: _onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search a town, e.g. Cabanatuan',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              _onQueryChanged('');
                            },
                            icon: const Icon(Icons.close),
                          ),
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFFE6EAE2), width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: green, width: 2),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 17, color: orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: muted, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final place in _results)
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: lightGreen,
                          child: Icon(Icons.place_outlined, color: green),
                        ),
                        title: Text(
                          place.label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(place.country),
                        onTap: () => _openPlace(place),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (_loadingPlace)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              WeatherCard(
                weather: _weather,
                audience: widget.audience,
                showForecastLink: false,
                onRefresh: _refresh,
              ),
              const SizedBox(height: 22),
              const SectionTitle(title: '7-day outlook', action: ''),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      for (final day in _weather.daily) _ForecastRow(day: day),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Weather data by Open-Meteo.com',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ForecastRow extends StatelessWidget {
  const _ForecastRow({required this.day});

  final DailyForecast day;

  @override
  Widget build(BuildContext context) {
    final wet = day.rainChance >= 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              day.label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
          Text(day.condition.emoji, style: const TextStyle(fontSize: 21)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.condition.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${day.rainChance}% rain • ${day.rainfallMm.toStringAsFixed(1)} mm',
                  style: TextStyle(
                    color: wet ? orange : muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${day.maxTemperature.round()}°',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 6),
          Text(
            '${day.minTemperature.round()}°',
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}
