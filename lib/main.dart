import 'package:flutter/material.dart';

import 'app/app.dart';
import 'shared/state/app_services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(BiffyApp(services: AppServices.demo()));
}
