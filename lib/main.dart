import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'screens/camera_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final state = await AppState.load();
  runApp(GpsCameraApp(state: state));
}

class GpsCameraApp extends StatelessWidget {
  const GpsCameraApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GPS Camera',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: CameraScreen(state: state),
      );
}
