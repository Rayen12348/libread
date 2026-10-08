import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_shell.dart';
import 'store.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  runApp(const LibreadApp());
}

class LibreadApp extends StatefulWidget {
  const LibreadApp({super.key});

  @override
  State<LibreadApp> createState() => _LibreadAppState();
}

class _LibreadAppState extends State<LibreadApp> {
  final _store = LibraryStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChanged);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // "Storm" and "Day" are complete themes in their own right, so each choice
    // pins both slots except when the user asks to follow the system.
    final (ThemeData light, ThemeData dark, ThemeMode mode) = switch (_store.theme) {
      AppTheme.night => (AppThemes.night(), AppThemes.night(), ThemeMode.dark),
      AppTheme.storm => (AppThemes.storm(), AppThemes.storm(), ThemeMode.dark),
      AppTheme.day => (AppThemes.day(), AppThemes.day(), ThemeMode.light),
      AppTheme.system => (AppThemes.day(), AppThemes.night(), ThemeMode.system),
    };

    return MaterialApp(
      title: 'Libread',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      builder: (context, child) {
        final theme = Theme.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppThemes.overlayFor(theme),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HomeShell(),
    );
  }
}
