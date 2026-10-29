import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme.dart';
import '../../../core/network_config.dart';
import '../../../core/api_client.dart';
import '../../../core/firebase_service.dart';

class ShareStayDrivSheet extends StatefulWidget {
  final bool isPilot;
  final String? referralCode;

  const ShareStayDrivSheet({
    super.key,
    this.isPilot = false,
    this.referralCode,
  });

  static Future<void> show(BuildContext context, {bool isPilot = false, String? referralCode}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareStayDrivSheet(isPilot: isPilot, referralCode: referralCode),
    );
  }

  @override
  State<ShareStayDrivSheet> createState() => _ShareStayDrivSheetState();
}

class _ShareStayDrivSheetState extends State<ShareStayDrivSheet> {
  final String _cdnBase = 'https://dk60tgl9yds4p.cloudfront.net';
  late final String _refParam = widget.isPilot ? 'pilot_share' : 'customer_share';
  late final String _shareUrl = widget.isPilot
      ? '$_cdnBase/staydriv-pilot.apk?ref=$_refParam'
      : '$_cdnBase/book?ref=$_refParam';
  
  String get _shareText {
    if (widget.isPilot) {
      return 'Drive with StayDriv — Earn up to ₹35,000/month with 85% payout & instant withdrawals! Download Pilot Partner App: $_shareUrl';
    } else {
      return 'Hey! Book safe & affordable rides on StayDriv (Bike, Auto, Cab & Round Trips). Tap here to open or download: $_shareUrl';
    }
  }

  Future<void> _trackShare(String channel) async {
    try {
      final baseUrl = NetworkConfig.backendUrl;
      final uid = FirebaseService().currentUid ?? 'user_${widget.isPilot ? 'pilot' : 'customer'}';
      final url = Uri.parse('$baseUrl/api/share/track');
      await ApiClient().post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'channel': channel,
          'role': widget.isPilot ? 'pilot' : 'customer',
          'refCode': widget.referralCode ?? _refParam,
          'userId': uid,
        }),
      );
    } catch (e) {
      debugPrint('[ShareSheet] Track error: $e');
    }
  }

  Future<void> _shareViaWhatsApp() async {
    await _trackShare('whatsapp');
    final whatsappUrl = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(_shareText)}');
    final webUrl = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(_shareText)}');
    try {
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareViaSms() async {
    await _trackShare('sms');
    final smsUri = Uri(
      scheme: 'sms',
      path: '',
      queryParameters: {'body': _shareText},
    );
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        _copyToClipboard();
      }
    } catch (_) {
      _copyToClipboard();
    }
  }

  Future<void> _shareViaInstagram() async {
    await _trackShare('instagram');
    await Clipboard.setData(ClipboardData(text: _shareText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share text copied! Opening Instagram...'),
        backgroundColor: Color(0xFFE1306C),
        duration: Duration(seconds: 2),
      ),
    );
    final igUri = Uri.parse('instagram://app');
    final webUri = Uri.parse('https://instagram.com');
    try {
      if (await canLaunchUrl(igUri)) {
        await launchUrl(igUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareViaArattai() async {
    await _trackShare('arattai');
    final arattaiUri = Uri.parse('arattai://send?text=${Uri.encodeComponent(_shareText)}');
    final playStoreUri = Uri.parse('https://play.google.com/store/apps/details?id=com.zoho.arattai');
    try {
      if (await canLaunchUrl(arattaiUri)) {
        await launchUrl(arattaiUri, mode: LaunchMode.externalApplication);
      } else {
        await _copyToClipboard();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link copied to clipboard! Paste it directly in Arattai.'),
            backgroundColor: Color(0xFF007ACC),
          ),
        );
      }
    } catch (_) {
      _copyToClipboard();
    }
  }

  Future<void> _shareViaFacebook() async {
    await _trackShare('facebook');
    final fbWeb = Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_shareUrl)}&quote=${Uri.encodeComponent(_shareText)}');
    await launchUrl(fbWeb, mode: LaunchMode.externalApplication);
  }

  Future<void> _shareNative() async {
    await _trackShare('native');
    // Using SMS or system share scheme fallback
    final shareUri = Uri(
      scheme: 'sms',
      path: '',
      queryParameters: {'body': _shareText},
    );
    try {
      if (await canLaunchUrl(shareUri)) {
        await launchUrl(shareUri);
      } else {
        _copyToClipboard();
      }
    } catch (_) {
      _copyToClipboard();
    }
  }

  Future<void> _copyToClipboard() async {
    await _trackShare('copy_link');
    await Clipboard.setData(ClipboardData(text: _shareUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('StayDriv App link copied to clipboard!'),
            ],
          ),
          backgroundColor: AppTheme.primaryColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header badge & title
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icon(
                    widget.isPilot ? Icons.drive_eta_rounded : Icons.share_rounded,
                    color: AppTheme.primaryColor,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.isPilot ? 'Invite Fellow Pilots' : 'Share StayDriv App',
                      style: GoogleFonts.hankenGrotesk(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.onSurfaceColor,
                      ),
                    ),
                    Text(
                      widget.isPilot
                          ? 'Share Pilot Partner app & earn referral bonuses'
                          : 'Share with friends & family for reliable rides',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Preview Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44,
                    height: 44,
                    color: AppTheme.primaryColor,
                    child: Center(
                      child: Text(
                        'SD',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isPilot ? 'StayDriv Pilot Partner App' : 'StayDriv Customer App',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.onSurfaceColor,
                        ),
                      ),
                      Text(
                        _shareUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _copyToClipboard,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Text(
                    'Copy',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Platform sharing icons grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildShareChannelItem(
                icon: Icons.chat_rounded,
                color: const Color(0xFF25D366),
                label: 'WhatsApp',
                onTap: _shareViaWhatsApp,
              ),
              _buildShareChannelItem(
                icon: Icons.camera_alt_rounded,
                color: const Color(0xFFE1306C),
                label: 'Instagram',
                onTap: _shareViaInstagram,
              ),
              _buildShareChannelItem(
                icon: Icons.forum_rounded,
                color: const Color(0xFF007ACC),
                label: 'Arattai',
                onTap: _shareViaArattai,
              ),
              _buildShareChannelItem(
                icon: Icons.sms_rounded,
                color: const Color(0xFF34B7F1),
                label: 'SMS',
                onTap: _shareViaSms,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildShareChannelItem(
                icon: Icons.facebook_rounded,
                color: const Color(0xFF1877F2),
                label: 'Facebook',
                onTap: _shareViaFacebook,
              ),
              _buildShareChannelItem(
                icon: Icons.link_rounded,
                color: const Color(0xFF6B7280),
                label: 'Copy Link',
                onTap: _copyToClipboard,
              ),
              _buildShareChannelItem(
                icon: Icons.share_rounded,
                color: AppTheme.primaryColor,
                label: 'More Apps',
                onTap: _shareNative,
              ),
              const SizedBox(width: 60), // balance row
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareChannelItem({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(icon, color: color, size: 26),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurfaceColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
