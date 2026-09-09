import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/bid.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/trip_post.dart';
import '../../core/widgets/info_line.dart';

const List<ChatMessage> _sampleMessages = [
  ChatMessage(
    id: 'message-1',
    senderName: 'System',
    message: 'Bid accepted',
    type: 'system',
    time: '8:45 AM',
    isMe: false,
  ),
  ChatMessage(
    id: 'message-2',
    senderName: 'You',
    message: 'Hi, please meet us near the airport arrivals gate.',
    type: 'text',
    time: '8:46 AM',
    isMe: true,
  ),
  ChatMessage(
    id: 'message-3',
    senderName: 'Nimal Perera',
    message: 'Sure. I will arrive 15 minutes early.',
    type: 'text',
    time: '8:47 AM',
    isMe: false,
  ),
  ChatMessage(
    id: 'message-4',
    senderName: 'You',
    message: 'Location shared',
    type: 'location',
    time: '8:48 AM',
    isMe: true,
  ),
];

class TripChatScreen extends StatelessWidget {
  const TripChatScreen({
    super.key,
    required this.tripPost,
    required this.acceptedBid,
  });

  final TripPost tripPost;
  final Bid acceptedBid;

  void _shareLocation(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo location shared. Real GPS sharing comes later.'),
      ),
    );
  }

  void _copyLocation(BuildContext context, String location, String label) {
    Clipboard.setData(ClipboardData(text: location));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip Chat')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Card(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tripPost.pickup} -> ${tripPost.drop}',
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(height: 8),
                      InfoLine(
                        icon: Icons.local_taxi_outlined,
                        text: acceptedBid.driverName,
                      ),
                      InfoLine(
                        icon: Icons.payments_outlined,
                        text: acceptedBid.price,
                      ),
                      const SizedBox(height: 8),
                      const AppStatusChip('PENDING'),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _shareLocation(context),
                    icon: const Icon(Icons.my_location_outlined),
                    label: const Text('Share My Location'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copyLocation(
                      context,
                      tripPost.pickup,
                      'Pickup location',
                    ),
                    icon: const Icon(Icons.content_copy),
                    label: const Text('Copy Pickup Location'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _copyLocation(context, tripPost.drop, 'Drop location'),
                    icon: const Icon(Icons.content_copy),
                    label: const Text('Copy Drop Location'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                itemCount: _sampleMessages.length,
                itemBuilder: (BuildContext context, int index) {
                  return _ChatBubble(message: _sampleMessages[index]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  const Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: () {}, child: const Icon(Icons.send)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isSystem = message.type == 'system';
    final bool isLocation = message.type == 'location';

    if (isSystem) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Chip(
            label: Text('${message.message} - ${message.time}'),
            backgroundColor: AppColors.softBlue,
            side: BorderSide.none,
          ),
        ),
      );
    }

    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          color: message.isMe ? AppColors.ocean : AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName,
                  style: message.isMe
                      ? AppTextStyles.onOcean
                      : AppTextStyles.caption,
                ),
                const SizedBox(height: 6),
                if (isLocation)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            color: message.isMe
                                ? AppColors.surface
                                : AppColors.charcoal,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Location shared',
                            style: AppTextStyles.body.copyWith(
                              color: message.isMe
                                  ? AppColors.surface
                                  : AppColors.charcoal,
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () {},
                        style: TextButton.styleFrom(
                          foregroundColor: message.isMe
                              ? AppColors.surface
                              : null,
                        ),
                        child: const Text('Open in Maps'),
                      ),
                    ],
                  )
                else
                  Text(
                    message.message,
                    style: AppTextStyles.body.copyWith(
                      color: message.isMe
                          ? AppColors.surface
                          : AppColors.charcoal,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  message.time,
                  style: message.isMe
                      ? AppTextStyles.onOcean
                      : AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
