import 'dart:math' as math;

import '../models/app_models.dart';

const Duration kClinicalTrendStep = Duration(minutes: 30);

class VitalTileSpec {
  const VitalTileSpec({
    required this.label,
    required this.value,
    required this.unit,
    required this.normalRange,
    required this.status,
  });

  final String label;
  final String value;
  final String unit;
  final String normalRange;
  final String status;
}

class PatternInsight {
  const PatternInsight({
    required this.title,
    required this.summary,
    required this.severity,
  });

  final String title;
  final String summary;
  final String severity;
}

class AdvancedMetricSpec {
  const AdvancedMetricSpec({
    required this.label,
    required this.value,
    required this.supportingText,
    required this.status,
  });

  final String label;
  final String value;
  final String supportingText;
  final String status;
}

class _ReferenceRange {
  const _ReferenceRange({
    required this.normalLow,
    required this.normalHigh,
    required this.warningLow,
    required this.criticalLow,
    required this.criticalHigh,
  });

  final double normalLow;
  final double normalHigh;
  final double warningLow;
  final double criticalLow;
  final double criticalHigh;
}

const Map<String, _ReferenceRange> _referenceRanges = {
  'HR': _ReferenceRange(
    normalLow: 60,
    normalHigh: 100,
    warningLow: 50,
    criticalLow: 40,
    criticalHigh: 135,
  ),
  'BP_sys': _ReferenceRange(
    normalLow: 90,
    normalHigh: 130,
    warningLow: 85,
    criticalLow: 75,
    criticalHigh: 180,
  ),
  'BP_dia': _ReferenceRange(
    normalLow: 60,
    normalHigh: 85,
    warningLow: 50,
    criticalLow: 40,
    criticalHigh: 110,
  ),
  'Temp': _ReferenceRange(
    normalLow: 36.1,
    normalHigh: 37.8,
    warningLow: 35.5,
    criticalLow: 35.0,
    criticalHigh: 39.0,
  ),
  'SpO2': _ReferenceRange(
    normalLow: 95,
    normalHigh: 100,
    warningLow: 92,
    criticalLow: 88,
    criticalHigh: 100,
  ),
  'Resp': _ReferenceRange(
    normalLow: 12,
    normalHigh: 20,
    warningLow: 10,
    criticalLow: 8,
    criticalHigh: 30,
  ),
  'GCS': _ReferenceRange(
    normalLow: 14,
    normalHigh: 15,
    warningLow: 9,
    criticalLow: 8,
    criticalHigh: 15,
  ),
};

List<VitalTileSpec> buildVitalTileSpecs(PatientReading patient) {
  return [
    _singleVitalSpec('HR', patient.heartRate),
    VitalTileSpec(
      label: 'BP',
      value:
          '${patient.systolicBp.toStringAsFixed(0)}/${patient.diastolicBp.toStringAsFixed(0)}',
      unit: 'mmHg',
      normalRange: 'Normal 90-130 / 60-85 mmHg',
      status: _mergeSeverity([
        classifyVital('BP_sys', patient.systolicBp),
        classifyVital('BP_dia', patient.diastolicBp),
      ]),
    ),
    _singleVitalSpec('Temp', patient.temperature),
    _singleVitalSpec('SpO2', patient.spo2),
    _singleVitalSpec('Resp', patient.respiratoryRate),
    _singleVitalSpec('GCS', patient.gcs),
  ];
}

List<PatternInsight> buildPatternInsights(PatientReading patient) {
  final insights = <PatternInsight>[
    _buildSpo2Insight(patient),
    _buildBpInsight(patient),
    _buildTemperatureInsight(patient),
    _buildGcsInsight(patient),
    _buildRiskInsight(patient),
  ];

  insights.sort((left, right) {
    return _severityRank(right.severity).compareTo(_severityRank(left.severity));
  });
  return insights;
}

