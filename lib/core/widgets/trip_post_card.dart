import 'package:flutter/material.dart';

import 'info_line.dart';

class TripPostCard extends StatelessWidget {
  const TripPostCard({
    super.key,
    required this.pickup,
    required this.drop,
    required this.dateTime,
    required this.passengers,
    required this.baggage,
    required this.status,
  });

  final String pickup;
  final String drop;
  final String dateTime;
  final String passengers;
  final String baggage;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              label: Text(
                status,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: const Color(0xFFE0F2F1),
              side: BorderSide.none,
            ),
            const SizedBox(height: 8),
            Text(
              '$pickup → $drop',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InfoLine(icon: Icons.calendar_month_outlined, text: dateTime),
            InfoLine(icon: Icons.group_outlined, text: passengers),
            InfoLine(icon: Icons.luggage_outlined, text: baggage),
          ],
        ),
      ),
    );
  }
}
