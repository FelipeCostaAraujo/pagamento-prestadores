import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/home_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

void main() => runApp(const DiariasApp());

class DiariasApp extends StatefulWidget {
  const DiariasApp({super.key});

  @override
  State<DiariasApp> createState() => _DiariasAppState();
}

class _DiariasAppState extends State<DiariasApp> {
  late final ApiClient _api;
  late final AppState _state;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _state = AppState(api: _api);
    _state.load();
  }

  @override
  void dispose() {
    _state.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diárias',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: AppScope(notifier: _state, child: const HomeScreen()),
    );
  }
}

/// Makes the single [AppState] available to the widget tree and rebuilds
/// dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState super.notifier,
    required super.child,
  });

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'No AppScope found in context');
    return scope!.notifier!;
  }
}
