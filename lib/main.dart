import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'engine/calc.dart';
import 'engine/models.dart';
import 'services/session.dart';
import 'services/storage.dart';
import 'ui/activity_screen.dart';
import 'ui/common.dart';
import 'ui/history_screen.dart';
import 'ui/profile_screen.dart';
import 'ui/result_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko');
  await Session.instance.init();
  runApp(const WorkoutApp());
}

class WorkoutApp extends StatelessWidget {
  const WorkoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '운동 기록',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.black,
            primary: Colors.black,
            surface: Colors.white),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            surfaceTintColor: Colors.white,
            elevation: 0),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _historyKey = GlobalKey<HistoryScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
  }

  /// 기록 도중 앱이 꺼졌으면 백업에서 복구
  Future<void> _checkRecovery() async {
    final log = await Storage.liveRead();
    if (log == null || !mounted) return;
    final w = Session.replay(log);
    if (w == null || w.distance < 10) {
      await Storage.liveDiscard();
      return;
    }
    final save = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('끝나지 않은 운동 기록'),
        content: Text(
            '${dateLabel(w.start)} ${timeLabel(w.start)}에 시작한 ${w.type.label} 기록이 있습니다.\n'
            '${km(w.distance)} km · ${formatDuration(w.movingSec)}\n\n저장할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('버리기')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ink),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('저장')),
        ],
      ),
    );
    await Storage.liveDiscard();
    if (save == true) {
      await Storage.saveWorkout(w);
      _historyKey.currentState?.reload();
      if (mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ResultScreen(workout: w)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        const ActivityScreen(),
        HistoryScreen(key: _historyKey),
        const ProfileScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEDEDED),
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 1) _historyKey.currentState?.reload();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: '액티비티'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: '기록'),
          NavigationDestination(
              icon: Icon(Icons.person_outline), label: '프로필'),
        ],
      ),
    );
  }
}
