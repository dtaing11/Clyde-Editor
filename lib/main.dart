import 'package:flutter/widgets.dart';
import 'package:rive_native/rive_native.dart' as rive;

import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await rive.RiveNative.init();
  runApp(const RiveEditorApp());
}
