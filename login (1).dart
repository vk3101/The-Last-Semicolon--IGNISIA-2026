import 'package:flutter/material.dart';

import '../theme/aegis_brand.dart';
import '../widgets/aegis_backdrop.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin});

  final ValueChanged<String> onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = TextEditingController(text: 'Dr. Aditya');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AegisBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;

              final storyPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandPill(
                    label: AegisBrand.appName,
                    color: AegisBrand.secondary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Protecting critical care decisions with explainable AI.',
                    style: theme.textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 0.98,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Text(
                      'AEGIS AI brings live deterioration surveillance, multi-agent synthesis, and clinician-ready risk communication into one calm command interface.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 17,
                        color: AegisBrand.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _MetricCard(
                        value: '4s',
                        label: 'feed refresh cadence',
                        tint: AegisBrand.primary,
                      ),
                      _MetricCard(
                        value: '5',
                        label: 'clinical agents in the loop',
                        tint: AegisBrand.secondary,
                      ),
                      _MetricCard(
                        value: 'Live',
                        label: 'explainable bedside risk',
                        tint: AegisBrand.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 660),
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.82),
                          const Color(0xFFEFF6FF),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: AegisBrand.stroke.withValues(alpha: 0.65),
                      ),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Why teams use it',
                          style: TextStyle(
                            color: AegisBrand.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 14),
                        _StoryRow(
                          icon: Icons.monitor_heart_outlined,
                          title: 'Unified surveillance',
                          body:
                              'Vitals, alerts, and doctor-created cases stay in one shared clinical view.',
                        ),
                        SizedBox(height: 12),
                        _StoryRow(
                          icon: Icons.psychology_alt_outlined,
                          title: 'Explainable outputs',
                          body:
                              'Every risk shift is translated into clinician-readable reasons and next-step recommendations.',
                        ),
                        SizedBox(height: 12),
                        _StoryRow(
                          icon: Icons.shield_outlined,
                          title: 'Calm decision support',
                          body:
                              'Designed to reduce visual noise while keeping the most important signals impossible to miss.',
                        ),
                      ],
                    ),
                  ),
                ],
              );

              final accessPanel = Container(
                width: isWide ? 430 : double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AegisBrand.panelElevated.withValues(alpha: 0.96),
                      AegisBrand.panel.withValues(alpha: 0.98),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: AegisBrand.primary.withValues(alpha: 0.18),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 36,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _BrandPill(
                      label: 'Secure Clinician Access',
                      color: AegisBrand.primary,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      AegisBrand.appName,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AegisBrand.appSubtitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AegisBrand.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Sign in to open the live care queue, review multi-agent reasoning, and manage physician-created patient cases.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _controller,
                      style: const TextStyle(
                        color: AegisBrand.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Clinician name',
                        hintText: 'Dr. Anita Rao',
                        prefixIcon: Icon(
                          Icons.badge_outlined,
                          color: AegisBrand.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: const [
                        _FeatureChip(
                          icon: Icons.auto_graph_rounded,
                          label: 'Temporal risk scoring',
                        ),
                        _FeatureChip(
                          icon: Icons.find_in_page_outlined,
                          label: 'Explainable recommendations',
                        ),
                        _FeatureChip(
                          icon: Icons.local_hospital_outlined,
                          label: 'Doctor case workspace',
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AegisBrand.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                        ),
                        onPressed: () {
                          final name = _controller.text.trim();
                          widget.onLogin(name.isEmpty ? 'Clinician' : name);
                        },
                        child: const Text('Open AEGIS AI Console'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Built for focused, bedside-ready interpretation rather than generic monitoring dashboards.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AegisBrand.textMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: storyPanel),
                              const SizedBox(width: 28),
                              accessPanel,
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              storyPanel,
                              const SizedBox(height: 28),
                              accessPanel,
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrandPill extends StatelessWidget {
  const _BrandPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.value,
    required this.label,
    required this.tint,
  });

  final String value;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white, tint.withValues(alpha: 0.10)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AegisBrand.stroke.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: tint,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AegisBrand.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  const _StoryRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AegisBrand.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AegisBrand.primary.withValues(alpha: 0.24),
            ),
          ),
          child: Icon(icon, color: AegisBrand.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AegisBrand.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  color: AegisBrand.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AegisBrand.stroke.withValues(alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AegisBrand.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AegisBrand.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
