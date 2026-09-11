import 'package:flutter/material.dart';
import '../../app/app_colors.dart';
import '../../app/app_text_styles.dart';

class AdminStatCard extends StatelessWidget {
  const AdminStatCard({super.key, required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.bar_chart_outlined, color: AppColors.ocean),
      const SizedBox(height: 12),
      Text('$value', style: AppTextStyles.title),
      const SizedBox(height: 6),
      Text(label, style: AppTextStyles.secondary),
    ]),
  ));
}
