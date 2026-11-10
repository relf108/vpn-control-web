import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final mullvadAccountUrl = Uri.https('mullvad.net', '/en/account/login');

/// Whole calendar years/months/days, anchored to the original UTC date.
/// Clamp month-end dates rather than approximating months as 30 days.
String remainingAccess(DateTime now, DateTime expiry) {
  final start = now.toUtc();
  final end = expiry.toUtc();
  if (!end.isAfter(start)) return 'Expired';
  DateTime addMonths(int count) {
    final month = DateTime.utc(start.year, start.month + count);
    final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
    return DateTime.utc(
      month.year,
      month.month,
      start.day.clamp(1, lastDay),
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }

  var months = (end.year - start.year) * 12 + end.month - start.month;
  if (addMonths(months).isAfter(end)) months--;
  final days = end.difference(addMonths(months)).inDays;
  return '${months ~/ 12}y / ${months % 12}m / ${days}d remaining';
}

class VpnAccessNotice extends StatelessWidget {
  const VpnAccessNotice({super.key, this.account, this.now, this.onOpen});
  final Map<String, dynamic>? account;
  final DateTime? now;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = now ?? DateTime.now();
    final raw = account?['expiry'];
    final expiry = raw is String ? DateTime.tryParse(raw) : null;
    final available = account?['state'] == 'available' && expiry != null;
    final expired = available && !expiry.isAfter(current);
    final soon =
        available && expiry.difference(current) <= const Duration(days: 7);
    final stale = account?['stale'] == true;
    final demo = account?['demo'] == true;
    final color = expired
        ? theme.colorScheme.error
        : soon || stale
        ? const Color(0xffffd48a)
        : theme.colorScheme.primary;
    final title = available
        ? remainingAccess(current, expiry)
        : account == null
        ? 'Checking renewal date…'
        : account?['state'] == 'notConfigured'
        ? 'Check renewal on Mullvad'
        : 'Renewal date unavailable';
    final local = expiry?.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final date = local == null
        ? ''
        : '${local.day} ${months[local.month - 1]} ${local.year}';
    final description = available
        ? expired
              ? 'VPN access expired $date. Add time on Mullvad.'
              : 'Renew by $date.'
        : account?['state'] == 'notConfigured'
        ? 'Automatic expiry checks are not configured.'
        : 'Open Mullvad to check or add account time.';

    Widget notice(VoidCallback? followLink) => Material(
      color: color.withValues(alpha: 0.065),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: followLink,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                expired || soon
                    ? Icons.event_busy_outlined
                    : Icons.event_available_outlined,
                color: color,
                size: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VPN access',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: theme.textTheme.bodySmall),
                    if (stale) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Cached estimate; latest expiry check failed.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ],
                    if (demo) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Simulated expiry for this preview.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Manage on Mullvad',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new, size: 17, color: color),
            ],
          ),
        ),
      ),
    );

    Future<void> openAccount() async {
      var opened = false;
      try {
        opened = await launchUrl(
          mullvadAccountUrl,
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        );
      } catch (_) {
        // Browser popup restrictions or a missing launcher must not break VPN controls.
      }
      if (!opened && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open Mullvad. Allow pop-ups and try again.',
            ),
          ),
        );
      }
    }

    // Link embeds a web platform view, splitting the canvas around rounded clips.
    // Keep this card Flutter-only while retaining accessible link semantics.
    return MergeSemantics(
      child: Semantics(
        link: true,
        linkUrl: mullvadAccountUrl,
        child: notice(onOpen ?? openAccount),
      ),
    );
  }
}
