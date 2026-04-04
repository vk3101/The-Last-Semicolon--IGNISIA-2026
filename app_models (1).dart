class PredictionResult {
  const PredictionResult({
    required this.riskScore,
    required this.riskLevel,
    required this.alert,
    required this.sequenceReady,
    required this.bufferFill,
    required this.doctorMessage,
    required this.topReasons,
    required this.recommendedActions,
    required this.componentScores,
    required this.timestamp,
  });

  final double riskScore;
  final String riskLevel;
  final bool alert;
  final bool sequenceReady;
  final int bufferFill;
  final String doctorMessage;
  final List<String> topReasons;
  final List<String> recommendedActions;
  final Map<String, double> componentScores;
  final String timestamp;

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    final rawScores = json['component_scores'] as Map<String, dynamic>? ?? {};
    return PredictionResult(
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0,
      riskLevel: (json['risk_level'] as String?) ?? 'SAFE',
      alert: json['alert'] as bool? ?? false,
      sequenceReady: json['sequence_ready'] as bool? ?? false,
      bufferFill: json['buffer_fill'] as int? ?? 0,
      doctorMessage:
          (json['doctor_message'] as String?) ?? 'No doctor message available.',
      topReasons: (json['top_reasons'] as List<dynamic>? ?? const [])
          .cast<String>(),
      recommendedActions:
          (json['recommended_actions'] as List<dynamic>? ?? const [])
              .cast<String>(),
      componentScores: rawScores.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      timestamp: (json['timestamp'] as String?) ?? '',
    );
  }
}

class PatientReading {
  const PatientReading({
    required this.id,
    required this.name,
    required this.age,
    required this.bedLabel,
    required this.diagnosis,
    required this.lastUpdated,
    required this.vitals,
    required this.hrTrend,
    required this.bpTrend,
    required this.tempTrend,
    required this.spo2Trend,
    required this.gcsTrend,
    required this.riskTrend,
    this.sourceType = 'standard',
    this.prediction,
  });

  final String id;
  final String name;
  final int age;
  final String bedLabel;
  final String diagnosis;
  final String lastUpdated;
  final Map<String, double> vitals;
  final List<double> hrTrend;
  final List<double> bpTrend;
  final List<double> tempTrend;
  final List<double> spo2Trend;
  final List<double> gcsTrend;
  final List<double> riskTrend;
  final String sourceType;
  final PredictionResult? prediction;

  bool get isDoctorCase => sourceType == 'doctor_case';

  double get heartRate => vitals['HR'] ?? 0;
  double get diastolicBp => vitals['BP_dia'] ?? 0;
  double get temperature => vitals['Temp'] ?? 0;
  double get spo2 => vitals['SpO2'] ?? 0;
  double get respiratoryRate => vitals['Resp'] ?? 0;
  double get systolicBp => vitals['BP_sys'] ?? 0;
  double get gcs => vitals['GCS'] ?? 15;

  PatientReading copyWith({
    String? lastUpdated,
    Map<String, double>? vitals,
    List<double>? hrTrend,
    List<double>? bpTrend,
    List<double>? tempTrend,
    List<double>? spo2Trend,
    List<double>? gcsTrend,
    List<double>? riskTrend,
    PredictionResult? prediction,
    bool clearPrediction = false,
  }) {
    return PatientReading(
      id: id,
      name: name,
      age: age,
      bedLabel: bedLabel,
      diagnosis: diagnosis,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      vitals: vitals ?? this.vitals,
      hrTrend: hrTrend ?? this.hrTrend,
      bpTrend: bpTrend ?? this.bpTrend,
      tempTrend: tempTrend ?? this.tempTrend,
      spo2Trend: spo2Trend ?? this.spo2Trend,
      gcsTrend: gcsTrend ?? this.gcsTrend,
      riskTrend: riskTrend ?? this.riskTrend,
      sourceType: sourceType,
      prediction: clearPrediction ? null : prediction ?? this.prediction,
    );
  }

  Map<String, dynamic> toPredictionPayload() {
    return {'patient_id': id, 'timestamp': lastUpdated, 'features': vitals};
  }
}

class AlertRecord {
  const AlertRecord({
    required this.patientId,
    required this.riskLevel,
    required this.riskScore,
    required this.doctorMessage,
    required this.timestamp,
  });

  final String patientId;
  final String riskLevel;
  final double riskScore;
  final String doctorMessage;
  final String timestamp;

