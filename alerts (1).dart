import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({
    super.key,
    required this.clinicianName,
    required this.apiService,
    required this.socketService,
  });

  final String clinicianName;
  final ApiService apiService;
  final SocketService socketService;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<AlertRecord>>(
        stream: socketService.watchAlerts(),
        builder: (context, snapshot) {
          final alerts = snapshot.data ?? const [];
          final criticalCount = alerts
              .where((alert) => alert.riskLevel == 'CRITICAL')
              .length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(
                'Live alerts',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF11212D),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hello $clinicianName. The feed below is refreshed automatically and highlights the patients who need attention first.',
                style: const TextStyle(color: Color(0xFF546674), height: 1.45),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      const Color(0xFFDF6D57).withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _AlertSummary(
                        title: 'Critical now',
                        value: '$criticalCount',
                        color: const Color(0xFFDF6D57),
                      ),
                    ),
                    Expanded(
                      child: _AlertSummary(
                        title: 'Feed mode',
                        value: apiService.demoMode ? 'Demo' : 'Live',
                        color: const Color(0xFF2C8C85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  alerts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (alerts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Text(
                    'No active alerts. The ICU looks stable right now.',
                    style: TextStyle(
                      color: Color(0xFF465763),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                ...alerts.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _AlertCard(alert: alert),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AlertSummary extends StatelessWidget {
  const _AlertSummary({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF556674),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 30,
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final accent = alert.riskLevel == 'CRITICAL'
        ? const Color(0xFFDF6D57)
        : const Color(0xFFF1B24A);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${alert.riskLevel} ${(alert.riskScore * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              Text(
                alert.patientId,
                style: const TextStyle(
                  color: Color(0xFF11212D),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            alert.doctorMessage,
            style: const TextStyle(color: Color(0xFF465763), height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            alert.timestamp,
            style: const TextStyle(
              color: Color(0xFF7A8993),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
