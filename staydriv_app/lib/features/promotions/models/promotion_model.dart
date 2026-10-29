class PromotionItem {
  final String promotionId;
  final String title;
  final String description;
  final String mediaType; // 'image', 'gif', 'video'
  final String mediaUrl;
  final String thumbnailUrl;
  final String targetScreen; // 'home', 'food', 'both'
  final String destinationType; // 'none', 'food_screen', 'restaurant', 'membership', 'external_url'
  final String destinationId;
  final String destinationUrl;
  final String offerText;
  final String buttonLabel;
  final int displayOrder;
  final DateTime? startAt;
  final DateTime? endAt;

  PromotionItem({
    required this.promotionId,
    required this.title,
    this.description = '',
    this.mediaType = 'image',
    required this.mediaUrl,
    this.thumbnailUrl = '',
    this.targetScreen = 'both',
    this.destinationType = 'none',
    this.destinationId = '',
    this.destinationUrl = '',
    this.offerText = '',
    this.buttonLabel = '',
    this.displayOrder = 0,
    this.startAt,
    this.endAt,
  });

  bool get isVideo => mediaType == 'video';
  bool get isGif => mediaType == 'gif';
  bool get hasClickAction => destinationType != 'none' && destinationType.isNotEmpty;
  bool get hasOfferText => offerText.trim().isNotEmpty;
  bool get hasButtonLabel => buttonLabel.trim().isNotEmpty;

  factory PromotionItem.fromJson(Map<String, dynamic> json) {
    return PromotionItem(
      promotionId: (json['promotionId'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      mediaType: (json['mediaType'] ?? 'image').toString().toLowerCase(),
      mediaUrl: (json['mediaUrl'] ?? '').toString(),
      thumbnailUrl: (json['thumbnailUrl'] ?? '').toString(),
      targetScreen: (json['targetScreen'] ?? 'both').toString().toLowerCase(),
      destinationType: (json['destinationType'] ?? 'none').toString().toLowerCase(),
      destinationId: (json['destinationId'] ?? '').toString(),
      destinationUrl: (json['destinationUrl'] ?? '').toString(),
      offerText: (json['offerText'] ?? json['discountText'] ?? '').toString(),
      buttonLabel: (json['buttonLabel'] ?? '').toString(),
      displayOrder: json['displayOrder'] is int
          ? json['displayOrder']
          : (int.tryParse(json['displayOrder']?.toString() ?? '0') ?? 0),
      startAt: json['startAt'] != null ? DateTime.tryParse(json['startAt'].toString()) : null,
      endAt: json['endAt'] != null ? DateTime.tryParse(json['endAt'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'promotionId': promotionId,
      'title': title,
      'description': description,
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'thumbnailUrl': thumbnailUrl,
      'targetScreen': targetScreen,
      'destinationType': destinationType,
      'destinationId': destinationId,
      'destinationUrl': destinationUrl,
      'offerText': offerText,
      'buttonLabel': buttonLabel,
      'displayOrder': displayOrder,
      'startAt': startAt?.toIso8601String(),
      'endAt': endAt?.toIso8601String(),
    };
  }
}
