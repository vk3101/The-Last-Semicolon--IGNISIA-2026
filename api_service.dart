import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class ApiService {
  ApiService({String? baseUrl})
    : _baseUrl = baseUrl ?? _resolveBaseUrl(),
      _client = http.Client();

  final String _baseUrl;
  final http.Client _client;
  bool _backendAvailable = false;
  DateTime? _lastSyncAt;
  List<PatientReading>? _simulatedPatients;
  Map<String, Map<String, double>>? _baselineVitals;
  DateTime? _lastSimulationAt;
  int _simulationTick = 0;
  Future<List<PatientReading>>? _dashboardRequest;
  final Map<String, DiagnosticReport> _diagnosticReports = {};
  final Map<String, Future<DiagnosticReport>> _diagnosticRequests = {};

  static const Duration _simulationCadence = Duration(seconds: 4);

  String get baseUrl => _baseUrl;
  bool get backendAvailable => _backendAvailable;
  bool get demoMode => !_backendAvailable;
  DateTime? get lastSyncAt => _lastSyncAt;

  static String _resolveBaseUrl() {
    const configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredBaseUrl.isNotEmpty) {
      return configuredBaseUrl;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:5001';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:5001';
      default:
        return 'http://127.0.0.1:5001';
    }
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<List<PatientReading>> fetchDashboardPatients({
    bool forceAdvance = false,
  }) {
    if (_dashboardRequest != null && !forceAdvance) {
      return _dashboardRequest!;
    }

    final future = _fetchDashboardPatients(forceAdvance: forceAdvance);
    if (!forceAdvance) {
      _dashboardRequest = future;
    }

    return future.whenComplete(() {
      if (identical(_dashboardRequest, future)) {
        _dashboardRequest = null;
      }
    });
  }

  Future<List<PatientReading>> _fetchDashboardPatients({
    bool forceAdvance = false,
  }) async {
    final snapshot = _preparePatients(forceAdvance: forceAdvance);

    if (!snapshot.advanced && snapshot.allPredictionsReady) {
      return snapshot.patients;
    }

    try {
      final response = await _client
          .post(
            _uri('/predict/batch'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'patients': snapshot.patients
                  .map((patient) => patient.toPredictionPayload())
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Unexpected status code ${response.statusCode}');
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final resultList = (payload['results'] as List<dynamic>? ?? const []);
      final predictions = <String, PredictionResult>{};

      for (final entry in resultList) {
        final item = entry as Map<String, dynamic>;
        final patientId = item['patient_id'] as String? ?? 'UNKNOWN';
        predictions[patientId] = PredictionResult.fromJson(item);
      }

      _backendAvailable = true;
      _lastSyncAt = DateTime.now();
      final updatedPatients = _mergePredictions(
        snapshot.patients,
        predictions,
        appendRiskPoint: snapshot.advanced,
      );
      _simulatedPatients = updatedPatients;
      return updatedPatients;
    } catch (_) {
      _backendAvailable = false;
      final fallbackPatients = snapshot.patients
          .map(
            (patient) => patient.copyWith(
              prediction: _fallbackPrediction(patient),
              riskTrend: snapshot.advanced
                  ? _appendMetricPoint(
                      patient.riskTrend,
                      _fallbackPrediction(patient).riskScore,
                    )
                  : patient.riskTrend,
            ),
          )
          .toList(growable: false);
      _simulatedPatients = fallbackPatients;
      return fallbackPatients;
    }
  }

  Future<PredictionResult> refreshPrediction(PatientReading patient) async {
    try {
      final response = await _client
          .post(
            _uri('/predict'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(patient.toPredictionPayload()),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Unexpected status code ${response.statusCode}');
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      _backendAvailable = true;
      _lastSyncAt = DateTime.now();
      return PredictionResult.fromJson(
        payload['result'] as Map<String, dynamic>,
      );
    } catch (_) {
      _backendAvailable = false;
      return _fallbackPrediction(patient);
    }
  }

  Future<List<AlertRecord>> fetchRecentAlerts({int limit = 8}) async {
    try {
      final response = await _client
          .get(_uri('/alerts/recent?limit=$limit'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception('Unexpected status code ${response.statusCode}');
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (payload['alerts'] as List<dynamic>? ?? const []);
      _backendAvailable = true;
      _lastSyncAt = DateTime.now();
      return items
          .map((item) => AlertRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _backendAvailable = false;
      final patients = await fetchDashboardPatients();
      return patients
          .where((patient) => patient.prediction?.alert ?? false)
          .map(
            (patient) => AlertRecord(
              patientId: patient.id,
              riskLevel: patient.prediction?.riskLevel ?? 'WARNING',
              riskScore: patient.prediction?.riskScore ?? 0.5,
              doctorMessage:
                  patient.prediction?.doctorMessage ??
                  'Watch this patient closely.',
              timestamp: patient.lastUpdated,
            ),
          )
          .toList();
    }
  }

  Future<DiagnosticReport> fetchDiagnosticReport(
    PatientReading patient, {
    bool forceRefresh = false,
  }) {
    final cached = _diagnosticReports[patient.id];
    if (!forceRefresh && cached != null) {
      return Future.value(cached);
    }

    final inFlight = _diagnosticRequests[patient.id];
    if (!forceRefresh && inFlight != null) {
      return inFlight;
    }

    final future = _fetchDiagnosticReport(patient);
    _diagnosticRequests[patient.id] = future;
    return future.whenComplete(() {
      if (identical(_diagnosticRequests[patient.id], future)) {
        _diagnosticRequests.remove(patient.id);
      }
    });
  }

  Future<DiagnosticReport> _fetchDiagnosticReport(
    PatientReading patient,
  ) async {
    final context = _buildDiagnosticCaseContext(patient);
    final payload = _buildDiagnosticPayload(patient, context);

    try {
      final response = await _client
          .post(
            _uri('/diagnostic-report'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('Unexpected status code ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final report = DiagnosticReport.fromJson(
        decoded['report'] as Map<String, dynamic>? ?? const {},
      ).withContext(context);
      _backendAvailable = true;
      _lastSyncAt = DateTime.now();
      _diagnosticReports[patient.id] = report;
      return report;
    } catch (_) {
      _backendAvailable = false;
      final fallback = _fallbackDiagnosticReport(patient, context);
      _diagnosticReports[patient.id] = fallback;
      return fallback;
    }
  }

  DiagnosticCaseContext _buildDiagnosticCaseContext(PatientReading patient) {
    final scenario = _scenarioForPatient(patient);
    final anchor =
        DateTime.tryParse(patient.lastUpdated)?.toUtc() ??
        DateTime.now().toUtc();
    final timestamps = [
      anchor.subtract(const Duration(hours: 48)),
      anchor.subtract(const Duration(hours: 18)),
      anchor,
    ];
    final timelineVitals = _timelineVitals(patient);

    final snapshots = List<DiagnosticTimelineSnapshot>.generate(3, (index) {
      return DiagnosticTimelineSnapshot(
        title: scenario.phaseTitles[index],
        timestamp: timestamps[index].toIso8601String(),
        severityLabel: scenario.phaseSeverities[index],
        clinicalNote: scenario.phaseNotes[index],
        vitals: timelineVitals[index],
        labs: Map<String, double>.from(scenario.labProfiles[index]),
        aiAnalysis: scenario.phaseAnalyses[index],
      );
    });

    return DiagnosticCaseContext(
      age: patient.age,
      diagnosis: patient.diagnosis,
      timelineSnapshots: snapshots,
      predictedComplications: _predictedComplications(patient, scenario),
    );
  }

  Map<String, dynamic> _buildDiagnosticPayload(
    PatientReading patient,
    DiagnosticCaseContext context,
  ) {
    final noteAuthors = [
      ('Dr. Meera', 'ICU'),
      ('Dr. Thomas', 'Critical Care'),
      ('Nurse Priya', 'Nursing'),
    ];

    final notes = <Map<String, dynamic>>[];
    final vitals = <Map<String, dynamic>>[];
    final labs = <Map<String, dynamic>>[];

    for (var index = 0; index < context.timelineSnapshots.length; index++) {
      final snapshot = context.timelineSnapshots[index];
      final author = noteAuthors[index % noteAuthors.length];
      notes.add({
        'timestamp': snapshot.timestamp,
        'author': author.$1,
        'specialty': author.$2,
        'text': snapshot.clinicalNote,
      });
      vitals.add({'timestamp': snapshot.timestamp, ...snapshot.vitals});

      snapshot.labs.forEach((name, value) {
        if (name == 'PCT') {
          return;
        }
        labs.add({
          'timestamp': snapshot.timestamp,
          'name': name,
          'value': value,
          'unit': _labUnitFor(name),
        });
      });
    }

    labs.addAll(_extraLabPayload(patient, context));

    return {
      'patient_id': patient.id,
      'demographics': {
        'age': patient.age,
        'sex': patient.id.hashCode.isEven ? 'Male' : 'Female',
      },
      'notes': notes,
      'vitals': vitals,
      'labs': labs,
    };
  }

  List<Map<String, dynamic>> _extraLabPayload(
    PatientReading patient,
    DiagnosticCaseContext context,
  ) {
    if (patient.id != 'ICU-103' || context.timelineSnapshots.length < 3) {
      return const [];
    }

    final redrawTime = DateTime.parse(
      context.timelineSnapshots.last.timestamp,
    ).toUtc().subtract(const Duration(hours: 2));

    return [
      {
        'timestamp': redrawTime.toIso8601String(),
        'name': 'Creatinine',
        'value': 1.0,
        'unit': 'mg/dL',
      },
      {
        'timestamp': context.timelineSnapshots.last.timestamp,
        'name': 'Creatinine',
        'value': 5.2,
        'unit': 'mg/dL',
        'confirmed_redraw': false,
      },
    ];
  }

  List<Map<String, double>> _timelineVitals(PatientReading patient) {
    final earlyIndex = patient.hrTrend.length >= 6 ? 1 : 0;
    final middleIndex = patient.hrTrend.length >= 4
        ? patient.hrTrend.length - 4
        : 0;

    return [
      {
        'HR': _trendValue(patient.hrTrend, earlyIndex),
        'BP_sys': _trendValue(patient.bpTrend, earlyIndex),
        'BP_dia': (patient.diastolicBp + 20).clamp(58, 88).toDouble(),
        'Temp': _trendValue(patient.tempTrend, earlyIndex),
        'SpO2': _trendValue(patient.spo2Trend, earlyIndex),
        'Resp': (patient.respiratoryRate - 6).clamp(12, 32).toDouble(),
        'GCS': _trendValue(patient.gcsTrend, earlyIndex),
      },
      {
        'HR': _trendValue(patient.hrTrend, middleIndex),
        'BP_sys': _trendValue(patient.bpTrend, middleIndex),
        'BP_dia': (patient.diastolicBp + 10).clamp(54, 84).toDouble(),
        'Temp': _trendValue(patient.tempTrend, middleIndex),
        'SpO2': _trendValue(patient.spo2Trend, middleIndex),
        'Resp': (patient.respiratoryRate - 3).clamp(12, 34).toDouble(),
        'GCS': _trendValue(patient.gcsTrend, middleIndex),
      },
      Map<String, double>.from(patient.vitals),
    ];
  }

  double _trendValue(List<double> values, int index) {
    if (values.isEmpty) {
      return 0;
    }
    final safeIndex = index.clamp(0, values.length - 1);
    return values[safeIndex];
  }

  String _labUnitFor(String name) {
    switch (name) {
      case 'WBC':
        return 'K/uL';
      case 'Lactate':
        return 'mmol/L';
      case 'Creatinine':
        return 'mg/dL';
      default:
        return '';
    }
  }

  DiagnosticReport _fallbackDiagnosticReport(
    PatientReading patient,
    DiagnosticCaseContext context,
  ) {
    final prediction = patient.prediction ?? _fallbackPrediction(patient);
    final citations = _fallbackCitations(patient);
    final flags = <Map<String, dynamic>>[
      {
        'title': patient.id == 'ICU-104'
            ? 'Observation and neurologic monitoring'
            : 'Early sepsis risk',
        'level': prediction.riskScore >= 0.7
            ? 'CRITICAL'
            : prediction.riskScore >= 0.45
            ? 'HIGH'
            : 'MODERATE',
        'score': prediction.riskScore,
        'summary': prediction.doctorMessage,
        'supporting_evidence': prediction.topReasons,
        'guideline_citations': citations.map((item) => item.toJson()).toList(),
      },
      if (patient.id == 'ICU-101' || patient.id == 'ICU-103')
        {
          'title': patient.id == 'ICU-103'
              ? 'Respiratory failure escalation'
              : 'Organ failure / AKI risk',
          'level': prediction.riskScore >= 0.75 ? 'CRITICAL' : 'HIGH',
          'score': (prediction.riskScore * 0.86).clamp(0.32, 0.97),
          'summary': patient.id == 'ICU-103'
              ? 'Persistent hypoxia, tachypnea, and pressure drift suggest worsening respiratory compromise.'
              : 'Combined perfusion decline and rising renal markers suggest evolving organ dysfunction.',
          'supporting_evidence': [
            ...prediction.topReasons.take(2),
            if (patient.id == 'ICU-101')
              'Creatinine and lactate trends remain concerning across the recent ICU window.',
            if (patient.id == 'ICU-103')
              'SpO2 fluctuation and respiratory workload continue to worsen.',
          ],
          'guideline_citations': citations
              .map((item) => item.toJson())
              .toList(),
        },
    ];

    final probableErrors = patient.id == 'ICU-103'
        ? [
            {
              'lab_name': 'Creatinine',
              'timestamp': context.timelineSnapshots.last.timestamp,
              'latest_value': 5.2,
              'unit': 'mg/dL',
              'reason':
                  'Creatinine is sharply discordant with three prior stable values and is being treated as a probable lab error.',
              'action':
                  'Hold diagnosis escalation from this lab result until a confirmed redraw is available.',
              'detection_method': 'robust_z_score + temporal_consistency',
            },
          ]
        : const <Map<String, dynamic>>[];

    final timelineDays = context.timelineSnapshots.asMap().entries.map((entry) {
      final snapshot = entry.value;
      return {
        'day_label': 'Day ${entry.key + 1}',
        'date': snapshot.timestamp.split('T').first,
        'events': [
          {
            'timestamp': snapshot.timestamp,
            'source': 'vitals',
            'severity': snapshot.severityLabel.toLowerCase(),
            'summary':
                'Vitals: HR ${snapshot.vitals['HR']?.toStringAsFixed(0)}, BP ${snapshot.vitals['BP_sys']?.toStringAsFixed(0)}/${snapshot.vitals['BP_dia']?.toStringAsFixed(0)}, Temp ${snapshot.vitals['Temp']?.toStringAsFixed(1)}, SpO2 ${snapshot.vitals['SpO2']?.toStringAsFixed(0)}.',
          },
          {
            'timestamp': snapshot.timestamp,
            'source': 'note',
            'severity': snapshot.severityLabel.toLowerCase(),
            'summary': snapshot.clinicalNote,
          },
          {
            'timestamp': snapshot.timestamp,
            'source': 'lab',
            'severity': snapshot.severityLabel.toLowerCase(),
            'summary':
                'Labs: WBC ${snapshot.labs['WBC']?.toStringAsFixed(1)} K/uL, Lactate ${snapshot.labs['Lactate']?.toStringAsFixed(1)} mmol/L, Creatinine ${snapshot.labs['Creatinine']?.toStringAsFixed(1)} mg/dL.',
          },
        ],
      };
    }).toList();

    final handoff =
        'Handoff summary for ${patient.id}: overall risk is ${prediction.riskLevel.toLowerCase()} with primary concern ${flags.first['title']}. Next step: ${(prediction.recommendedActions.isNotEmpty ? prediction.recommendedActions.first : 'continue close review')}.';

    final reportJson = <String, dynamic>{
      'patient_id': patient.id,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'safety_caveat':
          'Decision-support only. This report is not a clinical diagnosis. A licensed clinician must verify the patient and confirm critical labs.',
      'overall_risk_level': prediction.riskLevel == 'SAFE'
          ? 'LOW'
          : prediction.riskLevel,
      'primary_concern': flags.first['title'],
      'shift_handoff_summary': handoff,
      'latest_vitals': patient.vitals,
      'agents': {
        'note_parser_agent': {
          'agent_role': 'Note Parser Agent',
          'note_count': context.timelineSnapshots.length,
          'matched_signals': context.timelineSnapshots
              .map((snapshot) => {'signal': snapshot.title})
              .toList(),
          'evidence': context.timelineSnapshots
              .map((snapshot) => snapshot.clinicalNote)
              .toList(),
          'summary':
              'Extracted symptoms and deterioration cues from ICU notes for ${patient.name}.',
        },
        'temporal_lab_mapper_agent': {
          'agent_role': 'Temporal Lab Mapper Agent',
          'trend_summaries': {
            'wbc': {
              'trend': 'rising',
              'latest_value': context.timelineSnapshots.last.labs['WBC'],
            },
            'lactate': {
              'trend': patient.id == 'ICU-104' ? 'stable' : 'rising',
              'latest_value': context.timelineSnapshots.last.labs['Lactate'],
            },
            'creatinine': {
              'trend': patient.id == 'ICU-103' ? 'discordant' : 'rising',
              'latest_value': context.timelineSnapshots.last.labs['Creatinine'],
            },
          },
          'evidence': [
            'Temporal lab review tracked inflammatory, perfusion, and renal markers across three ICU phases.',
          ],
          'summary':
              'Mapped lab trajectories into a chronological progression timeline.',
        },
        'guideline_rag_agent': {
          'agent_role': 'Guideline RAG Agent',
          'retrieved_citations': citations
              .map((item) => item.toJson())
              .toList(),
          'summary':
              'Matched the patient pattern against the seeded clinical guideline corpus.',
        },
        'chief_synthesis_agent': {
          'agent_role': 'Chief Synthesis Agent',
          'overall_risk_level': prediction.riskLevel == 'SAFE'
              ? 'LOW'
              : prediction.riskLevel,
          'primary_concern': flags.first['title'],
          'chief_summary':
              '${patient.name} shows converging evidence for ${flags.first['title'].toString().toLowerCase()}.',
          'diagnosis_update_blocked': probableErrors.isNotEmpty,
          'shift_handoff_summary': handoff,
        },
      },
      'flagged_risks': flags,
      'probable_lab_errors': probableErrors,
      'disease_progression_timeline_by_day': timelineDays,
      'guideline_citations': citations.map((item) => item.toJson()).toList(),
      'recommended_actions': prediction.recommendedActions,
      'diagnostic_risk_report': {
        'probability': prediction.riskScore,
        'early_warning': flags.map((item) => item['title']).toList(),
        'evidence': prediction.topReasons,
        'guidelines': citations
            .map((item) => '${item.title} (${item.organization}, ${item.year})')
            .toList(),
        'safety_note': 'This is decision support only, not a diagnosis.',
      },
      'explainability': {
        'method':
            'Local feature contribution summary over abnormal vitals, lab trends, and model components.',
        'narrative': prediction.topReasons.isNotEmpty
            ? 'The main contributors were ${prediction.topReasons.take(3).join(', ')}.'
            : 'No major abnormal contributors were detected.',
        'flag_count': flags.length,
        'top_contributors': _fallbackExplainability(patient),
        'model_components': prediction.componentScores,
      },
    };

    return DiagnosticReport.fromJson(reportJson).withContext(context);
  }

  List<Map<String, dynamic>> _fallbackExplainability(PatientReading patient) {
    return [
      if (patient.heartRate > 100)
        {
          'feature': 'HR',
          'value': patient.heartRate,
          'impact_score': 0.72,
          'reason': 'Heart rate is above the monitored normal range.',
        },
      if (patient.systolicBp < 95)
        {
          'feature': 'BP_sys',
          'value': patient.systolicBp,
          'impact_score': 0.84,
          'reason': 'Systolic blood pressure suggests impaired perfusion.',
        },
      if (patient.spo2 < 94)
        {
          'feature': 'SpO2',
          'value': patient.spo2,
          'impact_score': 0.79,
          'reason': 'Oxygen saturation is below target for ICU monitoring.',
        },
      if (patient.gcs < 15)
        {
          'feature': 'GCS',
          'value': patient.gcs,
          'impact_score': 0.58,
          'reason': 'Neurologic status has dropped below baseline.',
        },
      {
        'feature': 'Temp',
        'value': patient.temperature,
        'impact_score': patient.temperature >= 38 ? 0.61 : 0.18,
        'reason': 'Temperature trend contributes to inflammatory risk review.',
      },
    ];
  }

  List<_FallbackCitation> _fallbackCitations(PatientReading patient) {
    final citations = <_FallbackCitation>[
      const _FallbackCitation(
        id: 'ssc-2021',
        title: 'Surviving Sepsis Campaign 2021',
        organization: 'SCCM',
        year: 2021,
        url:
            'https://www.sccm.org/clinical-resources/guidelines/guidelines/surviving-sepsis-guidelines-2021',
        summary:
            'Guideline emphasis on early recognition, lactate review, MAP support, and urgent antimicrobial therapy.',
      ),
    ];

    if (patient.id == 'ICU-101' || patient.id == 'ICU-103') {
      citations.add(
        const _FallbackCitation(
          id: 'kdigo-aki',
          title: 'KDIGO Acute Kidney Injury Guideline',
          organization: 'KDIGO',
          year: 2012,
          url:
              'https://kdigo.org/wp-content/uploads/2017/04/KDIGO-AKI-GL-for-JSN_wm.pdf',
          summary:
              'Renal injury staging guidance based on creatinine change and urine output deterioration.',
        ),
      );
    }

    return citations;
  }

  List<PredictedComplication> _predictedComplications(
    PatientReading patient,
    _DiagnosticScenario scenario,
  ) {
    return scenario.complications.map((item) {
      final blended =
          (item.baseRisk + (patient.prediction?.riskScore ?? 0.45) * 18)
              .round()
              .clamp(18, 92);
      return PredictedComplication(
        title: item.title,
        timeframe: item.timeframe,
        confidenceLabel: blended >= 60
            ? 'High'
            : blended >= 40
            ? 'Medium'
            : 'Low',
        riskPercent: blended,
      );
    }).toList();
  }

  _DiagnosticScenario _scenarioForPatient(PatientReading patient) {
    switch (patient.id) {
      case 'ICU-101':
        return const _DiagnosticScenario(
          phaseTitles: [
            'Initial Presentation',
            'Deterioration Phase',
            'Critical Deterioration',
          ],
          phaseSeverities: ['normal', 'warning', 'critical'],
          phaseNotes: [
            'Patient admitted after cardiac surgery with fever and malaise. Empiric antibiotics started while cultures were sent.',
            'Hypotension required fluid bolus. Mental status change noted and perfusion concerns escalated during shift handoff.',
            'Persistent hypotension despite resuscitation. Vasopressor support initiated with worsening urine output.',
          ],
          phaseAnalyses: [
            'Early inflammatory response detected. Baseline perfusion preserved.',
            'Escalating pattern: hypotension, tachycardia, and rising lactate suggest evolving sepsis.',
            'High-risk deterioration: concurrent perfusion failure and organ dysfunction pattern.',
          ],
          labProfiles: [
            {'WBC': 12.3, 'Lactate': 1.8, 'Creatinine': 1.0, 'PCT': 0.8},
            {'WBC': 18.7, 'Lactate': 3.2, 'Creatinine': 1.4, 'PCT': 4.2},
            {'WBC': 21.4, 'Lactate': 4.5, 'Creatinine': 2.1, 'PCT': 8.9},
          ],
          complications: [
            _ComplicationSeed(
              title: 'Septic Shock',
              timeframe: '4-6 hours',
              baseRisk: 54,
            ),
            _ComplicationSeed(
              title: 'Respiratory Distress',
              timeframe: '6-8 hours',
              baseRisk: 42,
            ),
            _ComplicationSeed(
              title: 'Cardiac Arrhythmia',
              timeframe: '8-12 hours',
              baseRisk: 24,
            ),
          ],
        );
      case 'ICU-102':
        return const _DiagnosticScenario(
          phaseTitles: [
            'Early Sepsis Workup',
            'Response Monitoring',
            'Ongoing ICU Surveillance',
          ],
          phaseSeverities: ['normal', 'warning', 'warning'],
          phaseNotes: [
            'Fever with probable urinary source. Blood cultures drawn and fluids initiated.',
            'Tachycardia persisted through the afternoon but perfusion remained responsive to fluids.',
            'Inflammatory markers remain abnormal, though oxygenation and mental status are relatively preserved.',
          ],
          phaseAnalyses: [
            'Infection concern present with early inflammatory activation.',
            'Moderate-risk trend: infection markers rising faster than bedside recovery.',
            'Continued close surveillance recommended while sepsis therapy is reassessed.',
          ],
          labProfiles: [
            {'WBC': 11.4, 'Lactate': 1.6, 'Creatinine': 0.9, 'PCT': 0.6},
            {'WBC': 13.8, 'Lactate': 2.1, 'Creatinine': 1.0, 'PCT': 1.9},
            {'WBC': 15.1, 'Lactate': 2.4, 'Creatinine': 1.1, 'PCT': 3.7},
          ],
          complications: [
            _ComplicationSeed(
              title: 'Sepsis Progression',
              timeframe: '6-12 hours',
              baseRisk: 38,
            ),
            _ComplicationSeed(
              title: 'Acute Kidney Injury',
              timeframe: '12-24 hours',
              baseRisk: 25,
            ),
            _ComplicationSeed(
              title: 'Respiratory Deterioration',
              timeframe: '8-12 hours',
              baseRisk: 18,
            ),
          ],
        );
      case 'ICU-103':
        return const _DiagnosticScenario(
          phaseTitles: [
            'Respiratory Decompensation',
            'Ventilatory Strain',
            'Critical Hypoxic Phase',
          ],
          phaseSeverities: ['warning', 'warning', 'critical'],
          phaseNotes: [
            'Increasing oxygen requirement overnight with coarse breath sounds and rising work of breathing.',
            'SpO2 drift and tachypnea continued despite respiratory support escalation. Lab redraw requested after unexpected renal value.',
            'Sustained hypoxia and pressure drift with concern for multisystem deterioration.',
          ],
          phaseAnalyses: [
            'Respiratory instability detected with early gas-exchange decline.',
            'Pattern recognition shows recurrent SpO2 fluctuation every 30 minutes with hemodynamic strain.',
            'Critical respiratory trajectory with competing renal lab discordance requiring redraw confirmation.',
          ],
          labProfiles: [
            {'WBC': 10.4, 'Lactate': 1.5, 'Creatinine': 1.0, 'PCT': 0.7},
            {'WBC': 13.1, 'Lactate': 2.2, 'Creatinine': 1.0, 'PCT': 1.8},
            {'WBC': 16.3, 'Lactate': 3.3, 'Creatinine': 1.0, 'PCT': 3.0},
          ],
          complications: [
            _ComplicationSeed(
              title: 'Respiratory Distress',
              timeframe: '2-4 hours',
              baseRisk: 56,
            ),
            _ComplicationSeed(
              title: 'Septic Shock',
              timeframe: '6-10 hours',
              baseRisk: 30,
            ),
            _ComplicationSeed(
              title: 'Cardiac Arrhythmia',
              timeframe: '8-12 hours',
              baseRisk: 34,
            ),
          ],
        );
      default:
        return const _DiagnosticScenario(
          phaseTitles: [
            'Post-Trauma Stabilization',
            'Observation Window',
            'Current Bedside State',
          ],
          phaseSeverities: ['normal', 'normal', 'normal'],
          phaseNotes: [
            'Initial trauma survey completed with stable hemodynamics and preserved neurologic status.',
            'Observation period remained stable without new organ dysfunction features.',
            'Current bedside review remains reassuring with no major deterioration pattern.',
          ],
          phaseAnalyses: [
            'Low-risk baseline established.',
            'No meaningful multi-parameter deterioration trend detected.',
            'Continue routine trauma observation and reassessment.',
          ],
          labProfiles: [
            {'WBC': 8.6, 'Lactate': 1.2, 'Creatinine': 0.8, 'PCT': 0.2},
            {'WBC': 8.9, 'Lactate': 1.1, 'Creatinine': 0.8, 'PCT': 0.2},
            {'WBC': 9.1, 'Lactate': 1.0, 'Creatinine': 0.9, 'PCT': 0.3},
          ],
          complications: [
            _ComplicationSeed(
              title: 'Secondary Bleeding',
              timeframe: '12-24 hours',
              baseRisk: 14,
            ),
            _ComplicationSeed(
              title: 'Respiratory Deterioration',
              timeframe: '12-24 hours',
              baseRisk: 12,
            ),
            _ComplicationSeed(
              title: 'Infection',
              timeframe: '24-48 hours',
              baseRisk: 10,
            ),
          ],
        );
    }
  }

  void dispose() {
    _client.close();
  }

  PredictionResult _fallbackPrediction(PatientReading patient) {
    final hr = patient.vitals['HR'] ?? 0;
    final bpSys = patient.vitals['BP_sys'] ?? 0;
    final temp = patient.vitals['Temp'] ?? 0;
    final spo2 = patient.vitals['SpO2'] ?? 0;
    final resp = patient.vitals['Resp'] ?? 0;
    final gcs = patient.vitals['GCS'] ?? 15;

    double risk = 0.15;
    final reasons = <String>[];
    final actions = <String>[];

    if (spo2 < 92) {
      risk += 0.28;
      reasons.add('Oxygen saturation is low at ${spo2.toStringAsFixed(0)}');
      actions.add(
        'Check airway patency, oxygen delivery, and probe placement.',
      );
    }
    if (resp > 24) {
      risk += 0.24;
      reasons.add('Respiratory rate is high at ${resp.toStringAsFixed(0)}');
      actions.add('Review respiratory effort and ventilatory support.');
    }
    if (hr > 115) {
      risk += 0.18;
      reasons.add('Heart rate is high at ${hr.toStringAsFixed(0)}');
      actions.add(
        'Assess pain, rhythm change, bleeding, and medication effects.',
      );
    }
    if (bpSys < 90) {
      risk += 0.15;
      reasons.add(
        'Systolic blood pressure is low at ${bpSys.toStringAsFixed(0)}',
      );
      actions.add('Review perfusion, fluids, and vasopressor requirements.');
    }
    if (temp > 38.4) {
      risk += 0.12;
      reasons.add('Temperature is high at ${temp.toStringAsFixed(1)}');
      actions.add('Evaluate infection and inflammatory burden.');
    }
    if (gcs < 13) {
      risk += 0.18;
      reasons.add('GCS has dropped to ${gcs.toStringAsFixed(0)}');
      actions.add(
        'Review neurological status, sedation, and airway protection.',
      );
    }
    if (gcs <= 8) {
      risk += 0.16;
      reasons.add('GCS is critically low at ${gcs.toStringAsFixed(0)}');
      actions.add('Urgent neurologic assessment and airway review are needed.');
    }

    final score = risk.clamp(0.05, 0.98);
    final level = score >= 0.65
        ? 'CRITICAL'
        : score >= 0.35
        ? 'WARNING'
        : 'SAFE';

    return PredictionResult(
      riskScore: score,
      riskLevel: level,
      alert: level != 'SAFE',
      sequenceReady: false,
      bufferFill: 0,
      doctorMessage:
          'Demo mode: patient ${patient.id} is $level with risk ${(score * 100).toStringAsFixed(0)}%.',
      topReasons: reasons.isEmpty
          ? ['Patient is stable in demo mode.']
          : reasons,
      recommendedActions: actions.isEmpty
          ? ['Continue routine ICU observation.']
          : actions,
      componentScores: {'demo_mode_score': score},
      timestamp: patient.lastUpdated,
    );
  }

  _PatientBatchSnapshot _preparePatients({bool forceAdvance = false}) {
    _ensureSimulationState();
    final currentPatients = _simulatedPatients!;
    final readyCount = currentPatients.where((patient) {
      return patient.prediction != null;
    }).length;

    if (_lastSimulationAt == null && !forceAdvance) {
      _lastSimulationAt = DateTime.now();
      return _PatientBatchSnapshot(
        patients: currentPatients,
        advanced: false,
        allPredictionsReady: readyCount == currentPatients.length,
      );
    }

    if (!_shouldAdvanceSimulation(forceAdvance: forceAdvance)) {
      return _PatientBatchSnapshot(
        patients: currentPatients,
        advanced: false,
        allPredictionsReady: readyCount == currentPatients.length,
      );
    }

    _simulationTick += 1;
    final advancedPatients = currentPatients
        .map((patient) => _advancePatient(patient, _simulationTick))
        .toList(growable: false);
    _simulatedPatients = advancedPatients;
    _diagnosticReports.clear();
    _lastSimulationAt = DateTime.now();

    return _PatientBatchSnapshot(
      patients: advancedPatients,
      advanced: true,
      allPredictionsReady: false,
    );
  }

  void _ensureSimulationState() {
    if (_simulatedPatients != null && _baselineVitals != null) {
      return;
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final seededPatients = _buildDemoPatients()
        .map((patient) => patient.copyWith(lastUpdated: nowIso))
        .toList(growable: false);

    _simulatedPatients = seededPatients;
    _baselineVitals = {
      for (final patient in seededPatients)
        patient.id: Map<String, double>.from(patient.vitals),
    };
  }

  bool _shouldAdvanceSimulation({bool forceAdvance = false}) {
    if (forceAdvance) {
      return true;
    }
    final lastSimulationAt = _lastSimulationAt;
    if (lastSimulationAt == null) {
      return false;
    }
    return DateTime.now().difference(lastSimulationAt) >= _simulationCadence;
  }

  PatientReading _advancePatient(PatientReading patient, int tick) {
    final baseline = _baselineVitals![patient.id]!;
    final profile = _profileForPatient(patient.id);
    final phase = tick + _phaseOffset(patient.id);

    final nextHr = _nextVital(
      current: patient.vitals['HR'] ?? baseline['HR'] ?? 0,
      baseline: baseline['HR'] ?? 0,
      drift: profile.hrDrift,
      oscillation: math.sin(phase * 0.62) * profile.variability,
      min: 58,
      max: 165,
      reversion: profile.reversion,
    );
    final nextBpSys = _nextVital(
      current: patient.vitals['BP_sys'] ?? baseline['BP_sys'] ?? 0,
      baseline: baseline['BP_sys'] ?? 0,
      drift: profile.bpSysDrift,
      oscillation: math.cos(phase * 0.54) * profile.variability * 1.3,
      min: 70,
      max: 155,
      reversion: profile.reversion,
    );
    final nextBpDia = _nextVital(
      current: patient.vitals['BP_dia'] ?? baseline['BP_dia'] ?? 0,
      baseline: baseline['BP_dia'] ?? 0,
      drift: profile.bpDiaDrift,
      oscillation: math.sin(phase * 0.47) * profile.variability,
      min: 40,
      max: 105,
      reversion: profile.reversion,
    );
    final nextTemp = _nextVital(
      current: patient.vitals['Temp'] ?? baseline['Temp'] ?? 0,
      baseline: baseline['Temp'] ?? 0,
      drift: profile.tempDrift,
      oscillation: math.cos(phase * 0.28) * profile.variability * 0.03,
      min: 35.4,
      max: 40.8,
      reversion: profile.reversion,
    );
    final nextSpo2 = _nextVital(
      current: patient.vitals['SpO2'] ?? baseline['SpO2'] ?? 0,
      baseline: baseline['SpO2'] ?? 0,
      drift: profile.spo2Drift,
      oscillation: math.sin(phase * 0.51) * profile.variability * 0.25,
      min: 84,
      max: 100,
      reversion: profile.reversion,
    );
    final nextResp = _nextVital(
      current: patient.vitals['Resp'] ?? baseline['Resp'] ?? 0,
      baseline: baseline['Resp'] ?? 0,
      drift: profile.respDrift,
      oscillation: math.cos(phase * 0.58) * profile.variability * 0.5,
      min: 10,
      max: 38,
      reversion: profile.reversion,
    );
    final nextGcs = _nextVital(
      current: patient.vitals['GCS'] ?? baseline['GCS'] ?? 15,
      baseline: baseline['GCS'] ?? 15,
      drift: profile.gcsDrift,
      oscillation: math.sin(phase * 0.34) * profile.variability * 0.08,
      min: 3,
      max: 15,
      reversion: profile.reversion,
    ).roundToDouble();

    final updatedVitals = <String, double>{
      'HR': nextHr,
      'BP_sys': nextBpSys,
      'BP_dia': nextBpDia,
      'Temp': nextTemp,
      'SpO2': nextSpo2,
      'Resp': nextResp,
      'GCS': nextGcs,
    };

    return patient.copyWith(
      lastUpdated: DateTime.now().toUtc().toIso8601String(),
      vitals: updatedVitals,
      hrTrend: _appendMetricPoint(patient.hrTrend, nextHr),
      bpTrend: _appendMetricPoint(patient.bpTrend, nextBpSys),
      tempTrend: _appendMetricPoint(patient.tempTrend, nextTemp),
      spo2Trend: _appendMetricPoint(patient.spo2Trend, nextSpo2),
      gcsTrend: _appendMetricPoint(patient.gcsTrend, nextGcs),
    );
  }

  double _nextVital({
    required double current,
    required double baseline,
    required double drift,
    required double oscillation,
    required double min,
    required double max,
    required double reversion,
  }) {
    final nextValue =
        current + drift + oscillation + ((baseline - current) * reversion);
    return nextValue.clamp(min, max).toDouble();
  }

  List<PatientReading> _mergePredictions(
    List<PatientReading> patients,
    Map<String, PredictionResult> predictions, {
    required bool appendRiskPoint,
  }) {
    return patients
        .map((patient) {
          final prediction =
              predictions[patient.id] ??
              patient.prediction ??
              _fallbackPrediction(patient);
          return patient.copyWith(
            prediction: prediction,
            riskTrend: appendRiskPoint
                ? _appendMetricPoint(patient.riskTrend, prediction.riskScore)
                : patient.riskTrend,
          );
        })
        .toList(growable: false);
  }

  List<double> _appendMetricPoint(List<double> trend, double newValue) {
    final values = List<double>.from(trend);
    values.add(newValue);
    if (values.length > 10) {
      values.removeAt(0);
    }
    return values;
  }

  double _phaseOffset(String patientId) {
    final seed = patientId.codeUnits.fold<int>(0, (sum, value) => sum + value);
    return (seed % 9) / 3;
  }

  _PatientTrajectory _profileForPatient(String patientId) {
    switch (patientId) {
      case 'ICU-101':
        return const _PatientTrajectory(
          hrDrift: 1.1,
          bpSysDrift: -0.95,
          bpDiaDrift: -0.55,
          tempDrift: 0.05,
          spo2Drift: -0.15,
          respDrift: 0.42,
          gcsDrift: -0.08,
          variability: 1.0,
          reversion: 0.08,
        );
      case 'ICU-102':
        return const _PatientTrajectory(
          hrDrift: 0.5,
          bpSysDrift: -0.22,
          bpDiaDrift: -0.1,
          tempDrift: 0.03,
          spo2Drift: -0.06,
          respDrift: 0.22,
          gcsDrift: -0.03,
          variability: 0.65,
          reversion: 0.13,
        );
      case 'ICU-103':
        return const _PatientTrajectory(
          hrDrift: 0.95,
          bpSysDrift: -0.72,
          bpDiaDrift: -0.45,
          tempDrift: 0.02,
          spo2Drift: -0.18,
          respDrift: 0.48,
          gcsDrift: -0.05,
          variability: 1.05,
          reversion: 0.09,
        );
      case 'ICU-104':
        return const _PatientTrajectory(
          hrDrift: 0.08,
          bpSysDrift: -0.04,
          bpDiaDrift: -0.03,
          tempDrift: 0.01,
          spo2Drift: -0.02,
          respDrift: 0.05,
          gcsDrift: 0,
          variability: 0.32,
          reversion: 0.2,
        );
      default:
        return const _PatientTrajectory(
          hrDrift: 0.1,
          bpSysDrift: 0,
          bpDiaDrift: 0,
          tempDrift: 0,
          spo2Drift: 0,
          respDrift: 0.05,
          gcsDrift: 0,
          variability: 0.45,
          reversion: 0.16,
        );
    }
  }

  List<PatientReading> _buildDemoPatients() {
    return const [
      PatientReading(
        id: 'ICU-101',
        name: 'Rohan Kumar',
        age: 58,
        bedLabel: 'ICU-101',
        diagnosis: 'Post-Cardiac Surgery',
        lastUpdated: '2026-04-03T10:15:00Z',
        vitals: {
          'HR': 126,
          'BP_sys': 88,
          'BP_dia': 52,
          'Temp': 38.9,
          'SpO2': 90,
          'Resp': 28,
          'GCS': 13,
        },
        hrTrend: [95, 101, 108, 114, 118, 123, 126],
        bpTrend: [125, 118, 112, 104, 98, 93, 88],
        tempTrend: [38.2, 38.4, 38.5, 38.7, 38.8, 38.9, 38.9],
        spo2Trend: [97, 96, 95, 94, 93, 91, 90],
        gcsTrend: [15, 15, 14, 14, 13, 13, 13],
        riskTrend: [0.34, 0.41, 0.48, 0.59, 0.68, 0.79, 0.87],
      ),
      PatientReading(
        id: 'ICU-102',
        name: 'Sahil Mishra',
        age: 45,
        bedLabel: 'ICU-102',
        diagnosis: 'Sepsis',
        lastUpdated: '2026-04-03T10:15:00Z',
        vitals: {
          'HR': 108,
          'BP_sys': 99,
          'BP_dia': 64,
          'Temp': 38.1,
          'SpO2': 94,
          'Resp': 24,
          'GCS': 14,
        },
        hrTrend: [92, 95, 97, 100, 103, 106, 108],
        bpTrend: [112, 109, 106, 104, 102, 100, 99],
        tempTrend: [37.5, 37.6, 37.7, 37.8, 37.9, 38.0, 38.1],
        spo2Trend: [97, 96, 96, 95, 95, 94, 94],
        gcsTrend: [15, 15, 15, 14, 14, 14, 14],
        riskTrend: [0.28, 0.31, 0.35, 0.4, 0.46, 0.51, 0.58],
      ),
      PatientReading(
        id: 'ICU-103',
        name: 'Riya Mukherjee',
        age: 62,
        bedLabel: 'ICU-103',
        diagnosis: 'Respiratory Failure',
        lastUpdated: '2026-04-03T10:15:00Z',
        vitals: {
          'HR': 121,
          'BP_sys': 92,
          'BP_dia': 58,
          'Temp': 37.8,
          'SpO2': 89,
          'Resp': 30,
          'GCS': 12,
        },
        hrTrend: [102, 106, 110, 113, 116, 119, 121],
        bpTrend: [110, 106, 102, 99, 97, 95, 92],
        tempTrend: [37.0, 37.1, 37.2, 37.4, 37.5, 37.7, 37.8],
        spo2Trend: [95, 94, 93, 92, 91, 90, 89],
        gcsTrend: [15, 15, 14, 14, 13, 13, 12],
        riskTrend: [0.32, 0.37, 0.44, 0.51, 0.58, 0.66, 0.74],
      ),
      PatientReading(
        id: 'ICU-104',
        name: 'Rani Yadav',
        age: 34,
        bedLabel: 'ICU-104',
        diagnosis: 'Trauma',
        lastUpdated: '2026-04-03T10:15:00Z',
        vitals: {
          'HR': 94,
          'BP_sys': 116,
          'BP_dia': 74,
          'Temp': 37.0,
          'SpO2': 98,
          'Resp': 18,
          'GCS': 15,
        },
        hrTrend: [88, 89, 90, 92, 93, 94, 94],
        bpTrend: [118, 118, 117, 117, 116, 116, 116],
        tempTrend: [36.7, 36.8, 36.9, 36.9, 37.0, 37.0, 37.0],
        spo2Trend: [98, 99, 98, 98, 98, 98, 98],
        gcsTrend: [15, 15, 15, 15, 15, 15, 15],
        riskTrend: [0.1, 0.11, 0.12, 0.14, 0.15, 0.16, 0.17],
      ),
    ];
  }
}

class _PatientBatchSnapshot {
  const _PatientBatchSnapshot({
    required this.patients,
    required this.advanced,
    required this.allPredictionsReady,
  });

  final List<PatientReading> patients;
  final bool advanced;
  final bool allPredictionsReady;
}

class _PatientTrajectory {
  const _PatientTrajectory({
    required this.hrDrift,
    required this.bpSysDrift,
    required this.bpDiaDrift,
    required this.tempDrift,
    required this.spo2Drift,
    required this.respDrift,
    required this.gcsDrift,
    required this.variability,
    required this.reversion,
  });

  final double hrDrift;
  final double bpSysDrift;
  final double bpDiaDrift;
  final double tempDrift;
  final double spo2Drift;
  final double respDrift;
  final double gcsDrift;
  final double variability;
  final double reversion;
}

class _DiagnosticScenario {
  const _DiagnosticScenario({
    required this.phaseTitles,
    required this.phaseSeverities,
    required this.phaseNotes,
    required this.phaseAnalyses,
    required this.labProfiles,
    required this.complications,
  });

  final List<String> phaseTitles;
  final List<String> phaseSeverities;
  final List<String> phaseNotes;
  final List<String> phaseAnalyses;
  final List<Map<String, double>> labProfiles;
  final List<_ComplicationSeed> complications;
}

class _ComplicationSeed {
  const _ComplicationSeed({
    required this.title,
    required this.timeframe,
    required this.baseRisk,
  });

  final String title;
  final String timeframe;
  final int baseRisk;
}

class _FallbackCitation {
  const _FallbackCitation({
    required this.id,
    required this.title,
    required this.organization,
    required this.year,
    required this.url,
    required this.summary,
  });

  final String id;
  final String title;
  final String organization;
  final int year;
  final String url;
  final String summary;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'organization': organization,
      'year': year,
      'url': url,
      'summary': summary,
      'support_points': [summary],
      'matched_terms': const <String>[],
    };
  }
}
