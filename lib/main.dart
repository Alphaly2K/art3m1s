import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'services/logger.dart';
import 'screens/library_screen.dart';
import 'services/storage_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await StorageService.ensureInitialized();
  Log.info('Art3m1s 启动');
  runApp(const ProviderScope(child: Art3m1sApp()));
}

class Art3m1sApp extends StatelessWidget {
  const Art3m1sApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Art3m1s',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      home: const LibraryScreen(),
    );
  }
}
