import 'package:flutter/material.dart';
import '../../app/app_colors.dart';
import '../../app/app_text_styles.dart';

/// Shared by page bodies and headers so their desktop edges stay aligned.
double appContentWidth(double viewportWidth) {
  if (viewportWidth >= 1200) return 1000;
  if (viewportWidth >= 1000) return 900;
  return 760;
}

EdgeInsets appPagePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final gutter = ((width - appContentWidth(width)) / 2)
      .clamp(20.0, double.infinity)
      .toDouble();
  return EdgeInsets.symmetric(horizontal: gutter, vertical: 20);
}

class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader(this.title, {super.key, this.subtitle, this.spacious = false});
  final String title;
  final String? subtitle;
  final bool spacious;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: spacious ? 24 : 12, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.section),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppTextStyles.secondary),
        ],
      ],
    ),
  );
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final value = status.toLowerCase();
    final cancelled = value == 'cancelled';
    final accepted = value == 'accepted' || value == 'completed';
    final closed = value == 'closed';
    final foreground = cancelled
        ? AppColors.error
        : accepted
        ? AppColors.success
        : closed
        ? AppColors.secondary
        : AppColors.ocean;
    final background = cancelled
        ? AppColors.errorSurface
        : accepted
        ? AppColors.successSurface
        : closed
        ? AppColors.pearl
        : AppColors.softBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: AppTextStyles.status.copyWith(color: foreground),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.route_outlined,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: AppColors.ocean),
          const SizedBox(height: 14),
          Text(
            title,
            style: AppTextStyles.cardTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppTextStyles.secondary,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class AppBrandHeader extends StatelessWidget {
  const AppBrandHeader({super.key, this.logo});
  final Widget? logo;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      children: [
        logo ??
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.ocean,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.explore_outlined,
                color: AppColors.gold,
                size: 26,
              ),
            ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('Ceylon Travel', style: AppTextStyles.section),
        ),
      ],
    ),
  );
}

class AppRoute extends StatelessWidget {
  const AppRoute({super.key, required this.pickup, required this.destination});
  final String pickup;
  final String destination;
  Widget _stop(String label, String value, IconData icon) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: AppColors.ocean),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            Text(value, style: AppTextStyles.cardTitle),
          ],
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _stop('Pickup', pickup, Icons.radio_button_checked),
      Container(
        height: 16,
        width: 1,
        margin: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
        color: AppColors.border,
      ),
      _stop('Destination', destination, Icons.location_on_outlined),
    ],
  );
}

class AppInfoCard extends StatelessWidget {
  const AppInfoCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

/// Aligns desktop page titles with their content while retaining native app-bar
/// navigation and the existing compact layout on mobile.
class AppPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppPageAppBar({
    super.key,
    required this.title,
    this.actions,
    this.contentWidth,
  });

  final Widget title;
  final List<Widget>? actions;
  final double? contentWidth;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final pageWidth = contentWidth ?? appContentWidth(constraints.maxWidth);
      if (constraints.maxWidth <= pageWidth + 48) {
        return AppBar(title: title, actions: actions);
      }
      final gutter = (constraints.maxWidth - pageWidth) / 2;
      final hasBackButton = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
      // Reserve space outside the content edge for the automatic back button.
      final leadingWidth = hasBackButton ? gutter.clamp(0.0, 56.0).toDouble() : 0.0;
      return Padding(
        padding: EdgeInsets.only(left: gutter - leadingWidth, right: gutter),
        child: AppBar(
          title: title,
          actions: actions,
          titleSpacing: 0,
          leadingWidth: hasBackButton ? leadingWidth : null,
        ),
      );
    },
  );
}
