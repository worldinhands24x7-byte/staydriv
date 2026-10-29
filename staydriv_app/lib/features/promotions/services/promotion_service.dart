import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/network_config.dart';
import '../../../core/socket_service.dart';
import '../models/promotion_model.dart';

class PromotionService {
  static final PromotionService _instance = PromotionService._internal();
  factory PromotionService() => _instance;
  PromotionService._internal() {
    _initSocket();
  }

  String get baseUrl => NetworkConfig.backendUrl;

  // In-memory cache by screen with timestamp
  final Map<String, List<PromotionItem>> _cache = {};
  final Map<String, DateTime> _cacheTimes = {};
  static const Duration _cacheTtl = Duration(seconds: 45);

  // Notifiers for real-time reactive UI updates
  final ValueNotifier<List<PromotionItem>> homePromotionsNotifier = ValueNotifier<List<PromotionItem>>([]);
  final ValueNotifier<List<PromotionItem>> foodPromotionsNotifier = ValueNotifier<List<PromotionItem>>([]);

  void _initSocket() {
    try {
      SocketService().addPromotionsUpdatedListener((data) {
        debugPrint('[PROMOTIONS] Received real-time promotions_updated event: $data');
        clearCache();
        // Trigger background refresh for active screens
        fetchActivePromotions('home', forceRefresh: true);
        fetchActivePromotions('food', forceRefresh: true);
      });
    } catch (e) {
      debugPrint('[PROMOTIONS] Socket listener init warning: $e');
    }
  }

  void clearCache() {
    _cache.clear();
    _cacheTimes.clear();
  }

  /// Fetches eligible, active promotions for the specified screen ('home' or 'food')
  Future<List<PromotionItem>> fetchActivePromotions(String screen, {bool forceRefresh = false}) async {
    final normalizedScreen = screen.toLowerCase().trim();

    // Check cache validity if not forcing refresh
    if (!forceRefresh && _cache.containsKey(normalizedScreen)) {
      final cachedAt = _cacheTimes[normalizedScreen];
      if (cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl) {
        return _cache[normalizedScreen]!;
      }
    }

    try {
      final url = Uri.parse('$baseUrl/api/promotions/active?screen=$normalizedScreen');
      final response = await http.get(
        url,
        headers: NetworkConfig.standardBypassHeaders,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['promotions'] is List) {
          final List<PromotionItem> items = (data['promotions'] as List)
              .map((p) => PromotionItem.fromJson(p as Map<String, dynamic>))
              .toList();

          _cache[normalizedScreen] = items;
          _cacheTimes[normalizedScreen] = DateTime.now();

          // Update ValueNotifiers
          if (normalizedScreen == 'home') {
            homePromotionsNotifier.value = items;
          } else if (normalizedScreen == 'food') {
            foodPromotionsNotifier.value = items;
          }

          return items;
        }
      }
    } catch (e) {
      debugPrint('[PROMOTIONS] Error fetching active promotions for $normalizedScreen: $e');
    }

    // Return cached items as fallback if network fails
    return _cache[normalizedScreen] ?? [];
  }

  /// Records an impression (view) asynchronously without blocking UI
  Future<void> recordImpression(String promotionId) async {
    if (promotionId.isEmpty) return;
    try {
      final url = Uri.parse('$baseUrl/api/promotions/$promotionId/impression');
      await http.post(
        url,
        headers: NetworkConfig.standardBypassHeaders,
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[PROMOTIONS] Error recording impression: $e');
    }
  }

  /// Records a click asynchronously without blocking UI
  Future<void> recordClick(String promotionId) async {
    if (promotionId.isEmpty) return;
    try {
      final url = Uri.parse('$baseUrl/api/promotions/$promotionId/click');
      await http.post(
        url,
        headers: NetworkConfig.standardBypassHeaders,
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[PROMOTIONS] Error recording click: $e');
    }
  }
}