  factory AlertRecord.fromJson(Map<String, dynamic> json) {
    return AlertRecord(
      patientId: (json['patient_id'] as String?) ?? 'UNKNOWN',
      riskLevel: (json['risk_level'] as String?) ?? 'SAFE',
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0,
      doctorMessage:
          (json['doctor_message'] as String?) ?? 'No alert summary available.',
      timestamp: (json['timestamp'] as String?) ?? '',
    );
  }
}

class DiagnosticReport {
  const DiagnosticReport({
    required this.patientId,
    required this.generatedAt,
    required this.safetyCaveat,
    required this.overallRiskLevel,
    required this.primaryConcern,
    required this.chiefSummary,
    required this.shiftHandoffSummary,
    required this.probability,
    required this.earlyWarnings,
    required this.evidence,
    required this.guidelineSummaries,
    required this.reportSafetyNote,
    required this.flaggedRisks,
    required this.guidelineCitations,
    required this.probableLabErrors,
    required this.recommendedActions,
    required this.timelineDays,
    required this.explainability,
    required this.latestVitals,
    required this.agents,
    this.familyCommunication,
    this.context,
  });

  final String patientId;
  final String generatedAt;
  final String safetyCaveat;
  final String overallRiskLevel;
  final String primaryConcern;
  final String chiefSummary;
  final String shiftHandoffSummary;
  final double probability;
  final List<String> earlyWarnings;
  final List<String> evidence;
  final List<String> guidelineSummaries;
  final String reportSafetyNote;
  final List<DiagnosticRiskFlag> flaggedRisks;
  final List<GuidelineCitation> guidelineCitations;
  final List<ProbableLabError> probableLabErrors;
  final List<String> recommendedActions;
  final List<TimelineDay> timelineDays;
  final ExplainabilitySummary explainability;
  final Map<String, double> latestVitals;
  final Map<String, Map<String, dynamic>> agents;
  final FamilyCommunication? familyCommunication;
  final DiagnosticCaseContext? context;

