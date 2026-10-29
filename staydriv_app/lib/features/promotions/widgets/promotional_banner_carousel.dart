import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/promotion_model.dart';
import '../services/promotion_service.dart';
import '../../food_ordering/screens/food_home_screen.dart';
import '../../food_ordering/screens/restaurant_menu_screen.dart';
import '../../food_ordering/models/food_models.dart';
import '../../food_ordering/services/food_service.dart';
import '../../ride_selection/screens/ride_selection_screen.dart';
import 'promotional_video_dialog.dart';

class PromotionalBannerCarousel extends StatefulWidget {
  final String screen; // 'home' or 'food'
  final EdgeInsetsGeometry padding;
  final double height;

  const PromotionalBannerCarousel({
    super.key,
    required this.screen,
    this.padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    this.height = 168.0,
  });

  @override
  State<PromotionalBannerCarousel> createState() => _PromotionalBannerCarouselState();
}

class _PromotionalBannerCarouselState extends State<PromotionalBannerCarousel> {
  final PromotionService _promoService = PromotionService();
  final PageController _pageController = PageController();
  
  List<PromotionItem> _promotions = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  Timer? _autoSlideTimer;
  final Set<String> _recordedImpressions = {};

  @override
  void initState() {
    super.initState();
    _loadPromotions();

    // Listen to real-time updates from Socket.IO / service
    final notifier = widget.screen == 'home' 
        ? _promoService.homePromotionsNotifier 
        : _promoService.foodPromotionsNotifier;

    notifier.addListener(_onPromotionsUpdated);
  }

  void _onPromotionsUpdated() {
    if (!mounted) return;
    final notifier = widget.screen == 'home' 
        ? _promoService.homePromotionsNotifier 
        : _promoService.foodPromotionsNotifier;
    
    setState(() {
      _promotions = notifier.value;
      if (_currentIndex >= _promotions.length) {
        _currentIndex = 0;
      }
    });
    _restartAutoSlideTimer();
    _recordCurrentImpression();
  }

  Future<void> _loadPromotions() async {
    final items = await _promoService.fetchActivePromotions(widget.screen);
    if (!mounted) return;
    setState(() {
      _promotions = items;
      _isLoading = false;
      _currentIndex = 0;
    });
    _restartAutoSlideTimer();
    _recordCurrentImpression();
  }

