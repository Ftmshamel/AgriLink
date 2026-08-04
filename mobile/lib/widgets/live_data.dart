import 'dart:async';

import 'package:flutter/material.dart';

import '../services/session.dart';
import '../utils/app_colors.dart';
import 'ui_kit.dart';

/// Tells descendants whether their tab is the one on screen.
///
/// Role shells keep every tab alive inside an [IndexedStack], so without this
/// each tab would keep polling Firestore (and GPS) in the background.
class ActiveTab extends InheritedWidget {
  const ActiveTab({
    super.key,
    required this.isActive,
    required super.child,
  });

  final bool isActive;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.isActive ?? true;

  @override
  bool updateShouldNotify(ActiveTab oldWidget) =>
      oldWidget.isActive != isActive;
}

/// [IndexedStack] that marks only the visible child as active.
class LiveIndexedStack extends StatelessWidget {
  const LiveIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < children.length; i++)
          ActiveTab(isActive: i == index, child: children[i]),
      ],
    );
  }
}

/// Loads data, keeps it fresh, and rebuilds when anything in the app writes.
///
/// Screens use this instead of a bare `FutureBuilder` so that an action taken
/// by one role (a farmer packing an order) shows up for the others without
/// anybody pulling to refresh.
class LiveBuilder<T> extends StatefulWidget {
  const LiveBuilder({
    super.key,
    required this.session,
    required this.load,
    required this.builder,
    this.interval = const Duration(seconds: 12),
    this.placeholder,
  });

  final AppSession session;
  final Future<T> Function() load;
  final Widget Function(BuildContext context, LiveData<T> data) builder;

  /// How often to poll while the screen is visible.
  final Duration interval;

  /// Shown on the very first load, before any data exists.
  final Widget? placeholder;

  @override
  State<LiveBuilder<T>> createState() => _LiveBuilderState<T>();
}

/// The snapshot handed to a [LiveBuilder] child.
class LiveData<T> {
  const LiveData({
    required this.value,
    required this.loading,
    required this.error,
    required this.reload,
  });

  final T? value;
  final bool loading;
  final Object? error;
  final Future<void> Function() reload;

  bool get hasValue => value != null;
  String get errorMessage =>
      '$error'.replaceFirst('Exception: ', '').trim();
}

class _LiveBuilderState<T> extends State<LiveBuilder<T>> {
  T? _value;
  Object? _error;
  bool _loading = true;
  Timer? _timer;
  int _seenRevision = -1;
  int _requestId = 0;
  bool _active = true;
  bool _loadedOnce = false;
  bool _staleWhileHidden = false;

  @override
  void initState() {
    super.initState();
    _seenRevision = widget.session.revision;
    widget.session.addListener(_onSessionChanged);
    _timer = Timer.periodic(widget.interval, (_) {
      if (_active) _fetch(quiet: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = ActiveTab.of(context);
    if (!_active) return;
    // A tab loads the first time it is actually shown, then catches up on
    // anything that changed while it sat in the background.
    if (!_loadedOnce) {
      _loadedOnce = true;
      _fetch();
    } else if (_staleWhileHidden) {
      _staleWhileHidden = false;
      _fetch(quiet: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted || widget.session.revision == _seenRevision) return;
    _seenRevision = widget.session.revision;
    if (!_active) {
      _staleWhileHidden = true;
      return;
    }
    _fetch(quiet: true);
  }

  Future<void> _fetch({bool quiet = false}) async {
    final requestId = ++_requestId;
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      final result = await widget.load();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _value = result;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_value == null && _loading) {
      return widget.placeholder ??
          const Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(),
            ),
          );
    }
    return widget.builder(
      context,
      LiveData<T>(
        value: _value,
        loading: _loading,
        error: _error,
        reload: () => _fetch(),
      ),
    );
  }
}

/// Standard "we could not reach Firestore" card with a retry action.
class LiveErrorCard extends StatelessWidget {
  const LiveErrorCard({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: Column(
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: orange),
            const SizedBox(height: 12),
            const Text(
              'Unable to load live data',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message.isEmpty ? 'Check your internet connection.' : message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps a live list page with pull-to-refresh and a thin "syncing" bar.
class LiveRefreshView extends StatelessWidget {
  const LiveRefreshView({
    super.key,
    required this.onRefresh,
    required this.loading,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 2,
          child: loading
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: RefreshIndicator(onRefresh: onRefresh, child: child),
        ),
      ],
    );
  }
}

/// Small helper used by empty live lists so every module reads the same way.
class LiveEmpty extends StatelessWidget {
  const LiveEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) =>
      EmptyState(icon: icon, title: title, message: message);
}
