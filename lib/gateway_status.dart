import 'package:flutter/material.dart';

import 'vpn_access.dart';

/// Present the existing controller snapshot without inferring client protection.
class GatewayStatus extends StatelessWidget {
  const GatewayStatus({
    super.key,
    required this.status,
    this.updatedAt,
    this.refreshing = false,
    this.account,
  });

  final String status;
  final DateTime? updatedAt;
  final bool refreshing;
  final Map<String, dynamic>? account;

  String? get _ipv4 {
    final value = RegExp(
      r'^Gateway (?:observed )?public IPv4: (\d{1,3}(?:\.\d{1,3}){3})(?:[; (]|$)',
      multiLine: true,
    ).firstMatch(status)?.group(1);
    if (value == null ||
        value.split('.').any((part) => int.parse(part) > 255)) {
      return null;
    }
    return value;
  }

  Widget _metric(
    BuildContext context, {
    required String label,
    required String value,
    required String detail,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.labelMedium)),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const amber = Color(0xffffd48a);
    final demo = status.startsWith('LOCAL DEMO');
    final verification = RegExp(
      r'^Gateway observed public IPv4: .+; Mullvad verified: (True|False)\.$',
      multiLine: true,
    ).firstMatch(status)?.group(1);
    final rules = RegExp(
      r'^\s+[^:\n]+: (?:bypass for at most |≤)\d+s(?: remaining)?$',
      multiLine: true,
    ).allMatches(status).length;
    final noRules = RegExp(
      r'^No active bypasses\.$',
      multiLine: true,
    ).hasMatch(status);
    final ruleCount = rules > 0
        ? rules
        : noRules
        ? 0
        : null;
    final observed = updatedAt?.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final timestamp = observed == null
        ? 'No snapshot yet'
        : 'Snapshot ${two(observed.hour)}:${two(observed.minute)}:${two(observed.second)}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.hub_outlined,
                        size: 22,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gateway status',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Read-only gateway snapshot',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message:
                      observed?.toIso8601String() ??
                      'No successful status refresh yet.',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (refreshing)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        else
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                        const SizedBox(width: 6),
                        Text(timestamp, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (demo) ...[
              const SizedBox(height: 16),
              const Text(
                'LOCAL PREVIEW · simulated data, not a live gateway check',
                style: TextStyle(
                  color: amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 20),
            VpnAccessNotice(
              account: account == null
                  ? null
                  : {...account!, if (demo) 'demo': true},
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 640
                    ? 3
                    : constraints.maxWidth >= 420
                    ? 2
                    : 1;
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _metric(
                        context,
                        label: 'Gateway IPv4',
                        value: _ipv4 ?? 'Not observed',
                        detail: demo
                            ? 'Simulated public address'
                            : 'Observed on this gateway only',
                        icon: Icons.language,
                        color: colors.onSurface,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric(
                        context,
                        label: 'Mullvad exit check',
                        value: demo
                            ? 'Demo data'
                            : switch (verification) {
                                'True' => 'Verified',
                                'False' => 'Not verified',
                                _ => 'Unavailable',
                              },
                        detail: demo
                            ? 'No live verification performed'
                            : 'Last reported gateway exit check',
                        icon: Icons.travel_explore,
                        color: demo || verification == 'False'
                            ? amber
                            : verification == 'True'
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _metric(
                        context,
                        label: 'Bypass rules',
                        value: ruleCount?.toString() ?? 'Not reported',
                        detail: ruleCount == null
                            ? 'See controller diagnostics'
                            : ruleCount == 0
                            ? 'No active rules in this snapshot'
                            : 'Active kernel entries, not device count',
                        icon: Icons.timer_outlined,
                        color: ruleCount != null && ruleCount > 0
                            ? amber
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Gateway observations only. Check exit IP and DNS from each client separately.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: colors.outlineVariant.withValues(alpha: 0.5)),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4),
                shape: const Border(),
                collapsedShape: const Border(),
                leading: Icon(
                  Icons.terminal,
                  size: 20,
                  color: colors.onSurfaceVariant,
                ),
                title: const Text('Gateway diagnostics'),
                subtitle: const Text('Full, selectable controller output'),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xff0a171e),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: SelectableText(
                      status,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['GatewayRoboto'],
                        fontSize: 12,
                        height: 1.7,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
