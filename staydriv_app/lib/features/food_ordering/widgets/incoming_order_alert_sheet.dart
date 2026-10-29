import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/call_masking_service.dart';
import '../models/food_models.dart';
import '../services/restaurant_order_ringtone_service.dart';

/// Modal & Dialog for Live Incoming Food Orders with High-Volume Ringtone Alerts,
/// Accept/Reject buttons, prep time selector, and Order Alert Settings.
class IncomingOrderAlertSheet extends StatefulWidget {
  final FoodOrder order;
  final int currentQueueIndex;
  final int totalQueueCount;
  final Function(FoodOrder order, String prepTime) onAccept;
  final Function(FoodOrder order, String reason) onReject;
  final VoidCallback onMute;
  final VoidCallback onClose;

  const IncomingOrderAlertSheet({
    super.key,
    required this.order,
    this.currentQueueIndex = 1,
    this.totalQueueCount = 1,
    required this.onAccept,
    required this.onReject,
    required this.onMute,
    required this.onClose,
  });

  static Future<void> show({
    required BuildContext context,
    required FoodOrder order,
    int currentQueueIndex = 1,
    int totalQueueCount = 1,
    required Function(FoodOrder order, String prepTime) onAccept,
    required Function(FoodOrder order, String reason) onReject,
    required VoidCallback onMute,
    required VoidCallback onClose,
  }) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => IncomingOrderAlertSheet(
        order: order,
        currentQueueIndex: currentQueueIndex,
        totalQueueCount: totalQueueCount,
        onAccept: onAccept,
        onReject: onReject,
        onMute: onMute,
        onClose: onClose,
      ),
    );
  }

  @override
  State<IncomingOrderAlertSheet> createState() => _IncomingOrderAlertSheetState();
}

