import 'package:flutter/material.dart';

import 'screens/dashboard.dart';
import 'screens/login.dart';
import 'services/api_service.dart';
import 'theme/aegis_brand.dart';

void main() {
  runApp(const RiskAssistantApp());
}

class RiskAssistantApp extends StatelessWidget {
  const RiskAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AegisBrand.appName,
      debugShowCheckedModeBanner: false,
      theme: AegisBrand.theme(),
      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  String? _clinicianName;

  @override
  Widget build(BuildContext context) {
    if (_clinicianName == null) {
      return LoginScreen(
        onLogin: (name) => setState(() => _clinicianName = name.trim()),
      );
    }

    return ClinicianHome(
      clinicianName: _clinicianName!,
      onLogout: () => setState(() => _clinicianName = null),
    );
  }
}

class ClinicianHome extends StatefulWidget {
  const ClinicianHome({
    super.key,
    required this.clinicianName,
    required this.onLogout,
  });

  final String clinicianName;
  final VoidCallback onLogout;

  @override
  State<ClinicianHome> createState() => _ClinicianHomeState();
}

class _ClinicianHomeState extends State<ClinicianHome> {
  late final ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DashboardScreen(
      clinicianName: widget.clinicianName,
      apiService: _apiService,
      onLogout: widget.onLogout,
    );
  }
}
