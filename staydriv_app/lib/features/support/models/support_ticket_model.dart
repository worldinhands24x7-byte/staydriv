import 'package:flutter/material.dart';

class SupportMessage {
  final String senderId;
  final String senderName;
  final String senderRole; // 'customer', 'pilot', 'admin', 'system'
  final String message;
  final DateTime timestamp;

  SupportMessage({
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.message,
    required this.timestamp,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    DateTime parsedTime;
    try {
      parsedTime = json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now();
    } catch (_) {
      parsedTime = DateTime.now();
    }

    return SupportMessage(
      senderId: json['senderId']?.toString() ?? '',
      senderName: json['senderName']?.toString() ?? 'Support Agent',
      senderRole: json['senderRole']?.toString() ?? 'admin',
      message: json['message']?.toString() ?? '',
      timestamp: parsedTime,
    );
  }

  Map<String, dynamic> toJson() => {
    'senderId': senderId,
    'senderName': senderName,
    'senderRole': senderRole,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
  };

  bool get isFromUser => senderRole == 'customer' || senderRole == 'pilot';
}

class SupportTicket {
  final String ticketId;
  final String userId;
  final String userType; // 'customer' or 'pilot'
  final String userName;
  final String userPhone;
  final String? rideId;
  final String category; // 'booking', 'payment', 'safety', 'complaint'
  final String subcategory;
  final String subject;
  final String description;
  final String status; // 'OPEN', 'IN_PROGRESS', 'WAITING_FOR_USER', 'RESOLVED', 'CLOSED'
  final String priority; // 'LOW', 'MEDIUM', 'HIGH', 'URGENT'
  final String? assignedAdminId;
  final String? assignedAdminName;
  final List<SupportMessage> chatHistory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  SupportTicket({
    required this.ticketId,
    required this.userId,
    required this.userType,
    required this.userName,
    required this.userPhone,
    this.rideId,
    required this.category,
    required this.subcategory,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    this.assignedAdminId,
    this.assignedAdminName,
    required this.chatHistory,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      try {
        return DateTime.parse(val.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    final rawChat = json['chatHistory'];
    List<SupportMessage> messages = [];
    if (rawChat is List) {
      messages = rawChat.map((m) => SupportMessage.fromJson(Map<String, dynamic>.from(m as Map))).toList();
    }

    return SupportTicket(
      ticketId: json['ticketId']?.toString() ?? json['id']?.toString() ?? 'STY-000000',
      userId: json['userId']?.toString() ?? '',
      userType: json['userType']?.toString() ?? 'customer',
      userName: json['userName']?.toString() ?? 'User',
      userPhone: json['userPhone']?.toString() ?? '',
      rideId: json['rideId']?.toString() ?? json['bookingId']?.toString(),
      category: json['category']?.toString() ?? 'general',
      subcategory: json['subcategory']?.toString() ?? '',
      subject: json['subject']?.toString() ?? 'Support Request',
      description: json['description']?.toString() ?? json['message']?.toString() ?? '',
      status: (json['status']?.toString() ?? 'OPEN').toUpperCase(),
      priority: (json['priority']?.toString() ?? 'MEDIUM').toUpperCase(),
      assignedAdminId: json['assignedAdminId']?.toString(),
      assignedAdminName: json['assignedAdminName']?.toString(),
      chatHistory: messages,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      resolvedAt: json['resolvedAt'] != null ? parseDate(json['resolvedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'ticketId': ticketId,
    'userId': userId,
    'userType': userType,
    'userName': userName,
    'userPhone': userPhone,
    'rideId': rideId,
    'category': category,
    'subcategory': subcategory,
    'subject': subject,
    'description': description,
    'status': status,
    'priority': priority,
    'assignedAdminId': assignedAdminId,
    'assignedAdminName': assignedAdminName,
    'chatHistory': chatHistory.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'resolvedAt': resolvedAt?.toIso8601String(),
  };

  Color get statusColor {
    switch (status) {
      case 'OPEN':
        return Colors.blue.shade700;
      case 'IN_PROGRESS':
        return Colors.amber.shade800;
      case 'WAITING_FOR_USER':
        return Colors.purple.shade700;
      case 'RESOLVED':
        return Colors.green.shade700;
      case 'CLOSED':
        return Colors.grey.shade600;
      default:
        return Colors.blue.shade700;
    }
  }

  String get statusDisplay {
    switch (status) {
      case 'OPEN':
        return 'Open';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'WAITING_FOR_USER':
        return 'Action Required';
      case 'RESOLVED':
        return 'Resolved';
      case 'CLOSED':
        return 'Closed';
      default:
        return status;
    }
  }

  Color get priorityColor {
    switch (priority) {
      case 'URGENT':
        return Colors.red.shade700;
      case 'HIGH':
        return Colors.orange.shade800;
      case 'MEDIUM':
        return Colors.blue.shade700;
      case 'LOW':
        return Colors.grey.shade600;
      default:
        return Colors.blue.shade700;
    }
  }
}
