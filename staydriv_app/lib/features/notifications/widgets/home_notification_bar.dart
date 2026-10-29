import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../models/in_app_notification_model.dart';
import '../services/notification_inbox_service.dart';
import '../screens/notifications_center_sheet.dart';

class HomeNotificationBar extends StatelessWidget {
  const HomeNotificationBar({super.key});

  @override
  Widget build(BuildContext context) {
    final inboxService = NotificationInboxService();

    return ValueListenableBuilder<InAppNotificationItem?>(
      valueListenable: inboxService.latestNotificationNotifier,
      builder: (context, latest, _) {
        return ValueListenableBuilder<int>(
          valueListenable: inboxService.unreadCountNotifier,
          builder: (context, unreadCount, _) {
            final hasUnread = latest != null && !latest.isRead;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => NotificationsCenterSheet.show(context),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A), // Dark navy matching screenshot
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasUnread 
                            ? AppTheme.primaryColor.withOpacity(0.6) 
                            : const Color(0xFF1E293B),
                        width: hasUnread ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: hasUnread
                              ? AppTheme.primaryColor.withOpacity(0.18)
                              : Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: hasUnread 
                                ? AppTheme.primaryColor.withOpacity(0.2) 
                                : Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            hasUnread
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            color: hasUnread ? AppTheme.primaryColor : Colors.white70,
                            size: 17,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: hasUnread
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          latest.title,
                                          style: GoogleFonts.inter(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'NEW',
                                            style: GoogleFonts.inter(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      latest.body,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.white.withOpacity(0.85),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                )
                              : Text(
                                  'No new notifications',
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: hasUnread ? AppTheme.primaryColor : Colors.white54,
                          size: 19,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
