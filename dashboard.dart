import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/clinical_insights.dart';
import '../widgets/chart_widget.dart';

enum _DashboardTab { overview, pipeline, timeline, report }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.clinicianName,
    required this.apiService,
    required this.onLogout,
  });

  final String clinicianName;
  final ApiService apiService;
  final VoidCallback onLogout;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Duration _refreshInterval = Duration(seconds: 4);

  bool _loading = true;
  bool _refreshInFlight = false;
  bool _reportLoading = false;
  List<PatientReading> _patients = const [];
  PatientReading? _selectedPatient;
  DiagnosticReport? _report;
  _DashboardTab _activeTab = _DashboardTab.report;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPatients(showSpinner: true);
    _autoRefreshTimer = Timer.periodic(_refreshInterval, (_) {
      _loadPatients();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPatients({
    bool showSpinner = false,
    bool forceAdvance = false,
  }) async {
    if (_refreshInFlight) {
      return;
    }

    _refreshInFlight = true;
    if (showSpinner && mounted) {
      setState(() => _loading = true);
    }

    final patients = await widget.apiService.fetchDashboardPatients(
      forceAdvance: forceAdvance,
    );

    if (!mounted) {
      _refreshInFlight = false;
      return;
    }

    final previousId = _selectedPatient?.id;
    PatientReading? nextSelected;
    if (patients.isNotEmpty) {
      nextSelected = patients.firstWhere(
        (patient) => patient.id == previousId,
        orElse: () => patients.first,
      );
    }
    final selectionChanged = previousId != nextSelected?.id;

    setState(() {
      _patients = patients;
      _selectedPatient = nextSelected;
      _loading = false;
    });

    _refreshInFlight = false;

    if (nextSelected != null) {
      await _loadDiagnosticReport(
        nextSelected,
        forceRefresh: forceAdvance || selectionChanged || _report == null,
      );
    }
  }

  Future<void> _loadDiagnosticReport(
    PatientReading patient, {
    bool forceRefresh = false,
  }) async {
    if (_reportLoading) {
      return;
    }

    setState(() => _reportLoading = true);
    final report = await widget.apiService.fetchDiagnosticReport(
      patient,
      forceRefresh: forceRefresh,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _report = report;
      _reportLoading = false;
    });
  }

  Future<void> _selectPatient(PatientReading patient) async {
    setState(() {
      _selectedPatient = patient;
      _report = null;
    });
    await _loadDiagnosticReport(patient, forceRefresh: true);
  }

  Future<void> _advanceFeed() async {
    await _loadPatients(forceAdvance: true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedPatient = _selectedPatient;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFF081426),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1180;

            return RefreshIndicator(
              onRefresh: _advanceFeed,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 40,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardHeader(
                        clinicianName: widget.clinicianName,
                        now: now,
                        demoMode: widget.apiService.demoMode,
                        backendLabel: widget.apiService.baseUrl,
                        onLogout: widget.onLogout,
                        onRefresh: _advanceFeed,
                      ),
                      const SizedBox(height: 16),
                      _TabStrip(
                        activeTab: _activeTab,
                        onChanged: (tab) => setState(() => _activeTab = tab),
                      ),
                      const SizedBox(height: 18),
                      if (_loading && selectedPatient == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 120),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (selectedPatient == null)
                        const _EmptyPanel(
                          message:
                              'No ICU patients are available yet. Pull to refresh to rehydrate the live feed.',
                        )
                      else
                        isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 340,
                                    child: _PatientRail(
                                      patients: _patients,
                                      selectedPatientId: selectedPatient.id,
                                      onSelect: _selectPatient,
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: _DashboardBody(
                                      tab: _activeTab,
                                      patient: selectedPatient,
                                      report: _report,
                                      reportLoading: _reportLoading,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _PatientRail(
                                    patients: _patients,
                                    selectedPatientId: selectedPatient.id,
                                    onSelect: _selectPatient,
                                  ),
                                  const SizedBox(height: 18),
                                  _DashboardBody(
                                    tab: _activeTab,
                                    patient: selectedPatient,
                                    report: _report,
                                    reportLoading: _reportLoading,
                                  ),
                                ],
                              ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.clinicianName,
    required this.now,
    required this.demoMode,
    required this.backendLabel,
    required this.onLogout,
    required this.onRefresh,
  });

  final String clinicianName;
  final DateTime now;
  final bool demoMode;
  final String backendLabel;
  final VoidCallback onLogout;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agentic Diagnosis Risk Assistant',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF72A4FF),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Multi-Agent ICU Complication Detection System',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF95A5C1),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatusBadge(
                    label: demoMode ? 'Demo Mode' : 'Backend Connected',
                    color: demoMode
                        ? const Color(0xFFF2B84B)
                        : const Color(0xFF19C884),
                  ),
                  _StatusBadge(
                    label: clinicianName,
                    color: const Color(0xFF2E6BFF),
                  ),
                  _StatusBadge(
                    label: backendLabel,
                    color: const Color(0xFF465B7D),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Current Time',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8E9CB8)),
            ),
            const SizedBox(height: 4),
            Text(
              _formatClock(now),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDate(now),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF8E9CB8)),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Advance live feed',
                  onPressed: onRefresh,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1B2740),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton.filledTonal(
                  tooltip: 'Log out',
                  onPressed: onLogout,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF1B2740),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.logout_rounded),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.activeTab, required this.onChanged});

  final _DashboardTab activeTab;
  final ValueChanged<_DashboardTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _DashboardTab.values.map((tab) {
        final selected = tab == activeTab;
        return InkWell(
          onTap: () => onChanged(tab),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF2E6BFF)
                  : const Color(0xFF1A2740),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFF4D85FF)
                    : const Color(0xFF243453),
              ),
            ),
            child: Text(
              _tabLabel(tab),
              style: TextStyle(
                color: Colors.white,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PatientRail extends StatelessWidget {
  const _PatientRail({
    required this.patients,
    required this.selectedPatientId,
    required this.onSelect,
  });

  final List<PatientReading> patients;
  final String selectedPatientId;
  final ValueChanged<PatientReading> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ICU Patients',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...patients.map((patient) {
            final selected = patient.id == selectedPatientId;
            final riskLevel = patient.prediction?.riskLevel ?? 'SAFE';
            final accent = _severityColor(riskLevel);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => onSelect(patient),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF1B2C55)
                        : const Color(0xFF18253C),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF437CFF)
                          : accent.withValues(alpha: 0.25),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              patient.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Icon(
                            patient.prediction?.alert ?? false
                                ? Icons.cancel_outlined
                                : Icons.check_circle_outline,
                            color: patient.prediction?.alert ?? false
                                ? const Color(0xFFFF5A6B)
                                : const Color(0xFF17C783),
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${patient.bedLabel} • Age ${patient.age}',
                        style: const TextStyle(
                          color: Color(0xFFA2B1CC),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        patient.diagnosis,
                        style: const TextStyle(
                          color: Color(0xFFC4D0E8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            riskLevel == 'SAFE'
                                ? Icons.shield_outlined
                                : Icons.warning_amber_rounded,
                            color: accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${riskLevel == 'WARNING' ? 'MEDIUM' : riskLevel} RISK',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.tab,
    required this.patient,
    required this.report,
    required this.reportLoading,
  });

  final _DashboardTab tab;
  final PatientReading patient;
  final DiagnosticReport? report;
  final bool reportLoading;

  @override
  Widget build(BuildContext context) {
    if (reportLoading && report == null) {
      return const _SurfacePanel(
        child: SizedBox(
          height: 280,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PatientSummaryHeader(patient: patient, report: report),
        const SizedBox(height: 16),
        switch (tab) {
          _DashboardTab.overview => _OverviewTab(
            patient: patient,
            report: report,
          ),
          _DashboardTab.pipeline => _PipelineTab(report: report),
          _DashboardTab.timeline => _TimelineTab(
            patient: patient,
            report: report,
          ),
          _DashboardTab.report => _DiagnosticReportTab(
            patient: patient,
            report: report,
          ),
        },
      ],
    );
  }
}

class _PatientSummaryHeader extends StatelessWidget {
  const _PatientSummaryHeader({required this.patient, required this.report});

  final PatientReading patient;
  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    final riskLevel =
        report?.overallRiskLevel ?? patient.prediction?.riskLevel ?? 'LOW';
    final probability =
        (report?.probability ?? patient.prediction?.riskScore ?? 0) * 100;
    final accent = _severityColor(riskLevel);

    return _SurfacePanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${patient.name} • ${patient.bedLabel}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${patient.diagnosis} • Age ${patient.age}',
                  style: const TextStyle(
                    color: Color(0xFF9EB1D1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  report?.primaryConcern ??
                      patient.prediction?.doctorMessage ??
                      'Awaiting multi-agent synthesis.',
                  style: const TextStyle(
                    color: Color(0xFFD4DCEF),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MiniMetric(
                      label: 'HR',
                      value: '${patient.heartRate.toStringAsFixed(0)} bpm',
                    ),
                    _MiniMetric(
                      label: 'BP',
                      value:
                          '${patient.systolicBp.toStringAsFixed(0)}/${patient.diastolicBp.toStringAsFixed(0)}',
                    ),
                    _MiniMetric(
                      label: 'SpO2',
                      value: '${patient.spo2.toStringAsFixed(0)}%',
                    ),
                    _MiniMetric(
                      label: 'GCS',
                      value: '${patient.gcs.toStringAsFixed(0)}/15',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 170,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  riskLevel,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${probability.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 34,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Confidence',
                  style: TextStyle(
                    color: Color(0xFF9FB0CB),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.patient, required this.report});

  final PatientReading patient;
  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    final vitalSpecs = buildVitalTileSpecs(patient);
    final patterns = buildPatternInsights(patient);
    final advancedMetrics = buildAdvancedMetrics(patient);
    final complications =
        report?.context?.predictedComplications ??
        const <PredictedComplication>[];
    final recommendationItems = report?.recommendedActions.isNotEmpty ?? false
        ? report!.recommendedActions
        : patient.prediction?.recommendedActions ?? const <String>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideCardWidth = constraints.maxWidth < 460
            ? constraints.maxWidth
            : 420.0;
        final narrowCardWidth = constraints.maxWidth < 360
            ? constraints.maxWidth
            : 320.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: vitalSpecs
                  .map((spec) => _VitalSpecCard(spec: spec))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: wideCardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'Predictive Analysis',
                          icon: Icons.insights_rounded,
                        ),
                        const SizedBox(height: 12),
                        ...complications.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ComplicationCard(item: item),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: wideCardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'Detected Patterns (AI-Identified)',
                          icon: Icons.radar_rounded,
                        ),
                        const SizedBox(height: 12),
                        ...patterns.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PatternTile(pattern: item),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHeading(
                    title: 'AI Recommendations',
                    icon: Icons.psychology_alt_outlined,
                  ),
                  const SizedBox(height: 12),
                  ...recommendationItems.asMap().entries.map((entry) {
                    final urgency = entry.key == 0
                        ? 'HIGH'
                        : entry.key < 3
                        ? 'MEDIUM'
                        : 'MONITOR';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RecommendationTile(
                        urgency: urgency,
                        text: entry.value,
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: narrowCardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'Advanced Features',
                          icon: Icons.auto_graph_rounded,
                        ),
                        const SizedBox(height: 12),
                        ...advancedMetrics.map(
                          (metric) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AdvancedMetricTile(metric: metric),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: wideCardWidth,
                  child: _TrendPanel(
                    title: 'Heart Rate Trend',
                    subtitle:
                        'Real-time drift across 30-minute windows helps expose subtle deterioration.',
                    values: patient.hrTrend,
                    color: const Color(0xFFFF7A88),
                    unitLabel: 'bpm',
                  ),
                ),
                SizedBox(
                  width: wideCardWidth,
                  child: _TrendPanel(
                    title: 'Oxygen Saturation Trend',
                    subtitle:
                        'Fluctuation analysis highlights early gas-exchange instability.',
                    values: patient.spo2Trend,
                    color: const Color(0xFF20C98B),
                    unitLabel: '%',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PipelineTab extends StatelessWidget {
  const _PipelineTab({required this.report});

  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return const _EmptyPanel(
        message:
            'The multi-agent pipeline will appear as soon as the diagnostic report is generated.',
      );
    }

    final agents = report!.agents;
    final cards = [
      _AgentDefinition(
        keyName: 'note_parser_agent',
        title: 'Note Parser Agent',
        accent: const Color(0xFF437CFF),
        subtitle: 'Extracts symptoms from unstructured clinical notes',
      ),
      _AgentDefinition(
        keyName: 'temporal_lab_mapper_agent',
        title: 'Temporal Lab Mapper Agent',
        accent: const Color(0xFFB262FF),
        subtitle: 'Maps lab anomalies into a chronological timeline',
      ),
      _AgentDefinition(
        keyName: 'guideline_rag_agent',
        title: 'Guideline RAG Agent',
        accent: const Color(0xFF1FCB84),
        subtitle: 'Cross-references patterns against clinical guidelines',
      ),
      _AgentDefinition(
        keyName: 'chief_synthesis_agent',
        title: 'Chief Synthesis Agent',
        accent: const Color(0xFFFF8C43),
        subtitle: 'Integrates all outputs and guards against bad labs',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 460
            ? constraints.maxWidth
            : 430.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SurfacePanel(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Multi-Agent Processing Pipeline',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const _StatusBadge(
                    label: 'PIPELINE COMPLETED',
                    color: Color(0xFF17C783),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: cards.map((definition) {
                final raw =
                    agents[definition.keyName] ?? const <String, dynamic>{};
                return SizedBox(
                  width: cardWidth,
                  child: _AgentCard(
                    definition: definition,
                    lines: _agentOutputLines(definition.keyName, raw),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            _SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Processing Flow',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _FlowChip(label: 'Note'),
                      _FlowChip(label: 'Temporal'),
                      _FlowChip(label: 'Guideline'),
                      _FlowChip(label: 'Chief'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelineTab extends StatelessWidget {
  const _TimelineTab({required this.patient, required this.report});

  final PatientReading patient;
  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    final snapshots =
        report?.context?.timelineSnapshots ??
        const <DiagnosticTimelineSnapshot>[];

    if (snapshots.isEmpty) {
      return const _EmptyPanel(
        message:
            'The disease progression timeline will populate after the patient context is synthesized.',
      );
    }

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_rounded, color: Color(0xFFA07BFF)),
              const SizedBox(width: 10),
              Text(
                'Disease Progression Timeline',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                patient.bedLabel,
                style: const TextStyle(
                  color: Color(0xFFA2B2CC),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...snapshots.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _TimelineSnapshotCard(
                dayLabel: 'Day ${entry.key + 1}',
                snapshot: entry.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticReportTab extends StatelessWidget {
  const _DiagnosticReportTab({required this.patient, required this.report});

  final PatientReading patient;
  final DiagnosticReport? report;

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return const _EmptyPanel(
        message:
            'Diagnostic report is being generated from the multi-agent pipeline.',
      );
    }

    final complications =
        report!.context?.predictedComplications ??
        const <PredictedComplication>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 460
            ? constraints.maxWidth
            : 420.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: Color(0xFF20C98B),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Diagnostic Risk Report',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Generated: ${_formatDateTime(report!.generatedAt)}\nPatient: ${patient.bedLabel}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Color(0xFFA7B6D0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _DisclaimerBanner(text: report!.safetyCaveat),
                  const SizedBox(height: 18),
                  _ChiefSummaryCard(report: report!),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SurfacePanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHeading(
                    title: 'Clinical Findings (with Medical RAG Citations)',
                    icon: Icons.menu_book_rounded,
                  ),
                  const SizedBox(height: 12),
                  ...report!.flaggedRisks.map(
                    (flag) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _FlaggedRiskCard(flag: flag),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'Predicted Complications',
                          icon: Icons.warning_amber_rounded,
                        ),
                        const SizedBox(height: 12),
                        ...complications.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ComplicationCard(item: item),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'AI-Generated Recommendations',
                          icon: Icons.check_circle_outline,
                        ),
                        const SizedBox(height: 12),
                        ...report!.recommendedActions.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RecommendationTile(
                              urgency: entry.key < 2
                                  ? 'IMMEDIATE'
                                  : entry.key < 4
                                  ? 'URGENT'
                                  : 'MONITOR',
                              text: entry.value,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'Outlier Detection Analysis',
                          icon: Icons.verified_user_outlined,
                        ),
                        const SizedBox(height: 12),
                        if (report!.probableLabErrors.isEmpty)
                          const _NoOutlierTile()
                        else
                          ...report!.probableLabErrors.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _LabErrorCard(error: item),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _SurfacePanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionHeading(
                          title: 'Explainability',
                          icon: Icons.bubble_chart_outlined,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          report!.explainability.narrative,
                          style: const TextStyle(
                            color: Color(0xFFD6DEEF),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ...report!.explainability.topContributors.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ContributorTile(item: item),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          report!.shiftHandoffSummary,
                          style: const TextStyle(
                            color: Color(0xFFA7B6D0),
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({this.child, this.padding = const EdgeInsets.all(18)});

  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF101D33),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F3151)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFC8D3E8),
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF17253D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF223556)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8FA3C3),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalSpecCard extends StatelessWidget {
  const _VitalSpecCard({required this.spec});

  final VitalTileSpec spec;

  @override
  Widget build(BuildContext context) {
    final accent = _severityColor(spec.status);
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101D33),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spec.label,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '${spec.value}${spec.unit.isEmpty ? '' : ' ${spec.unit}'}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            spec.normalRange,
            style: const TextStyle(color: Color(0xFF96A6C2), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF7EA8FF)),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ComplicationCard extends StatelessWidget {
  const _ComplicationCard({required this.item});

  final PredictedComplication item;

  @override
  Widget build(BuildContext context) {
    final accent = item.riskPercent >= 60
        ? const Color(0xFFF2B84B)
        : item.riskPercent >= 40
        ? const Color(0xFFFF9F43)
        : const Color(0xFF20C98B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17253C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Timeframe: ${item.timeframe} • Confidence: ${item.confidenceLabel}',
                  style: const TextStyle(
                    color: Color(0xFF9EB0CC),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.riskPercent}%',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              const Text('Risk', style: TextStyle(color: Color(0xFF8EA0BC))),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({required this.pattern});

  final PatternInsight pattern;

  @override
  Widget build(BuildContext context) {
    final accent = _severityColor(pattern.severity);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pattern.title,
            style: TextStyle(color: accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            pattern.summary,
            style: const TextStyle(color: Color(0xFFD6DEEF), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({required this.urgency, required this.text});

  final String urgency;
  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = switch (urgency) {
      'IMMEDIATE' => const Color(0xFFFF485A),
      'URGENT' => const Color(0xFFFF7A1A),
      'HIGH' => const Color(0xFFFF5A6B),
      'MEDIUM' => const Color(0xFFF2B84B),
      _ => const Color(0xFF2E6BFF),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17253C),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              urgency,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
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
    final accent = _severityColor(metric.status);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17253C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.label,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                metric.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            metric.supportingText,
            style: const TextStyle(color: Color(0xFFA8B7D0), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.color,
    required this.unitLabel,
  });

  final String title;
  final String subtitle;
  final List<double> values;
  final Color color;
  final String unitLabel;

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFFA7B6D0), height: 1.45),
          ),
          const SizedBox(height: 14),
          MiniTrendChart(
            title: unitLabel,
            values: values,
            lineColor: color,
            height: 160,
            showLabels: true,
          ),
        ],
      ),
    );
  }
}

class _AgentDefinition {
  const _AgentDefinition({
    required this.keyName,
    required this.title,
    required this.accent,
    required this.subtitle,
  });

  final String keyName;
  final String title;
  final Color accent;
  final String subtitle;
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.definition, required this.lines});

  final _AgentDefinition definition;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF101D33),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: definition.accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, color: definition.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  definition.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const _StatusBadge(label: 'COMPLETED', color: Color(0xFF17C783)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            definition.subtitle,
            style: const TextStyle(color: Color(0xFFABC0DF), height: 1.4),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF17253D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF243759)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OUTPUT',
                  style: TextStyle(
                    color: Color(0xFFA9B9D3),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                ...lines
                    .take(5)
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '• $line',
                          style: const TextStyle(
                            color: Color(0xFFDCE4F5),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowChip extends StatelessWidget {
  const _FlowChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF17315B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF9BD2FF),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TimelineSnapshotCard extends StatelessWidget {
  const _TimelineSnapshotCard({required this.dayLabel, required this.snapshot});

  final String dayLabel;
  final DiagnosticTimelineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final accent = _severityColor(snapshot.severityLabel);
    final vitals = snapshot.vitals;
    final labs = snapshot.labs;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  dayLabel.replaceAll('Day ', ''),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _shortTime(snapshot.timestamp),
                style: const TextStyle(
                  color: Color(0xFF8CA0C0),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withValues(alpha: 0.72)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDateTime(snapshot.timestamp),
                  style: const TextStyle(
                    color: Color(0xFF8FA4C5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                _LabeledBlock(
                  label: 'Clinical Notes',
                  value: snapshot.clinicalNote,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SignalTile(
                      label: 'Temp',
                      value: '${vitals['Temp']?.toStringAsFixed(1)}°C',
                    ),
                    _SignalTile(
                      label: 'HR',
                      value: '${vitals['HR']?.toStringAsFixed(0)} bpm',
                    ),
                    _SignalTile(
                      label: 'BP',
                      value:
                          '${vitals['BP_sys']?.toStringAsFixed(0)}/${vitals['BP_dia']?.toStringAsFixed(0)}',
                    ),
                    _SignalTile(
                      label: 'SpO2',
                      value: '${vitals['SpO2']?.toStringAsFixed(0)}%',
                    ),
                    _SignalTile(
                      label: 'WBC',
                      value: '${labs['WBC']?.toStringAsFixed(1)} K/μL',
                    ),
                    _SignalTile(
                      label: 'Lactate',
                      value: '${labs['Lactate']?.toStringAsFixed(1)} mmol/L',
                    ),
                    _SignalTile(
                      label: 'Creatinine',
                      value: '${labs['Creatinine']?.toStringAsFixed(1)} mg/dL',
                    ),
                    _SignalTile(
                      label: 'PCT',
                      value: '${labs['PCT']?.toStringAsFixed(1)} ng/mL',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A225C),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF8D49FF)),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: Color(0xFFEADAFE),
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(
                          text: 'AI ANALYSIS: ',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        TextSpan(text: snapshot.aiAnalysis),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17253D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF93A6C3),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(color: Color(0xFFE0E7F5), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF17253D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF243456)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF91A4C2),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclaimerBanner extends StatelessWidget {
  const _DisclaimerBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF321927),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD83B4A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFFFBE4A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CRITICAL DISCLAIMER',
                  style: TextStyle(
                    color: Color(0xFFFFC857),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFFFFD9DB),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChiefSummaryCard extends StatelessWidget {
  const _ChiefSummaryCard({required this.report});

  final DiagnosticReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF18253C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF233758)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CHIEF SYNTHESIS AGENT OUTPUT',
                  style: TextStyle(
                    color: Color(0xFF8EA1BE),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  report.primaryConcern,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  report.chiefSummary,
                  style: const TextStyle(color: Color(0xFFC9D5EA), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(report.probability * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Color(0xFF22D382),
                  fontWeight: FontWeight.w900,
                  fontSize: 38,
                ),
              ),
              const Text(
                'Confidence',
                style: TextStyle(color: Color(0xFF8EA2C0)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlaggedRiskCard extends StatelessWidget {
  const _FlaggedRiskCard({required this.flag});

  final DiagnosticRiskFlag flag;

  @override
  Widget build(BuildContext context) {
    final accent = _severityColor(flag.level);
    final citation = flag.guidelineCitations.isNotEmpty
        ? flag.guidelineCitations.first
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF17253C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  flag.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  flag.level,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            flag.summary,
            style: const TextStyle(color: Color(0xFFD5DFF0), height: 1.4),
          ),
          const SizedBox(height: 10),
          ...flag.supportingEvidence
              .take(3)
              .map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• $line',
                    style: const TextStyle(
                      color: Color(0xFFAFC0DA),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
          if (citation != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF20325C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF355FCA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GUIDELINE CITATION',
                    style: TextStyle(
                      color: Color(0xFFDDE8FF),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${citation.title} - ${citation.organization} ${citation.year}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    citation.summary,
                    style: const TextStyle(
                      color: Color(0xFFC8D7F7),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoOutlierTile extends StatelessWidget {
  const _NoOutlierTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF11352D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1FCB84)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF1FCB84)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'No statistical outliers detected. Current lab values show a consistent clinical progression pattern.',
              style: TextStyle(color: Color(0xFFD8FFF0), height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabErrorCard extends StatelessWidget {
  const _LabErrorCard({required this.error});

  final ProbableLabError error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF37221A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFF9E43)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${error.labName} ${error.latestValue.toStringAsFixed(1)} ${error.unit}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.reason,
            style: const TextStyle(color: Color(0xFFFFE0C6), height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            error.action,
            style: const TextStyle(color: Color(0xFFFFD2A6), height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _ContributorTile extends StatelessWidget {
  const _ContributorTile({required this.item});

  final ExplainabilityContributor item;

  @override
  Widget build(BuildContext context) {
    final percent = (item.impactScore * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF17253C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF243556)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.feature,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.reason,
                  style: const TextStyle(
                    color: Color(0xFFAEBEDA),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$percent%',
            style: const TextStyle(
              color: Color(0xFF7EA8FF),
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _agentOutputLines(String key, Map<String, dynamic> raw) {
  switch (key) {
    case 'note_parser_agent':
      final signals = (raw['matched_signals'] as List<dynamic>? ?? const [])
          .map(
            (item) => item is Map<String, dynamic> ? item['signal'] : '$item',
          )
          .whereType<Object>()
          .map((item) => item.toString())
          .toList();
      final evidence = (raw['evidence'] as List<dynamic>? ?? const [])
          .cast<String>();
      return [
        if (signals.isNotEmpty) ...signals.map((item) => item),
        if (evidence.isNotEmpty) ...evidence.take(3),
        (raw['summary'] as String?) ?? 'Parsed bedside note signals.',
      ];
    case 'temporal_lab_mapper_agent':
      final trends =
          raw['trend_summaries'] as Map<String, dynamic>? ?? const {};
      return [
        for (final entry in trends.entries)
          () {
            final details = entry.value is Map
                ? Map<String, dynamic>.from(entry.value as Map)
                : const <String, dynamic>{};
            return '${entry.key.toUpperCase()}: ${details['trend'] ?? 'stable'}'
                ' at ${details['latest_value'] ?? '--'}';
          }(),
        (raw['summary'] as String?) ?? 'Mapped lab changes into chronology.',
      ];
    case 'guideline_rag_agent':
      final citations =
          (raw['retrieved_citations'] as List<dynamic>? ?? const [])
              .map(
                (item) => item is Map<String, dynamic>
                    ? item['title']?.toString() ?? 'Guideline match'
                    : item.toString(),
              )
              .toList();
      return [
        ...citations.take(3),
        (raw['summary'] as String?) ??
            'Retrieved supporting guideline evidence.',
      ];
    case 'chief_synthesis_agent':
      return [
        if (raw['primary_concern'] != null)
          'Primary concern: ${raw['primary_concern']}',
        if (raw['chief_summary'] != null) raw['chief_summary'].toString(),
        if (raw['shift_handoff_summary'] != null)
          raw['shift_handoff_summary'].toString(),
        if (raw['diagnosis_update_blocked'] == true)
          'Diagnosis update blocked pending redraw confirmation.',
      ];
    default:
      return [(raw['summary'] as String?) ?? 'Pipeline output available.'];
  }
}

String _tabLabel(_DashboardTab tab) {
  return switch (tab) {
    _DashboardTab.overview => 'Real-Time Overview',
    _DashboardTab.pipeline => 'Multi-Agent Pipeline',
    _DashboardTab.timeline => 'Disease Timeline',
    _DashboardTab.report => 'Diagnostic Report',
  };
}

Color _severityColor(String raw) {
  final value = raw.toUpperCase();
  switch (value) {
    case 'CRITICAL':
    case 'HIGH':
    case 'WARNING':
    case 'WATCH':
      if (value == 'WARNING' || value == 'WATCH') {
        return const Color(0xFFF2B84B);
      }
      return const Color(0xFFFF5A6B);
    case 'MODERATE':
      return const Color(0xFFFFB347);
    case 'SAFE':
    case 'LOW':
    case 'NORMAL':
      return const Color(0xFF20C98B);
    default:
      return const Color(0xFF7EA8FF);
  }
}

String _formatClock(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute:$second $period';
}

String _formatDate(DateTime value) {
  return '${value.month}/${value.day}/${value.year}';
}

String _formatDateTime(String rawValue) {
  final parsed = DateTime.tryParse(rawValue)?.toLocal();
  if (parsed == null) {
    return rawValue;
  }
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} at ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}

String _shortTime(String rawValue) {
  final parsed = DateTime.tryParse(rawValue)?.toLocal();
  if (parsed == null) {
    return rawValue;
  }
  return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}