  factory DiagnosticReport.fromJson(Map<String, dynamic> json) {
    final riskSummary =
        json['diagnostic_risk_report'] as Map<String, dynamic>? ?? {};
    final agentPayload = json['agents'] as Map<String, dynamic>? ?? {};
    final chiefAgent =
        agentPayload['chief_synthesis_agent'] as Map<String, dynamic>? ?? {};

    return DiagnosticReport(
      patientId: (json['patient_id'] as String?) ?? 'UNKNOWN',
      generatedAt: (json['generated_at'] as String?) ?? '',
      safetyCaveat:
          (json['safety_caveat'] as String?) ??
          'Decision-support only. Clinical validation required.',
      overallRiskLevel: (json['overall_risk_level'] as String?) ?? 'LOW',
      primaryConcern:
          (json['primary_concern'] as String?) ??
          'No major concern identified.',
      chiefSummary:
          (chiefAgent['chief_summary'] as String?) ??
          (json['chief_summary'] as String?) ??
          (json['shift_handoff_summary'] as String?) ??
          (json['chief_summary'] as String?) ??
          'Chief synthesis summary unavailable.',
      shiftHandoffSummary:
          (json['shift_handoff_summary'] as String?) ?? 'No handoff summary.',
      probability: (riskSummary['probability'] as num?)?.toDouble() ?? 0,
      earlyWarnings:
          (riskSummary['early_warning'] as List<dynamic>? ?? const [])
              .cast<String>(),
      evidence: (riskSummary['evidence'] as List<dynamic>? ?? const [])
          .cast<String>(),
      guidelineSummaries:
          (riskSummary['guidelines'] as List<dynamic>? ?? const [])
              .cast<String>(),
      reportSafetyNote:
          (riskSummary['safety_note'] as String?) ??
          'Decision support only, not a clinical diagnosis.',
      flaggedRisks: (json['flagged_risks'] as List<dynamic>? ?? const [])
          .map(
            (item) => DiagnosticRiskFlag.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      guidelineCitations:
          (json['guideline_citations'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    GuidelineCitation.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      probableLabErrors:
          (json['probable_lab_errors'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    ProbableLabError.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
      recommendedActions:
          (json['recommended_actions'] as List<dynamic>? ?? const [])
              .cast<String>(),
      timelineDays:
          (json['disease_progression_timeline_by_day'] as List<dynamic>? ??
                  const [])
              .map((item) => TimelineDay.fromJson(item as Map<String, dynamic>))
              .toList(),
      explainability: ExplainabilitySummary.fromJson(
        json['explainability'] as Map<String, dynamic>? ?? const {},
      ),
      latestVitals: _toDoubleMap(
        json['latest_vitals'] as Map<String, dynamic>? ?? const {},
      ),
      agents: {
        for (final entry in agentPayload.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: Map<String, dynamic>.from(
              entry.value as Map<String, dynamic>,
            )
          else if (entry.value is Map)
            entry.key: Map<String, dynamic>.from(
              (entry.value as Map).map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
      },
      familyCommunication:
          (json['family_communication'] as Map<String, dynamic>?) == null
          ? null
          : FamilyCommunication.fromJson(
              json['family_communication'] as Map<String, dynamic>,
            ),
    );
  }

  DiagnosticReport withContext(DiagnosticCaseContext value) {
    return DiagnosticReport(
      patientId: patientId,
      generatedAt: generatedAt,
      safetyCaveat: safetyCaveat,
      overallRiskLevel: overallRiskLevel,
      primaryConcern: primaryConcern,
      chiefSummary: chiefSummary,
      shiftHandoffSummary: shiftHandoffSummary,
      probability: probability,
      earlyWarnings: earlyWarnings,
      evidence: evidence,
      guidelineSummaries: guidelineSummaries,
      reportSafetyNote: reportSafetyNote,
      flaggedRisks: flaggedRisks,
      guidelineCitations: guidelineCitations,
      probableLabErrors: probableLabErrors,
      recommendedActions: recommendedActions,
      timelineDays: timelineDays,
      explainability: explainability,
      latestVitals: latestVitals,
      agents: agents,
      familyCommunication: familyCommunication,
      context: value,
    );
  }
}

class FamilyCommunication {
  const FamilyCommunication({
    required this.agentRole,
    required this.lookbackHours,
    required this.overallTrend,
    required this.diagnosisUpdateBlocked,
    required this.english,
    required this.regionalLanguage,
    required this.regionalVariants,
    required this.redrawNoteEnglish,
    required this.redrawNoteRegional,
  });

  final String agentRole;
  final int lookbackHours;
  final String overallTrend;
  final bool diagnosisUpdateBlocked;
  final FamilyCommunicationContent english;
  final FamilyCommunicationContent regionalLanguage;
  final List<FamilyCommunicationContent> regionalVariants;
  final String redrawNoteEnglish;
  final String redrawNoteRegional;

  factory FamilyCommunication.fromJson(Map<String, dynamic> json) {
    final defaultRegional = FamilyCommunicationContent.fromJson(
      json['regional_language'] as Map<String, dynamic>? ?? const {},
    );
    final parsedVariants =
        (json['regional_variants'] as List<dynamic>? ?? const [])
            .map(
              (item) => FamilyCommunicationContent.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .where((item) => item.summary.trim().isNotEmpty)
            .toList();
    final hasMeaningfulDefaultRegional =
        defaultRegional.summary.trim().isNotEmpty &&
        defaultRegional.summary != 'No family summary available.';
    final regionalVariants = <FamilyCommunicationContent>[
      if (hasMeaningfulDefaultRegional &&
          !parsedVariants.any((item) => item.code == defaultRegional.code))
        defaultRegional,
      ...parsedVariants,
    ];

    return FamilyCommunication(
      agentRole:
          (json['agent_role'] as String?) ?? 'Family Communication Agent',
      lookbackHours: (json['lookback_hours'] as num?)?.toInt() ?? 12,
      overallTrend: (json['overall_trend'] as String?) ?? 'stable',
      diagnosisUpdateBlocked:
          json['diagnosis_update_blocked'] as bool? ?? false,
      english: FamilyCommunicationContent.fromJson(
        json['english'] as Map<String, dynamic>? ?? const {},
      ),
      regionalLanguage: regionalVariants.isEmpty
          ? defaultRegional
          : regionalVariants.first,
      regionalVariants: regionalVariants,
      redrawNoteEnglish: (json['redraw_note_english'] as String?) ?? '',
      redrawNoteRegional: (json['redraw_note_regional'] as String?) ?? '',
    );
  }

  FamilyCommunicationContent regionalForCode(String? code) {
    if (regionalVariants.isEmpty) {
      return regionalLanguage;
    }
    if (code == null || code.trim().isEmpty) {
      return regionalVariants.first;
    }
    return regionalVariants.firstWhere(
      (item) => item.code == code,
      orElse: () => regionalVariants.first,
    );
  }
}

class FamilyCommunicationContent {
  const FamilyCommunicationContent({
    required this.title,
    required this.summary,
    required this.currentCondition,
    required this.trend,
    required this.keyEvents,
    required this.bullets,
    this.label = '',
    this.code = '',
  });

  final String title;
  final String summary;
  final String currentCondition;
  final String trend;
  final List<String> keyEvents;
  final List<String> bullets;
  final String label;
  final String code;

  factory FamilyCommunicationContent.fromJson(Map<String, dynamic> json) {
    return FamilyCommunicationContent(
      title: (json['title'] as String?) ?? 'Family Communication',
      summary: (json['summary'] as String?) ?? 'No family summary available.',
      currentCondition: (json['current_condition'] as String?) ?? '',
      trend: (json['trend'] as String?) ?? '',
      keyEvents: (json['key_events'] as List<dynamic>? ?? const [])
          .cast<String>(),
      bullets: (json['bullets'] as List<dynamic>? ?? const []).cast<String>(),
      label: (json['label'] as String?) ?? '',
      code: (json['code'] as String?) ?? '',
    );
  }
}

class DiagnosticRiskFlag {
  const DiagnosticRiskFlag({
    required this.title,
    required this.level,
    required this.score,
    required this.summary,
    required this.supportingEvidence,
    required this.guidelineCitations,
  });

  final String title;
  final String level;
  final double score;
  final String summary;
  final List<String> supportingEvidence;
  final List<GuidelineCitation> guidelineCitations;

  factory DiagnosticRiskFlag.fromJson(Map<String, dynamic> json) {
    return DiagnosticRiskFlag(
      title: (json['title'] as String?) ?? 'Unspecified risk',
      level: (json['level'] as String?) ?? 'LOW',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      summary: (json['summary'] as String?) ?? 'No summary provided.',
      supportingEvidence:
          (json['supporting_evidence'] as List<dynamic>? ?? const [])
              .cast<String>(),
      guidelineCitations:
          (json['guideline_citations'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    GuidelineCitation.fromJson(item as Map<String, dynamic>),
              )
              .toList(),
    );
  }
}

class GuidelineCitation {
  const GuidelineCitation({
    required this.id,
    required this.title,
    required this.organization,
    required this.year,
    required this.url,
    required this.summary,
    required this.supportPoints,
    required this.matchedTerms,
  });

  final String id;
  final String title;
  final String organization;
  final int year;
  final String url;
  final String summary;
  final List<String> supportPoints;
  final List<String> matchedTerms;

  factory GuidelineCitation.fromJson(Map<String, dynamic> json) {
    return GuidelineCitation(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Guideline',
      organization: (json['organization'] as String?) ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
      url: (json['url'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      supportPoints: (json['support_points'] as List<dynamic>? ?? const [])
          .cast<String>(),
      matchedTerms: (json['matched_terms'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }
}

class ProbableLabError {
  const ProbableLabError({
    required this.labName,
    required this.timestamp,
    required this.latestValue,
    required this.unit,
    required this.reason,
    required this.action,
    required this.detectionMethod,
  });

  final String labName;
  final String timestamp;
  final double latestValue;
  final String unit;
  final String reason;
  final String action;
  final String detectionMethod;

  factory ProbableLabError.fromJson(Map<String, dynamic> json) {
    return ProbableLabError(
      labName: (json['lab_name'] as String?) ?? 'Lab',
      timestamp: (json['timestamp'] as String?) ?? '',
      latestValue: (json['latest_value'] as num?)?.toDouble() ?? 0,
      unit: (json['unit'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? 'Potentially discordant result.',
      action:
          (json['action'] as String?) ??
          'Repeat the lab before changing the diagnosis.',
      detectionMethod:
          (json['detection_method'] as String?) ?? 'Temporal consistency',
    );
  }
}

class TimelineDay {
  const TimelineDay({
    required this.dayLabel,
    required this.date,
    required this.events,
  });

  final String dayLabel;
  final String date;
  final List<TimelineEvent> events;

  factory TimelineDay.fromJson(Map<String, dynamic> json) {
    return TimelineDay(
      dayLabel: (json['day_label'] as String?) ?? 'Day',
      date: (json['date'] as String?) ?? '',
      events: (json['events'] as List<dynamic>? ?? const [])
          .map((item) => TimelineEvent.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TimelineEvent {
  const TimelineEvent({
    required this.timestamp,
    required this.source,
    required this.severity,
    required this.summary,
  });

  final String timestamp;
  final String source;
  final String severity;
  final String summary;

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      timestamp: (json['timestamp'] as String?) ?? '',
      source: (json['source'] as String?) ?? 'timeline',
      severity: (json['severity'] as String?) ?? 'normal',
      summary: (json['summary'] as String?) ?? 'No event summary.',
    );
  }
}

class ExplainabilitySummary {
  const ExplainabilitySummary({
    required this.method,
    required this.narrative,
    required this.flagCount,
    required this.topContributors,
    required this.modelComponents,
  });

  final String method;
  final String narrative;
  final int flagCount;
  final List<ExplainabilityContributor> topContributors;
  final Map<String, double> modelComponents;

  factory ExplainabilitySummary.fromJson(Map<String, dynamic> json) {
    return ExplainabilitySummary(
      method: (json['method'] as String?) ?? 'Local contribution summary',
      narrative: (json['narrative'] as String?) ?? 'No narrative available.',
      flagCount: (json['flag_count'] as num?)?.toInt() ?? 0,
      topContributors: (json['top_contributors'] as List<dynamic>? ?? const [])
          .map(
            (item) => ExplainabilityContributor.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      modelComponents: _toDoubleMap(
        json['model_components'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class ExplainabilityContributor {
  const ExplainabilityContributor({
    required this.feature,
    required this.value,
    required this.impactScore,
    required this.reason,
  });

  final String feature;
  final double value;
  final double impactScore;
  final String reason;

  factory ExplainabilityContributor.fromJson(Map<String, dynamic> json) {
    return ExplainabilityContributor(
      feature: (json['feature'] as String?) ?? 'Signal',
      value: (json['value'] as num?)?.toDouble() ?? 0,
      impactScore: (json['impact_score'] as num?)?.toDouble() ?? 0,
      reason: (json['reason'] as String?) ?? 'No rationale available.',
    );
  }
}

class DiagnosticCaseContext {
  const DiagnosticCaseContext({
    required this.age,
    required this.diagnosis,
    required this.timelineSnapshots,
    required this.predictedComplications,
  });

  final int age;
  final String diagnosis;
  final List<DiagnosticTimelineSnapshot> timelineSnapshots;
  final List<PredictedComplication> predictedComplications;
}

class DiagnosticTimelineSnapshot {
  const DiagnosticTimelineSnapshot({
    required this.title,
    required this.timestamp,
    required this.severityLabel,
    required this.clinicalNote,
    required this.vitals,
    required this.labs,
    required this.aiAnalysis,
  });

  final String title;
  final String timestamp;
  final String severityLabel;
  final String clinicalNote;
  final Map<String, double> vitals;
  final Map<String, double> labs;
  final String aiAnalysis;
}

class PredictedComplication {
  const PredictedComplication({
    required this.title,
    required this.timeframe,
    required this.confidenceLabel,
    required this.riskPercent,
  });

  final String title;
  final String timeframe;
  final String confidenceLabel;
  final int riskPercent;
}

Map<String, double> _toDoubleMap(Map<String, dynamic> raw) {
  return raw.map(
    (key, value) => MapEntry(
      key,
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0,
    ),
  );
}

class DoctorDocumentDraft {
  const DoctorDocumentDraft({
    required this.documentType,
    required this.title,
    required this.content,
    this.timestamp,
    this.author,
    this.specialty,
  });

  final String documentType;
  final String title;
  final String content;
  final String? timestamp;
  final String? author;
  final String? specialty;

  Map<String, dynamic> toJson() {
    return {
      'document_type': documentType,
      'title': title,
      'content': content,
      if (timestamp != null && timestamp!.isNotEmpty) 'timestamp': timestamp,
      if (author != null && author!.isNotEmpty) 'author': author,
      if (specialty != null && specialty!.isNotEmpty) 'specialty': specialty,
    };
  }
}

class DoctorCaseCounts {
  const DoctorCaseCounts({
    required this.documents,
    required this.notes,
    required this.labs,
    required this.vitals,
  });

  final int documents;
  final int notes;
  final int labs;
  final int vitals;

  factory DoctorCaseCounts.fromJson(Map<String, dynamic> json) {
    return DoctorCaseCounts(
      documents: (json['documents'] as num?)?.toInt() ?? 0,
      notes: (json['notes'] as num?)?.toInt() ?? 0,
      labs: (json['labs'] as num?)?.toInt() ?? 0,
      vitals: (json['vitals'] as num?)?.toInt() ?? 0,
    );
  }
}

class DoctorProfile {
  const DoctorProfile({required this.name, required this.specialty});

  final String name;
  final String specialty;

  factory DoctorProfile.fromJson(Map<String, dynamic> json) {
    return DoctorProfile(
      name: (json['name'] as String?) ?? 'Doctor',
      specialty: (json['specialty'] as String?) ?? 'ICU',
    );
  }
}

class DoctorPatientProfile {
  const DoctorPatientProfile({
    required this.name,
    required this.age,
    required this.sex,
    required this.bedLabel,
    required this.diagnosis,
    required this.admissionDate,
  });

  final String name;
  final int age;
  final String sex;
  final String bedLabel;
  final String diagnosis;
  final String admissionDate;

  factory DoctorPatientProfile.fromJson(Map<String, dynamic> json) {
    return DoctorPatientProfile(
      name: (json['name'] as String?) ?? 'Unknown Patient',
      age: (json['age'] as num?)?.toInt() ?? 0,
      sex: (json['sex'] as String?) ?? 'Unknown',
      bedLabel: (json['bed_label'] as String?) ?? '',
      diagnosis: (json['diagnosis'] as String?) ?? 'Undifferentiated ICU case',
      admissionDate: (json['admission_date'] as String?) ?? '',
    );
  }
}

class DoctorDocumentRecord {
  const DoctorDocumentRecord({
    required this.documentId,
    required this.title,
    required this.documentType,
    required this.mimeType,
    required this.sourceKind,
    required this.ocrStatus,
    required this.ocrBackend,
    required this.preprocessingSummary,
    required this.author,
    required this.specialty,
    required this.timestamp,
    required this.preview,
    required this.routedAgents,
    required this.externalUrl,
  });

  final String documentId;
  final String title;
  final String documentType;
  final String mimeType;
  final String sourceKind;
  final String ocrStatus;
  final String ocrBackend;
  final String preprocessingSummary;
  final String author;
  final String specialty;
  final String timestamp;
  final String preview;
  final List<String> routedAgents;
  final String externalUrl;

  factory DoctorDocumentRecord.fromJson(Map<String, dynamic> json) {
    return DoctorDocumentRecord(
      documentId: (json['document_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Document',
      documentType: (json['document_type'] as String?) ?? 'clinical_note',
      mimeType: (json['mime_type'] as String?) ?? 'text/plain',
      sourceKind: (json['source_kind'] as String?) ?? 'text_upload',
      ocrStatus: (json['ocr_status'] as String?) ?? 'not_applicable',
      ocrBackend: (json['ocr_backend'] as String?) ?? '',
      preprocessingSummary: (json['preprocessing_summary'] as String?) ?? '',
      author: (json['author'] as String?) ?? 'Doctor upload',
      specialty: (json['specialty'] as String?) ?? 'Clinical',
      timestamp: (json['timestamp'] as String?) ?? '',
      preview: (json['preview'] as String?) ?? '',
      routedAgents: (json['routed_agents'] as List<dynamic>? ?? const [])
          .cast<String>(),
      externalUrl:
          (json['external_url'] as String?) ?? (json['url'] as String?) ?? '',
    );
  }
}

class DoctorNoteEntry {
  const DoctorNoteEntry({
    required this.timestamp,
    required this.text,
    required this.author,
    required this.specialty,
    required this.sourceDocumentId,
  });

  final String timestamp;
  final String text;
  final String author;
  final String specialty;
  final String sourceDocumentId;

  factory DoctorNoteEntry.fromJson(Map<String, dynamic> json) {
    return DoctorNoteEntry(
      timestamp: (json['timestamp'] as String?) ?? '',
      text: (json['text'] as String?) ?? (json['note'] as String?) ?? '',
      author: (json['author'] as String?) ?? 'Unknown',
      specialty: (json['specialty'] as String?) ?? 'Clinical',
      sourceDocumentId:
          (json['source_document_id'] as String?) ??
          (json['document_id'] as String?) ??
          '',
    );
  }
}

class DoctorLabEntry {
  const DoctorLabEntry({
    required this.timestamp,
    required this.name,
    required this.value,
    required this.unit,
    required this.sourceDocumentId,
  });

  final String timestamp;
  final String name;
  final double value;
  final String unit;
  final String sourceDocumentId;

  factory DoctorLabEntry.fromJson(Map<String, dynamic> json) {
    return DoctorLabEntry(
      timestamp: (json['timestamp'] as String?) ?? '',
      name: (json['name'] as String?) ?? (json['lab'] as String?) ?? 'Lab',
      value:
          (json['value'] as num?)?.toDouble() ??
          (json['result'] as num?)?.toDouble() ??
          0,
      unit: (json['unit'] as String?) ?? (json['units'] as String?) ?? '',
      sourceDocumentId:
          (json['source_document_id'] as String?) ??
          (json['document_id'] as String?) ??
          '',
    );
  }
}

class DoctorVitalSnapshot {
  const DoctorVitalSnapshot({
    required this.timestamp,
    required this.values,
    required this.sourceDocumentId,
  });

  final String timestamp;
  final Map<String, double> values;
  final String sourceDocumentId;

  factory DoctorVitalSnapshot.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json)
      ..removeWhere(
        (key, _) => {
          'timestamp',
          'source_document_id',
          'document_id',
          'sort_key',
        }.contains(key),
      );
    return DoctorVitalSnapshot(
      timestamp: (json['timestamp'] as String?) ?? '',
      values: _toDoubleMap(map),
      sourceDocumentId:
          (json['source_document_id'] as String?) ??
          (json['document_id'] as String?) ??
          '',
    );
  }
}

class DoctorRoutingSummary {
  const DoctorRoutingSummary({
    required this.documentCount,
    required this.noteCount,
    required this.labCount,
    required this.vitalSnapshotCount,
    required this.noteParserAgentDocuments,
    required this.temporalLabMapperAgentDocuments,
    required this.summary,
  });

  final int documentCount;
  final int noteCount;
  final int labCount;
  final int vitalSnapshotCount;
  final List<String> noteParserAgentDocuments;
  final List<String> temporalLabMapperAgentDocuments;
  final String summary;

  factory DoctorRoutingSummary.fromJson(Map<String, dynamic> json) {
    return DoctorRoutingSummary(
      documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
      noteCount: (json['note_count'] as num?)?.toInt() ?? 0,
      labCount: (json['lab_count'] as num?)?.toInt() ?? 0,
      vitalSnapshotCount: (json['vital_snapshot_count'] as num?)?.toInt() ?? 0,
      noteParserAgentDocuments:
          (json['note_parser_agent_documents'] as List<dynamic>? ?? const [])
              .cast<String>(),
      temporalLabMapperAgentDocuments:
          (json['temporal_lab_mapper_agent_documents'] as List<dynamic>? ??
                  const [])
              .cast<String>(),
      summary: (json['summary'] as String?) ?? 'No routing summary available.',
    );
  }
}

class DoctorDocumentIntake {
  const DoctorDocumentIntake({
    required this.agentRole,
    required this.documents,
    required this.routingSummary,
  });

  final String agentRole;
  final List<DoctorDocumentRecord> documents;
  final DoctorRoutingSummary routingSummary;

  factory DoctorDocumentIntake.fromJson(Map<String, dynamic> json) {
    return DoctorDocumentIntake(
      agentRole: (json['agent_role'] as String?) ?? 'Document Router Agent',
      documents: (json['documents'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                DoctorDocumentRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      routingSummary: DoctorRoutingSummary.fromJson(
        json['routing_summary'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class DoctorPatientCaseSummary {
  const DoctorPatientCaseSummary({
    required this.patientId,
    required this.createdAt,
    required this.updatedAt,
    required this.patient,
    required this.doctor,
    required this.counts,
    required this.overallRiskLevel,
    required this.primaryConcern,
  });

  final String patientId;
  final String createdAt;
  final String updatedAt;
  final DoctorPatientProfile patient;
  final DoctorProfile doctor;
  final DoctorCaseCounts counts;
  final String? overallRiskLevel;
  final String? primaryConcern;

  factory DoctorPatientCaseSummary.fromJson(Map<String, dynamic> json) {
    return DoctorPatientCaseSummary(
      patientId: (json['patient_id'] as String?) ?? 'UNKNOWN',
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      patient: DoctorPatientProfile.fromJson(
        json['patient'] as Map<String, dynamic>? ?? const {},
      ),
      doctor: DoctorProfile.fromJson(
        json['doctor'] as Map<String, dynamic>? ?? const {},
      ),
      counts: DoctorCaseCounts.fromJson(
        json['counts'] as Map<String, dynamic>? ?? const {},
      ),
      overallRiskLevel: json['overall_risk_level'] as String?,
      primaryConcern: json['primary_concern'] as String?,
    );
  }
}

class DoctorPatientCase {
  const DoctorPatientCase({
    required this.patientId,
    required this.createdAt,
    required this.updatedAt,
    required this.patient,
    required this.doctor,
    required this.counts,
    required this.documents,
    required this.documentIntake,
    required this.notes,
    required this.labs,
    required this.vitals,
    this.latestReport,
    this.overallRiskLevel,
    this.primaryConcern,
  });

  final String patientId;
  final String createdAt;
  final String updatedAt;
  final DoctorPatientProfile patient;
  final DoctorProfile doctor;
  final DoctorCaseCounts counts;
  final List<DoctorDocumentRecord> documents;
  final DoctorDocumentIntake? documentIntake;
  final List<DoctorNoteEntry> notes;
  final List<DoctorLabEntry> labs;
  final List<DoctorVitalSnapshot> vitals;
  final DiagnosticReport? latestReport;
  final String? overallRiskLevel;
  final String? primaryConcern;

  factory DoctorPatientCase.fromEnvelope(Map<String, dynamic> payload) {
    final caseJson =
        payload['patient_case'] as Map<String, dynamic>? ?? const {};
    final summaryJson = payload['summary'] as Map<String, dynamic>? ?? const {};
    final reportJson = payload['report'] as Map<String, dynamic>?;
    return DoctorPatientCase.fromJson(
      caseJson,
      summaryJson: summaryJson,
      reportJson: reportJson,
    );
  }

  factory DoctorPatientCase.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? summaryJson,
    Map<String, dynamic>? reportJson,
  }) {
    final summary = summaryJson ?? const {};
    final intakeJson = json['document_intake'] as Map<String, dynamic>?;
    final routedDocumentsJson =
        intakeJson?['documents'] as List<dynamic>? ?? const [];
    final documentsJson =
        json['documents'] as List<dynamic>? ?? routedDocumentsJson;
    final latestReportJson =
        reportJson ??
        json['latest_report'] as Map<String, dynamic>? ??
        const {};
    final routingSummary =
        intakeJson?['routing_summary'] as Map<String, dynamic>? ?? const {};
    final countsJson =
        summary['counts'] as Map<String, dynamic>? ??
        {
          'documents': routingSummary['document_count'],
          'notes': routingSummary['note_count'],
          'labs': routingSummary['lab_count'],
          'vitals': routingSummary['vital_snapshot_count'],
        };

    final latestReport = latestReportJson.isEmpty
        ? null
        : DiagnosticReport.fromJson(latestReportJson);
    final notesJson = json['notes'] as List<dynamic>? ?? const [];
    final labsJson = json['labs'] as List<dynamic>? ?? const [];
    final vitalsJson = json['vitals'] as List<dynamic>? ?? const [];

    return DoctorPatientCase(
      patientId:
          (json['patient_id'] as String?) ??
          (summary['patient_id'] as String?) ??
          'UNKNOWN',
      createdAt:
          (json['created_at'] as String?) ??
          (summary['created_at'] as String?) ??
          '',
      updatedAt:
          (json['updated_at'] as String?) ??
          (summary['updated_at'] as String?) ??
          '',
      patient: DoctorPatientProfile.fromJson(
        json['patient'] as Map<String, dynamic>? ??
            summary['patient'] as Map<String, dynamic>? ??
            const {},
      ),
      doctor: DoctorProfile.fromJson(
        json['doctor'] as Map<String, dynamic>? ??
            summary['doctor'] as Map<String, dynamic>? ??
            const {},
      ),
      counts: DoctorCaseCounts.fromJson(countsJson),
      documents: documentsJson
          .map(
            (item) =>
                DoctorDocumentRecord.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      documentIntake: intakeJson == null
          ? null
          : DoctorDocumentIntake.fromJson(intakeJson),
      notes: notesJson
          .map((item) => DoctorNoteEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
      labs: labsJson
          .map((item) => DoctorLabEntry.fromJson(item as Map<String, dynamic>))
          .toList(),
      vitals: vitalsJson
          .map(
            (item) =>
                DoctorVitalSnapshot.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      latestReport: latestReport,
      overallRiskLevel:
          summary['overall_risk_level'] as String? ??
          latestReport?.overallRiskLevel,
      primaryConcern:
          summary['primary_concern'] as String? ?? latestReport?.primaryConcern,
    );
  }

  DoctorPatientCaseSummary get summary {
    return DoctorPatientCaseSummary(
      patientId: patientId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      patient: patient,
      doctor: doctor,
      counts: counts,
      overallRiskLevel: overallRiskLevel,
      primaryConcern: primaryConcern,
    );
  }
}
