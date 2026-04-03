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
  final PredictionResult? prediction;

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
      context: value,
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