List<AdvancedMetricSpec> buildAdvancedMetrics(PatientReading patient) {
  final shockIndex = patient.systolicBp <= 0
      ? 0.0
      : patient.heartRate / patient.systolicBp;
  final map = (patient.systolicBp + (2 * patient.diastolicBp)) / 3;
  final pulsePressure = patient.systolicBp - patient.diastolicBp;
  final oxygenVolatility = _range(patient.spo2Trend);
  final riskVelocity = _ratePerHour(patient.riskTrend);

  final metrics = <AdvancedMetricSpec>[
    AdvancedMetricSpec(
      label: 'Shock Index',
      value: shockIndex.toStringAsFixed(2),
      supportingText: 'Normal < 0.70, concerning above 0.90.',
      status: shockIndex >= 1.0
          ? 'critical'
          : shockIndex >= 0.9
          ? 'watch'
          : 'normal',
    ),
    AdvancedMetricSpec(
      label: 'MAP',
      value: '${map.toStringAsFixed(0)} mmHg',
      supportingText: 'Target is usually above 65 mmHg for perfusion.',
      status: map < 60
          ? 'critical'
          : map < 65
          ? 'watch'
          : 'normal',
    ),
    AdvancedMetricSpec(
      label: 'Pulse Pressure',
      value: '${pulsePressure.toStringAsFixed(0)} mmHg',
      supportingText: 'Low < 25 can suggest poor stroke volume.',
      status: pulsePressure < 20
          ? 'critical'
          : pulsePressure < 25 || pulsePressure > 60
          ? 'watch'
          : 'normal',
    ),
    AdvancedMetricSpec(
      label: 'SpO2 Volatility',
      value: '${oxygenVolatility.toStringAsFixed(1)} pts',
      supportingText: 'Calculated over recent 30-minute windows.',
      status: oxygenVolatility >= 5
          ? 'critical'
          : oxygenVolatility >= 3
          ? 'watch'
          : 'normal',
    ),
    AdvancedMetricSpec(
      label: 'Risk Velocity',
      value: '${riskVelocity >= 0 ? '+' : ''}${riskVelocity.toStringAsFixed(2)}/hr',
      supportingText: 'Positive slope means deterioration is accelerating.',
      status: riskVelocity >= 0.12
          ? 'critical'
          : riskVelocity >= 0.06
          ? 'watch'
          : 'normal',
    ),
  ];

  return metrics;
}

String classifyVital(String key, double value) {
  final range = _referenceRanges[key]!;
  if (key == 'SpO2') {
    if (value <= range.criticalLow) {
      return 'critical';
    }
    if (value < range.normalLow) {
      return 'watch';
    }
    return 'normal';
  }

  if (key == 'GCS') {
    if (value <= range.criticalLow) {
      return 'critical';
    }
    if (value < range.normalLow) {
      return 'watch';
    }
    return 'normal';
  }

  if (value <= range.criticalLow || value >= range.criticalHigh) {
    return 'critical';
  }
  if (value < range.normalLow || value > range.normalHigh) {
    return 'watch';
  }
  return 'normal';
}

String trendResolutionLabel([int points = 1]) {
  final windows = math.max(points - 1, 1);
  final totalMinutes = windows * kClinicalTrendStep.inMinutes;
  if (totalMinutes >= 60) {
    final hours = totalMinutes / 60;
    return hours == hours.roundToDouble()
        ? '${hours.toStringAsFixed(0)} hours'
        : '${hours.toStringAsFixed(1)} hours';
  }
  return '$totalMinutes min';
}

VitalTileSpec _singleVitalSpec(String key, double value) {
  return VitalTileSpec(
    label: key,
    value: _formatValue(key, value),
    unit: _unitFor(key),
    normalRange: _normalRangeLabel(key),
    status: classifyVital(key, value),
  );
}

String _formatValue(String key, double value) {
  if (key == 'Temp') {
    return value.toStringAsFixed(1);
  }
  return value.toStringAsFixed(0);
}

String _unitFor(String key) {
  switch (key) {
    case 'HR':
      return 'bpm';
    case 'Temp':
      return 'C';
    case 'SpO2':
      return '%';
    case 'Resp':
      return '/min';
    case 'GCS':
      return '/15';
    default:
      return '';
  }
}

String _normalRangeLabel(String key) {
  switch (key) {
    case 'HR':
      return 'Normal 60-100 bpm';
    case 'Temp':
      return 'Normal 36.1-37.8 C';
    case 'SpO2':
      return 'Normal 95-100 %';
    case 'Resp':
      return 'Normal 12-20 /min';
    case 'GCS':
      return 'Normal 14-15 /15';
    default:
      return '';
  }
}

PatternInsight _buildSpo2Insight(PatientReading patient) {
  final window = _tail(patient.spo2Trend, 6);
  final minutes = trendResolutionLabel(window.length);
  final fluctuation = _range(window);
  final delta = _delta(window);
  final severity = patient.spo2 <= 90 || fluctuation >= 5
      ? 'critical'
      : patient.spo2 < 95 || fluctuation >= 3 || delta <= -2
      ? 'watch'
      : 'normal';

  final summary = delta <= -2
      ? 'SpO2 fell ${delta.abs().toStringAsFixed(0)} points across the last $minutes and is now ${patient.spo2.toStringAsFixed(0)}%.'
      : 'SpO2 fluctuated ${fluctuation.toStringAsFixed(0)} points across the last $minutes and is now ${patient.spo2.toStringAsFixed(0)}%.';
  return PatternInsight(
    title: 'SpO2 Pattern',
    summary: summary,
    severity: severity,
  );
}