class _IncomingOrderAlertSheetState extends State<IncomingOrderAlertSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnimation;
  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  String _selectedPrepTime = '25 mins';
  bool _isAccepting = false;
  bool _isRejecting = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _calcElapsed();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _calcElapsed();
    });
  }

  void _calcElapsed() {
    final placed = widget.order.placedAt;
    setState(() {
      _elapsed = DateTime.now().difference(placed);
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  String _formatElapsed() {
    final m = _elapsed.inMinutes;
    final s = _elapsed.inSeconds % 60;
    if (m > 0) return '${m}m ${s}s ago';
    return '${s}s ago';
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isOnlinePayment = order.paymentMethod.toLowerCase() != 'cod';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Dark executive slate
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x66F59E0B),
            blurRadius: 30,
            spreadRadius: 2,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Drag Handle & Ringing Status
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Animated Pulsating Ringing Banner
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFDC2626), Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x44DC2626),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '🚨 NEW INCOMING ORDER (RINGING)',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (widget.totalQueueCount > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.currentQueueIndex} of ${widget.totalQueueCount}',
                            style: GoogleFonts.robotoMono(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      // Quick silence button
                      InkWell(
                        onTap: widget.onMute,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.volume_off_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text('Silence', style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Header: Order ID & Elapsed Timer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.orderId}',
                        style: GoogleFonts.robotoMono(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Placed ${_formatElapsed()}',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFF59E0B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isOnlinePayment ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      border: Border.all(
                        color: isOnlinePayment ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOnlinePayment ? 'PAID ONLINE' : 'CASH ON DELIVERY',
                      style: GoogleFonts.inter(
                        color: isOnlinePayment ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 14),

              // Customer & Delivery Address Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline_rounded, color: Color(0xFF94A3B8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.customerName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (order.customerPhone.isNotEmpty)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF38BDF8), size: 18),
                            onPressed: () async {
                              await CallMaskingService().callFoodOrder(
                                orderId: order.orderId,
                                callerRole: 'restaurant',
                                targetRole: 'customer',
                                contactName: order.customerName.isNotEmpty ? order.customerName : 'Customer',
                                context: context,
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, color: Color(0xFF94A3B8), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.deliveryAddress,
                            style: GoogleFonts.inter(
                              color: const Color(0xFFCBD5E1),
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Food Items List Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ORDER ITEMS (${order.items.length})',
                          style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'TOTAL: ₹${order.totalAmount.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF38BDF8),
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...order.items.map((item) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF334155),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${item.quantity}x',
                                style: GoogleFonts.robotoMono(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.item.name,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (item.customization.isNotEmpty)
                                    Text(
                                      item.customization,
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFF94A3B8),
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${(item.item.price * item.quantity).toStringAsFixed(0)}',
                              style: GoogleFonts.inter(
                                color: const Color(0xFFCBD5E1),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Preparation Time Selector
              Text(
                'ESTIMATED KITCHEN PREPARATION TIME:',
                style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['15 mins', '25 mins', '35 mins', '45 mins'].map((time) {
                  final isSel = _selectedPrepTime == time;
                  return ChoiceChip(
                    label: Text(time),
                    selected: isSel,
                    onSelected: (val) {
                      if (val) setState(() => _selectedPrepTime = time);
                    },
                    selectedColor: const Color(0xFF2563EB),
                    backgroundColor: const Color(0xFF1E293B),
                    labelStyle: GoogleFonts.inter(
                      color: isSel ? Colors.white : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              // Action Buttons: ACCEPT & REJECT
              Row(
                children: [
                  // Reject Button
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isAccepting || _isRejecting
                          ? null
                          : () => _promptRejectionReason(context),
                      child: Text(
                        'Reject',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Accept Button (Prominent)
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      onPressed: _isAccepting || _isRejecting
                          ? null
                          : () {
                              setState(() => _isAccepting = true);
                              widget.onAccept(widget.order, _selectedPrepTime);
                            },
                      icon: _isAccepting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 20),
                      label: Text(
                        _isAccepting ? 'Accepting...' : 'Accept Order',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptRejectionReason(BuildContext context) {
    final reasonCtrl = TextEditingController(text: 'Kitchen at full capacity');
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Specify Rejection Reason',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order #${widget.order.orderId} will be cancelled and the customer will be refunded:',
                style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Back', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _isRejecting = true);
                widget.onReject(widget.order, reasonCtrl.text.trim());
              },
              child: const Text('Confirm Reject', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
}

/// Order Alert Settings Dialog
class OrderAlertSettingsDialog extends StatefulWidget {
  const OrderAlertSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const OrderAlertSettingsDialog(),
    );
  }

  @override
  State<OrderAlertSettingsDialog> createState() => _OrderAlertSettingsDialogState();
}

class _OrderAlertSettingsDialogState extends State<OrderAlertSettingsDialog> {
  final RestaurantOrderRingtoneService _ringtoneService = RestaurantOrderRingtoneService();
  String _permissionStatus = 'Checking...';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await _ringtoneService.getNotificationPermission();
    if (mounted) {
      setState(() {
        _permissionStatus = status;
      });
    }
  }

  Future<void> _requestPermission() async {
    final status = await _ringtoneService.requestNotificationPermission();
    if (mounted) {
      setState(() {
        _permissionStatus = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF0F172A),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.volume_up_rounded, color: Color(0xFF38BDF8), size: 24),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Order Alert Settings',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 18),

              // 1. Enable/Disable Ringtone
              ValueListenableBuilder<bool>(
                valueListenable: _ringtoneService.soundEnabledNotifier,
                builder: (context, enabled, _) {
                  return SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Incoming Order Ringtone',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      enabled ? 'Loud sound repeats continuously for new orders' : 'Ringtone is muted',
                      style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                    ),
                    value: enabled,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => _ringtoneService.setSoundEnabled(val),
                  );
                },
              ),

              const SizedBox(height: 12),

              // 2. Volume Preference
              ValueListenableBuilder<double>(
                valueListenable: _ringtoneService.volumeNotifier,
                builder: (context, volume, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Alert Volume',
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          Text(
                            '${(volume * 100).toInt()}%',
                            style: GoogleFonts.robotoMono(color: const Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      Slider(
                        value: volume,
                        min: 0.1,
                        max: 1.0,
                        divisions: 9,
                        activeColor: const Color(0xFF2563EB),
                        inactiveColor: Colors.white24,
                        onChanged: (val) => _ringtoneService.setVolume(val),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 12),

              // 3. Test Ringtone Button
              ValueListenableBuilder<bool>(
                valueListenable: _ringtoneService.isRingingNotifier,
                builder: (context, isRinging, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRinging ? const Color(0xFFEF4444) : const Color(0xFF334155),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _ringtoneService.testRingtone(),
                      icon: Icon(isRinging ? Icons.stop_rounded : Icons.play_arrow_rounded),
                      label: Text(
                        isRinging ? 'Stop Test Sound' : 'Test Ringtone (4s)',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 18),

              // 4. Notification Permission Status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined, color: Color(0xFF94A3B8), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Browser & Device Notifications',
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Status: ${_permissionStatus.toUpperCase()}',
                          style: GoogleFonts.inter(
                            color: _permissionStatus == 'granted' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_permissionStatus != 'granted' && _permissionStatus != 'unsupported')
                          TextButton(
                            onPressed: _requestPermission,
                            child: const Text('Allow', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 5. Practical Advisory
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Important: In a noisy kitchen, set device volume to maximum. Tap anywhere on the screen at least once during startup to allow web audio playback.',
                        style: GoogleFonts.inter(color: const Color(0xFFFCD34D), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
