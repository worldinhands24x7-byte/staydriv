class InAppNotificationItem {
  final String id;
  final String? campaignId;
  final String title;
  final String body;
  final String type; // 'push', 'promo', 'alert', 'emergency'
  final String targetGroup;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? destination;

  InAppNotificationItem({
    required this.id,
    this.campaignId,
    required this.title,
    required this.body,
    this.type = 'push',
    this.targetGroup = 'all',
    required this.createdAt,
    this.isRead = false,
    this.destination,
  });

  factory InAppNotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    try {
      parsedDate = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now();
    } catch (_) {
      parsedDate = DateTime.now();
    }

    return InAppNotificationItem(
      id: json['id']?.toString() ?? json['notificationId']?.toString() ?? '',
      campaignId: json['campaignId']?.toString(),
      title: json['title']?.toString() ?? 'StayDriv Notification',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? 'push',
      targetGroup: json['targetGroup']?.toString() ?? 'all',
      createdAt: parsedDate,
      isRead: json['isRead'] == true,
      destination: json['destination'] is Map<String, dynamic>
          ? json['destination'] as Map<String, dynamic>
          : null,
    );
  }

  InAppNotificationItem copyWith({
    bool? isRead,
  }) {
    return InAppNotificationItem(
      id: id,
      campaignId: campaignId,
      title: title,
      body: body,
      type: type,
      targetGroup: targetGroup,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      destination: destination,
    );
  }
}
