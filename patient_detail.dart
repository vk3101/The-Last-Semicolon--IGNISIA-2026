import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/clinical_insights.dart';
import '../widgets/chart_widget.dart';

class PatientDetailScreen extends StatefulWidget {
  const PatientDetailScreen({
    super.key,
    required this.patient,
    required this.apiService,
  });

  final PatientReading patient;
  final ApiService apiService;

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  static const Duration _refreshInterval = Duration(seconds: 4);

  late PatientReading _patient;
  bool _refreshing = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _patient = widget.patient;
    _autoRefreshTimer = Timer.periodic(_refreshInterval, (_) {
      _refreshPatient();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPatient({bool forceAdvance = false}) async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    final patients = await widget.apiService.fetchDashboardPatients(
      forceAdvance: forceAdvance,
    );
    if (!mounted) {
      return;
    }
    final refreshedPatient = patients.firstWhere(
      (patient) => patient.id == _patient.id,
      orElse: () => _patient,
    );

    setState(() {
      _patient = refreshedPatient;
      _refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prediction = _patient.prediction;
    final vitalSpecs = buildVitalTileSpecs(_patient);
    final patternInsights = buildPatternInsights(_patient);
    final advancedMetrics = buildAdvancedMetrics(_patient);
    final riskLevel = prediction?.riskLevel ?? 'SAFE';
    final accent = switch (riskLevel) {
      'CRITICAL' => const Color(0xFFDF6D57),
      'WARNING' => const Color(0xFFF1B24A),
      _ => const Color(0xFF2C8C85),
    };

    return Scaffold(
      appBar: AppBar(title: Text(_patient.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                colors: [Colors.white, accent.withValues(alpha: 0.14)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_patient.bedLabel} • ${_patient.diagnosis}',
                  style: const TextStyle(
                    color: Color(0xFF5B6B76),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        riskLevel,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              color: const Color(0xFF11212D),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _refreshing
                          ? null
                          : () => _refreshPatient(forceAdvance: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF11212D),
                        foregroundColor: Colors.white,
                      ),
                      icon: _refreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Advance live feed'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Live vitals refresh every 4 seconds. Each new point represents 30 minutes of ICU trend history. Last update: ${_formatTimestamp(_patient.lastUpdated)}',
                  style: const TextStyle(
                    color: Color(0xFF5B6B76),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  prediction?.doctorMessage ??
                      'No AI assessment available yet.',
                  style: const TextStyle(
                    color: Color(0xFF3F515D),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: vitalSpecs
                .map((spec) => _VitalParameterCard(spec: spec))
                .toList(),
          ),
          const SizedBox(height: 18),
          _PatternInsightsCard(insights: patternInsights),
          const SizedBox(height: 16),
          _AdvancedMetricsCard(metrics: advancedMetrics),
          const SizedBox(height: 16),
          VitalChartCard(
            title: 'Heart Rate Trend',
            subtitle:
                '30-minute bedside snapshots help reveal evolving tachycardia before overt instability.',
            values: _patient.hrTrend,
            lineColor: const Color(0xFFDF6D57),
            unitLabel: 'bpm',
          ),
          const SizedBox(height: 16),
          VitalChartCard(
            title: 'Blood Pressure Trend',
            subtitle:
                'Systolic blood pressure is sampled in 30-minute windows to expose perfusion drift.',
            values: _patient.bpTrend,
            lineColor: const Color(0xFF11212D),
            unitLabel: 'mmHg',
          ),
          const SizedBox(height: 16),
          VitalChartCard(
            title: 'Temperature Trend',
            subtitle:
                'Thermal drift over 30-minute intervals helps catch inflammatory progression.',
            values: _patient.tempTrend,
            lineColor: const Color(0xFFF1B24A),
            unitLabel: 'C',
          ),
          const SizedBox(height: 16),
          VitalChartCard(
            title: 'Oxygen Saturation Trend',
            subtitle:
                'Small SpO2 fluctuations every 30 minutes can matter in critically ill patients.',
            values: _patient.spo2Trend,
            lineColor: const Color(0xFF2C8C85),
            unitLabel: '%',
          ),
          const SizedBox(height: 16),
          VitalChartCard(
            title: 'GCS Trend',
            subtitle:
                'Neurologic status is tracked across 30-minute windows for subtle decline.',
            values: _patient.gcsTrend,
            lineColor: const Color(0xFF8C5C2C),
            unitLabel: '/15',
          ),
          const SizedBox(height: 16),
          VitalChartCard(
            title: 'AI Risk Trend',
            subtitle:
                'The fused score reflects rule-based findings plus trained model output at 30-minute timeline resolution.',
            values: _patient.riskTrend,
            lineColor: accent,
            unitLabel: 'score',
          ),
          const SizedBox(height: 16),
          _ReasonCard(
            title: 'Top reasons',
            items:
                prediction?.topReasons ?? const ['No risk reasons available.'],
            accent: accent,
          ),
          const SizedBox(height: 16),
          _ReasonCard(
            title: 'Recommended actions',
            items:
                prediction?.recommendedActions ??
                const ['Continue standard ICU monitoring.'],
            accent: const Color(0xFF2C8C85),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String rawValue) {
    final parsed = DateTime.tryParse(rawValue);
    if (parsed == null) {
      return rawValue;
    }
    final local = parsed.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class _VitalParameterCard extends StatelessWidget {
  const _VitalParameterCard({required this.spec});

  final VitalTileSpec spec;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(spec.status);
    return Container(
      width: 170,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.label,
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Color(0xFF11212D)),
              children: [
                TextSpan(
                  text: spec.value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: spec.unit.isEmpty ? '' : ' ${spec.unit}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A7B86),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            spec.normalRange,
            style: const TextStyle(
              color: Color(0xFF6A7B86),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusLabel(spec.status),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternInsightsCard extends StatelessWidget {
  const _PatternInsightsCard({required this.insights});

  final List<PatternInsight> insights;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pattern Detection',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF11212D),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The agent reads each patient in 30-minute windows to surface precise physiologic drift and fluctuation patterns.',
            style: TextStyle(color: Color(0xFF5B6B76), height: 1.45),
          ),
          const SizedBox(height: 14),
          ...insights.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(
                      color: _statusColor(insight.severity),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: Color(0xFF475864),
                          height: 1.45,
                        ),
                        children: [
                          TextSpan(
                            text: '${insight.title}: ',
                            style: const TextStyle(
                              color: Color(0xFF11212D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(text: insight.summary),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedMetricsCard extends StatelessWidget {
  const _AdvancedMetricsCard({required this.metrics});

  final List<AdvancedMetricSpec> metrics;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Advanced Features',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF11212D),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Out-of-box ICU features convert raw vitals into perfusion, oxygen-variability, and deterioration-velocity signals.',
            style: TextStyle(color: Color(0xFF5B6B76), height: 1.45),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: metrics
                .map((metric) => _AdvancedMetricTile(metric: metric))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _AdvancedMetricTile extends StatelessWidget {
  const _AdvancedMetricTile({required this.metric});

  final AdvancedMetricSpec metric;

  @override
  Widget build(BuildContext context) {
    final accent = _statusColor(metric.status);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            metric.label,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            metric.value,
            style: const TextStyle(
              color: Color(0xFF11212D),
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            metric.supportingText,
            style: const TextStyle(
              color: Color(0xFF556674),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonCard extends StatelessWidget {
  const _ReasonCard({
    required this.title,
    required this.items,
    required this.accent,
  });

  final String title;
  final List<String> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: const Color(0xFF11212D),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    height: 10,
                    width: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF4B5B67),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'critical':
      return const Color(0xFFDF6D57);
    case 'watch':
      return const Color(0xFFF1B24A);
    default:
      return const Color(0xFF2C8C85);
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'critical':
      return 'Critical range';
    case 'watch':
      return 'Watch closely';
    default:
      return 'Within range';
  }
}