  void _restartAutoSlideTimer() {
    _autoSlideTimer?.cancel();
    if (_promotions.length > 1) {
      _autoSlideTimer = Timer.periodic(const Duration(milliseconds: 4500), (timer) {
        if (!mounted || !_pageController.hasClients || _promotions.isEmpty) return;
        final nextIndex = (_currentIndex + 1) % _promotions.length;
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  void _pauseAutoSlide() {
    _autoSlideTimer?.cancel();
  }

  void _recordCurrentImpression() {
    if (_promotions.isEmpty || _currentIndex >= _promotions.length) return;
    final currentPromo = _promotions[_currentIndex];
    if (!_recordedImpressions.contains(currentPromo.promotionId)) {
      _recordedImpressions.add(currentPromo.promotionId);
      _promoService.recordImpression(currentPromo.promotionId);
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    final notifier = widget.screen == 'home' 
        ? _promoService.homePromotionsNotifier 
        : _promoService.foodPromotionsNotifier;
    notifier.removeListener(_onPromotionsUpdated);
    super.dispose();
  }

  Future<void> _handleBannerTap(PromotionItem promo) async {
    // Record click analytics
    _promoService.recordClick(promo.promotionId);

    // If it's a video advertisement, open the in-app video player
    if (promo.isVideo) {
      PromotionalVideoDialog.show(
        context,
        promo,
        onCtaPressed: () => _executeDestination(promo),
      );
      return;
    }

    _executeDestination(promo);
  }

  Future<void> _executeDestination(PromotionItem promo) async {
    if (!promo.hasClickAction) return;

    try {
      final dest = promo.destinationType.toLowerCase();

      if (dest == 'food' || dest == 'food_screen') {
        if (widget.screen != 'food') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FoodHomeScreen()),
          );
        }
      } else if (dest == 'restaurant') {
        if (promo.destinationId.isNotEmpty) {
          _navigateToRestaurant(promo.destinationId);
        }
      } else if (dest == 'membership') {
        if (widget.screen != 'food') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FoodHomeScreen()),
          );
        }
      } else if (dest == 'ride' || dest == 'ride_screen') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RideSelectionScreen(serviceType: 'auto'),
          ),
        );
      } else if (dest == 'parcel' || dest == 'parcel_screen') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RideSelectionScreen(serviceType: 'parcel'),
          ),
        );
      } else if (dest == 'external_url' || dest == 'url') {
        if (promo.destinationUrl.isNotEmpty) {
          final uri = Uri.tryParse(promo.destinationUrl);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      debugPrint('[PROMOTIONS] Error handling banner destination: $e');
    }
  }

  Future<void> _navigateToRestaurant(String restaurantId) async {
    try {
      final restaurants = await FoodService().fetchRestaurants();
      final match = restaurants.firstWhere(
        (r) => r.restaurantId == restaurantId || r.name.toLowerCase() == restaurantId.toLowerCase(),
        orElse: () => Restaurant(
          restaurantId: restaurantId,
          name: 'Partner Restaurant',
          phone: '',
          cuisines: const ['Special Offers'],
          rating: 4.5,
          deliveryTime: '25-35 mins',
          imageUrl: '',
          address: 'StayDriv Partner',
        ),
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantMenuScreen(
              restaurant: match,
              deliveryAddress: 'Current Location',
              deliveryLat: 17.5169,
              deliveryLng: 78.4435,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PROMOTIONS] Error opening restaurant: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_promotions.isEmpty) {
      return const SizedBox.shrink();
    }

    final isSingle = _promotions.length == 1;
    final primaryColor = widget.screen == 'food' ? const Color(0xFFEA580C) : const Color(0xFF2563EB);

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: widget.height,
            child: Listener(
              onPointerDown: (_) => _pauseAutoSlide(),
              onPointerUp: (_) => _restartAutoSlideTimer(),
              child: PageView.builder(
                controller: _pageController,
                itemCount: _promotions.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  _recordCurrentImpression();
                },
                itemBuilder: (context, index) {
                  final promo = _promotions[index];
                  return _buildZomatoBannerCard(promo);
                },
              ),
            ),
          ),

          // Pagination Dots (Only if multiple promotions)
          if (!isSingle) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_promotions.length, (dotIndex) {
                final isActive = dotIndex == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: isActive ? 20.0 : 6.0,
                  height: 6.0,
                  decoration: BoxDecoration(
                    color: isActive ? primaryColor : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZomatoBannerCard(PromotionItem promo) {
    final hasCta = promo.buttonLabel.isNotEmpty || (promo.hasClickAction && !promo.isVideo);
    final ctaText = promo.buttonLabel.isNotEmpty 
        ? promo.buttonLabel 
        : (widget.screen == 'food' ? 'Order now' : 'Book now');

    return GestureDetector(
      onTap: () => _handleBannerTap(promo),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Artwork / Media Banner (Image / Animated GIF / Video Poster)
              Image.network(
                promo.mediaUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackBanner(promo);
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: const Color(0xFFF8FAFC),
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                        strokeWidth: 2,
                        color: widget.screen == 'food' ? const Color(0xFFEA580C) : const Color(0xFF2563EB),
                      ),
                    ),
                  );
                },
              ),

              // 2. Subtle Gradient Overlay for readable typography
              if (promo.hasOfferText || promo.title.isNotEmpty || hasCta)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.70),
                        ],
                        stops: const [0.0, 0.40, 1.0],
                      ),
                    ),
                  ),
                ),

              // 3. Zomato Center/Bottom Content Layout
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grand Festive / Offer Text (Zomato-Style Bold Heading)
                    if (promo.hasOfferText)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          promo.offerText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: const Color(0xFFFFE4E6),
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.8),
                                blurRadius: 6,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Title & Description
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (promo.title.isNotEmpty)
                                Text(
                                  promo.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: promo.hasOfferText ? 12 : 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(alpha: 0.8),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              if (promo.description.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  promo.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.90),
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(alpha: 0.8),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Zomato-Style Call-to-Action Pill Button with Chevron
                        if (hasCta) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _handleBannerTap(promo),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    ctaText,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 9,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 4. Media Badges (GIF / Video) in Top-Right Corner
              if (promo.isVideo || promo.isGif)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: promo.isVideo 
                          ? Colors.red.withValues(alpha: 0.90) 
                          : const Color(0xFF7C3AED).withValues(alpha: 0.90),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          promo.isVideo ? Icons.play_arrow_rounded : Icons.gif_box_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          promo.isVideo ? 'VIDEO' : 'GIF',
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackBanner(PromotionItem promo) {
    final isFood = widget.screen == 'food';
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isFood 
              ? [const Color(0xFFEA580C), const Color(0xFFF97316)] 
              : [const Color(0xFF1E40AF), const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isFood ? Icons.fastfood_rounded : Icons.directions_car_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (promo.hasOfferText)
                  Text(
                    promo.offerText,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFFE4E6),
                    ),
                  ),
                Text(
                  promo.title.isNotEmpty ? promo.title : 'StayDriv Promotions',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                if (promo.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    promo.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
