import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_scope.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppScope(child: App()));
}
