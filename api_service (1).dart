import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class ApiService {
  ApiService({String? baseUrl})
    : _baseUrl = _normalizeBaseUrl(baseUrl ?? _resolveBaseUrl()),
      _client = http.Client();

  String _baseUrl;
  final http.Client _client;
  bool _backendAvailable = false;
  bool _doctorBackendAvailable = false;
  DateTime? _lastSyncAt;
  List<PatientReading>? _simulatedPatients;
  Map<String, Map<String, double>>? _baselineVitals;
  DateTime? _lastSimulationAt;
  int _simulationTick = 0;
  Future<List<PatientReading>>? _dashboardRequest;
  final Map<String, DiagnosticReport> _diagnosticReports = {};
  final Map<String, Future<DiagnosticReport>> _diagnosticRequests = {};
  final Map<String, DoctorPatientCase> _doctorCasesById = {};

  static const Duration _simulationCadence = Duration(seconds: 4);

  String get baseUrl => _baseUrl;
  bool get backendAvailable => _backendAvailable;
  bool get doctorBackendAvailable => _doctorBackendAvailable;
  bool get demoMode => !_backendAvailable;
  DateTime? get lastSyncAt => _lastSyncAt;
  static String get defaultBaseUrl => _normalizeBaseUrl(_resolveBaseUrl());

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

  static String _normalizeBaseUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      normalized = _resolveBaseUrl();
    }
    if (!normalized.contains('://')) {
      normalized = 'http://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  void setBaseUrl(String value) {
    final normalized = _normalizeBaseUrl(value);
    if (normalized == _baseUrl) {
      return;
    }

    _baseUrl = normalized;
    _backendAvailable = false;
    _doctorBackendAvailable = false;
    _lastSyncAt = null;
    _dashboardRequest = null;
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
    final doctorPatients = await _fetchDoctorDashboardPatients();

    if (!snapshot.advanced && snapshot.allPredictionsReady) {
      return _mergeDashboardFeeds(snapshot.patients, doctorPatients);
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
      return _mergeDashboardFeeds(updatedPatients, doctorPatients);
    } catch (_) {
      _backendAvailable = doctorPatients.isNotEmpty;
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
      return _mergeDashboardFeeds(fallbackPatients, doctorPatients);
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

    final future = _fetchDiagnosticReport(patient, forceRefresh: forceRefresh);
    _diagnosticRequests[patient.id] = future;
    return future.whenComplete(() {
      if (identical(_diagnosticRequests[patient.id], future)) {
        _diagnosticRequests.remove(patient.id);
      }
    });
  }

  Future<DiagnosticReport> _fetchDiagnosticReport(
    PatientReading patient, {
    bool forceRefresh = false,
  }) async {
    if (patient.isDoctorCase) {
      try {
        final caseRecord = await _resolveDoctorCase(
          patient.id,
          forceRefresh: forceRefresh,
        );
        final report = _diagnosticReportForDoctorCase(caseRecord);
        if (report != null) {
          _backendAvailable = true;
          _lastSyncAt = DateTime.now();
          _diagnosticReports[patient.id] = report;
          return report;
        }
      } catch (_) {}
    }

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

  Future<List<DoctorPatientCaseSummary>> fetchDoctorPatientCases() async {
    try {
      final response = await _client
          .get(_uri('/doctor/patients'))
          .timeout(const Duration(seconds: 8));

      final payload = _decodeOkPayload(response);
      final items = payload['cases'] as List<dynamic>? ?? const [];
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      return items
          .map(
            (item) =>
                DoctorPatientCaseSummary.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      if (_isConnectivityError(error)) {
        _backendAvailable = false;
        _doctorBackendAvailable = false;
        return _cachedDoctorCaseSummaries();
      }
      throw Exception(
        _errorMessage(error, fallback: 'Unable to load doctor patient cases.'),
      );
    }
  }

  Future<DoctorPatientCase> createDoctorPatientCase({
    required String clinicianName,
    required String doctorSpecialty,
    required String patientId,
    required String patientName,
    required int age,
    required String sex,
    required String bedLabel,
    required String diagnosis,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('/doctor/patients'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'patient_id': patientId,
              'doctor': {'name': clinicianName, 'specialty': doctorSpecialty},
              'patient': {
                'name': patientName,
                'age': age,
                'sex': sex,
                'bed_label': bedLabel,
                'diagnosis': diagnosis,
              },
            }),
          )
          .timeout(const Duration(seconds: 8));

      final payload = _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      final caseRecord = DoctorPatientCase.fromEnvelope(payload);
      _rememberDoctorCase(caseRecord);
      return caseRecord;
    } catch (error) {
      if (_isConnectivityError(error)) {
        _doctorBackendAvailable = false;
      }
      throw Exception(
        _errorMessage(error, fallback: 'Unable to create doctor patient case.'),
      );
    }
  }

  Future<DoctorPatientCase> importDoctorPatientCase(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _client
          .post(
            _uri('/doctor/patients'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));

      final decoded = _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      final caseRecord = DoctorPatientCase.fromEnvelope(decoded);
      _rememberDoctorCase(caseRecord);
      return caseRecord;
    } catch (error) {
      if (_isConnectivityError(error)) {
        _doctorBackendAvailable = false;
      }
      throw Exception(
        _errorMessage(
          error,
          fallback: 'Unable to import the structured patient JSON case.',
        ),
      );
    }
  }

  Future<DoctorPatientCase> fetchDoctorPatientCase(String patientId) async {
    try {
      final response = await _client
          .get(_uri('/doctor/patients/$patientId'))
          .timeout(const Duration(seconds: 8));

      final payload = _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      final caseRecord = DoctorPatientCase.fromEnvelope(payload);
      _rememberDoctorCase(caseRecord);
      return caseRecord;
    } catch (error) {
      if (_isConnectivityError(error)) {
        _backendAvailable = false;
        _doctorBackendAvailable = false;
        final cached = _doctorCasesById[patientId];
        if (cached != null) {
          return cached;
        }
      }
      throw Exception(
        _errorMessage(
          error,
          fallback: 'Unable to load the selected patient case.',
        ),
      );
    }
  }

  Future<DoctorPatientCase> uploadDoctorDocuments(
    String patientId,
    List<DoctorDocumentDraft> documents, {
    bool analyzeNow = true,
  }) async {
    try {
      final response = await _client
          .post(
            _uri('/doctor/patients/$patientId/documents?analyze=$analyzeNow'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'documents': documents.map((item) => item.toJson()).toList(),
              'analyze_now': analyzeNow,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final payload = _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      final caseRecord = DoctorPatientCase.fromEnvelope(payload);
      _rememberDoctorCase(caseRecord);
      return caseRecord;
    } catch (error) {
      if (_isConnectivityError(error)) {
        _doctorBackendAvailable = false;
      }
      throw Exception(
        _errorMessage(error, fallback: 'Unable to upload doctor documents.'),
      );
    }
  }

  Future<DoctorPatientCase> uploadDoctorDocumentFile(
    String patientId, {
    required Uint8List fileBytes,
    required String fileName,
    required String documentType,
    required String title,
    String? mimeType,
    String? timestamp,
    String? author,
    String? specialty,
    String? content,
    bool analyzeNow = true,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        _uri('/doctor/patients/$patientId/documents?analyze=$analyzeNow'),
      );
      request.fields['document_type'] = documentType;
      request.fields['title'] = title;
      request.fields['analyze_now'] = '$analyzeNow';
      if (timestamp != null && timestamp.isNotEmpty) {
        request.fields['timestamp'] = timestamp;
      }
      if (author != null && author.isNotEmpty) {
        request.fields['author'] = author;
      }
      if (specialty != null && specialty.isNotEmpty) {
        request.fields['specialty'] = specialty;
      }
      if (content != null && content.trim().isNotEmpty) {
        request.fields['content'] = content.trim();
      }

      final multipartFile = http.MultipartFile.fromBytes(
        'files',
        fileBytes,
        filename: fileName,
      );
      request.files.add(multipartFile);
      if (mimeType != null && mimeType.isNotEmpty) {
        request.fields['mime_type'] = mimeType;
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 18),
      );
      final response = await http.Response.fromStream(streamed);
      final payload = _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      final caseRecord = DoctorPatientCase.fromEnvelope(payload);
      _rememberDoctorCase(caseRecord);
      return caseRecord;
    } catch (error) {
      if (_isConnectivityError(error)) {
        _doctorBackendAvailable = false;
      }
      throw Exception(
        _errorMessage(
          error,
          fallback: 'Unable to upload doctor image document.',
        ),
      );
    }
  }

  Future<DoctorPatientCase> analyzeDoctorPatientCase(String patientId) async {
    try {
      final response = await _client
          .post(_uri('/doctor/patients/$patientId/analyze'))
          .timeout(const Duration(seconds: 10));

      final payload = _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      try {
        return await fetchDoctorPatientCase(patientId);
      } catch (_) {
        final caseRecord = DoctorPatientCase.fromEnvelope(payload);
        _rememberDoctorCase(caseRecord);
        return caseRecord;
      }
    } catch (error) {
      if (_isConnectivityError(error)) {
        _doctorBackendAvailable = false;
      }
      throw Exception(
        _errorMessage(
          error,
          fallback: 'Unable to analyze the selected patient case.',
        ),
      );
    }
  }

  Future<void> deleteDoctorPatientCase(String patientId) async {
    try {
      final response = await _client
          .delete(_uri('/doctor/patients/$patientId'))
          .timeout(const Duration(seconds: 8));

      _decodeOkPayload(response);
      _backendAvailable = true;
      _doctorBackendAvailable = true;
      _lastSyncAt = DateTime.now();
      _forgetDoctorCase(patientId);
    } catch (error) {
      if (_isConnectivityError(error)) {
        _doctorBackendAvailable = false;
      }
      throw Exception(
        _errorMessage(
          error,
          fallback: 'Unable to delete the selected patient case.',
        ),
      );
    }
  }

  void _rememberDoctorCase(DoctorPatientCase caseRecord) {
    _doctorCasesById[caseRecord.patientId] = caseRecord;
    final report = _diagnosticReportForDoctorCase(caseRecord);
    if (report != null) {
      _diagnosticReports[caseRecord.patientId] = report;
    }
  }

  void _forgetDoctorCase(String patientId) {
    _doctorCasesById.remove(patientId);
    _diagnosticReports.remove(patientId);
    _diagnosticRequests.remove(patientId);
    _dashboardRequest = null;
  }

  List<DoctorPatientCaseSummary> _cachedDoctorCaseSummaries() {
    final summaries = _doctorCasesById.values
        .map((caseRecord) => caseRecord.summary)
        .toList(growable: false);
    final sorted = [...summaries];
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  Future<List<PatientReading>> _fetchDoctorDashboardPatients() async {
    try {
      final summaries = await fetchDoctorPatientCases();
      if (summaries.isEmpty) {
        return const [];
      }

      final readings = <PatientReading>[];
      for (final summary in summaries) {
        var detail = _doctorCasesById[summary.patientId];
        if (detail == null || detail.updatedAt != summary.updatedAt) {
          try {
            detail = await fetchDoctorPatientCase(summary.patientId);
          } catch (_) {}
        }
        if (detail != null) {
          readings.add(_doctorCaseToPatientReading(detail));
        }
      }

      if (readings.isNotEmpty) {
        _backendAvailable = true;
        _lastSyncAt = DateTime.now();
      }
      return readings;
    } catch (_) {
      return const [];
    }
  }

  Future<DoctorPatientCase> _resolveDoctorCase(
    String patientId, {
    bool forceRefresh = false,
  }) async {
    final cached = _doctorCasesById[patientId];
    if (!forceRefresh && cached != null) {
      return cached;
    }

    if (forceRefresh) {
      try {
        final analyzed = await analyzeDoctorPatientCase(patientId);
        _rememberDoctorCase(analyzed);
        return analyzed;
      } catch (_) {
        if (cached != null && cached.latestReport != null) {
          return cached;
        }
      }
    }

    final detail = await fetchDoctorPatientCase(patientId);
    _rememberDoctorCase(detail);
    return detail;
  }

  List<PatientReading> _mergeDashboardFeeds(
    List<PatientReading> baseline,
    List<PatientReading> doctorCases,
  ) {
    if (doctorCases.isEmpty) {
      return baseline;
    }
    final doctorIds = doctorCases.map((patient) => patient.id).toSet();
    return [
      ...doctorCases,
      ...baseline.where((patient) => !doctorIds.contains(patient.id)),
    ];
  }

  PatientReading _doctorCaseToPatientReading(DoctorPatientCase caseRecord) {
    final latestVitals = _doctorLatestVitals(caseRecord);
    final snapshotCount = math.max(3, caseRecord.vitals.length);
    final probability =
        caseRecord.latestReport?.probability ??
        _riskProbabilityFromLevel(caseRecord.overallRiskLevel);

    return PatientReading(
      id: caseRecord.patientId,
      name: caseRecord.patient.name,
      age: caseRecord.patient.age,
      bedLabel: caseRecord.patient.bedLabel.isEmpty
          ? caseRecord.patientId
          : caseRecord.patient.bedLabel,
      diagnosis: caseRecord.patient.diagnosis,
      lastUpdated: caseRecord.updatedAt,
      vitals: latestVitals,
      hrTrend: _doctorTrend(
        caseRecord,
        'HR',
        fallback: latestVitals['HR'] ?? 80,
      ),
      bpTrend: _doctorTrend(
        caseRecord,
        'BP_sys',
        fallback: latestVitals['BP_sys'] ?? 115,
      ),
      tempTrend: _doctorTrend(
        caseRecord,
        'Temp',
        fallback: latestVitals['Temp'] ?? 36.9,
      ),
      spo2Trend: _doctorTrend(
        caseRecord,
        'SpO2',
        fallback: latestVitals['SpO2'] ?? 98,
      ),
      gcsTrend: _doctorTrend(caseRecord, 'GCS', fallback: 15),
      riskTrend: List<double>.generate(snapshotCount, (index) {
        final fraction = snapshotCount <= 1 ? 1.0 : (index + 1) / snapshotCount;
        return (probability * (0.55 + (0.45 * fraction)))
            .clamp(0.0, 1.0)
            .toDouble();
      }),
      sourceType: 'doctor_case',
      prediction: _predictionFromDoctorCase(caseRecord),
    );
  }

  Map<String, double> _doctorLatestVitals(DoctorPatientCase caseRecord) {
    final latest = <String, double>{
      'HR': 80,
      'BP_sys': 115,
      'BP_dia': 75,
      'Temp': 36.9,
      'SpO2': 98,
      'Resp': 16,
      'GCS': 15,
    };
    final reportVitals = caseRecord.latestReport?.latestVitals;
    if (reportVitals != null) {
      latest.addAll(reportVitals);
    }
    if (caseRecord.vitals.isNotEmpty) {
      final sorted = [...caseRecord.vitals]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      latest.addAll(sorted.last.values);
    }
    return latest;
  }

  List<double> _doctorTrend(
    DoctorPatientCase caseRecord,
    String key, {
    required double fallback,
  }) {
    final values = [...caseRecord.vitals]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final trend = values
        .map((snapshot) => snapshot.values[key])
        .whereType<double>()
        .toList(growable: false);
    if (trend.isEmpty) {
      return List<double>.filled(3, fallback);
    }
    return trend;
  }

  PredictionResult _predictionFromDoctorCase(DoctorPatientCase caseRecord) {
    final report = caseRecord.latestReport;
    final riskScore =
        report?.probability ??
        _riskProbabilityFromLevel(caseRecord.overallRiskLevel);
    final riskLevel =
        report?.overallRiskLevel ?? caseRecord.overallRiskLevel ?? 'LOW';
    final evidence =
        report?.flaggedRisks
            .expand((item) => item.supportingEvidence)
            .take(3)
            .toList() ??
        const <String>[];

    return PredictionResult(
      riskScore: riskScore,
      riskLevel: riskLevel,
      alert: riskScore >= 0.65 || {'CRITICAL', 'HIGH'}.contains(riskLevel),
      sequenceReady: caseRecord.vitals.isNotEmpty,
      bufferFill: caseRecord.vitals.length,
      doctorMessage:
          report?.primaryConcern ??
          caseRecord.primaryConcern ??
          'Structured doctor case imported and ready for review.',
      topReasons: evidence.isNotEmpty ? evidence : report?.evidence ?? const [],
      recommendedActions: report?.recommendedActions ?? const [],
      componentScores:
          report?.explainability.modelComponents ?? const <String, double>{},
      timestamp: report?.generatedAt ?? caseRecord.updatedAt,
    );
  }

  DiagnosticReport? _diagnosticReportForDoctorCase(
    DoctorPatientCase caseRecord,
  ) {
    final report = caseRecord.latestReport;
    if (report == null) {
      return null;
    }
    return report.withContext(_buildDoctorCaseContext(caseRecord, report));
  }

  DiagnosticCaseContext _buildDoctorCaseContext(
    DoctorPatientCase caseRecord,
    DiagnosticReport report,
  ) {
    final snapshots = [...caseRecord.vitals]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final selected = snapshots.length <= 3
        ? snapshots
        : snapshots.sublist(snapshots.length - 3);
    final labs = [...caseRecord.labs]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final notes = [...caseRecord.notes]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final timelineSnapshots = <DiagnosticTimelineSnapshot>[];
    final labState = <String, double>{};
    var labIndex = 0;

    for (var index = 0; index < selected.length; index++) {
      final snapshot = selected[index];
      while (labIndex < labs.length &&
          labs[labIndex].timestamp.compareTo(snapshot.timestamp) <= 0) {
        labState[labs[labIndex].name] = labs[labIndex].value;
        labIndex += 1;
      }

      var noteText = report.primaryConcern;
      for (final note in notes) {
        if (note.timestamp.compareTo(snapshot.timestamp) <= 0) {
          noteText = note.text;
        }
      }

      timelineSnapshots.add(
        DiagnosticTimelineSnapshot(
          title: index == selected.length - 1
              ? 'Latest Deterioration Snapshot'
              : 'Clinical Snapshot ${index + 1}',
          timestamp: snapshot.timestamp,
          severityLabel: index == selected.length - 1
              ? report.overallRiskLevel.toLowerCase()
              : 'warning',
          clinicalNote: noteText,
          vitals: {
            'HR': snapshot.values['HR'] ?? 0,
            'BP_sys': snapshot.values['BP_sys'] ?? 0,
            'BP_dia': snapshot.values['BP_dia'] ?? 0,
            'Temp': snapshot.values['Temp'] ?? 0,
            'SpO2': snapshot.values['SpO2'] ?? 0,
            'Resp': snapshot.values['Resp'] ?? 0,
            'GCS': snapshot.values['GCS'] ?? 15,
          },
          labs: Map<String, double>.from(labState),
          aiAnalysis: index == selected.length - 1
              ? report.chiefSummary
              : report.flaggedRisks.isNotEmpty
              ? report.flaggedRisks.first.summary
              : report.primaryConcern,
        ),
      );
    }

    if (timelineSnapshots.isEmpty) {
      timelineSnapshots.add(
        DiagnosticTimelineSnapshot(
          title: 'Imported Structured Case',
          timestamp: caseRecord.updatedAt,
          severityLabel: report.overallRiskLevel.toLowerCase(),
          clinicalNote: notes.isNotEmpty
              ? notes.last.text
              : report.primaryConcern,
          vitals: _doctorLatestVitals(caseRecord),
          labs: {for (final item in labs) item.name: item.value},
          aiAnalysis: report.chiefSummary,
        ),
      );
    }

    final complications = report.flaggedRisks
        .map(
          (item) => PredictedComplication(
            title: item.title,
            timeframe: item.level == 'CRITICAL' ? '0-6 hours' : '6-24 hours',
            confidenceLabel: item.level,
            riskPercent: (item.score * 100).round().clamp(1, 99),
          ),
        )
        .toList(growable: false);

    return DiagnosticCaseContext(
      age: caseRecord.patient.age,
      diagnosis: caseRecord.patient.diagnosis,
      timelineSnapshots: timelineSnapshots,
      predictedComplications: complications,
    );
  }

  double _riskProbabilityFromLevel(String? label) {
    switch ((label ?? '').toUpperCase()) {
      case 'CRITICAL':
        return 0.9;
      case 'HIGH':
        return 0.74;
      case 'MODERATE':
        return 0.52;
      case 'LOW':
      case 'SAFE':
        return 0.22;
      default:
        return 0.35;
    }
  }

  Map<String, dynamic> _decodeOkPayload(http.Response response) {
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || payload['ok'] == false) {
      final errorMessage =
          (payload['error'] as String?) ??
          'Unexpected status code ${response.statusCode}';
      throw Exception(errorMessage);
    }
    return payload;
  }

  String _errorMessage(Object error, {required String fallback}) {
    if (error is SocketException) {
      return 'Backend not reachable at $_baseUrl. Start the backend server or update the backend URL.';
    }
    if (error is TimeoutException) {
      return 'Backend timed out at $_baseUrl. Check connectivity or server health.';
    }
    if (error is http.ClientException) {
      final lowered = error.message.toLowerCase();
      if (lowered.contains('failed to fetch') ||
          lowered.contains('xmlhttprequest') ||
          lowered.contains('connection closed')) {
        return 'Backend not reachable at $_baseUrl. Start the backend server or update the backend URL.';
      }
      return 'Network error talking to $_baseUrl: ${error.message}';
    }
    final text = error.toString();
    return text.startsWith('Exception: ')
        ? text.substring('Exception: '.length)
        : fallback;
  }

  bool _isConnectivityError(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is http.ClientException) {
      final lowered = error.message.toLowerCase();
      return lowered.contains('failed to fetch') ||
          lowered.contains('xmlhttprequest') ||
          lowered.contains('connection closed');
    }
    return false;
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
                  'Creatinine sharply contradicts three prior days of stable results and is being treated as a probable mislabeled lab result.',
              'action':
                  'Do not revise the diagnosis from this value. Hold the current diagnosis until a confirmed redraw is received and verified.',
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
        'diagnosis_update_blocked': probableErrors.isNotEmpty,
        'blocked_reasons': probableErrors
            .map((item) => item['reason'])
            .whereType<String>()
            .toList(),
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
      'family_communication': _fallbackFamilyCommunication(
        patient,
        prediction,
        flags,
        probableErrors,
      ),
    };

    return DiagnosticReport.fromJson(reportJson).withContext(context);
  }

  Map<String, dynamic> _fallbackFamilyCommunication(
    PatientReading patient,
    PredictionResult prediction,
    List<Map<String, dynamic>> flags,
    List<Map<String, dynamic>> probableErrors,
  ) {
    final riskLevel = prediction.riskLevel == 'SAFE'
        ? 'LOW'
        : prediction.riskLevel;
    final overallTrend = _fallbackFamilyTrend(patient, prediction);
    final introEnglish = switch (riskLevel) {
      'CRITICAL' || 'HIGH' =>
        'Over the last 12 hours, your family member has remained seriously unwell, and the ICU team is monitoring them very closely.',
      'MODERATE' =>
        'Over the last 12 hours, your family member has shown some changes that need close watching, and the ICU team is actively responding.',
      _ =>
        'Over the last 12 hours, your family member has been relatively stable, but the ICU team is still watching closely.',
    };
    final introHindi = switch (riskLevel) {
      'CRITICAL' || 'HIGH' =>
        'पिछले 12 घंटों में आपके परिजन की स्थिति गंभीर बनी हुई है, और आईसीयू टीम उन पर बहुत नज़दीकी निगरानी रख रही है।',
      'MODERATE' =>
        'पिछले 12 घंटों में आपके परिजन में कुछ ऐसे बदलाव दिखे हैं जिन पर करीबी नज़र रखने की जरूरत है, और आईसीयू टीम सक्रिय रूप से देखभाल कर रही है।',
      _ =>
        'पिछले 12 घंटों में आपके परिजन की स्थिति अपेक्षाकृत स्थिर रही है, लेकिन आईसीयू टीम अभी भी बहुत नज़दीकी निगरानी कर रही है।',
    };
    final concernTitle = _fallbackConcernTitle(flags);
    final concernTitleHindi = _fallbackConcernTitleHindi(flags);
    final redrawEnglish = probableErrors.isEmpty
        ? ''
        : 'One new lab result does not match the steady pattern seen over the previous days. The team is treating it as a possible mislabeled or incorrect sample and will not change the diagnosis until a confirmed repeat test is received.';
    final redrawHindi = probableErrors.isEmpty
        ? ''
        : 'एक नया लैब परिणाम पिछले कई दिनों के स्थिर पैटर्न से मेल नहीं खाता। टीम इसे संभावित गलत लेबल या गलत सैंपल मानकर चल रही है और पुष्टि वाले दोबारा टेस्ट तक निदान में कोई बदलाव नहीं करेगी।';
    final currentConditionEnglish =
        'Right now, the main concern is $concernTitle, and the ICU team is continuing close monitoring.';
    final currentConditionHindi =
        'इस समय सबसे बड़ी चिंता $concernTitleHindi है, और आईसीयू टीम लगातार करीबी निगरानी कर रही है।';
    final trendEnglish = switch (overallTrend) {
      'worsening' =>
        'Compared with earlier today, the overall trend looks more concerning, with ongoing changes in heart rate, breathing, or blood pressure.',
      'improving' =>
        'Compared with earlier today, there are some encouraging signs, although close ICU monitoring is still needed.',
      _ =>
        'Compared with earlier today, the overall trend is fairly stable, but the team is still watching closely for any sudden change.',
    };
    final trendHindi = switch (overallTrend) {
      'worsening' =>
        'आज पहले की तुलना में कुल रुझान अधिक चिंताजनक दिख रहा है, और हृदय गति, सांस या ब्लड प्रेशर में बदलाव पर करीबी नज़र रखी जा रही है।',
      'improving' =>
        'आज पहले की तुलना में कुछ उत्साहजनक संकेत हैं, हालांकि अभी भी आईसीयू में करीबी निगरानी की जरूरत है।',
      _ =>
        'आज पहले की तुलना में कुल रुझान अपेक्षाकृत स्थिर है, लेकिन टीम किसी भी अचानक बदलाव पर करीबी नज़र रख रही है।',
    };
    final keyEventsEnglish = [
      if (patient.heartRate >= 110)
        'Heart rate has been faster than usual and is being watched closely.',
      if (patient.systolicBp > 0 && patient.systolicBp < 95)
        'Blood pressure has stayed on the lower side, so circulation is being monitored carefully.',
      if (patient.spo2 > 0 && patient.spo2 < 94)
        'Oxygen levels have needed closer watching through the last several hours.',
      if (probableErrors.isNotEmpty)
        'One lab result looked inconsistent, so the team requested a repeat sample before making any major change.',
    ];
    final keyEventsHindi = [
      if (patient.heartRate >= 110)
        'हृदय गति सामान्य से तेज रही है और उस पर करीबी नज़र रखी जा रही है।',
      if (patient.systolicBp > 0 && patient.systolicBp < 95)
        'ब्लड प्रेशर कुछ कम रहा है, इसलिए खून के प्रवाह पर सावधानी से नज़र रखी जा रही है।',
      if (patient.spo2 > 0 && patient.spo2 < 94)
        'पिछले कई घंटों में ऑक्सीजन के स्तर पर ज्यादा करीबी नज़र रखनी पड़ी है।',
      if (probableErrors.isNotEmpty)
        'एक लैब परिणाम मेल नहीं खा रहा था, इसलिए किसी बड़े बदलाव से पहले टीम ने दोबारा सैंपल मांगा है।',
    ];
    final hindiContent = {
      'label': 'Hindi',
      'code': 'hi-IN',
      'title': 'परिवार के लिए अपडेट',
      'summary':
          '$introHindi $currentConditionHindi $trendHindi ${redrawHindi.isEmpty ? "" : "$redrawHindi "}हमें पता है कि यह परिवार के लिए तनावपूर्ण समय है, और कोई महत्वपूर्ण बदलाव होने पर टीम परिवार को बताएगी।',
      'current_condition': currentConditionHindi,
      'trend': trendHindi,
      'key_events': keyEventsHindi.take(3).toList(),
      'bullets': [
        'टीम बेडसाइड रुझानों, दोबारा खून की जांच और इलाज के असर की समीक्षा कर रही है।',
        'आईसीयू टीम लगातार दोबारा जांच और सहायक देखभाल जारी रखे हुए है।',
        if (probableErrors.isNotEmpty)
          'विरोधाभासी परिणाम के आधार पर निदान बदलने से पहले दोबारा लैब सैंपल लिया जा रहा है।',
      ],
    };
    final regionalVariants = [
      hindiContent,
      _fallbackRegionalLanguageContent(
        languageKey: 'mr',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'bn',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'pa',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'gu',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'ml',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'te',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'ta',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
      _fallbackRegionalLanguageContent(
        languageKey: 'kn',
        riskLevel: riskLevel,
        overallTrend: overallTrend,
        flags: flags,
        probableErrors: probableErrors,
        patient: patient,
      ),
    ];

    return {
      'agent_role': 'Family Communication Agent',
      'lookback_hours': 12,
      'overall_trend': overallTrend,
      'diagnosis_update_blocked': probableErrors.isNotEmpty,
      'english': {
        'label': 'English',
        'code': 'en-US',
        'title': 'Family Communication Update',
        'summary':
            '$introEnglish $currentConditionEnglish $trendEnglish ${redrawEnglish.isEmpty ? "" : "$redrawEnglish "}We know this is stressful, and the team will keep updating the family if there is any important change.',
        'current_condition': currentConditionEnglish,
        'trend': trendEnglish,
        'key_events': keyEventsEnglish.take(3).toList(),
        'bullets': [
          'The team is reviewing bedside trends, repeat blood work, and response to treatment.',
          'The ICU team is continuing close reassessment and supportive care.',
          if (probableErrors.isNotEmpty)
            'A repeat lab draw is being requested before any diagnosis change is made from the conflicting result.',
        ],
      },
      'regional_language': regionalVariants.first,
      'regional_variants': regionalVariants,
      'redraw_note_english': redrawEnglish,
      'redraw_note_regional': redrawHindi,
    };
  }

  String _fallbackFamilyTrend(
    PatientReading patient,
    PredictionResult prediction,
  ) {
    final riskPoints = patient.riskTrend;
    if (riskPoints.length >= 2) {
      final delta = riskPoints.last - riskPoints.first;
      if (delta >= 0.08) {
        return 'worsening';
      }
      if (delta <= -0.08) {
        return 'improving';
      }
    }

    if (prediction.riskScore >= 0.7) {
      return 'worsening';
    }
    if (prediction.riskScore <= 0.3) {
      return 'improving';
    }
    return 'stable';
  }

  String _fallbackConcernTitle(List<Map<String, dynamic>> flags) {
    final title = flags.isNotEmpty
        ? flags.first['title']?.toString().toLowerCase() ?? ''
        : '';
    if (title.contains('sepsis')) {
      return 'possible serious infection';
    }
    if (title.contains('aki') || title.contains('kidney')) {
      return 'possible kidney stress';
    }
    return title.isEmpty ? 'the current ICU problem' : title;
  }

  String _fallbackConcernTitleHindi(List<Map<String, dynamic>> flags) {
    final title = flags.isNotEmpty
        ? flags.first['title']?.toString().toLowerCase() ?? ''
        : '';
    if (title.contains('sepsis')) {
      return 'संभावित गंभीर संक्रमण';
    }
    if (title.contains('aki') || title.contains('kidney')) {
      return 'किडनी पर संभावित दबाव';
    }
    return 'मरीज की वर्तमान स्थिति';
  }

  String _fallbackConcernTitleLocalized(
    List<Map<String, dynamic>> flags,
    String languageKey,
  ) {
    final title = flags.isNotEmpty
        ? flags.first['title']?.toString().toLowerCase() ?? ''
        : '';
    if (title.contains('sepsis')) {
      return switch (languageKey) {
        'mr' => 'गंभीर संसर्गाची शक्यता',
        'bn' => 'গুরুতর সংক্রমণের সম্ভাবনা',
        'pa' => 'ਗੰਭੀਰ ਇਨਫੈਕਸ਼ਨ ਦੀ ਸੰਭਾਵਨਾ',
        'gu' => 'ગંભીર ચેપની શક્યતા',
        'ml' => 'ഗുരുതരമായ അണുബാധയ്ക്കുള്ള സാധ്യത',
        'te' => 'తీవ్రమైన ఇన్‌ఫెక్షన్ అవకాశం',
        'ta' => 'கடுமையான தொற்று இருக்கலாம்',
        'kn' => 'ತೀವ್ರ ಸೋಂಕಿನ ಸಾಧ್ಯತೆ',
        _ => 'संभावित गंभीर संक्रमण',
      };
    }
    if (title.contains('aki') || title.contains('kidney')) {
      return switch (languageKey) {
        'mr' => 'मूत्रपिंडांवर ताण असू शकतो',
        'bn' => 'কিডনির ওপর চাপ থাকতে পারে',
        'pa' => 'ਗੁਰਦਿਆਂ \'ਤੇ ਦਬਾਅ ਹੋ ਸਕਦਾ ਹੈ',
        'gu' => 'કિડની પર તાણ હોઈ શકે',
        'ml' => 'വൃക്കകളിൽ സമ്മർദ്ദം ഉണ്ടായിരിക്കാം',
        'te' => 'మూత్రపిండాలపై ఒత్తిడి ఉండొచ్చు',
        'ta' => 'சிறுநீரகங்களுக்கு அழுத்தம் இருக்கலாம்',
        'kn' => 'ಮೂತ್ರಪಿಂಡಗಳ ಮೇಲೆ ಒತ್ತಡ ಇರಬಹುದು',
        _ => 'किडनी पर संभावित दबाव',
      };
    }
    return switch (languageKey) {
      'mr' => 'रुग्णाची एकूण आयसीयू स्थिती',
      'bn' => 'রোগীর সামগ্রিক আইসিইউ অবস্থা',
      'pa' => 'ਮਰੀਜ਼ ਦੀ ਕੁੱਲ ਆਈਸੀਯੂ ਹਾਲਤ',
      'gu' => 'દર્દીની કુલ આઈસીઇયુ સ્થિતિ',
      'ml' => 'രോഗിയുടെ ആകെ ഐസിയു നില',
      'te' => 'రోగి మొత్తం ఐసీయూ పరిస్థితి',
      'ta' => 'நோயாளியின் மொத்த ஐசியு நிலை',
      'kn' => 'ರೋಗಿಯ ಒಟ್ಟಾರೆ ಐಸಿಯು ಸ್ಥಿತಿ',
      _ => 'मरीज की वर्तमान स्थिति',
    };
  }

  Map<String, dynamic> _fallbackRegionalLanguageContent({
    required String languageKey,
    required String riskLevel,
    required String overallTrend,
    required List<Map<String, dynamic>> flags,
    required List<Map<String, dynamic>> probableErrors,
    required PatientReading patient,
  }) {
    final meta = switch (languageKey) {
      'mr' => (label: 'Marathi', code: 'mr-IN', title: 'कुटुंबासाठी अद्यतन'),
      'bn' => (
        label: 'Bengali',
        code: 'bn-IN',
        title: 'পরিবারের জন্য হালনাগাদ',
      ),
      'pa' => (label: 'Punjabi', code: 'pa-IN', title: 'ਪਰਿਵਾਰ ਲਈ ਅਪডੇਟ'),
      'gu' => (label: 'Gujarati', code: 'gu-IN', title: 'પરિવાર માટે અપડેટ'),
      'ml' => (
        label: 'Malayalam',
        code: 'ml-IN',
        title: 'കുടുംബത്തിനുള്ള അപ്ഡേറ്റ്',
      ),
      'te' => (label: 'Telugu', code: 'te-IN', title: 'కుటుంబానికి నవీకరణ'),
      'ta' => (
        label: 'Tamil',
        code: 'ta-IN',
        title: 'குடும்பத்திற்கு புதுப்பிப்பு',
      ),
      'kn' => (label: 'Kannada', code: 'kn-IN', title: 'ಕುಟುಂಬದ ನವೀಕರಣ'),
      _ => (label: 'Hindi', code: 'hi-IN', title: 'परिवार के लिए अपडेट'),
    };
    final intro = switch (languageKey) {
      'mr' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'गेल्या 12 तासांत आपल्या कुटुंबातील सदस्याची प्रकृती अजूनही गंभीर आहे, आणि आयसीयू टीम त्यांच्यावर खूप जवळून लक्ष ठेवत आहे.',
        'MODERATE' =>
          'गेल्या 12 तासांत आपल्या कुटुंबातील सदस्याच्या प्रकृतीत काही बदल दिसले आहेत ज्यावर बारकाईने लक्ष ठेवण्याची गरज आहे, आणि आयसीयू टीम सक्रियपणे उपचार करत आहे.',
        _ =>
          'गेल्या 12 तासांत आपल्या कुटुंबातील सदस्याची प्रकृती तुलनेने स्थिर राहिली आहे, पण आयसीयू टीम अजूनही खूप जवळून लक्ष ठेवत आहे.',
      },
      'bn' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'গত 12 ঘণ্টায় আপনার পরিবারের সদস্যের অবস্থা এখনও গুরুতর রয়েছে, এবং আইসিইউ দল খুব কাছ থেকে নজর রাখছে।',
        'MODERATE' =>
          'গত 12 ঘণ্টায় আপনার পরিবারের সদস্যের অবস্থায় কিছু পরিবর্তন দেখা গেছে যেগুলো নিবিড়ভাবে পর্যবেক্ষণ করা দরকার, এবং আইসিইউ দল সক্রিয়ভাবে সাড়া দিচ্ছে।',
        _ =>
          'গত 12 ঘণ্টায় আপনার পরিবারের সদস্যের অবস্থা তুলনামূলকভাবে স্থিতিশীল ছিল, কিন্তু আইসিইউ দল এখনও খুব কাছ থেকে নজর রাখছে।',
      },
      'pa' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'ਪਿਛਲੇ 12 ਘੰਟਿਆਂ ਵਿੱਚ ਤੁਹਾਡੇ ਪਰਿਵਾਰਕ ਮੈਂਬਰ ਦੀ ਹਾਲਤ ਅਜੇ ਵੀ ਗੰਭੀਰ ਰਹੀ ਹੈ, ਅਤੇ ਆਈਸੀਯੂ ਟੀਮ ਬਹੁਤ ਨੇੜੇ ਤੋਂ ਨਿਗਰਾਨੀ ਰੱਖ ਰਹੀ ਹੈ।',
        'MODERATE' =>
          'ਪਿਛਲੇ 12 ਘੰਟਿਆਂ ਵਿੱਚ ਤੁਹਾਡੇ ਪਰਿਵਾਰਕ ਮੈਂਬਰ ਦੀ ਹਾਲਤ ਵਿੱਚ ਕੁਝ ਅਜੇਹੇ ਬਦਲਾਅ ਦਿਖੇ ਹਨ ਜਿਨ੍ਹਾਂ ਉੱਤੇ ਨਜ਼ਦੀਕੀ ਨਿਗਰਾਨੀ ਦੀ ਲੋੜ ਹੈ, ਅਤੇ ਆਈਸੀਯੂ ਟੀਮ ਸਰਗਰਮ ਤਰੀਕੇ ਨਾਲ ਜਵਾਬ ਦੇ ਰਹੀ ਹੈ।',
        _ =>
          'ਪਿਛਲੇ 12 ਘੰਟਿਆਂ ਵਿੱਚ ਤੁਹਾਡੇ ਪਰਿਵਾਰਕ ਮੈਂਬਰ ਦੀ ਹਾਲਤ ਤੁਲਨਾਤਮਕ ਤੌਰ \'ਤੇ ਸਥਿਰ ਰਹੀ ਹੈ, ਪਰ ਆਈਸੀਯੂ ਟੀਮ ਅਜੇ ਵੀ ਬਹੁਤ ਨੇੜੇ ਤੋਂ ਨਿਗਰਾਨੀ ਕਰ ਰਹੀ ਹੈ।',
      },
      'gu' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'ગત 12 કલાકમાં તમારા પરિવારના સભ્યની સ્થિતિ હજુ પણ ગંભીર છે, અને આઈસીઇયુ ટીમ ખૂબ નજીકથી નજર રાખી રહી છે.',
        'MODERATE' =>
          'ગત 12 કલાકમાં તમારા પરિવારના સભ્યની સ્થિતિમાં કેટલાક એવા ફેરફારો જોવા મળ્યા છે જેને નજીકથી જોવાની જરૂર છે, અને આઈસીઇયુ ટીમ સક્રિય રીતે પ્રતિસાદ આપી રહી છે.',
        _ =>
          'ગત 12 કલાકમાં તમારા પરિવારના સભ્યની સ્થિતિ તુલનાત્મક રીતે સ્થિર રહી છે, પરંતુ આઈસીઇયુ ટીમ હજુ પણ ખૂબ નજીકથી નજર રાખી રહી છે.',
      },
      'ml' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'കഴിഞ്ഞ 12 മണിക്കൂറിനിടെ നിങ്ങളുടെ കുടുംബാംഗത്തിന്റെ നില ഇപ്പോഴും ഗുരുതരമാണ്, ഐസിയു സംഘം വളരെ അടുത്ത് നിരീക്ഷിച്ചുകൊണ്ടിരിക്കുന്നു.',
        'MODERATE' =>
          'കഴിഞ്ഞ 12 മണിക്കൂറിനിടെ നിങ്ങളുടെ കുടുംബാംഗത്തിന്റെ നിലയിൽ അടുത്ത് ശ്രദ്ധിക്കേണ്ട ചില മാറ്റങ്ങൾ കണ്ടിട്ടുണ്ട്, ഐസിയു സംഘം സജീവമായി പ്രതികരിച്ചുകൊണ്ടിരിക്കുന്നു.',
        _ =>
          'കഴിഞ്ഞ 12 മണിക്കൂറിനിടെ നിങ്ങളുടെ കുടുംബാംഗത്തിന്റെ നില താരതമ്യേന സ്ഥിരമായിരുന്നു, പക്ഷേ ഐസിയു സംഘം ഇപ്പോഴും വളരെ അടുത്ത് നിരീക്ഷിച്ചുകൊണ്ടിരിക്കുന്നു.',
      },
      'te' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'గత 12 గంటల్లో మీ కుటుంబ సభ్యుడి పరిస్థితి ఇంకా తీవ్రముగానే ఉంది, మరియు ఐసీయూ బృందం చాలా దగ్గరగా గమనిస్తోంది.',
        'MODERATE' =>
          'గత 12 గంటల్లో మీ కుటుంబ సభ్యుడి పరిస్థితిలో దగ్గరగా గమనించాల్సిన కొన్ని మార్పులు కనిపించాయి, మరియు ఐసీయూ బృందం చురుకుగా స్పందిస్తోంది.',
        _ =>
          'గత 12 గంటుల్లో మీ కుటుంబ సభ్యుడి పరిస్థితి తక్కువ మార్పులతో స్థిరంగా ఉంది, అయినప్పటికీ ఐసీయూ బృందం ఇంకా చాలా దగ్గరగా గమనిస్తోంది.',
      },
      'ta' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'கடந்த 12 மணி நேரத்தில் உங்கள் குடும்ப உறுப்பினரின் நிலை இன்னும் கவலைக்கிடமாகவே உள்ளது, மற்றும் ஐசியு குழு மிக நெருக்கமாக கண்காணித்து வருகிறது.',
        'MODERATE' =>
          'கடந்த 12 மணி நேரத்தில் உங்கள் குடும்ப உறுப்பினரின் நிலையில் நெருக்கமாக கவனிக்க வேண்டிய சில மாற்றங்கள் காணப்பட்டுள்ளன, மற்றும் ஐசியு குழு செயலில் பதிலளித்து வருகிறது.',
        _ =>
          'கடந்த 12 மணி நேரத்தில் உங்கள் குடும்ப உறுப்பினரின் நிலை ஒப்பீட்டளவில் நிலையாக இருந்தது, ஆனால் ஐசியு குழு இன்னும் மிக நெருக்கமாக கவனித்து வருகிறது.',
      },
      'kn' => switch (riskLevel) {
        'CRITICAL' || 'HIGH' =>
          'ಕಳೆದ 12 ಗಂಟೆಗಳಲ್ಲಿ ನಿಮ್ಮ ಕುಟುಂಬ ಸದಸ್ಯರ ಸ್ಥಿತಿ ಇನ್ನೂ ಗಂಭೀರವಾಗಿಯೇ ಇದೆ, ಮತ್ತು ಐಸಿಯು ತಂಡವು ಅವರನ್ನು ಬಹಳ ಸಮೀಪದಿಂದ ಗಮನಿಸುತ್ತಿದೆ.',
        'MODERATE' =>
          'ಕಳೆದ 12 ಗಂಟೆಗಳಲ್ಲಿ ನಿಮ್ಮ ಕುಟುಂಬ ಸದಸ್ಯರ ಸ್ಥಿತಿಯಲ್ಲಿ ಸಮೀಪದಿಂದ ಗಮನಿಸಬೇಕಾದ ಕೆಲವು ಬದಲಾವಣೆಗಳು ಕಂಡುಬಂದಿವೆ, ಮತ್ತು ಐಸಿಯು ತಂಡವು ಸಕ್ರಿಯವಾಗಿ ಪ್ರತಿಕ್ರಿಯಿಸುತ್ತಿದೆ.',
        _ =>
          'ಕಳೆದ 12 ಗಂಟೆಗಳಲ್ಲಿ ನಿಮ್ಮ ಕುಟುಂಬ ಸದಸ್ಯರ ಸ್ಥಿತಿ ಹೋಲಿಸಿದರೆ ಸ್ಥಿರವಾಗಿತ್ತು, ಆದರೂ ಐಸಿಯು ತಂಡವು ಇನ್ನೂ ಬಹಳ ಸಮೀಪದಿಂದ ಗಮನಿಸುತ್ತಿದೆ.',
      },
      _ => '',
    };
    final concernTitle = _fallbackConcernTitleLocalized(flags, languageKey);
    final redraw = probableErrors.isEmpty
        ? ''
        : switch (languageKey) {
            'mr' =>
              'एक नवीन लॅब निकाल मागील काही दिवसांच्या स्थिर नमुन्याशी जुळत नाही. टीम याकडे चुकीचा लेबल लावलेला किंवा चुकीचा नमुना असू शकतो असे मानत आहे आणि पुष्टी झालेला पुन्हा तपासणी निकाल मिळेपर्यंत निदान बदलणार नाही.',
            'bn' =>
              'একটি নতুন ল্যাব ফল আগের কয়েক দিনের স্থিতিশীল ধাঁচের সঙ্গে মিলছে না। দল এটিকে ভুল লেবেলযুক্ত বা ভুল নমুনা হতে পারে বলে মনে করছে এবং নিশ্চিত পুনরায় পরীক্ষার ফল না আসা পর্যন্ত রোগনির্ণয় বদলাবে না।',
            'pa' =>
              'ਇੱਕ ਨਵਾਂ ਲੈਬ ਨਤੀਜਾ ਪਿਛਲੇ ਕੁਝ ਦਿਨਾਂ ਦੇ ਸਥਿਰ ਪੈਟਰਨ ਨਾਲ ਮੇਲ ਨਹੀਂ ਖਾਂਦਾ। ਟੀਮ ਇਸਨੂੰ ਸੰਭਾਵਤ ਤੌਰ \'ਤੇ ਗਲਤ ਲੇਬਲ ਕੀਤਾ ਜਾਂ ਗਲਤ ਨਮੂਨਾ ਮੰਨ ਰਹੀ ਹੈ ਅਤੇ ਪੁਸ਼ਟੀਸ਼ੁਦਾ ਦੁਬਾਰਾ ਟੈਸਟ ਆਉਣ ਤੱਕ ਰੋਗ-ਨਿਰਣਾ ਨਹੀਂ ਬਦਲੇਗੀ।',
            'gu' =>
              'એક નવું લેબ પરિણામ છેલ્લા કેટલાક દિવસોના સ્થિર પેટર્ન સાથે મેળ ખાતું નથી. ટીમ માને છે કે આ ખોટું લેબલ કરાયેલું અથવા ખોટું નમૂનું હોઈ શકે છે અને ખાતરીવાળી ફરી તપાસ મળે ત્યાં સુધી નિદાન બદલે નહીં.',
            'ml' =>
              'ഒരു പുതിയ ലാബ് ഫലം കഴിഞ്ഞ ചില ദിവസങ്ങളിലെ സ്ഥിരമായ മാതൃകയുമായി പൊരുത്തപ്പെടുന്നില്ല. ഇത് തെറ്റായി ലേബൽ ചെയ്തതോ തെറ്റായ സാമ്പിളോ ആയിരിക്കാമെന്ന് സംഘം കരുതുന്നു; സ്ഥിരീകരിച്ച വീണ്ടും പരിശോധന ലഭിക്കും വരെ രോഗനിർണ്ണയം മാറ്റില്ല.',
            'te' =>
              'కొత్త ల్యాబ్ ఫలితం గత కొన్ని రోజుల స్థిరమైన నమూనాతో సరిపోలడం లేదు. బృందం దీన్ని తప్పుగా లేబుల్ చేసిన లేదా తప్పు నమూనా కావచ్చని భావిస్తోంది మరియు ధృవీకరించిన మళ్లీ పరీక్ష వచ్చే వరకు నిర్ధారణను మార్చదు.',
            'ta' =>
              'புதிய ஆய்வக முடிவு கடந்த சில நாட்களில் இருந்த நிலையான படிவத்துடன் பொருந்தவில்லை. இது தவறாக பெயரிடப்பட்ட அல்லது தவறான மாதிரி இருக்கலாம் என்று குழு கருதுகிறது; உறுதிப்படுத்தப்பட்ட மறுபரிசோதனை வரும் வரை நோயறிதலை மாற்றமாட்டார்கள்.',
            'kn' =>
              'ಹೊಸ ಲ್ಯಾಬ್ ಫಲಿತಾಂಶವು ಕಳೆದ ಕೆಲವು ದಿನಗಳ ಸ್ಥಿರ ಮಾದರಿಯೊಂದಿಗೆ ಹೊಂದಿಕೆಯಾಗುವುದಿಲ್ಲ. ತಂಡವು ಇದನ್ನು ತಪ್ಪಾಗಿ ಲೇಬಲ್ ಮಾಡಲಾದ ಅಥವಾ ತಪ್ಪಾದ ನಮೂನೆ ಇರಬಹುದು ಎಂದು கருதி, ದೃಢೀಕರಿಸಿದ ಮರುಪರೀಕ್ಷೆ ಬರುವವರೆಗೆ ರೋಗನಿರ್ಣಯವನ್ನು ಬದಲಿಸುವುದಿಲ್ಲ.',
            _ => '',
          };
    final currentCondition = switch (languageKey) {
      'mr' =>
        'आत्ता मुख्य चिंता $concernTitle आहे, आणि आयसीयू टीम सतत बारकाईने लक्ष ठेवत आहे.',
      'bn' =>
        'এই মুহূর্তে প্রধান উদ্বেগ হলো $concernTitle, এবং আইসিইউ দল নিবিড়ভাবে পর্যবেক্ষণ করছে।',
      'pa' =>
        'ਇਸ ਵੇਲੇ ਮੁੱਖ ਚਿੰਤਾ $concernTitle ਹੈ, ਅਤੇ ਆਈਸੀਯੂ ਟੀਮ ਲਗਾਤਾਰ ਨੇੜੇ ਤੋਂ ਨਿਗਰਾਨੀ ਕਰ ਰਹੀ ਹੈ।',
      'gu' =>
        'હાલ મુખ્ય ચિંતા $concernTitle છે, અને આઈસીઇયુ ટીમ સતત નજીકથી નજર રાખી રહી છે.',
      'ml' =>
        'ഇപ്പോൾ പ്രധാന ആശങ്ക $concernTitle ആണ്, ഐസിയു സംഘം തുടർച്ചയായി അടുത്ത് നിരീക്ഷിച്ചുകൊണ്ടിരിക്കുന്നു.',
      'te' =>
        'ఇప్పుడున్న ప్రధాన ఆందోళన $concernTitle, మరియు ఐసీయూ బృందం నిరంతరం దగ్గరగా గమనిస్తోంది.',
      'ta' =>
        'இப்போது முக்கிய கவலை $concernTitle, மற்றும் ஐசியு குழு தொடர்ந்து நெருக்கமாக கண்காணித்து வருகிறது.',
      'kn' =>
        'ಈಗ ಮುಖ್ಯ ಚಿಂತೆ $concernTitle, ಮತ್ತು ಐಸಿಯು ತಂಡವು ನಿರಂತರವಾಗಿ ಸಮೀಪದಿಂದ ಗಮನಿಸುತ್ತಿದೆ.',
      _ => '',
    };
    final trend = switch (languageKey) {
      'mr' => switch (overallTrend) {
        'worsening' =>
          'आजच्या आधीच्या वेळेच्या तुलनेत एकूण स्थिती अधिक चिंताजनक दिसत आहे; हृदयाचे ठोके, श्वासोच्छ्वास किंवा रक्तदाबातील बदल सुरू आहेत.',
        'improving' =>
          'आजच्या आधीच्या वेळेच्या तुलनेत काही उत्साहवर्धक चिन्हे आहेत, तरीही आयसीयूमध्ये जवळून लक्ष ठेवण्याची गरज आहे.',
        _ =>
          'आजच्या आधीच्या वेळेच्या तुलनेत एकूण स्थिती तुलनेने स्थिर आहे, पण टीम कोणत्याही अचानक बदलावर बारकाईने लक्ष ठेवत आहे.',
      },
      'bn' => switch (overallTrend) {
        'worsening' =>
          'আজকের আগের সময়ের তুলনায় সামগ্রিক অবস্থা আরও উদ্বেগজনক মনে হচ্ছে; হৃদস্পন্দন, শ্বাসপ্রশ্বাস বা রক্তচাপের পরিবর্তন চলছেই।',
        'improving' =>
          'আজকের আগের সময়ের তুলনায় কিছু উৎসাহজনক লক্ষণ আছে, যদিও আইসিইউতে নিবিড় পর্যবেক্ষণ এখনও দরকার।',
        _ =>
          'আজকের আগের সময়ের তুলনায় সামগ্রিক অবস্থা তুলনামূলকভাবে স্থিতিশীল, কিন্তু দল যেকোনো হঠাৎ পরিবর্তনের দিকে নিবিড় নজর রাখছে।',
      },
      'pa' => switch (overallTrend) {
        'worsening' =>
          'ਅੱਜ ਦੇ ਪਹਿਲਾਂ ਵਾਲੇ ਸਮੇਂ ਨਾਲੋਂ ਕੁੱਲ ਹਾਲਤ ਹੋਰ ਚਿੰਤਾਜਨਕ ਲੱਗ ਰਹੀ ਹੈ; ਦਿਲ ਦੀ ਧੜਕਣ, ਸਾਹ ਜਾਂ ਬਲੱਡ ਪ੍ਰੈਸ਼ਰ ਵਿੱਚ ਬਦਲਾਅ ਜਾਰੀ ਹਨ।',
        'improving' =>
          'ਅੱਜ ਦੇ ਪਹਿਲਾਂ ਵਾਲੇ ਸਮੇਂ ਨਾਲੋਂ ਕੁਝ ਹੌਸਲਾ ਦੇਣ ਵਾਲੇ ਸੰਕੇਤ ਹਨ, ਹਾਲਾਂਕਿ ਆਈਸੀਯੂ ਵਿੱਚ ਨੇੜੀ ਨਿਗਰਾਨੀ ਅਜੇ ਵੀ ਲੋੜੀਂਦੀ ਹੈ।',
        _ =>
          'ਅੱਜ ਦੇ ਪਹਿਲਾਂ ਵਾਲੇ ਸਮੇਂ ਨਾਲੋਂ ਕੁੱਲ ਹਾਲਤ ਤੁਲਨਾਤਮਕ ਤੌਰ \'ਤੇ ਸਥਿਰ ਹੈ, ਪਰ ਟੀਮ ਕਿਸੇ ਵੀ ਅਚਾਨਕ ਬਦਲਾਅ ਉੱਤੇ ਨੇੜੇ ਤੋਂ ਨਿਗਰਾਨੀ ਕਰ ਰਹੀ ਹੈ।',
      },
      'gu' => switch (overallTrend) {
        'worsening' =>
          'આજના પહેલાંના સમયની સરખામણીએ કુલ સ્થિતિ વધુ ચિંતાજનક લાગે છે; હૃદયની ધડકન, શ્વાસ અથવા બ્લડ પ્રેશરના ફેરફારો ચાલુ છે.',
        'improving' =>
          'આજના પહેલાંના સમયની સરખામણીએ કેટલાક હકારાત્મક સંકેતો છે, છતાં આઈસીઇયુમાં નજીકથી દેખરેખની જરૂર છે.',
        _ =>
          'આજના પહેલાંના સમયની સરખામણીએ કુલ સ્થિતિ તુલનાત્મક રીતે સ્થિર છે, પરંતુ ટીમ કોઈપણ અચાનક ફેરફાર પર નજીકથી નજર રાખી રહી છે.',
      },
      'ml' => switch (overallTrend) {
        'worsening' =>
          'ഇന്നത്തെ മുൻപത്തെ സമയവുമായി താരതമ്യം ചെയ്യുമ്പോൾ മൊത്തത്തിലുള്ള നില കൂടുതൽ ആശങ്കാജനകമാണ്; ഹൃദയമിടിപ്പ്, ശ്വാസം, അല്ലെങ്കിൽ രക്തസമ്മർദ്ദത്തിലെ മാറ്റങ്ങൾ തുടരുന്നു.',
        'improving' =>
          'ഇന്നത്തെ മുൻപത്തെ സമയവുമായി താരതമ്യം ചെയ്യുമ്പോൾ ചില പ്രോത്സാഹക സൂചനകൾ കാണുന്നു, എങ്കിലും ഐസിയുവിൽ അടുത്ത നിരീക്ഷണം ഇപ്പോഴും ആവശ്യമാണ്.',
        _ =>
          'ഇന്നത്തെ മുൻപത്തെ സമയവുമായി താരതമ്യം ചെയ്യുമ്പോൾ മൊത്തത്തിലുള്ള നില താരതമ്യേന സ്ഥിരമാണ്, പക്ഷേ ഏതെങ്കിലും പെട്ടെന്നുള്ള മാറ്റം സംഘം അടുത്ത് നിരീക്ഷിച്ചുകൊണ്ടിരിക്കുന്നു.',
      },
      'te' => switch (overallTrend) {
        'worsening' =>
          'ఈరోజు ముందుతో పోలిస్తే మొత్తం పరిస్థితి మరింత ఆందోళనకరంగా కనిపిస్తోంది; హృదయ స్పందన, శ్వాస లేదా రక్తపోటులో మార్పులు కొనసాగుతున్నాయి.',
        'improving' =>
          'ఈరోజు ముందుతో పోలిస్తే కొన్ని ప్రోత్సాహకరమైన సంకేతాలు ఉన్నాయి, అయినప్పటికీ ఐసీయూలో దగ్గర గమనిక ఇంకా అవసరం.',
        _ =>
          'ఈరోజు ముందుతో పోలిస్తే మొత్తం పరిస్థితి తక్కువ మార్పులతో స్థిరంగా ఉంది, కానీ ఏ ఆకస్మిక మార్పునైనా బృందం దగ్గరగా గమనిస్తోంది.',
      },
      'ta' => switch (overallTrend) {
        'worsening' =>
          'இன்றைய முன்னேரத்துடன் ஒப்பிடும்போது மொத்த நிலை மேலும் கவலைக்குரியதாக தெரிகிறது; இதய துடிப்பு, சுவாசம் அல்லது இரத்த அழுத்தத்தில் மாற்றங்கள் தொடர்கின்றன.',
        'improving' =>
          'இன்றைய முன்னேரத்துடன் ஒப்பிடும்போது சில ஊக்கமளிக்கும் அறிகுறிகள் உள்ளன, இருந்தாலும் ஐசியுவில் நெருக்கமான கண்காணிப்பு இன்னும் தேவைப்படுகிறது.',
        _ =>
          'இன்றைய முன்னேரத்துடன் ஒப்பிடும்போது மொத்த நிலை ஒப்பீட்டளவில் நிலையாக உள்ளது, ஆனால் எந்த திடீர் மாற்றத்தையும் குழு நெருக்கமாக கவனித்து வருகிறது.',
      },
      'kn' => switch (overallTrend) {
        'worsening' =>
          'ಇಂದಿನ ಹಿಂದಿನ ಸಮಯದೊಂದಿಗೆ ಹೋಲಿಸಿದರೆ ಒಟ್ಟಾರೆ ಸ್ಥಿತಿ ಹೆಚ್ಚು ಚಿಂತಾಜನಕವಾಗಿದೆ; ಹೃದಯಬಡಿತ, ಉಸಿರಾಟ ಅಥವಾ ರಕ್ತದೊತ್ತಡದ ಬದಲಾವಣೆಗಳು ಮುಂದುವರಿದಿವೆ.',
        'improving' =>
          'ಇಂದಿನ ಹಿಂದಿನ ಸಮಯದೊಂದಿಗೆ ಹೋಲಿಸಿದರೆ ಕೆಲವು ಉತ್ತೇಜನಕಾರಿ ಲಕ್ಷಣಗಳು ಕಾಣುತ್ತಿವೆ, ಆದರೂ ಐಸಿಯುನಲ್ಲಿ ಸಮೀಪದ ನಿಗಾ ಇನ್ನೂ ಅಗತ್ಯವಿದೆ.',
        _ =>
          'ಇಂದಿನ ಹಿಂದಿನ ಸಮಯದೊಂದಿಗೆ ಹೋಲಿಸಿದರೆ ಒಟ್ಟಾರೆ ಸ್ಥಿತಿ ಹೋಲಿಸಿದರೆ ಸ್ಥಿರವಾಗಿದೆ, ಆದರೆ ಯಾವುದೇ ಆಕಸ್ಮಿಕ ಬದಲಾವಣೆಯನ್ನು ತಂಡವು ಸಮೀಪದಿಂದ ಗಮನಿಸುತ್ತಿದೆ.',
      },
      _ => '',
    };

    final keyEvents = [
      if (patient.heartRate >= 110)
        switch (languageKey) {
          'mr' =>
            'हृदयाचे ठोके नेहमीपेक्षा वेगाने आहेत आणि त्यावर बारकाईने लक्ष ठेवले जात आहे.',
          'bn' =>
            'হৃদস্পন্দন স্বাভাবিকের চেয়ে বেশি এবং তা নিবিড়ভাবে পর্যবেক্ষণ করা হচ্ছে।',
          'pa' =>
            'ਦਿਲ ਦੀ ਧੜਕਣ ਆਮ ਨਾਲੋਂ ਤੇਜ਼ ਹੈ ਅਤੇ ਇਸ \'ਤੇ ਨੇੜੇ ਤੋਂ ਨਿਗਰਾਨੀ ਰੱਖੀ ਜਾ ਰਹੀ ਹੈ।',
          'gu' =>
            'હૃદયની ધડકન સામાન્ય કરતાં વધુ ઝડપી છે અને તેના પર નજીકથી નજર રાખવામાં આવી રહી છે.',
          'ml' =>
            'ഹൃദയമിടിപ്പ് സാധാരണത്തേക്കാൾ വേഗത്തിലാണ്, അതിനാൽ അത് അടുത്ത് നിരീക്ഷിക്കപ്പെടുന്നു.',
          'te' =>
            'హృదయ స్పందన సాధారణం కంటే వేగంగా ఉంది మరియు దాన్ని దగ్గరగా గమనిస్తున్నారు.',
          'ta' =>
            'இதய துடிப்பு வழக்கத்தை விட வேகமாக உள்ளது மற்றும் அது நெருக்கமாக கவனிக்கப்படுகிறது.',
          'kn' =>
            'ಹೃದಯಬಡಿತ ಸಾಮಾನ್ಯಕ್ಕಿಂತ ವೇಗವಾಗಿದೆ ಮತ್ತು ಅದನ್ನು ಸಮೀಪದಿಂದ ಗಮನಿಸಲಾಗುತ್ತಿದೆ.',
          _ => '',
        },
      if (patient.systolicBp > 0 && patient.systolicBp < 95)
        switch (languageKey) {
          'mr' =>
            'रक्तदाब कमी बाजूला आहे, म्हणून रक्तप्रवाहावर काळजीपूर्वक लक्ष ठेवले जात आहे.',
          'bn' =>
            'রক্তচাপ নিচের দিকে রয়েছে, তাই রক্তপ্রবাহ সাবধানে পর্যবেক্ষণ করা হচ্ছে।',
          'pa' =>
            'ਬਲੱਡ ਪ੍ਰੈਸ਼ਰ ਹੇਠਾਂ ਵਾਲੇ ਪਾਸੇ ਰਿਹਾ ਹੈ, ਇਸ ਲਈ ਖੂਨ ਦੇ ਪ੍ਰਵਾਹ ਨੂੰ ਧਿਆਨ ਨਾਲ ਦੇਖਿਆ ਜਾ ਰਿਹਾ ਹੈ।',
          'gu' =>
            'બ્લડ પ્રેશર નીચી બાજુએ છે, તેથી રક્તપ્રવાહને કાળજીપૂર્વક જોવામાં આવી રહ્યો છે.',
          'ml' =>
            'രക്തസമ്മർദ്ദം താഴ്ന്ന നിലയിലാണ്, അതിനാൽ രക്തപ്രവാഹം ശ്രദ്ധാപൂർവ്വം നിരീക്ഷിക്കുന്നു.',
          'te' =>
            'రక్తపోటు తక్కువ వైపునే ఉంది, కాబట్టి రక్త ప్రసరణను జాగ్రత్తగా గమనిస్తున్నారు.',
          'ta' =>
            'இரத்த அழுத்தம் குறைவாகவே உள்ளது; அதனால் இரத்த ஓட்டம் கவனமாக கண்காணிக்கப்படுகிறது.',
          'kn' =>
            'ರಕ್ತದೊತ್ತಡ ಕಡಿಮೆ ಭಾಗದಲ್ಲೇ ಇದೆ; ಆದ್ದರಿಂದ ರಕ್ತಪ್ರಸರಣವನ್ನು ಜಾಗ್ರತೆಯಿಂದ ಗಮನಿಸಲಾಗುತ್ತಿದೆ.',
          _ => '',
        },
      if (patient.spo2 > 0 && patient.spo2 < 94)
        switch (languageKey) {
          'mr' =>
            'गेल्या काही तासांत ऑक्सिजनच्या पातळीवर अधिक बारकाईने लक्ष ठेवावे लागले आहे.',
          'bn' =>
            'গত কয়েক ঘণ্টায় অক্সিজেনের মাত্রা আরও নিবিড়ভাবে পর্যবেক্ষণ করতে হয়েছে।',
          'pa' =>
            'ਪਿਛਲੇ ਕੁਝ ਘੰਟਿਆਂ ਵਿੱਚ ਆਕਸੀਜਨ ਦੇ ਪੱਧਰ \'ਤੇ ਹੋਰ ਨੇੜੀ ਨਿਗਰਾਨੀ ਰੱਖਣੀ ਪਈ ਹੈ।',
          'gu' =>
            'ગયા કેટલાક કલાકોમાં ઓક્સિજનના સ્તર પર વધુ નજીકથી નજર રાખવી પડી છે.',
          'ml' =>
            'കഴിഞ്ഞ ചില മണിക്കൂറുകളിൽ ഓക്സിജൻ നില കൂടുതൽ അടുത്ത് നിരീക്ഷിക്കേണ്ടി വന്നു.',
          'te' =>
            'గత కొన్ని గంటల్లో ఆక్సిజన్ స్థాయిలను మరింత దగ్గరగా గమనించాల్సి వచ్చింది.',
          'ta' =>
            'கடந்த சில மணிநேரங்களில் ஆக்சிஜன் அளவை மேலும் நெருக்கமாக கவனிக்க வேண்டியுள்ளது.',
          'kn' =>
            'ಕಳೆದ ಕೆಲವು ಗಂಟೆಗಳಲ್ಲಿ ಆಮ್ಲಜನಕ ಮಟ್ಟವನ್ನು ಇನ್ನಷ್ಟು ಸಮೀಪದಿಂದ ಗಮನಿಸಬೇಕಾಯಿತು.',
          _ => '',
        },
      if (probableErrors.isNotEmpty)
        switch (languageKey) {
          'mr' =>
            'एक लॅब निकाल जुळत नव्हता, म्हणून मोठा बदल करण्यापूर्वी टीमने पुन्हा नमुना मागवला आहे.',
          'bn' =>
            'একটি ল্যাব ফল মিলছিল না, তাই বড় কোনো পরিবর্তনের আগে দল আবার নমুনা চেয়েছে।',
          'pa' =>
            'ਇੱਕ ਲੈਬ ਨਤੀਜਾ ਮਿਲਦਾ ਨਹੀਂ ਸੀ, ਇਸ ਲਈ ਕਿਸੇ ਵੱਡੇ ਬਦਲਾਅ ਤੋਂ ਪਹਿਲਾਂ ਟੀਮ ਨੇ ਮੁੜ ਨਮੂਨਾ ਮੰਗਿਆ ਹੈ।',
          'gu' =>
            'એક લેબ પરિણામ મેળ ખાતું નહોતું, તેથી મોટા બદલાવ પહેલાં ટીમે ફરી નમૂનો માંગ્યો છે.',
          'ml' =>
            'ഒരു ലാബ് ഫലം പൊരുത്തപ്പെട്ടില്ല, അതിനാൽ വലിയ മാറ്റത്തിന് മുമ്പ് സംഘം വീണ്ടും സാമ്പിൾ ആവശ്യപ്പെട്ടു.',
          'te' =>
            'ఒక ల్యాబ్ ఫలితం సరిపోలలేదు, అందుకే పెద్ద మార్పు చేసే ముందు బృందం మళ్లీ నమూనా కోరింది.',
          'ta' =>
            'ஒரு ஆய்வக முடிவு பொருந்தவில்லை; அதனால் பெரிய மாற்றத்திற்கு முன் குழு மறுபடியும் மாதிரியை கேட்டுள்ளது.',
          'kn' =>
            'ಒಂದು ಲ್ಯಾಬ್ ಫಲಿತಾಂಶ ಹೊಂದಿಕೆಯಾಗಲಿಲ್ಲ; ಆದ್ದರಿಂದ ದೊಡ್ಡ ಬದಲಾವಣೆಗೆ ಮೊದಲು ತಂಡವು ಮರು ಮಾದರಿಯನ್ನು ಕೇಳಿದೆ.',
          _ => '',
        },
    ].where((item) => item.isNotEmpty).take(3).toList();

    final bullets = [
      switch (languageKey) {
        'mr' =>
          'टीम बेडसाइडवरील कल, पुन्हा होणाऱ्या रक्त तपासण्या आणि उपचारांना मिळणारा प्रतिसाद यांचा आढावा घेत आहे.',
        'bn' =>
          'দল বেডসাইডের প্রবণতা, পুনরায় করা রক্তপরীক্ষা এবং চিকিৎসার প্রতিক্রিয়া পর্যালোচনা করছে।',
        'pa' =>
          'ਟੀਮ ਬੈਡਸਾਈਡ ਰੁਝਾਨਾਂ, ਮੁੜ ਹੋ ਰਹੀਆਂ ਖੂਨ ਦੀਆਂ ਜਾਂਚਾਂ ਅਤੇ ਇਲਾਜ ਦੇ ਜਵਾਬ ਦੀ ਸਮੀਖਿਆ ਕਰ ਰਹੀ ਹੈ।',
        'gu' =>
          'ટીમ બેડસાઇડ રૂઝાનો, ફરી થતી રક્ત તપાસો અને ઈલાજના પ્રતિસાદની સમીક્ષા કરી રહી છે.',
        'ml' =>
          'സംഘം കിടക്കയ്‌ക്കരികിലെ പ്രവണതകളും വീണ്ടും ചെയ്യുന്ന രക്തപരിശോധനകളും ചികിത്സയ്ക്ക് ലഭിക്കുന്ന പ്രതികരണവും പരിശോധിക്കുന്നു.',
        'te' =>
          'బృందం పడక పక్క ధోరణులు, మళ్లీ చేసే రక్త పరీక్షలు, చికిత్సకు స్పందనను సమీక్షిస్తోంది.',
        'ta' =>
          'குழு படுக்கையருகான போக்குகள், மீண்டும் செய்யும் இரத்த பரிசோதனைகள் மற்றும் சிகிச்சைக்கு உள்ள பதிலை பரிசீலித்து வருகிறது.',
        'kn' =>
          'ತಂಡವು ಹಾಸಿಗೆಯ ಪಕ್ಕದ ಪ್ರವೃತ್ತಿಗಳು, ಮರು ರಕ್ತ ಪರೀಕ್ಷೆಗಳು ಮತ್ತು ಚಿಕಿತ್ಸೆಗೆ ಪ್ರತಿಕ್ರಿಯೆಯನ್ನು ಪರಿಶೀಲಿಸುತ್ತಿದೆ.',
        _ => '',
      },
      switch (languageKey) {
        'mr' =>
          'आयसीयू टीम सतत पुनर्मूल्यांकन आणि आधार देणारी काळजी चालू ठेवत आहे.',
        'bn' =>
          'আইসিইউ দল ধারাবাহিক পুনর্মূল্যায়ন ও সহায়ক চিকিৎসা চালিয়ে যাচ্ছে।',
        'pa' =>
          'ਆਈਸੀਯੂ ਟੀਮ ਲਗਾਤਾਰ ਮੁੜ-ਮੁਲਾਂਕਣ ਅਤੇ ਸਹਾਇਕ ਦੇਖਭਾਲ ਜਾਰੀ ਰੱਖ ਰਹੀ ਹੈ।',
        'gu' =>
          'આઈસીઇયુ ટીમ સતત પુનર્મૂલ્યાંકન અને સહાયક સારવાર ચાલુ રાખી રહી છે.',
        'ml' =>
          'ഐസിയു സംഘം തുടർച്ചയായ പുനർമൂല്യനിർണ്ണയവും സഹായക ചികിത്സയും തുടരുന്നു.',
        'te' =>
          'ఐసీయూ బృందం నిరంతర మళ్లీ సమీక్ష మరియు సహాయక చికిత్స కొనసాగిస్తోంది.',
        'ta' =>
          'ஐசியு குழு தொடர்ந்து மறுமதிப்பீடும் ஆதரவு சிகிச்சையும் வழங்கி வருகிறது.',
        'kn' =>
          'ಐಸಿಯು ತಂಡವು ನಿರಂತರ ಮರುಮೌಲ್ಯಮಾಪನ ಮತ್ತು ಸಹಾಯಕ ಆರೈಕೆಯನ್ನು ಮುಂದುವರಿಸುತ್ತಿದೆ.',
        _ => '',
      },
      if (probableErrors.isNotEmpty)
        switch (languageKey) {
          'mr' =>
            'विरोधाभासी निकालावरून निदान बदलण्याआधी पुन्हा लॅब नमुना घेतला जात आहे.',
          'bn' =>
            'বিরোধপূর্ণ ফলাফলের ভিত্তিতে রোগনির্ণয় বদলানোর আগে আবার ল্যাব নমুনা নেওয়া হচ্ছে।',
          'pa' =>
            'ਵਿਰੋਧੀ ਨਤੀਜੇ ਦੇ ਆਧਾਰ \'ਤੇ ਰੋਗ-ਨਿਰਣਾ ਬਦਲਣ ਤੋਂ ਪਹਿਲਾਂ ਮੁੜ ਲੈਬ ਨਮੂਨਾ ਲਿਆ ਜਾ ਰਿਹਾ ਹੈ।',
          'gu' =>
            'વिरोधાભાસી પરિણામના આધારે નિદાન બદલતાં પહેલાં ફરી લેબ નમૂનો લેવામાં આવી રહ્યો છે.',
          'ml' =>
            'വിരുദ്ധമായ ഫലത്തെ അടിസ്ഥാനമാക്കി രോഗനിർണ്ണയം മാറ്റുന്നതിന് മുമ്പ് വീണ്ടും ലാബ് സാമ്പിൾ എടുക്കുന്നു.',
          'te' =>
            'విరుద్ధమైన ఫలితం ఆధారంగా నిర్ధారణ మార్పు చేసే ముందు మళ్లీ ల్యాబ్ నమూనా తీసుకుంటున్నారు.',
          'ta' =>
            'முரண்படும் முடிவின் அடிப்படையில் நோயறிதலை மாற்றுவதற்கு முன் மறுபடியும் ஆய்வக மாதிரி எடுக்கப்படுகிறது.',
          'kn' =>
            'ವಿರೋಧಾಭಾಸದ ಫಲಿತಾಂಶದ ಆಧಾರವಾಗಿ ರೋಗನಿರ್ಣಯವನ್ನು ಬದಲಿಸುವ ಮೊದಲು ಮರು ಲ್ಯಾಬ್ ಮಾದರಿ ಪಡೆಯಲಾಗುತ್ತಿದೆ.',
          _ => '',
        },
    ].where((item) => item.isNotEmpty).toList();

    final closing = switch (languageKey) {
      'mr' =>
        'हा काळ कुटुंबासाठी तणावाचा आहे हे आम्हाला माहीत आहे. आयसीयू टीम बारकाईने लक्ष ठेवत राहील आणि कोणताही महत्त्वाचा बदल झाल्यास कुटुंबाला कळवेल.',
      'bn' =>
        'এটি পরিবারের জন্য চাপের সময়, তা আমরা জানি। আইসিইউ দল খুব কাছ থেকে নজর রাখবে এবং কোনো গুরুত্বপূর্ণ পরিবর্তন হলে পরিবারকে জানাবে।',
      'pa' =>
        'ਸਾਨੂੰ ਪਤਾ ਹੈ ਕਿ ਇਹ ਪਰਿਵਾਰ ਲਈ ਤਣਾਓਭਰਾ ਸਮਾਂ ਹੈ। ਆਈਸੀਯੂ ਟੀਮ ਬਹੁਤ ਨੇੜੇ ਤੋਂ ਨਿਗਰਾਨੀ ਕਰਦੀ ਰਹੇਗੀ ਅਤੇ ਕੋਈ ਮਹੱਤਵਪੂਰਨ ਬਦਲਾਅ ਹੋਣ \'ਤੇ ਪਰਿਵਾਰ ਨੂੰ ਦੱਸੇਗੀ।',
      'gu' =>
        'આ પરિવાર માટે તણાવનો સમય છે તે અમને ખબર છે. આઈસીઇયુ ટીમ ખૂબ નજીકથી નજર રાખતી રહેશે અને કોઈ મહત્વપૂર્ણ ફેરફાર થશે તો પરિવારને જાણ કરશે.',
      'ml' =>
        'ഇത് കുടുംബത്തിന് സമ്മർദ്ദമുള്ള സമയമാണെന്ന് ഞങ്ങൾ അറിയുന്നു. ഐസിയു സംഘം വളരെ അടുത്ത് നിരീക്ഷിച്ചു കൊണ്ടിരിക്കും, ഏതെങ്കിലും പ്രധാനപ്പെട്ട മാറ്റമുണ്ടായാൽ കുടുംബത്തെ അറിയിക്കും.',
      'te' =>
        'ఇది కుటుంబానికి ఒత్తిడిగా ఉంటుందని మాకు తెలుసు. ఐసీయూ బృందం చాలా దగ్గరగా గమనిస్తూ, ఏ ముఖ్యమైన మార్పు వచ్చినా కుటుంబానికి తెలియజేస్తుంది.',
      'ta' =>
        'இது குடும்பத்திற்கு மன அழுத்தமான நேரம் என்பதை நாங்கள் அறிந்திருக்கிறோம். ஐசியு குழு மிக நெருக்கமாக கண்காணித்து, எந்த முக்கியமான மாற்றமும் ஏற்பட்டால் குடும்பத்திற்கு தெரிவிக்கும்.',
      'kn' =>
        'ಇದು ಕುಟುಂಬಕ್ಕೆ ಒತ್ತಡದ ಸಮಯವೆಂಬುದನ್ನು ನಾವು ಅರಿತಿದ್ದೇವೆ. ಐಸಿಯು ತಂಡವು ಬಹಳ ಸಮೀಪದಿಂದ ಗಮನಿಸಿ, ಯಾವುದೇ ಪ್ರಮುಖ ಬದಲಾವಣೆ ಬಂದರೆ ಕುಟುಂಬಕ್ಕೆ ತಿಳಿಸುತ್ತದೆ.',
      _ => '',
    };

    return {
      'label': meta.label,
      'code': meta.code,
      'title': meta.title,
      'summary':
          '$intro $currentCondition $trend ${redraw.isEmpty ? "" : "$redraw "}$closing',
      'current_condition': currentCondition,
      'trend': trend,
      'key_events': keyEvents,
      'bullets': bullets,
    };
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