PatternInsight _buildBpInsight(PatientReading patient) {
  final window = _tail(patient.bpTrend, 6);
  final minutes = trendResolutionLabel(window.length);
  final delta = _delta(window);
  final map = (patient.systolicBp + (2 * patient.diastolicBp)) / 3;
  final severity = patient.systolicBp < 85 || map < 60
      ? 'critical'
      : patient.systolicBp < 90 || delta <= -8
      ? 'watch'
      : 'normal';
  final summary = delta <= -5
      ? 'Systolic pressure dropped ${delta.abs().toStringAsFixed(0)} mmHg over the last $minutes; current MAP is ${map.toStringAsFixed(0)}.'
      : 'Blood pressure is holding around ${patient.systolicBp.toStringAsFixed(0)}/${patient.diastolicBp.toStringAsFixed(0)} with MAP ${map.toStringAsFixed(0)}.';
  return PatternInsight(
    title: 'Perfusion Pattern',
    summary: summary,
    severity: severity,
  );
}

PatternInsight _buildTemperatureInsight(PatientReading patient) {
  final window = _tail(patient.tempTrend, 6);
  final minutes = trendResolutionLabel(window.length);
  final delta = _delta(window);
  final severity = patient.temperature >= 39.0
      ? 'critical'
      : patient.temperature >= 38.0 || delta >= 0.4
      ? 'watch'
      : 'normal';
  final summary = delta >= 0.4
      ? 'Temperature rose ${delta.toStringAsFixed(1)} C during the last $minutes and is now ${patient.temperature.toStringAsFixed(1)} C.'
      : 'Temperature is ${patient.temperature.toStringAsFixed(1)} C with no major shift across the last $minutes.';
  return PatternInsight(
    title: 'Temperature Pattern',
    summary: summary,
    severity: severity,
  );
}

PatternInsight _buildGcsInsight(PatientReading patient) {
  final window = _tail(patient.gcsTrend, 6);
  final minutes = trendResolutionLabel(window.length);
  final delta = _delta(window);
  final severity = patient.gcs <= 8
      ? 'critical'
      : patient.gcs < 14 || delta <= -1
      ? 'watch'
      : 'normal';
  final summary = delta <= -1
      ? 'GCS declined by ${delta.abs().toStringAsFixed(0)} point over the last $minutes and is now ${patient.gcs.toStringAsFixed(0)}/15.'
      : 'GCS is currently ${patient.gcs.toStringAsFixed(0)}/15 and has remained stable over the last $minutes.';
  return PatternInsight(
    title: 'Neurologic Pattern',
    summary: summary,
    severity: severity,
  );
}

PatternInsight _buildRiskInsight(PatientReading patient) {
  final window = _tail(patient.riskTrend, 5);
  final minutes = trendResolutionLabel(window.length);
  final delta = _delta(window);
  final severity = delta >= 0.22
      ? 'critical'
      : delta >= 0.1
      ? 'watch'
      : 'normal';
  final summary = delta > 0
      ? 'AI risk climbed by ${delta.toStringAsFixed(2)} over the last $minutes, showing active deterioration velocity.'
      : 'AI risk remained steady across the last $minutes.';
  return PatternInsight(
    title: 'Risk Trajectory',
    summary: summary,
    severity: severity,
  );
}

List<double> _tail(List<double> values, int count) {
  if (values.length <= count) {
    return values;
  }
  return values.sublist(values.length - count);
}

double _delta(List<double> values) {
  if (values.length < 2) {
    return 0;
  }
  return values.last - values.first;
}

double _range(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  final minValue = values.reduce(math.min);
  final maxValue = values.reduce(math.max);
  return maxValue - minValue;
}

double _ratePerHour(List<double> values) {
  if (values.length < 2) {
    return 0;
  }
  final hours = ((values.length - 1) * kClinicalTrendStep.inMinutes) / 60;
  if (hours <= 0) {
    return 0;
  }
  return (values.last - values.first) / hours;
}

String _mergeSeverity(List<String> states) {
  if (states.contains('critical')) {
    return 'critical';
  }
  if (states.contains('watch')) {
    return 'watch';
  }
  return 'normal';
}

int _severityRank(String severity) {
  switch (severity) {
    case 'critical':
      return 3;
    case 'watch':
      return 2;
    default:
      return 1;
  }
}
