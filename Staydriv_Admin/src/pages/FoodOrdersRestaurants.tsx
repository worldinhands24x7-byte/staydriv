import React, { useState, useEffect } from 'react';
import { 
  UtensilsCrossed, Search, CheckCircle2, XCircle, Clock, 
  Store, AlertCircle, RefreshCw, Sliders, DollarSign, Eye, X, Check,
  Plus, Edit, Trash2, Menu as MenuIcon, Upload, ImageIcon, Filter,
  TrendingUp, Percent, ChevronRight, Phone, MapPin, Award, FileText,
  ExternalLink, ZoomIn, ShieldCheck, AlertTriangle, Copy, FileCheck, Bike,
  Volume2, VolumeX, BellRing
} from 'lucide-react';

const API_BASE = '/api/food';

export const FoodOrdersRestaurants: React.FC = () => {
  const [activeSubTab, setActiveSubTab] = useState<'orders' | 'restaurants' | 'pending_approvals' | 'settlements' | 'config' | 'coupons'>('restaurants');
  
  // Data states
  const [orders, setOrders] = useState<any[]>([]);
  const [restaurants, setRestaurants] = useState<any[]>([]);
  const [coupons, setCoupons] = useState<any[]>([]);

  // Restaurant Settlements States
  const [settlementOverview, setSettlementOverview] = useState<any>(null);
  const [settlementsList, setSettlementsList] = useState<any[]>([]);
  const [settlementStatusFilter, setSettlementStatusFilter] = useState<string>('all');
  const [settlementViewMode, setSettlementViewMode] = useState<'partners' | 'transactions'>('partners');
  const [loadingSettlements, setLoadingSettlements] = useState<boolean>(false);
  const [settlementSearchQuery, setSettlementSearchQuery] = useState<string>('');

  // Modals for Bank Verification, Initiate Payout, Confirm Payout, Commission Edit
  const [verifyBankModalRest, setVerifyBankModalRest] = useState<any | null>(null);
  const [bankRejectionReason, setBankRejectionReason] = useState<string>('');
  
  const [initiateModalRest, setInitiateModalRest] = useState<any | null>(null);
  const [initiateNotes, setInitiateNotes] = useState<string>('');
  
  const [confirmPayoutModalSettlement, setConfirmPayoutModalSettlement] = useState<any | null>(null);
  const [payoutUtrInput, setPayoutUtrInput] = useState<string>('');
  const [payoutRemarksInput, setPayoutRemarksInput] = useState<string>('');

  const [failPayoutModalSettlement, setFailPayoutModalSettlement] = useState<any | null>(null);
  const [payoutFailReasonInput, setPayoutFailReasonInput] = useState<string>('');

  const [editCommissionRest, setEditCommissionRest] = useState<any | null>(null);
  const [commissionInput, setCommissionInput] = useState<number>(15.0);
  const [settlementActionLoading, setSettlementActionLoading] = useState<boolean>(false);
  const [isAddCouponModalOpen, setIsAddCouponModalOpen] = useState(false);
  const [editingCoupon, setEditingCoupon] = useState<any | null>(null);
  const [couponFormData, setCouponFormData] = useState<any>({
    code: '',
    title: '',
    description: '',
    discountType: 'percentage',
    discountValue: 50,
    minOrderAmount: 99,
    maxDiscountAmount: 70,
    freeDelivery: false,
    restaurantId: '',
    validTill: new Date(Date.now() + 180 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
    isActive: true
  });
  const [stats, setStats] = useState<any>({
    totalRestaurants: 0,
    approvedRestaurants: 0,
    pendingRestaurants: 0,
    totalOrders: 0,
    activeOrders: 0,
    grossMerchandiseValue: 0,
    platformRevenue: 0
  });
  const [counts, setCounts] = useState({
    all: 0,
    pending: 0,
    action_required: 0,
    approved: 0,
    rejected: 0,
    suspended: 0,
    active: 0,
    inactive: 0
  });
  const [config, setConfig] = useState<any>({
    platformFee: 15,
    discountedPlatformFee: 9,
    deliveryBaseFee: 30,
    deliveryPerKmFee: 8,
    defaultPackagingFee: 10,
    taxRatePercent: 5.0,
    defaultCommissionRate: 15.0,
    cashRoundingEnabled: true,
    minOrderAmount: 0
  });

  const [loading, setLoading] = useState(false);
  const [searchTerm, setSearchTerm] = useState(() => {
    const auto = sessionStorage.getItem('admin_auto_filter');
    if (auto) {
      sessionStorage.removeItem('admin_auto_filter');
      return auto;
    }
    return '';
  });

  useEffect(() => {
    const handleSearchNav = (e: any) => {
      if (e.detail?.filter && (e.detail?.tab === 'food-orders' || !e.detail?.tab)) {
        setSearchTerm(e.detail.filter);
        if (e.detail?.item?.module === 'restaurants') {
          setActiveSubTab('restaurants');
        } else if (e.detail?.item?.module === 'food_orders') {
          setActiveSubTab('orders');
        }
      }
    };
    window.addEventListener('admin:search-navigate', handleSearchNav);
    return () => window.removeEventListener('admin:search-navigate', handleSearchNav);
  }, []);
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedOrder, setSelectedOrder] = useState<any | null>(null);
  const [actionSuccessMsg, setActionSuccessMsg] = useState('');
  const [orderAlertSoundEnabled, setOrderAlertSoundEnabled] = useState(true);
  const prevOrdersCountRef = React.useRef(0);

  const playNewOrderAlertChime = () => {
    try {
      const AudioCtx = window.AudioContext || (window as any).webkitAudioContext;
      if (!AudioCtx) return;
      const ctx = new AudioCtx();
      const now = ctx.currentTime;
      [784, 1046.5, 1318.5, 1568].forEach((freq, idx) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'triangle';
        osc.frequency.setValueAtTime(freq, now + idx * 0.15);
        gain.gain.setValueAtTime(0.4, now + idx * 0.15);
        gain.gain.exponentialRampToValueAtTime(0.001, now + idx * 0.15 + 0.22);
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now + idx * 0.15);
        osc.stop(now + idx * 0.15 + 0.22);
      });
    } catch (_) {}
  };

  // Delivery Pilot Assignment States (Strict Bike & Scooty Only)
  const [eligiblePilots, setEligiblePilots] = useState<any[]>([]);
  const [selectedPilotToAssign, setSelectedPilotToAssign] = useState('');
  const [assigningPilot, setAssigningPilot] = useState(false);
  const [pilotAssignError, setPilotAssignError] = useState('');
  const [pilotAssignSuccess, setPilotAssignSuccess] = useState('');

  // ---------------------------------------------------------------------------
  // RESTAURANT MANAGEMENT & APPROVAL STATES (Pictures 1, 2, 3)
  // ---------------------------------------------------------------------------
  const [restSearchQuery, setRestSearchQuery] = useState('');
  const [restStatusFilter, setRestStatusFilter] = useState('all');
  const [isAddEditRestModalOpen, setIsAddEditRestModalOpen] = useState(false);
  const [isEditingRest, setIsEditingRest] = useState(false);
  const [isGeocoding, setIsGeocoding] = useState(false);
  const [restFormData, setRestFormData] = useState<any>({
    restaurantId: '',
    name: '',
    ownerName: '',
    phone: '',
    email: '',
    address: '',
    lat: 17.5230,
    lng: 78.4222,
    cuisines: 'South Indian, Breakfast, Pure Veg, Snacks',
    categories: 'South Indian, Snacks, Breads, Desserts, Beverages',
    openingHours: '07:00 AM - 10:30 PM',
    deliveryFee: 30,
    deliveryTime: '25-35 mins',
    commissionRate: 15.0,
    fssaiNumber: '',
    fssaiDocUrl: '',
    fssaiValidity: '',
    gstNumber: '',
    gstDocUrl: '',
    panNumber: '',
    panDocUrl: '',
    bankAccount: '',
    bankIfsc: '',
    bankHolderName: '',
    upiId: '',
    isVegOnly: false,
    isOpen: true,
    status: 'approved',
    imageUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80'
  });

  // Application Inspection & Review Modals
  const [isAppDetailsModalOpen, setIsAppDetailsModalOpen] = useState(false);
  const [selectedApp, setSelectedApp] = useState<any | null>(null);

  // Approval confirmation modal
  const [isApproveModalOpen, setIsApproveModalOpen] = useState(false);
  const [restaurantToApprove, setRestaurantToApprove] = useState<any | null>(null);
  const [approveNotes, setApproveNotes] = useState('');

  // Rejection modal
  const [isRejectModalOpen, setIsRejectModalOpen] = useState(false);
  const [restaurantToReject, setRestaurantToReject] = useState<any | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');

  // Request Correction modal
  const [isCorrectionModalOpen, setIsCorrectionModalOpen] = useState(false);
  const [restaurantForCorrection, setRestaurantForCorrection] = useState<any | null>(null);
  const [correctionNotes, setCorrectionNotes] = useState('');

  // Document Lightbox Preview
  const [previewDoc, setPreviewDoc] = useState<{ label: string; url: string } | null>(null);
  const [copiedKey, setCopiedKey] = useState<string | null>(null);

  const copyToClipboard = (text: string, key: string) => {
    navigator.clipboard.writeText(text);
    setCopiedKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  // ---------------------------------------------------------------------------
  // MANAGE MENU & EDITABLE RATES STATES (Picture 2)
  // ---------------------------------------------------------------------------
  const [isManageMenuModalOpen, setIsManageMenuModalOpen] = useState(false);
  const [activeRestaurantForMenu, setActiveRestaurantForMenu] = useState<any | null>(null);
  const [menuItems, setMenuItems] = useState<any[]>([]);
  const [loadingMenu, setLoadingMenu] = useState(false);
  const [menuFilterCategory, setMenuFilterCategory] = useState('All');
  const [menuSearchQuery, setMenuSearchQuery] = useState('');

  // Add/Edit Dish Modal
  const [isDishModalOpen, setIsDishModalOpen] = useState(false);
  const [isEditingDish, setIsEditingDish] = useState(false);
  const [dishFormData, setDishFormData] = useState<any>({
    itemId: '',
    name: '',
    category: 'South Indian',
    description: '',
    price: 150,
    discountPrice: 0,
    isVeg: true,
    isAvailable: true,
    prepTime: '20 mins',
    isBestseller: false,
    isRecommended: false,
    imageUrl: 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=800&auto=format&fit=crop&q=80'
  });

  // Price Update states & Bulk Rate Preview states (Picture 2 reference)
  const [savingItemPriceId, setSavingItemPriceId] = useState<string | null>(null);
  const [savedItemIds, setSavedItemIds] = useState<{ [id: string]: boolean }>({});
  const [priceUpdateError, setPriceUpdateError] = useState<string>('');
  
  // Bulk Rate Preview Modal (Picture 2 UX)
  const [isBulkPreviewModalOpen, setIsBulkPreviewModalOpen] = useState(false);
  const [bulkPreviewLoading, setBulkPreviewLoading] = useState(false);
  const [bulkPreviewData, setBulkPreviewData] = useState<{
    delta?: number;
    percentDelta?: number;
    category?: string;
    items: any[];
    affectedCount: number;
    title: string;
  } | null>(null);

  // View Restaurant Orders State
  const [isRestOrdersModalOpen, setIsRestOrdersModalOpen] = useState(false);
  const [activeRestaurantForOrders, setActiveRestaurantForOrders] = useState<any | null>(null);
  const [restaurantOrders, setRestaurantOrders] = useState<any[]>([]);
  const [loadingRestOrders, setLoadingRestOrders] = useState(false);

  // Image Upload state
  const [isUploadingImage, setIsUploadingImage] = useState(false);

  // Fetch initial data
  const fetchData = async () => {
    setLoading(true);
    try {
      // 1. Stats
      const statsRes = await fetch(`${API_BASE}/admin/stats`).then(r => r.json()).catch(() => null);
      if (statsRes?.success) setStats(statsRes.stats);

      // 2. Orders
      const ordersRes = await fetch(`${API_BASE}/admin/orders?status=${statusFilter}&search=${encodeURIComponent(searchTerm)}`)
        .then(r => r.json()).catch(() => null);
      if (ordersRes?.success) {
        const fetchedOrders = ordersRes.orders || [];
        if (orderAlertSoundEnabled && prevOrdersCountRef.current > 0 && fetchedOrders.length > prevOrdersCountRef.current) {
          const hasNewPlaced = fetchedOrders.some((fo: any) => fo.orderStatus === 'placed');
          if (hasNewPlaced) {
            playNewOrderAlertChime();
          }
        }
        prevOrdersCountRef.current = fetchedOrders.length;
        setOrders(fetchedOrders);
      }

      // 3. Restaurants with dynamic counts
      const effectiveFilter = activeSubTab === 'pending_approvals' && restStatusFilter === 'all'
        ? 'pending'
        : restStatusFilter;
      const restRes = await fetch(`${API_BASE}/admin/restaurants?status=${effectiveFilter}&search=${encodeURIComponent(restSearchQuery)}`)
        .then(r => r.json()).catch(() => null);
      if (restRes?.success) {
        setRestaurants(restRes.restaurants || []);
        if (restRes.counts) setCounts(restRes.counts);
      }

      // 4. Config
      const configRes = await fetch(`${API_BASE}/admin/config`).then(r => r.json()).catch(() => null);
      if (configRes?.success) setConfig(configRes.config);

      // 5. Coupons
      const couponsRes = await fetch(`${API_BASE}/admin/coupons`).then(r => r.json()).catch(() => null);
      if (couponsRes?.success) setCoupons(couponsRes.coupons || []);

      // 6. Settlements Overview & Transactions
      const settleOverviewRes = await fetch(`${API_BASE}/admin/settlements/overview`).then(r => r.json()).catch(() => null);
      if (settleOverviewRes?.success) setSettlementOverview(settleOverviewRes);

      const settlementsRes = await fetch(`${API_BASE}/admin/settlements?status=${settlementStatusFilter}&search=${encodeURIComponent(settlementSearchQuery)}`)
        .then(r => r.json()).catch(() => null);
      if (settlementsRes?.success) setSettlementsList(settlementsRes.settlements || []);
    } catch (err) {
      console.error('Error fetching food data:', err);
    } finally {
      setLoading(false);
    }
  };

  const fetchEligiblePilots = async () => {
    try {
      const res = await fetch(`${API_BASE}/admin/eligible-delivery-pilots`).then(r => r.json());
      if (res?.success) {
        setEligiblePilots(res.pilots || []);
      }
    } catch (err) {
      console.error('Error fetching eligible delivery pilots:', err);
    }
  };

  const handleManualAssignPilot = async (orderId: string) => {
    if (!orderId || !selectedPilotToAssign) {
      setPilotAssignError('Please select an eligible Bike or Scooty pilot from the dropdown.');
      return;
    }
    setAssigningPilot(true);
    setPilotAssignError('');
    setPilotAssignSuccess('');
    try {
      const res = await fetch(`${API_BASE}/admin/orders/${orderId}/assign-pilot`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pilotId: selectedPilotToAssign,
          adminName: 'Admin Operations'
        })
      }).then(r => r.json());

      if (res?.success && res.order) {
        setPilotAssignSuccess(`Pilot "${res.order.deliveryPartnerName}" (${res.order.deliveryPartnerVehicleType || 'Bike'}) assigned successfully!`);
        setSelectedOrder(res.order);
        setSelectedPilotToAssign('');
        fetchData();
        setTimeout(() => setPilotAssignSuccess(''), 5000);
      } else {
        setPilotAssignError(res?.message || 'Assignment failed. Only approved Bike and Scooty pilots can be assigned.');
      }
    } catch (err: any) {
      setPilotAssignError('Error contacting assignment service: ' + err.message);
    } finally {
      setAssigningPilot(false);
    }
  };

  useEffect(() => {
    fetchData();

    // Silent background poll every 5s when viewing live orders
    let interval: any = null;
    if (activeSubTab === 'orders') {
      interval = setInterval(() => {
        fetch(`${API_BASE}/admin/orders?status=${statusFilter}&search=${encodeURIComponent(searchTerm)}`)
          .then(r => r.json())
          .then(res => {
            if (res?.success) {
              const fetchedOrders = res.orders || [];
              if (orderAlertSoundEnabled && prevOrdersCountRef.current > 0 && fetchedOrders.length > prevOrdersCountRef.current) {
                const hasNewPlaced = fetchedOrders.some((fo: any) => fo.orderStatus === 'placed');
                if (hasNewPlaced) {
                  playNewOrderAlertChime();
                }
              }
              prevOrdersCountRef.current = fetchedOrders.length;
              setOrders(fetchedOrders);
            }
          })
          .catch(() => null);
      }, 5000);
    }

    return () => {
      if (interval) clearInterval(interval);
    };
  }, [statusFilter, restStatusFilter, activeSubTab, orderAlertSoundEnabled, searchTerm]);

  useEffect(() => {
    if (selectedOrder) {
      fetchEligiblePilots();
      setSelectedPilotToAssign('');
      setPilotAssignError('');
      setPilotAssignSuccess('');
    }
  }, [selectedOrder?.orderId]);

  // ---------------------------------------------------------------------------
  // RESTAURANT VERIFICATION & APPROVAL HANDLERS
  // ---------------------------------------------------------------------------

  const handleOpenApplicationDetails = async (rest: any) => {
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${rest.restaurantId}/application`).then(r => r.json());
      if (res.success && res.restaurant) {
        setSelectedApp(res.restaurant);
      } else {
        setSelectedApp(rest);
      }
    } catch {
      setSelectedApp(rest);
    }
    setIsAppDetailsModalOpen(true);
  };

  const handleApprove = (rest: any) => {
    setRestaurantToApprove(rest);
    setApproveNotes('Application verified and approved for live orders');
    setIsApproveModalOpen(true);
  };

  const handleConfirmApprove = async () => {
    if (!restaurantToApprove) return;
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantToApprove.restaurantId}/approve`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          adminName: 'Admin Operations',
          notes: approveNotes
        })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant "${restaurantToApprove.name}" approved successfully!`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setIsApproveModalOpen(false);
        setIsAppDetailsModalOpen(false);
        setRestaurantToApprove(null);
        fetchData();
      } else {
        alert('Approval failed: ' + (res.message || 'Unknown error'));
      }
    } catch (err: any) {
      alert('Error approving restaurant: ' + err.message);
    }
  };

  const handleReject = (rest: any) => {
    setRestaurantToReject(rest);
    setRejectionReason('Documents incomplete or unreadable');
    setIsRejectModalOpen(true);
  };

  const handleConfirmReject = async () => {
    if (!restaurantToReject) return;
    if (!rejectionReason.trim()) {
      alert('Please enter a rejection reason');
      return;
    }
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantToReject.restaurantId}/reject`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          adminName: 'Admin Operations',
          reason: rejectionReason.trim()
        })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant "${restaurantToReject.name}" application rejected`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setIsRejectModalOpen(false);
        setIsAppDetailsModalOpen(false);
        setRestaurantToReject(null);
        fetchData();
      } else {
        alert('Rejection failed: ' + (res.message || 'Unknown error'));
      }
    } catch (err: any) {
      alert('Error rejecting restaurant: ' + err.message);
    }
  };

  const handleRequestCorrection = (rest: any) => {
    setRestaurantForCorrection(rest);
    setCorrectionNotes('Please upload a clear copy of FSSAI license certificate and valid GST certificate.');
    setIsCorrectionModalOpen(true);
  };

  const handleConfirmCorrection = async () => {
    if (!restaurantForCorrection) return;
    if (!correctionNotes.trim()) {
      alert('Please specify the required corrections');
      return;
    }
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantForCorrection.restaurantId}/request-correction`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          adminName: 'Admin Operations',
          notes: correctionNotes.trim()
        })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Correction requested from "${restaurantForCorrection.name}"`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setIsCorrectionModalOpen(false);
        setIsAppDetailsModalOpen(false);
        setRestaurantForCorrection(null);
        fetchData();
      } else {
        alert('Failed to request correction: ' + (res.message || 'Unknown error'));
      }
    } catch (err: any) {
      alert('Error requesting correction: ' + err.message);
    }
  };

  // ---------------------------------------------------------------------------
  // RESTAURANT MANAGEMENT HANDLERS
  // ---------------------------------------------------------------------------

  const handleOpenAddRestaurant = () => {
    setIsEditingRest(false);
    setRestFormData({
      restaurantId: '',
      name: '',
      ownerName: '',
      phone: '',
      email: '',
      address: '',
      lat: 17.5230,
      lng: 78.4222,
      cuisines: 'South Indian, Breakfast, Pure Veg, Snacks',
      categories: 'South Indian, Snacks, Breads, Desserts, Beverages',
      openingHours: '07:00 AM - 10:30 PM',
      deliveryFee: 30,
      deliveryTime: '25-35 mins',
      commissionRate: 15.0,
      fssaiNumber: '',
      fssaiDocUrl: '',
      fssaiValidity: '',
      gstNumber: '',
      gstDocUrl: '',
      panNumber: '',
      panDocUrl: '',
      bankAccount: '',
      bankIfsc: '',
      bankHolderName: '',
      upiId: '',
      isVegOnly: false,
      isOpen: true,
      status: 'approved',
      imageUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80'
    });
    setIsAddEditRestModalOpen(true);
  };

  const handleOpenEditRestaurant = (rest: any) => {
    setIsEditingRest(true);
    setRestFormData({
      restaurantId: rest.restaurantId,
      name: rest.name || '',
      ownerName: rest.ownerName || '',
      phone: rest.phone || '',
      email: rest.email || '',
      address: rest.address || '',
      lat: (rest.lat !== undefined && rest.lat !== null) ? rest.lat : 17.5230,
      lng: (rest.lng !== undefined && rest.lng !== null) ? rest.lng : 78.4222,
      cuisines: Array.isArray(rest.cuisines) ? rest.cuisines.join(', ') : (rest.cuisines || ''),
      categories: Array.isArray(rest.categories) ? rest.categories.join(', ') : (rest.categories || ''),
      openingHours: rest.openingHours || '07:00 AM - 10:30 PM',
      deliveryFee: rest.deliveryFee || 30,
      deliveryTime: rest.deliveryTime || '25-35 mins',
      commissionRate: rest.commissionRate || 15.0,
      fssaiNumber: rest.fssaiNumber || '',
      fssaiDocUrl: rest.fssaiDocUrl || '',
      fssaiValidity: rest.fssaiValidity || '',
      gstNumber: rest.gstNumber || '',
      gstDocUrl: rest.gstDocUrl || '',
      panNumber: rest.panNumber || '',
      panDocUrl: rest.panDocUrl || '',
      bankAccount: rest.bankAccount || '',
      bankIfsc: rest.bankIfsc || '',
      bankHolderName: rest.bankHolderName || '',
      upiId: rest.upiId || '',
      isVegOnly: Boolean(rest.isVegOnly),
      isOpen: Boolean(rest.isOpen),
      status: rest.status || 'approved',
      imageUrl: rest.imageUrl || 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80'
    });
    setIsAddEditRestModalOpen(true);
  };

  const handleGeocodeAddress = async (addressToGeocode?: string) => {
    const targetAddr = (addressToGeocode || restFormData.address || '').trim();
    if (!targetAddr) {
      alert('Please enter a restaurant address first');
      return;
    }
    setIsGeocoding(true);
    try {
      const res = await fetch(`${API_BASE}/admin/geocode?address=${encodeURIComponent(targetAddr)}`).then(r => r.json());
      if (res.success && res.lat && res.lng) {
        setRestFormData((prev: any) => ({
          ...prev,
          lat: parseFloat(res.lat.toFixed(6)),
          lng: parseFloat(res.lng.toFixed(6))
        }));
        setActionSuccessMsg(`Detected GPS Coordinates: ${res.lat.toFixed(4)}, ${res.lng.toFixed(4)} (${res.formattedAddress || 'Resolved'})`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
      } else {
        alert(res.message || 'Could not find coordinates for this address. Please verify or enter manually.');
      }
    } catch (e: any) {
      alert('Geocoding failed: ' + e.message);
    } finally {
      setIsGeocoding(false);
    }
  };

  const handleQuickGeocodeRestaurant = async (restaurantId: string, address: string) => {
    if (!confirm(`Auto-detect and update GPS coordinates for this restaurant based on its address?\n\n"${address}"`)) {
      return;
    }
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}/geocode`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ address })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant coordinates updated: ${res.lat.toFixed(4)}, ${res.lng.toFixed(4)}`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        fetchData();
      } else {
        alert(res.message || 'Failed to update coordinates');
      }
    } catch (e: any) {
      alert('Error updating coordinates: ' + e.message);
    }
  };

  const handleSaveRestaurant = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const payload = {
        ...restFormData,
        lat: parseFloat(restFormData.lat) || 17.5230,
        lng: parseFloat(restFormData.lng) || 78.4222,
        cuisines: typeof restFormData.cuisines === 'string' ? restFormData.cuisines.split(',').map((s: string) => s.trim()).filter(Boolean) : restFormData.cuisines,
        categories: typeof restFormData.categories === 'string' ? restFormData.categories.split(',').map((s: string) => s.trim()).filter(Boolean) : restFormData.categories,
        deliveryFee: parseFloat(restFormData.deliveryFee) || 30,
        commissionRate: parseFloat(restFormData.commissionRate) || 15.0,
      };

      const url = isEditingRest 
        ? `${API_BASE}/admin/restaurants/${restFormData.restaurantId}`
        : `${API_BASE}/admin/restaurants`;
      const method = isEditingRest ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant ${isEditingRest ? 'updated' : 'created'} successfully!`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setIsAddEditRestModalOpen(false);
        fetchData();
      } else {
        alert('Operation failed: ' + (res.message || 'Unknown error'));
      }
    } catch (err: any) {
      alert('Error saving restaurant: ' + err.message);
    }
  };

  const handleApproveRejectRestaurant = async (restaurantId: string, approved: boolean) => {
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}/approval`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ approved })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant ${approved ? 'approved' : 'rejected'} successfully.`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        fetchData();
      }
    } catch (e: any) {
      alert('Error updating restaurant: ' + e.message);
    }
  };

  // --- Restaurant Settlement Handlers ---
  const handleVerifyBankDetails = async (restaurantId: string, status: 'verified' | 'rejected', rejectionReason?: string) => {
    setSettlementActionLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}/verify-bank`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status, rejectionReason })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Bank details ${status === 'verified' ? 'verified' : 'rejected'} successfully!`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setVerifyBankModalRest(null);
        setBankRejectionReason('');
        fetchData();
      } else {
        alert(res.message || 'Failed to verify bank details');
      }
    } catch (e: any) {
      alert('Error updating bank status: ' + e.message);
    } finally {
      setSettlementActionLoading(false);
    }
  };

  const handleInitiateSettlement = async (restaurantId: string, notes?: string) => {
    setSettlementActionLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}/initiate-settlement`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ notes, initiatedBy: 'Admin' })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Settlement of ₹${res.settlement?.netPayable} initiated successfully!`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setInitiateModalRest(null);
        setInitiateNotes('');
        fetchData();
      } else {
        alert(res.message || 'Failed to initiate settlement');
      }
    } catch (e: any) {
      alert('Error initiating settlement: ' + e.message);
    } finally {
      setSettlementActionLoading(false);
    }
  };

  const handleConfirmPayout = async (settlementId: string, payoutReference: string, remarks?: string) => {
    if (!payoutReference || !payoutReference.trim()) {
      alert('Please enter a valid Bank UTR or Transaction Reference number');
      return;
    }
    setSettlementActionLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/settlements/${settlementId}/confirm`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ payoutReference: payoutReference.trim(), remarks, settledBy: 'Admin' })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Payout confirmed with UTR ${payoutReference.trim()}! Ledger updated.`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setConfirmPayoutModalSettlement(null);
        setPayoutUtrInput('');
        setPayoutRemarksInput('');
        fetchData();
      } else {
        alert(res.message || 'Failed to confirm payout');
      }
    } catch (e: any) {
      alert('Error confirming payout: ' + e.message);
    } finally {
      setSettlementActionLoading(false);
    }
  };

  const handleFailPayout = async (settlementId: string, failureReason: string) => {
    if (!failureReason || !failureReason.trim()) {
      alert('Please provide a failure reason');
      return;
    }
    setSettlementActionLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/settlements/${settlementId}/fail`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ failureReason: failureReason.trim(), failedBy: 'Admin' })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Settlement marked as failed. Amount retained in restaurant pending balance.`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setFailPayoutModalSettlement(null);
        setPayoutFailReasonInput('');
        fetchData();
      } else {
        alert(res.message || 'Failed to mark settlement as failed');
      }
    } catch (e: any) {
      alert('Error updating settlement: ' + e.message);
    } finally {
      setSettlementActionLoading(false);
    }
  };

  const handleUpdateCommission = async (restaurantId: string, commissionRate: number) => {
    if (isNaN(commissionRate) || commissionRate < 0 || commissionRate > 50) {
      alert('Commission rate must be between 0% and 50%');
      return;
    }
    setSettlementActionLoading(true);
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}/commission`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ commissionRate, updatedBy: 'Admin' })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Commission rate updated to ${commissionRate}%`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setEditCommissionRest(null);
        fetchData();
      } else {
        alert(res.message || 'Failed to update commission rate');
      }
    } catch (e: any) {
      alert('Error updating commission: ' + e.message);
    } finally {
      setSettlementActionLoading(false);
    }
  };

  const handleToggleRestaurantStatus = async (restaurantId: string, currentStatus: string) => {
    const newStatus = currentStatus === 'approved' ? 'suspended' : 'approved';
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}/status`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: newStatus, isOpen: newStatus === 'approved' })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant status updated to ${newStatus}`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        fetchData();
      }
    } catch (e: any) {
      alert('Error: ' + e.message);
    }
  };

  const handleDeleteRestaurant = async (restaurantId: string, name: string) => {
    if (!window.confirm(`Are you sure you want to suspend and remove ${name} from active ordering?`)) {
      return;
    }
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${restaurantId}`, {
        method: 'DELETE'
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Restaurant ${name} suspended and hidden from customer app.`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        fetchData();
      }
    } catch (err: any) {
      alert('Error deleting restaurant: ' + err.message);
    }
  };

  // ---------------------------------------------------------------------------
  // MANAGE MENU & EDITABLE RATES HANDLERS (Picture 2)
  // ---------------------------------------------------------------------------

  const handleOpenManageMenu = async (rest: any) => {
    setActiveRestaurantForMenu(rest);
    setIsManageMenuModalOpen(true);
    setLoadingMenu(true);
    try {
      const res = await fetch(`${API_BASE}/partner/${rest.restaurantId}/menu`).then(r => r.json());
      if (res.success) {
        setMenuItems(res.menuItems || []);
      }
    } catch (err) {
      console.error('Error fetching menu items:', err);
    } finally {
      setLoadingMenu(false);
    }
  };

  // Instant rate adjustment (-₹50, -₹10, -₹5, +₹5, +₹10, +₹50)
  const handleAdjustItemPrice = async (itemId: string, delta: number) => {
    if (!activeRestaurantForMenu) return;
    const currentItem = menuItems.find(i => i.itemId === itemId);
    if (!currentItem) return;

    const oldPrice = currentItem.price || 0;
    const newPrice = Math.max(0, Math.round((oldPrice + delta) * 100) / 100);

    // Optimistic UI update
    setMenuItems(prev => prev.map(item => item.itemId === itemId ? { ...item, price: newPrice } : item));
    setSavingItemPriceId(itemId);
    setPriceUpdateError('');

    try {
      const res = await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/${itemId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ price: newPrice, priceDelta: delta, delta })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        // Rollback state on error
        setMenuItems(prev => prev.map(item => item.itemId === itemId ? { ...item, price: oldPrice } : item));
        setPriceUpdateError(`Update failed: ${data.message || 'Failed to update price on server'}`);
        setTimeout(() => setPriceUpdateError(''), 5000);
      } else {
        setSavedItemIds(prev => ({ ...prev, [itemId]: true }));
        setTimeout(() => setSavedItemIds(prev => ({ ...prev, [itemId]: false })), 2000);
      }
    } catch (err: any) {
      // Rollback on network failure
      setMenuItems(prev => prev.map(item => item.itemId === itemId ? { ...item, price: oldPrice } : item));
      setPriceUpdateError(`Update failed: ${err.message || 'Failed to update price on server'}`);
      setTimeout(() => setPriceUpdateError(''), 5000);
    } finally {
      setSavingItemPriceId(null);
    }
  };

  // Manual price input edit & save
  const handleSaveItemPrice = async (itemId: string, newPrice: number) => {
    if (!activeRestaurantForMenu || isNaN(newPrice) || newPrice < 0) return;
    const currentItem = menuItems.find(i => i.itemId === itemId);
    if (!currentItem) return;

    const oldPrice = currentItem.price || 0;
    setSavingItemPriceId(itemId);
    setPriceUpdateError('');

    try {
      const res = await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/${itemId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ price: newPrice })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        setMenuItems(prev => prev.map(item => item.itemId === itemId ? { ...item, price: oldPrice } : item));
        setPriceUpdateError(`Update failed: ${data.message || 'Failed to update price on server'}`);
        setTimeout(() => setPriceUpdateError(''), 5000);
      } else {
        setSavedItemIds(prev => ({ ...prev, [itemId]: true }));
        setTimeout(() => setSavedItemIds(prev => ({ ...prev, [itemId]: false })), 2000);
        setActionSuccessMsg(`Saved rate ₹${newPrice} for ${currentItem.name}`);
        setTimeout(() => setActionSuccessMsg(''), 3000);
      }
    } catch (err: any) {
      setMenuItems(prev => prev.map(item => item.itemId === itemId ? { ...item, price: oldPrice } : item));
      setPriceUpdateError(`Update failed: ${err.message || 'Failed to update price on server'}`);
      setTimeout(() => setPriceUpdateError(''), 5000);
    } finally {
      setSavingItemPriceId(null);
    }
  };

  // Bulk rate adjustment preview request (Picture 2 UX: +10% All, -10% All, +₹20 All, Reset)
  const handleRequestBulkPreview = async (options: { delta?: number; percentDelta?: number; category?: string; title: string }) => {
    if (!activeRestaurantForMenu) return;
    setBulkPreviewLoading(true);
    setPriceUpdateError('');
    try {
      const res = await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/adjust-prices`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          preview: true,
          delta: options.delta,
          percentDelta: options.percentDelta,
          category: options.category || menuFilterCategory
        })
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setBulkPreviewData({
          delta: options.delta,
          percentDelta: options.percentDelta,
          category: options.category || menuFilterCategory,
          items: data.items || [],
          affectedCount: data.affectedCount || 0,
          title: options.title
        });
        setIsBulkPreviewModalOpen(true);
      } else {
        setPriceUpdateError(`Preview failed: ${data.message || 'Failed to generate bulk preview'}`);
        setTimeout(() => setPriceUpdateError(''), 5000);
      }
    } catch (err: any) {
      setPriceUpdateError(`Preview failed: ${err.message}`);
      setTimeout(() => setPriceUpdateError(''), 5000);
    } finally {
      setBulkPreviewLoading(false);
    }
  };

  // Confirm and apply bulk changes after preview confirmation
  const handleConfirmBulkAdjust = async () => {
    if (!activeRestaurantForMenu || !bulkPreviewData) return;
    setBulkPreviewLoading(true);
    setPriceUpdateError('');
    try {
      const res = await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/adjust-prices`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          preview: false,
          delta: bulkPreviewData.delta,
          percentDelta: bulkPreviewData.percentDelta,
          category: bulkPreviewData.category
        })
      });
      const data = await res.json();
      if (res.ok && data.success) {
        setIsBulkPreviewModalOpen(false);
        setBulkPreviewData(null);
        // Refresh menu
        const menuRes = await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu`).then(r => r.json());
        if (menuRes.success) setMenuItems(menuRes.menuItems || []);
        setActionSuccessMsg(data.message || 'Rates updated successfully');
        setTimeout(() => setActionSuccessMsg(''), 4000);
        fetchData();
      } else {
        setPriceUpdateError(`Update failed: ${data.message || 'Failed to update rates on server'}`);
        setTimeout(() => setPriceUpdateError(''), 5000);
      }
    } catch (err: any) {
      setPriceUpdateError(`Update failed: ${err.message || 'Server connection error'}`);
      setTimeout(() => setPriceUpdateError(''), 5000);
    } finally {
      setBulkPreviewLoading(false);
    }
  };

  // Helper alias for quick bulk adjustments
  const handleBulkAdjustRates = (delta: number) => {
    handleRequestBulkPreview({
      delta,
      title: `${delta >= 0 ? '+' : ''}₹${delta} Across ${menuFilterCategory === 'All' ? 'All Dishes' : menuFilterCategory}`
    });
  };

  // Temporary local edit before explicit save or blur
  const handleManualPriceChange = (itemId: string, newPrice: number) => {
    setMenuItems(prev => prev.map(item => item.itemId === itemId ? { ...item, price: newPrice } : item));
  };

  // Toggle In Stock / Out of Stock
  const handleToggleItemStock = async (itemId: string, currentVal: boolean) => {
    if (!activeRestaurantForMenu) return;
    const newVal = !currentVal;

    setMenuItems(prev => prev.map(item => {
      if (item.itemId === itemId) {
        return { ...item, isAvailable: newVal };
      }
      return item;
    }));

    try {
      await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/${itemId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isAvailable: newVal })
      });
    } catch (err) {
      console.error('Error toggling item availability:', err);
    }
  };

  // Delete dish
  const handleDeleteMenuItem = async (itemId: string, name: string) => {
    if (!activeRestaurantForMenu) return;
    if (!window.confirm(`Delete dish "${name}" from this restaurant menu?`)) return;

    setMenuItems(prev => prev.filter(i => i.itemId !== itemId));

    try {
      await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/${itemId}`, {
        method: 'DELETE'
      });
    } catch (err) {
      console.error('Error deleting menu item:', err);
    }
  };

  // Add / Edit Dish Dialog
  const handleOpenAddDish = () => {
    setIsEditingDish(false);
    setDishFormData({
      itemId: '',
      name: '',
      category: activeRestaurantForMenu?.categories?.[0] || 'South Indian',
      description: '',
      price: 150,
      discountPrice: 0,
      isVeg: true,
      isAvailable: true,
      prepTime: '20 mins',
      isBestseller: false,
      isRecommended: false,
      imageUrl: 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=800&auto=format&fit=crop&q=80'
    });
    setIsDishModalOpen(true);
  };

  const handleOpenEditDish = (item: any) => {
    setIsEditingDish(true);
    setDishFormData({
      itemId: item.itemId,
      name: item.name || '',
      category: item.category || 'General',
      description: item.description || '',
      price: item.price || 0,
      discountPrice: item.discountPrice || 0,
      isVeg: Boolean(item.isVeg),
      isAvailable: Boolean(item.isAvailable),
      prepTime: item.prepTime || '20 mins',
      isBestseller: Boolean(item.isBestseller),
      isRecommended: Boolean(item.isRecommended),
      imageUrl: item.imageUrl || ''
    });
    setIsDishModalOpen(true);
  };

  const handleSaveDish = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeRestaurantForMenu) return;

    try {
      const url = isEditingDish
        ? `${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu/${dishFormData.itemId}`
        : `${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu`;
      const method = isEditingDish ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(dishFormData)
      }).then(r => r.json());

      if (res.success) {
        setIsDishModalOpen(false);
        // Refresh menu
        const menuRes = await fetch(`${API_BASE}/partner/${activeRestaurantForMenu.restaurantId}/menu`).then(r => r.json());
        if (menuRes.success) setMenuItems(menuRes.menuItems || []);
        fetchData();
        setActionSuccessMsg(`Dish ${isEditingDish ? 'updated' : 'added'} successfully!`);
        setTimeout(() => setActionSuccessMsg(''), 3000);
      } else {
        alert('Operation failed: ' + (res.message || 'Unknown error'));
      }
    } catch (err: any) {
      alert('Error saving dish: ' + err.message);
    }
  };

  // ---------------------------------------------------------------------------
  // IMAGE UPLOADER HANDLER (Local FileReader -> Base64 -> /api/food/upload-image)
  // ---------------------------------------------------------------------------
  const handleImageFileChange = async (e: React.ChangeEvent<HTMLInputElement>, target: 'restaurant' | 'dish') => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (file.size > 10 * 1024 * 1024) {
      alert('Image file size exceeds maximum limit of 10MB');
      return;
    }

    setIsUploadingImage(true);
    const reader = new FileReader();
    reader.onload = async () => {
      const base64Data = reader.result as string;
      try {
        const res = await fetch(`${API_BASE}/upload-image`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            imageData: base64Data,
            fileName: file.name,
            type: target
          })
        }).then(r => r.json());

        if (res.success && res.imageUrl) {
          if (target === 'restaurant') {
            setRestFormData((prev: any) => ({ ...prev, imageUrl: res.imageUrl }));
          } else {
            setDishFormData((prev: any) => ({ ...prev, imageUrl: res.imageUrl }));
          }
          setActionSuccessMsg('Image uploaded and previewed successfully!');
          setTimeout(() => setActionSuccessMsg(''), 3000);
        } else {
          alert('Upload failed: ' + (res.message || 'Unknown error'));
        }
      } catch (err: any) {
        alert('Error uploading image: ' + err.message);
      } finally {
        setIsUploadingImage(false);
      }
    };
    reader.readAsDataURL(file);
  };

  // ---------------------------------------------------------------------------
  // RESTAURANT ORDERS VIEW HANDLER
  // ---------------------------------------------------------------------------
  const handleOpenRestOrders = async (rest: any) => {
    setActiveRestaurantForOrders(rest);
    setIsRestOrdersModalOpen(true);
    setLoadingRestOrders(true);
    try {
      const res = await fetch(`${API_BASE}/admin/restaurants/${rest.restaurantId}/orders`).then(r => r.json());
      if (res.success) {
        setRestaurantOrders(res.orders || []);
      }
    } catch (err) {
      console.error('Error fetching restaurant orders:', err);
    } finally {
      setLoadingRestOrders(false);
    }
  };

  const handleUpdateOrderStatus = async (orderId: string, newStatus: string) => {
    try {
      const res = await fetch(`${API_BASE}/admin/orders/${orderId}/status`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: newStatus })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Order ${orderId} updated to ${newStatus}`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setSelectedOrder(null);
        fetchData();
      }
    } catch (e: any) {
      alert('Error updating order: ' + e.message);
    }
  };

  const handleSaveConfig = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await fetch(`${API_BASE}/admin/config`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config)
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg('Food commission & fee configuration saved to server!');
        setTimeout(() => setActionSuccessMsg(''), 4000);
      }
    } catch (e: any) {
      alert('Error saving config: ' + e.message);
    }
  };

  const handleSaveCoupon = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const url = editingCoupon 
        ? `${API_BASE}/admin/coupons/${editingCoupon._id}`
        : `${API_BASE}/admin/coupons`;
      const method = editingCoupon ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(couponFormData)
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Coupon '${couponFormData.code}' ${editingCoupon ? 'updated' : 'created'} successfully!`);
        setTimeout(() => setActionSuccessMsg(''), 4000);
        setIsAddCouponModalOpen(false);
        setEditingCoupon(null);
        fetchData();
      } else {
        alert(res.message || 'Failed to save coupon');
      }
    } catch (e: any) {
      alert('Error saving coupon: ' + e.message);
    }
  };

  const handleToggleCouponStatus = async (coupon: any) => {
    try {
      const res = await fetch(`${API_BASE}/admin/coupons/${coupon._id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isActive: !coupon.isActive })
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Coupon '${coupon.code}' ${!coupon.isActive ? 'activated' : 'deactivated'}`);
        setTimeout(() => setActionSuccessMsg(''), 3000);
        fetchData();
      }
    } catch (e: any) {
      alert('Error toggling coupon: ' + e.message);
    }
  };

  const handleDeleteCoupon = async (couponId: string, code: string) => {
    if (!window.confirm(`Are you sure you want to delete coupon '${code}'?`)) return;
    try {
      const res = await fetch(`${API_BASE}/admin/coupons/${couponId}`, {
        method: 'DELETE'
      }).then(r => r.json());

      if (res.success) {
        setActionSuccessMsg(`Coupon '${code}' deleted`);
        setTimeout(() => setActionSuccessMsg(''), 3000);
        fetchData();
      }
    } catch (e: any) {
      alert('Error deleting coupon: ' + e.message);
    }
  };

  const getOrderStatusBadge = (status: string) => {
    switch (status) {
      case 'placed':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#fef3c7', color: '#b45309' }}>PLACED</span>;
      case 'accepted':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#e0e7ff', color: '#4338ca' }}>ACCEPTED</span>;
      case 'preparing':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#ffedd5', color: '#c2410c' }}>PREPARING</span>;
      case 'ready_for_pickup':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#f0fdf4', color: '#15803d' }}>READY FOR PICKUP</span>;
      case 'pilot_assigned':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#e0f2fe', color: '#0369a1' }}>PILOT ASSIGNED</span>;
      case 'out_for_delivery':
      case 'picked_up':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#ede9fe', color: '#6d28d9' }}>ON THE WAY</span>;
      case 'delivered':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#dcfce7', color: '#166534' }}>DELIVERED</span>;
      case 'delivery_failed_reported':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#fee2e2', color: '#991b1b', border: '1px solid #f87171' }}>⚠️ FAILED DELIVERY</span>;
      case 'return_to_restaurant':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#fef3c7', color: '#92400e', border: '1px solid #f59e0b' }}>↩️ RETURNING</span>;
      case 'return_arrived_at_restaurant':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#ffedd5', color: '#c2410c', border: '1px solid #fb923c' }}>📍 ARRIVED FOR RETURN</span>;
      case 'return_otp_pending':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#ede9fe', color: '#6d28d9', border: '1px solid #c084fc' }}>🔑 RETURN OTP PENDING</span>;
      case 'returned_to_restaurant':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#f1f5f9', color: '#475569', border: '1px solid #cbd5e1' }}>📦 RETURNED TO RESTAURANT</span>;
      case 'rejected':
      case 'cancelled':
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#fee2e2', color: '#b91c1c' }}>{status.toUpperCase()}</span>;
      default:
        return <span style={{ padding: '4px 10px', borderRadius: '12px', fontSize: '11px', fontWeight: 700, background: '#f1f5f9', color: '#475569' }}>{status.toUpperCase()}</span>;
    }
  };

  // Filtered menu items for modal
  const filteredMenuItems = menuItems.filter(item => {
    const matchesCat = menuFilterCategory === 'All' || item.category === menuFilterCategory;
    const matchesSearch = !menuSearchQuery.trim() || 
      item.name.toLowerCase().includes(menuSearchQuery.toLowerCase()) ||
      item.category.toLowerCase().includes(menuSearchQuery.toLowerCase());
    return matchesCat && matchesSearch;
  });

  return (
    <div className="page-container" style={{ padding: '24px' }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{ background: '#ffedd5', padding: '8px', borderRadius: '10px' }}>
              <UtensilsCrossed size={24} color="#ea580c" />
            </div>
            <div>
              <h2 style={{ margin: 0, fontSize: '22px', fontWeight: 800, color: 'var(--text-main)' }}>
                Food Orders & Restaurant Management
              </h2>
              <p style={{ margin: '4px 0 0', color: 'var(--text-muted)', fontSize: '13px' }}>
                Manage StayDriv restaurants, edit rates (+₹10, -₹10, +₹50, -₹50), update menus, and track kitchen orders.
              </p>
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: '10px' }}>
          <button 
            onClick={fetchData} 
            style={{ 
              display: 'flex', 
              alignItems: 'center', 
              gap: '6px', 
              background: 'var(--card-bg)', 
              border: '1px solid var(--border-color)', 
              padding: '8px 14px', 
              borderRadius: '8px', 
              cursor: 'pointer',
              fontWeight: 600,
              fontSize: '13px'
            }}
          >
            <RefreshCw size={14} className={loading ? 'spin' : ''} /> Refresh
          </button>
        </div>
      </div>

      {actionSuccessMsg && (
        <div style={{ 
          background: '#dcfce7', 
          color: '#15803d', 
          padding: '12px 18px', 
          borderRadius: '8px', 
          marginBottom: '18px', 
          fontSize: '13px', 
          fontWeight: 600,
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          boxShadow: '0 2px 8px rgba(0,0,0,0.05)'
        }}>
          <CheckCircle2 size={16} /> {actionSuccessMsg}
        </div>
      )}

      {/* KPI Stats Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '14px', marginBottom: '24px' }}>
        <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>TOTAL FOOD ORDERS</div>
          <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: 'var(--text-main)' }}>{stats.totalOrders || 0}</div>
          <div style={{ fontSize: '11px', color: '#16a34a', marginTop: '4px', fontWeight: 600 }}>{stats.activeOrders || 0} active now</div>
        </div>
        <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>APPROVED RESTAURANTS</div>
          <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: 'var(--text-main)' }}>{stats.approvedRestaurants || 0}</div>
          <div style={{ fontSize: '11px', color: stats.pendingRestaurants > 0 ? '#ea580c' : 'var(--text-muted)', marginTop: '4px', fontWeight: 600 }}>
            {stats.pendingRestaurants || 0} pending review
          </div>
        </div>
        <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>FOOD GMV (SALES)</div>
          <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: '#ea580c' }}>₹{(stats.grossMerchandiseValue || 0).toLocaleString()}</div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>Customer food spend</div>
        </div>
        <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
          <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600 }}>PLATFORM COMMISSIONS</div>
          <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: '#2563eb' }}>₹{(stats.platformRevenue || 0).toLocaleString()}</div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>15% commission + platform fee</div>
        </div>
      </div>

      {/* 4 Navigation Tabs - Picture 2 Style */}
      <div style={{ display: 'flex', gap: '8px', borderBottom: '1px solid var(--border-color)', marginBottom: '20px' }}>
        <button
          onClick={() => setActiveSubTab('orders')}
          style={{
            padding: '10px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: activeSubTab === 'orders' ? '2px solid #ea580c' : '2px solid transparent',
            color: activeSubTab === 'orders' ? '#ea580c' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          <Clock size={16} /> Live Food Orders ({orders.length})
          <span
            title={orderAlertSoundEnabled ? 'Order Sound Alert: Active (Click to mute)' : 'Order Sound Alert: Muted (Click to enable)'}
            onClick={(e) => {
              e.stopPropagation();
              setOrderAlertSoundEnabled(!orderAlertSoundEnabled);
              if (!orderAlertSoundEnabled) playNewOrderAlertChime();
            }}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              padding: '2px 8px',
              borderRadius: '6px',
              background: orderAlertSoundEnabled ? 'rgba(16, 185, 129, 0.15)' : 'rgba(148, 163, 184, 0.15)',
              color: orderAlertSoundEnabled ? '#10b981' : '#94a3b8',
              marginLeft: '4px',
              fontSize: '11px',
              fontWeight: 800
            }}
          >
            {orderAlertSoundEnabled ? <Volume2 size={13} style={{ marginRight: '4px' }} /> : <VolumeX size={13} style={{ marginRight: '4px' }} />}
            {orderAlertSoundEnabled ? 'ALERT ON' : 'MUTED'}
          </span>
        </button>

        <button
          onClick={() => { setActiveSubTab('restaurants'); setRestStatusFilter('all'); }}
          style={{
            padding: '10px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: activeSubTab === 'restaurants' ? '2px solid #ea580c' : '2px solid transparent',
            color: activeSubTab === 'restaurants' ? '#ea580c' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          <Store size={16} /> Restaurant Partners ({counts.all || restaurants.length})
        </button>

        <button
          onClick={() => { setActiveSubTab('pending_approvals'); setRestStatusFilter('pending'); }}
          style={{
            padding: '10px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: activeSubTab === 'pending_approvals' ? '2px solid #ea580c' : '2px solid transparent',
            color: activeSubTab === 'pending_approvals' ? '#ea580c' : (counts.pending > 0 ? '#f59e0b' : 'var(--text-muted)'),
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          <AlertCircle size={16} /> Pending Approvals ({counts.pending})
          {counts.pending > 0 && (
            <span style={{ 
              background: '#ef4444', 
              color: '#fff', 
              borderRadius: '10px', 
              padding: '2px 7px', 
              fontSize: '11px', 
              fontWeight: 800 
            }}>
              {counts.pending}
            </span>
          )}
        </button>

        <button
          onClick={() => setActiveSubTab('settlements')}
          style={{
            padding: '10px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: activeSubTab === 'settlements' ? '2px solid #ea580c' : '2px solid transparent',
            color: activeSubTab === 'settlements' ? '#ea580c' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          <DollarSign size={16} /> Sales & Settlements
          {settlementOverview?.overview?.restaurantsWithPendingSettlements > 0 && (
            <span style={{ 
              background: '#ea580c', 
              color: '#fff', 
              borderRadius: '10px', 
              padding: '2px 7px', 
              fontSize: '11px', 
              fontWeight: 800 
            }}>
              {settlementOverview.overview.restaurantsWithPendingSettlements}
            </span>
          )}
        </button>

        <button
          onClick={() => setActiveSubTab('config')}
          style={{
            padding: '10px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: activeSubTab === 'config' ? '2px solid #ea580c' : '2px solid transparent',
            color: activeSubTab === 'config' ? '#ea580c' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          <Sliders size={16} /> Bill & Fee Settings
        </button>

        <button
          onClick={() => setActiveSubTab('coupons')}
          style={{
            padding: '10px 18px',
            background: 'transparent',
            border: 'none',
            borderBottom: activeSubTab === 'coupons' ? '2px solid #ea580c' : '2px solid transparent',
            color: activeSubTab === 'coupons' ? '#ea580c' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            gap: '8px'
          }}
        >
          <Percent size={16} /> Food Coupons & Offers ({coupons.length})
        </button>
      </div>

      {/* ===================================================================== */}
      {/* SUB-TABS: RESTAURANTS & PENDING APPROVALS (Pictures 1, 2 & 3 Pattern) */}
      {/* ===================================================================== */}
      {(activeSubTab === 'restaurants' || activeSubTab === 'pending_approvals') && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {/* Card containing Picture 3 Search Bar and Status Filters */}
          <div className="card" style={{ padding: '16px', display: 'flex', flexDirection: 'column', gap: '14px', background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
              {/* Picture 3 Styled Search Bar */}
              <div className="input-icon-wrapper" style={{ position: 'relative', flex: '1 1 360px', minWidth: '280px' }}>
                <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
                <input 
                  type="text" 
                  placeholder="Search restaurant name, Partner ID, mobile number, owner name, or location…" 
                  value={restSearchQuery}
                  onChange={(e) => setRestSearchQuery(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && fetchData()}
                  style={{
                    width: '100%',
                    padding: '9px 12px 9px 36px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--bg-main, transparent)',
                    color: 'var(--text-main)',
                    fontSize: '13px'
                  }}
                />
              </div>

              <div style={{ display: 'flex', gap: '8px' }}>
                <button
                  onClick={fetchData}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '6px',
                    padding: '8px 14px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--card-bg)',
                    color: 'var(--text-main)',
                    fontSize: '13px',
                    fontWeight: 600,
                    cursor: 'pointer'
                  }}
                >
                  <Search size={14} /> Search
                </button>

                <button
                  onClick={handleOpenAddRestaurant}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '6px',
                    background: '#ea580c',
                    color: '#fff',
                    border: 'none',
                    padding: '8px 16px',
                    borderRadius: '8px',
                    fontWeight: 700,
                    fontSize: '13px',
                    cursor: 'pointer',
                    boxShadow: '0 2px 6px rgba(234, 88, 12, 0.3)'
                  }}
                >
                  <Plus size={15} /> Add Restaurant
                </button>
              </div>
            </div>

            {/* Picture 3 Status Filter Pills with dynamic counts */}
            <div style={{ display: 'flex', gap: '6px', flexWrap: 'wrap' }}>
              {[
                { id: 'all', label: `All Restaurants (${counts.all})` },
                { id: 'pending', label: `⏳ Pending Approvals (${counts.pending})`, alert: counts.pending > 0 },
                { id: 'action_required', label: `⚠️ Action Required (${counts.action_required})`, alert: counts.action_required > 0 },
                { id: 'approved', label: `✓ Approved (${counts.approved})` },
                { id: 'rejected', label: `🚫 Rejected (${counts.rejected})` },
                { id: 'suspended', label: `⛔ Suspended (${counts.suspended})` },
                { id: 'active', label: `🟢 Active (${counts.active})` },
                { id: 'inactive', label: `Offline (${counts.inactive})` },
              ].map(tab => {
                const isActive = restStatusFilter === tab.id;
                return (
                  <button 
                    key={tab.id}
                    className={`btn btn-sm ${isActive ? 'btn-primary' : 'btn-secondary'}`}
                    onClick={() => {
                      setRestStatusFilter(tab.id as any);
                    }}
                    style={{ 
                      fontSize: '12px', 
                      fontWeight: isActive ? 700 : 500,
                      padding: '6px 12px',
                      borderRadius: '8px',
                      cursor: 'pointer',
                      border: isActive ? '1px solid #ea580c' : '1px solid var(--border-color)',
                      background: isActive ? '#ea580c' : 'var(--card-bg)',
                      color: isActive ? '#ffffff' : (tab.alert ? '#f59e0b' : 'var(--text-main)'),
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px'
                    }}
                  >
                    {tab.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Restaurant Applications & Partners Table */}
          <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px', overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '12.5px' }}>
              <thead>
                <tr style={{ background: 'rgba(0,0,0,0.03)', borderBottom: '1px solid var(--border-color)' }}>
                  <th style={{ padding: '14px 16px', fontWeight: 700 }}>RESTAURANT</th>
                  <th style={{ padding: '14px 16px', fontWeight: 700 }}>REGISTERED PARTNER</th>
                  <th style={{ padding: '14px 16px', fontWeight: 700 }}>CUISINE CATEGORIES</th>
                  <th style={{ padding: '14px 16px', fontWeight: 700 }}>TIMINGS & STATUS</th>
                  <th style={{ padding: '14px 16px', fontWeight: 700 }}>COMMISSION & MENU</th>
                  <th style={{ padding: '14px 16px', fontWeight: 700 }}>APPROVAL STATUS</th>
                  <th style={{ padding: '14px 16px', fontWeight: 700, minWidth: '220px' }}>ACTIONS</th>
                </tr>
              </thead>
              <tbody>
                {restaurants.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                      No restaurants found matching search or filter criteria.
                    </td>
                  </tr>
                ) : (
                  restaurants.map(rest => {
                    const isPending = rest.status === 'pending';
                    const isActionReq = rest.status === 'action_required';
                    const isApproved = rest.status === 'approved';
                    const isSuspended = rest.status === 'suspended';
                    const isRejected = rest.status === 'rejected';
                    const isOpen = rest.isOpen !== false;

                    return (
                      <tr 
                        key={rest.restaurantId} 
                        style={{ 
                          borderBottom: '1px solid var(--border-color)',
                          background: isPending ? 'rgba(245, 158, 11, 0.04)' : (isSuspended ? 'rgba(239, 68, 68, 0.03)' : 'transparent'),
                          transition: 'background 0.2s'
                        }}
                      >
                        {/* 1. Restaurant Name, Logo, Address, Rating (Picture 1 reference) */}
                        <td style={{ padding: '14px 16px' }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                            <img 
                              src={rest.imageUrl || 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80'} 
                              alt={rest.name} 
                              style={{ width: '48px', height: '48px', borderRadius: '10px', objectFit: 'cover', border: '1px solid var(--border-color)', flexShrink: 0 }} 
                            />
                            <div>
                              <div style={{ fontWeight: 800, fontSize: '14px', color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                                {rest.name}
                              </div>
                              <div style={{ fontSize: '11.5px', color: 'var(--text-muted)', marginTop: '2px', maxWidth: '240px', lineHeight: '1.3' }}>
                                {rest.address}
                              </div>
                              <div style={{ fontSize: '10.5px', color: '#0284c7', marginTop: '3px', display: 'flex', alignItems: 'center', gap: '3px' }}>
                                <MapPin size={11} />
                                <span>{rest.lat ? `${Number(rest.lat).toFixed(4)}, ${Number(rest.lng).toFixed(4)}` : 'GPS Not Set'}</span>
                                {(!rest.lat || (rest.lat === 17.4485 && rest.lng === 78.3741)) && (
                                  <span style={{ color: '#d97706', fontWeight: 600 }}>(Default)</span>
                                )}
                              </div>
                              <div style={{ fontSize: '11px', color: '#ea580c', fontWeight: 700, marginTop: '3px', display: 'flex', alignItems: 'center', gap: '3px' }}>
                                <span>★ {rest.rating || 4.5}</span>
                                <span style={{ color: 'var(--text-muted)' }}>({rest.ratingCount || 120} reviews)</span>
                              </div>
                            </div>
                          </div>
                        </td>

                        {/* 2. Registered Partner Details (Picture 1 reference) */}
                        <td style={{ padding: '14px 16px' }}>
                          <div style={{ fontWeight: 800, fontSize: '13px', color: 'var(--text-main)' }}>
                            {rest.ownerName || 'Venkatesh Rao'}
                          </div>
                          <div style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 600, marginTop: '2px' }}>
                            {rest.phone}
                          </div>
                          <div style={{ fontSize: '11px', color: '#64748b', marginTop: '2px' }}>
                            {rest.fssaiNumber ? `FSSAI: ${rest.fssaiNumber}` : `ID: ${rest.restaurantId}`}
                          </div>
                        </td>

                        {/* 3. Cuisine Categories (Picture 1 reference) */}
                        <td style={{ padding: '14px 16px' }}>
                          <div style={{ display: 'flex', flexDirection: 'column', gap: '3px' }}>
                            {(Array.isArray(rest.cuisines) ? rest.cuisines : (rest.cuisines ? String(rest.cuisines).split(',') : ['Multi-cuisine'])).slice(0, 3).map((c: string, idx: number) => (
                              <span key={idx} style={{ fontSize: '11.5px', fontWeight: 600, color: 'var(--text-main)' }}>
                                {c.trim()}
                              </span>
                            ))}
                          </div>
                        </td>

                        {/* 4. Timings & Availability Status (Picture 1 reference) */}
                        <td style={{ padding: '14px 16px' }}>
                          <div style={{ fontSize: '12px', fontWeight: 600, color: 'var(--text-main)' }}>
                            {rest.openingHours || '08:00 AM - 11:00 PM'}
                          </div>
                          <div style={{ marginTop: '4px' }}>
                            {isOpen ? (
                              <span style={{ fontSize: '11px', fontWeight: 800, color: '#16a34a', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                                <span style={{ width: '7px', height: '7px', borderRadius: '50%', background: '#16a34a' }}></span>
                                OPEN NOW
                              </span>
                            ) : (
                              <span style={{ fontSize: '11px', fontWeight: 800, color: '#dc2626', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                                <span style={{ width: '7px', height: '7px', borderRadius: '50%', border: '1.5px solid #dc2626' }}></span>
                                CLOSED
                              </span>
                            )}
                          </div>
                        </td>

                        {/* 5. Platform Commission & Menu Count (Picture 1 reference) */}
                        <td style={{ padding: '14px 16px' }}>
                          <div style={{ fontSize: '14px', fontWeight: 800, color: 'var(--text-main)' }}>
                            {rest.commissionRate !== undefined ? `${rest.commissionRate}%` : '15%'}
                          </div>
                          <div style={{ fontSize: '11px', color: '#64748b', marginTop: '2px', fontWeight: 600 }}>
                            {rest.menuItemCount !== undefined ? `${rest.menuItemCount} items` : 'Menu loaded'}
                          </div>
                        </td>

                        {/* 6. Approval Status Badge (Picture 1 reference) */}
                        <td style={{ padding: '14px 16px' }}>
                          <span style={{
                            padding: '4px 10px',
                            borderRadius: '16px',
                            fontSize: '11px',
                            fontWeight: 800,
                            letterSpacing: '0.4px',
                            display: 'inline-block',
                            background: 
                              isApproved ? '#dcfce7' : 
                              (isSuspended ? '#fee2e2' :
                              (isPending ? '#ffedd5' : 
                              (isActionReq ? '#fef3c7' : '#fee2e2'))),
                            color: 
                              isApproved ? '#166534' : 
                              (isSuspended ? '#b91c1c' :
                              (isPending ? '#c2410c' : 
                              (isActionReq ? '#b45309' : '#b91c1c'))),
                            border: 
                              isApproved ? '1px solid #86efac' : 
                              (isSuspended ? '1px solid #fca5a5' :
                              (isPending ? '1px solid #fdba74' : '1px solid #fecaca'))
                          }}>
                            {String(rest.status || 'PENDING').toUpperCase()}
                          </span>
                        </td>

                        {/* 7. Action Controls (Picture 1 & Picture 2 requirements) */}
                        <td style={{ padding: '14px 16px' }}>
                          <div style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: '6px' }}>
                            {/* Prominent Picture 1 Pill: Activate / Suspend */}
                            {isSuspended ? (
                              <button
                                onClick={() => handleToggleRestaurantStatus(rest.restaurantId, rest.status)}
                                style={{
                                  background: '#dcfce7',
                                  color: '#15803d',
                                  border: '1px solid #86efac',
                                  padding: '5px 14px',
                                  borderRadius: '8px',
                                  fontWeight: 800,
                                  fontSize: '11.5px',
                                  cursor: 'pointer'
                                }}
                                title="Activate restaurant for live orders"
                              >
                                Activate
                              </button>
                            ) : isApproved ? (
                              <button
                                onClick={() => handleToggleRestaurantStatus(rest.restaurantId, rest.status)}
                                style={{
                                  background: '#fef3c7',
                                  color: '#b45309',
                                  border: '1px solid #fde68a',
                                  padding: '5px 14px',
                                  borderRadius: '8px',
                                  fontWeight: 800,
                                  fontSize: '11.5px',
                                  cursor: 'pointer'
                                }}
                                title="Suspend restaurant"
                              >
                                Suspend
                              </button>
                            ) : (
                              <>
                                <button
                                  onClick={() => handleApprove(rest)}
                                  style={{
                                    background: '#16a34a',
                                    color: '#fff',
                                    border: 'none',
                                    padding: '5px 10px',
                                    borderRadius: '6px',
                                    fontWeight: 700,
                                    fontSize: '11px',
                                    cursor: 'pointer'
                                  }}
                                  title="Approve restaurant application"
                                >
                                  Approve
                                </button>
                                <button
                                  onClick={() => handleReject(rest)}
                                  style={{
                                    background: '#ef4444',
                                    color: '#fff',
                                    border: 'none',
                                    padding: '5px 10px',
                                    borderRadius: '6px',
                                    fontWeight: 700,
                                    fontSize: '11px',
                                    cursor: 'pointer'
                                  }}
                                  title="Reject restaurant application"
                                >
                                  Reject
                                </button>
                              </>
                            )}

                            {/* Manage Menu Button */}
                            <button
                              onClick={() => handleOpenManageMenu(rest)}
                              style={{
                                display: 'flex',
                                alignItems: 'center',
                                gap: '3px',
                                background: '#f0fdf4',
                                border: '1px solid #bbf7d0',
                                color: '#166534',
                                padding: '5px 9px',
                                borderRadius: '6px',
                                cursor: 'pointer',
                                fontSize: '11px',
                                fontWeight: 700
                              }}
                              title="Manage dishes and rate controls"
                            >
                              <MenuIcon size={12} /> Manage Menu
                            </button>

                            {/* View Application Details / Documents */}
                            <button
                              onClick={() => handleOpenApplicationDetails(rest)}
                              style={{
                                display: 'flex',
                                alignItems: 'center',
                                gap: '3px',
                                background: '#f8fafc',
                                border: '1px solid #cbd5e1',
                                color: '#334155',
                                padding: '5px 9px',
                                borderRadius: '6px',
                                cursor: 'pointer',
                                fontSize: '11px',
                                fontWeight: 700
                              }}
                              title="Inspect full details, documents, and order history"
                            >
                              <Eye size={12} /> View Details
                            </button>

                            {/* Auto GPS button */}
                            <button
                              onClick={() => handleQuickGeocodeRestaurant(rest.restaurantId, rest.address)}
                              style={{
                                display: 'flex',
                                alignItems: 'center',
                                gap: '3px',
                                background: '#f0f9ff',
                                border: '1px solid #bae6fd',
                                color: '#0369a1',
                                padding: '5px 8px',
                                borderRadius: '6px',
                                cursor: 'pointer',
                                fontSize: '11px',
                                fontWeight: 700
                              }}
                              title="Auto-detect & update GPS coordinates from address"
                            >
                              <MapPin size={11} /> Auto GPS
                            </button>

                            {/* Edit Restaurant */}
                            <button
                              onClick={() => handleOpenEditRestaurant(rest)}
                              style={{
                                display: 'flex',
                                alignItems: 'center',
                                gap: '3px',
                                background: '#eff6ff',
                                border: '1px solid #bfdbfe',
                                color: '#1d4ed8',
                                padding: '5px 8px',
                                borderRadius: '6px',
                                cursor: 'pointer',
                                fontSize: '11px',
                                fontWeight: 700
                              }}
                              title="Edit restaurant profile"
                            >
                              <Edit size={12} /> Edit
                            </button>

                            {/* Delete / Remove */}
                            <button
                              onClick={() => handleDeleteRestaurant(rest.restaurantId, rest.name)}
                              style={{
                                background: 'transparent',
                                border: 'none',
                                color: '#ef4444',
                                padding: '4px 6px',
                                cursor: 'pointer'
                              }}
                              title="Remove restaurant"
                            >
                              <Trash2 size={13} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* SUB-TAB 2: LIVE FOOD ORDERS (Picture 2 Exact Layout)                  */}
      {/* ===================================================================== */}
      {activeSubTab === 'orders' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {/* Picture 2 Style Search & Order Filter Bar */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '12px' }}>
            <div style={{ position: 'relative', flex: '1 1 360px', minWidth: '280px' }}>
              <Search size={16} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)' }} />
              <input
                type="text"
                placeholder="Search by Order ID, customer, phone, restaurant, or OTP..."
                value={searchTerm}
                onChange={e => setSearchTerm(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && fetchData()}
                style={{
                  width: '100%',
                  padding: '9px 12px 9px 36px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--card-bg)',
                  color: 'var(--text-main)',
                  fontSize: '13px'
                }}
              />
            </div>

            <select
              value={statusFilter}
              onChange={e => setStatusFilter(e.target.value)}
              style={{
                padding: '9px 14px',
                borderRadius: '8px',
                border: '1px solid var(--border-color)',
                background: 'var(--card-bg)',
                color: 'var(--text-main)',
                fontSize: '13px',
                fontWeight: 600
              }}
            >
              <option value="all">All Order Statuses</option>
              <option value="platinum">👑 Platinum Free Delivery Orders</option>
              <option value="placed">Placed (New)</option>
              <option value="accepted">Accepted by Kitchen</option>
              <option value="preparing">Preparing Food</option>
              <option value="ready_for_pickup">Ready for Pickup</option>
              <option value="pilot_assigned">Pilot Assigned</option>
              <option value="out_for_delivery">Out for Delivery</option>
              <option value="delivered">Delivered</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>

          {/* Orders Table */}
          <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '12px', overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '13px' }}>
              <thead>
                <tr style={{ background: 'rgba(0,0,0,0.03)', borderBottom: '1px solid var(--border-color)' }}>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>ORDER ID</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>RESTAURANT</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>CUSTOMER</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>ITEMS</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700, minWidth: '150px' }}>CUSTOMER OTP</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700, minWidth: '150px' }}>RESTAURANT OTP</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>DELIVERY PILOT</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>TOTAL</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>STATUS</th>
                  <th style={{ padding: '12px 16px', fontWeight: 700 }}>ACTION</th>
                </tr>
              </thead>
              <tbody>
                {orders.length === 0 ? (
                  <tr>
                    <td colSpan={10} style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                      No live food orders found.
                    </td>
                  </tr>
                ) : (
                  orders.map(order => (
                    <tr key={order.orderId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '14px 16px' }}>
                        <span style={{ fontWeight: 800, fontFamily: 'monospace', color: '#ea580c' }}>
                          {order.orderId}
                        </span>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {new Date(order.placedAt || order.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </div>
                        {order.isPlatinumDelivery && (
                          <div style={{ marginTop: '4px' }}>
                            <span style={{
                              fontSize: '10px',
                              fontWeight: 800,
                              background: '#e0f2fe',
                              color: '#0369a1',
                              padding: '2px 6px',
                              borderRadius: '4px',
                              border: '1px solid #7dd3fc',
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '3px'
                            }}>
                              👑 Platinum Free Del
                            </span>
                          </div>
                        )}
                      </td>
                      <td style={{ padding: '14px 16px' }}>
                        <div style={{ fontWeight: 700, color: 'var(--text-main)' }}>{order.restaurantName}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>ID: {order.restaurantId}</div>
                      </td>
                      <td style={{ padding: '14px 16px' }}>
                        <div style={{ fontWeight: 600 }}>{order.customerName}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{order.customerPhone}</div>
                      </td>
                      <td style={{ padding: '14px 16px', maxWidth: '240px' }}>
                        <div style={{ fontSize: '12px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                          {(order.items || []).map((i: any) => `${i.quantity}x ${i.name}`).join(', ')}
                        </div>
                      </td>

                      {/* Customer OTP Column */}
                      <td style={{ padding: '14px 16px', whiteSpace: 'nowrap' }}>
                        {order.customerOtp || order.deliveryOtp ? (
                          <div style={{ display: 'inline-flex', flexDirection: 'column', gap: '3px' }}>
                            <div style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '6px',
                              background: 'rgba(37, 99, 235, 0.1)',
                              border: '1px solid rgba(59, 130, 246, 0.35)',
                              color: '#38bdf8',
                              padding: '3px 8px',
                              borderRadius: '6px',
                              fontFamily: 'monospace',
                              fontWeight: 800,
                              fontSize: '13px',
                              letterSpacing: '1px',
                              width: 'fit-content'
                            }}>
                              <ShieldCheck size={13} color="#38bdf8" />
                              <span>{order.customerOtp || order.deliveryOtp}</span>
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  copyToClipboard(order.customerOtp || order.deliveryOtp, `cust_${order.orderId}`);
                                }}
                                title="Copy Customer OTP"
                                style={{
                                  background: 'transparent',
                                  border: 'none',
                                  padding: '0',
                                  cursor: 'pointer',
                                  display: 'flex',
                                  alignItems: 'center',
                                  color: copiedKey === `cust_${order.orderId}` ? '#22c55e' : 'rgba(56, 189, 248, 0.7)'
                                }}
                              >
                                {copiedKey === `cust_${order.orderId}` ? <Check size={11} /> : <Copy size={11} />}
                              </button>
                            </div>
                            <div style={{
                              fontSize: '10px',
                              fontWeight: 700,
                              color: (order.customerOtpVerified || order.orderStatus === 'delivered') ? '#22c55e' : '#94a3b8',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '4px'
                            }}>
                              <span style={{
                                width: '6px',
                                height: '6px',
                                borderRadius: '50%',
                                background: (order.customerOtpVerified || order.orderStatus === 'delivered') ? '#22c55e' : '#f59e0b',
                                display: 'inline-block'
                              }}></span>
                              {(order.customerOtpVerified || order.orderStatus === 'delivered') ? 'Verified' : 'Pending Handover'}
                            </div>
                          </div>
                        ) : (
                          <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>—</span>
                        )}
                      </td>

                      {/* Restaurant OTP Column */}
                      <td style={{ padding: '14px 16px', whiteSpace: 'nowrap' }}>
                        {order.restaurantOtp ? (
                          <div style={{ display: 'inline-flex', flexDirection: 'column', gap: '3px' }}>
                            <div style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '6px',
                              background: 'rgba(217, 119, 6, 0.1)',
                              border: '1px solid rgba(245, 158, 11, 0.35)',
                              color: '#fbbf24',
                              padding: '3px 8px',
                              borderRadius: '6px',
                              fontFamily: 'monospace',
                              fontWeight: 800,
                              fontSize: '13px',
                              letterSpacing: '1px',
                              width: 'fit-content'
                            }}>
                              <Store size={13} color="#fbbf24" />
                              <span>{order.restaurantOtp}</span>
                              <button
                                type="button"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  copyToClipboard(order.restaurantOtp, `rest_${order.orderId}`);
                                }}
                                title="Copy Restaurant OTP"
                                style={{
                                  background: 'transparent',
                                  border: 'none',
                                  padding: '0',
                                  cursor: 'pointer',
                                  display: 'flex',
                                  alignItems: 'center',
                                  color: copiedKey === `rest_${order.orderId}` ? '#22c55e' : 'rgba(251, 191, 36, 0.7)'
                                }}
                              >
                                {copiedKey === `rest_${order.orderId}` ? <Check size={11} /> : <Copy size={11} />}
                              </button>
                            </div>
                            <div style={{
                              fontSize: '10px',
                              fontWeight: 700,
                              color: (order.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(order.orderStatus)) ? '#22c55e' : '#94a3b8',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '4px'
                            }}>
                              <span style={{
                                width: '6px',
                                height: '6px',
                                borderRadius: '50%',
                                background: (order.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(order.orderStatus)) ? '#22c55e' : '#f59e0b',
                                display: 'inline-block'
                              }}></span>
                              {(order.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(order.orderStatus)) ? 'Verified' : 'Pending Pickup'}
                            </div>
                          </div>
                        ) : (
                          <span style={{ color: 'var(--text-muted)', fontSize: '12px' }}>—</span>
                        )}
                      </td>

                      {/* Delivery Pilot Column */}
                      <td style={{ padding: '14px 16px', whiteSpace: 'nowrap' }}>
                        {order.deliveryPartnerName ? (
                          <div>
                            <div style={{ fontWeight: 700, fontSize: '12.5px', color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                              <Bike size={13} color="#16a34a" /> {order.deliveryPartnerName}
                            </div>
                            <div style={{ marginTop: '2px' }}>
                              <span style={{ fontSize: '10.5px', color: '#166534', fontWeight: 800, background: '#dcfce7', padding: '1px 6px', borderRadius: '4px', border: '1px solid #bbf7d0' }}>
                                🏍️ {order.deliveryPartnerVehicleType || 'Bike'}
                              </span>
                            </div>
                          </div>
                        ) : (
                          <span style={{ fontSize: '11px', color: '#b45309', fontWeight: 700, background: '#fef3c7', padding: '2px 8px', borderRadius: '4px', border: '1px solid #fde68a' }}>
                            ⏳ Unassigned
                          </span>
                        )}
                      </td>

                      <td style={{ padding: '14px 16px' }}>
                        <div style={{ fontWeight: 800, color: 'var(--text-main)', fontSize: '14px' }}>
                          ₹{order.totalAmount}
                        </div>
                        {order.isPlatinumDelivery ? (
                          <div style={{ fontSize: '10.5px', color: '#16a34a', fontWeight: 700, marginTop: '2px' }}>
                            Free Del (Funded ₹{order.staydrivFundedDeliveryAmount || order.originalDeliveryFee || 0})
                          </div>
                        ) : (
                          <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginTop: '2px' }}>
                            Del: ₹{order.customerDeliveryFee || order.deliveryFee || 0}
                          </div>
                        )}
                      </td>
                      <td style={{ padding: '14px 16px' }}>
                        {getOrderStatusBadge(order.orderStatus)}
                      </td>
                      <td style={{ padding: '14px 16px' }}>
                        <button
                          onClick={() => setSelectedOrder(order)}
                          style={{
                            background: '#ffedd5',
                            border: '1px solid #fed7aa',
                            color: '#c2410c',
                            padding: '6px 12px',
                            borderRadius: '6px',
                            fontSize: '11.5px',
                            fontWeight: 700,
                            cursor: 'pointer'
                          }}
                        >
                          View Details
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* SUB-TAB: RESTAURANT SALES & SETTLEMENTS                                */}
      {/* ===================================================================== */}
      {activeSubTab === 'settlements' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          {/* KPI CARDS */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))', gap: '16px' }}>
            <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '14px', padding: '18px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Gross Delivered Sales</span>
                <DollarSign size={18} color="#1e60ff" />
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--text-main)' }}>
                ₹{(settlementOverview?.overview?.totalGrossSales || 0).toLocaleString('en-IN')}
              </div>
              <div style={{ fontSize: '11px', color: '#16a34a', marginTop: '4px', fontWeight: 600 }}>
                From delivered food orders
              </div>
            </div>

            <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '14px', padding: '18px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Platform Fee (Commission)</span>
                <Percent size={18} color="#f59e0b" />
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, color: '#f59e0b' }}>
                ₹{(settlementOverview?.overview?.totalCommission || 0).toLocaleString('en-IN')}
              </div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                Platform revenue share
              </div>
            </div>

            <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '14px', padding: '18px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Total Settled (Paid Out)</span>
                <CheckCircle2 size={18} color="#16a34a" />
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, color: '#16a34a' }}>
                ₹{(settlementOverview?.overview?.totalSettled || 0).toLocaleString('en-IN')}
              </div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                Confirmed bank payouts
              </div>
            </div>

            <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '14px', padding: '18px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Pending Settlement</span>
                <Clock size={18} color="#ea580c" />
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, color: '#ea580c' }}>
                ₹{(settlementOverview?.overview?.totalPending || 0).toLocaleString('en-IN')}
              </div>
              <div style={{ fontSize: '11px', color: (settlementOverview?.overview?.restaurantsWithPendingSettlements || 0) > 0 ? '#ea580c' : 'var(--text-muted)', marginTop: '4px', fontWeight: 600 }}>
                {settlementOverview?.overview?.restaurantsWithPendingSettlements || 0} partners awaiting payout
              </div>
            </div>
          </div>

          {/* VIEW SWITCHER & SEARCH */}
          <div style={{ 
            background: 'var(--card-bg)', 
            border: '1px solid var(--border-color)', 
            borderRadius: '16px', 
            padding: '16px 20px',
            display: 'flex',
            flexWrap: 'wrap',
            justifyContent: 'space-between',
            alignItems: 'center',
            gap: '12px'
          }}>
            <div style={{ display: 'flex', gap: '8px' }}>
              <button
                onClick={() => setSettlementViewMode('partners')}
                style={{
                  padding: '8px 16px',
                  borderRadius: '8px',
                  border: 'none',
                  background: settlementViewMode === 'partners' ? '#ea580c' : 'var(--bg-main)',
                  color: settlementViewMode === 'partners' ? '#fff' : 'var(--text-muted)',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Partner Balances & Payouts ({settlementOverview?.restaurants?.length || 0})
              </button>
              <button
                onClick={() => setSettlementViewMode('transactions')}
                style={{
                  padding: '8px 16px',
                  borderRadius: '8px',
                  border: 'none',
                  background: settlementViewMode === 'transactions' ? '#ea580c' : 'var(--bg-main)',
                  color: settlementViewMode === 'transactions' ? '#fff' : 'var(--text-muted)',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Settlement Transactions ({settlementsList.length})
              </button>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <div style={{ position: 'relative' }}>
                <Search size={14} style={{ position: 'absolute', left: '10px', top: '10px', color: 'var(--text-muted)' }} />
                <input
                  type="text"
                  placeholder="Search partner or settlement ID..."
                  value={settlementSearchQuery}
                  onChange={(e) => setSettlementSearchQuery(e.target.value)}
                  style={{
                    padding: '8px 12px 8px 30px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--bg-main)',
                    color: 'var(--text-main)',
                    fontSize: '12px',
                    width: '220px'
                  }}
                />
              </div>

              {settlementViewMode === 'transactions' && (
                <select
                  value={settlementStatusFilter}
                  onChange={(e) => setSettlementStatusFilter(e.target.value)}
                  style={{
                    padding: '8px 12px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--bg-main)',
                    color: 'var(--text-main)',
                    fontSize: '12px'
                  }}
                >
                  <option value="all">All Statuses</option>
                  <option value="processing">Processing</option>
                  <option value="paid">Paid</option>
                  <option value="pending">Pending</option>
                  <option value="failed">Failed</option>
                </select>
              )}

              <button
                onClick={fetchData}
                style={{
                  padding: '8px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--bg-main)',
                  color: 'var(--text-muted)',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '6px',
                  fontSize: '12px',
                  fontWeight: 600
                }}
              >
                <RefreshCw size={14} /> Refresh
              </button>
            </div>
          </div>

          {/* VIEW A: PARTNER BALANCES & BENEFICIARY ACCOUNTS TABLE */}
          {settlementViewMode === 'partners' && (
            <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '16px', overflow: 'hidden' }}>
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--border-color)', background: 'var(--bg-main)' }}>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Restaurant Partner</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Beneficiary Bank Account</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Bank Verification</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Delivered Orders</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Gross Sales</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Commission</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Net Earnings</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Amount Paid</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Pending Payout</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(!settlementOverview?.restaurants || settlementOverview.restaurants.length === 0) ? (
                      <tr>
                        <td colSpan={10} style={{ padding: '36px', textAlign: 'center', color: 'var(--text-muted)' }}>
                          No restaurant partner sales records found.
                        </td>
                      </tr>
                    ) : (
                      settlementOverview.restaurants
                        .filter((r: any) => {
                          if (!settlementSearchQuery.trim()) return true;
                          const q = settlementSearchQuery.toLowerCase();
                          return (
                            (r.name || '').toLowerCase().includes(q) ||
                            (r.restaurantId || '').toLowerCase().includes(q) ||
                            (r.phone || '').includes(q) ||
                            (r.bankName || '').toLowerCase().includes(q)
                          );
                        })
                        .map((r: any) => {
                          const hasBank = Boolean(r.hasBankAccount || r.bankAccountMasked);
                          const isVerified = r.bankVerificationStatus === 'verified';
                          const isPendingVer = r.bankVerificationStatus === 'pending_verification';
                          const isRejected = r.bankVerificationStatus === 'rejected';

                          return (
                            <tr key={r.restaurantId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                              <td style={{ padding: '14px 16px' }}>
                                <div style={{ fontWeight: 800, color: 'var(--text-main)', fontSize: '13.5px' }}>{r.name}</div>
                                <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{r.restaurantId}</div>
                                <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{r.phone}</div>
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                {hasBank ? (
                                  <div>
                                    <div style={{ fontWeight: 700, color: 'var(--text-main)', fontSize: '12px' }}>
                                      {r.bankName || 'Bank'} ({r.accountType || 'Current'})
                                    </div>
                                    <div style={{ fontSize: '11.5px', fontFamily: 'monospace', fontWeight: 800, color: '#1e60ff' }}>
                                      {r.bankAccountMasked || '••••••••'}
                                    </div>
                                    <div style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>
                                      IFSC: {r.bankIfsc || 'N/A'} {r.upiId ? `• UPI: ${r.upiId}` : ''}
                                    </div>
                                    <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
                                      Holder: {r.accountHolderName || 'N/A'}
                                    </div>
                                  </div>
                                ) : (
                                  <span style={{ fontSize: '11px', color: 'var(--text-muted)', fontStyle: 'italic' }}>
                                    No bank details added
                                  </span>
                                )}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                {isVerified ? (
                                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#dcfce7', color: '#166534', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                                    <CheckCircle2 size={12} /> VERIFIED
                                  </span>
                                ) : isPendingVer ? (
                                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#fef3c7', color: '#92400E', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                                    <Clock size={12} /> UNDER REVIEW
                                  </span>
                                ) : isRejected ? (
                                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#fee2e2', color: '#991b1b', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                                    <XCircle size={12} /> REJECTED
                                  </span>
                                ) : (
                                  <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#f1f5f9', color: '#475569', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                                    NOT CONFIGURED
                                  </span>
                                )}
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-main)' }}>
                                {r.completedOrdersCount || 0}
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 800, color: 'var(--text-main)', fontFamily: 'monospace' }}>
                                ₹{(r.totalSales || 0).toLocaleString('en-IN')}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                  <span style={{ fontWeight: 700, color: '#f59e0b' }}>
                                    {r.commissionRate || 15}%
                                  </span>
                                  <button
                                    onClick={() => {
                                      setEditCommissionRest(r);
                                      setCommissionInput(r.commissionRate || 15);
                                    }}
                                    style={{
                                      background: 'transparent',
                                      border: 'none',
                                      cursor: 'pointer',
                                      color: 'var(--text-muted)',
                                      padding: '2px'
                                    }}
                                    title="Edit Commission %"
                                  >
                                    <Edit size={12} />
                                  </button>
                                </div>
                                <div style={{ fontSize: '10.5px', color: 'var(--text-muted)' }}>
                                  ₹{(r.platformCommissionAmount || 0).toLocaleString('en-IN')}
                                </div>
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 800, color: 'var(--text-main)', fontFamily: 'monospace' }}>
                                ₹{(r.netEarnings || 0).toLocaleString('en-IN')}
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 800, color: '#16a34a', fontFamily: 'monospace' }}>
                                ₹{(r.amountPaid || 0).toLocaleString('en-IN')}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                <div style={{ 
                                  fontWeight: 900, 
                                  color: (r.pendingSettlement || 0) > 0 ? '#ea580c' : 'var(--text-muted)', 
                                  fontFamily: 'monospace',
                                  fontSize: '14px' 
                                }}>
                                  ₹{(r.pendingSettlement || 0).toLocaleString('en-IN')}
                                </div>
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                                  {hasBank && !isVerified && (
                                    <button
                                      onClick={() => setVerifyBankModalRest(r)}
                                      style={{
                                        padding: '4px 8px',
                                        borderRadius: '6px',
                                        border: '1px solid #1e60ff',
                                        background: '#eff6ff',
                                        color: '#1e60ff',
                                        fontSize: '11px',
                                        fontWeight: 700,
                                        cursor: 'pointer'
                                      }}
                                    >
                                      Verify Bank
                                    </button>
                                  )}

                                  {(r.pendingSettlement || 0) > 0 && (
                                    <button
                                      onClick={() => {
                                        if (!isVerified) {
                                          alert('Bank account must be verified before initiating payout.');
                                          setVerifyBankModalRest(r);
                                          return;
                                        }
                                        setInitiateModalRest(r);
                                      }}
                                      style={{
                                        padding: '4px 8px',
                                        borderRadius: '6px',
                                        border: 'none',
                                        background: isVerified ? '#ea580c' : '#cbd5e1',
                                        color: '#fff',
                                        fontSize: '11px',
                                        fontWeight: 700,
                                        cursor: isVerified ? 'pointer' : 'not-allowed'
                                      }}
                                    >
                                      Initiate Payout
                                    </button>
                                  )}
                                </div>
                              </td>
                            </tr>
                          );
                        })
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* VIEW B: SETTLEMENT TRANSACTIONS AUDIT TABLE */}
          {settlementViewMode === 'transactions' && (
            <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '16px', overflow: 'hidden' }}>
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--border-color)', background: 'var(--bg-main)' }}>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Settlement ID</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Restaurant</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Orders</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Gross Sales</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Commission</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Net Payout</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Status</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Bank Ref (UTR)</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Date</th>
                      <th style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-muted)' }}>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {settlementsList.length === 0 ? (
                      <tr>
                        <td colSpan={10} style={{ padding: '36px', textAlign: 'center', color: 'var(--text-muted)' }}>
                          No settlement transactions found.
                        </td>
                      </tr>
                    ) : (
                      settlementsList
                        .filter((s: any) => {
                          if (settlementStatusFilter !== 'all' && s.status !== settlementStatusFilter) return false;
                          if (!settlementSearchQuery.trim()) return true;
                          const q = settlementSearchQuery.toLowerCase();
                          return (
                            (s.settlementId || '').toLowerCase().includes(q) ||
                            (s.restaurantName || '').toLowerCase().includes(q) ||
                            (s.payoutReference || '').toLowerCase().includes(q)
                          );
                        })
                        .map((s: any) => {
                          const isPaid = s.status === 'paid';
                          const isProc = s.status === 'processing';
                          const isFailed = s.status === 'failed';

                          return (
                            <tr key={s.settlementId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                              <td style={{ padding: '14px 16px', fontFamily: 'monospace', fontWeight: 700, color: 'var(--text-main)' }}>
                                #{s.settlementId}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                <div style={{ fontWeight: 700, color: 'var(--text-main)' }}>{s.restaurantName}</div>
                                <div style={{ fontSize: '11px', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{s.restaurantId}</div>
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-main)' }}>
                                {s.ordersCount || (s.orderIds || []).length}
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 700, color: 'var(--text-main)', fontFamily: 'monospace' }}>
                                ₹{(s.grossSales || 0).toLocaleString('en-IN')}
                              </td>

                              <td style={{ padding: '14px 16px', color: '#f59e0b', fontWeight: 700, fontFamily: 'monospace' }}>
                                -₹{(s.totalCommission || 0).toLocaleString('en-IN')}
                              </td>

                              <td style={{ padding: '14px 16px', fontWeight: 900, color: isPaid ? '#16a34a' : 'var(--text-main)', fontSize: '14px', fontFamily: 'monospace' }}>
                                ₹{(s.netPayable || 0).toLocaleString('en-IN')}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                {isPaid ? (
                                  <span style={{ background: '#dcfce7', color: '#166534', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 800 }}>
                                    PAID
                                  </span>
                                ) : isProc ? (
                                  <span style={{ background: '#eff6ff', color: '#1d4ed8', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 800 }}>
                                    PROCESSING
                                  </span>
                                ) : isFailed ? (
                                  <span style={{ background: '#fee2e2', color: '#991b1b', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 800 }}>
                                    FAILED
                                  </span>
                                ) : (
                                  <span style={{ background: '#fef3c7', color: '#92400e', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 800 }}>
                                    PENDING
                                  </span>
                                )}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                {s.payoutReference ? (
                                  <div style={{ fontFamily: 'monospace', fontWeight: 700, color: '#1e60ff', fontSize: '12px' }}>
                                    {s.payoutReference}
                                  </div>
                                ) : s.failureReason ? (
                                  <div style={{ color: '#ef4444', fontSize: '11px' }}>
                                    {s.failureReason}
                                  </div>
                                ) : (
                                  <span style={{ color: 'var(--text-muted)', fontSize: '11px' }}>—</span>
                                )}
                              </td>

                              <td style={{ padding: '14px 16px', color: 'var(--text-muted)', fontSize: '11.5px' }}>
                                {s.settledAt ? new Date(s.settledAt).toLocaleDateString() : s.createdAt ? new Date(s.createdAt).toLocaleDateString() : '—'}
                              </td>

                              <td style={{ padding: '14px 16px' }}>
                                {isProc && (
                                  <div style={{ display: 'flex', gap: '6px' }}>
                                    <button
                                      onClick={() => setConfirmPayoutModalSettlement(s)}
                                      style={{
                                        padding: '4px 8px',
                                        borderRadius: '6px',
                                        border: 'none',
                                        background: '#16a34a',
                                        color: '#fff',
                                        fontSize: '11px',
                                        fontWeight: 700,
                                        cursor: 'pointer'
                                      }}
                                    >
                                      Record UTR
                                    </button>
                                    <button
                                      onClick={() => setFailPayoutModalSettlement(s)}
                                      style={{
                                        padding: '4px 8px',
                                        borderRadius: '6px',
                                        border: '1px solid #ef4444',
                                        background: 'transparent',
                                        color: '#ef4444',
                                        fontSize: '11px',
                                        fontWeight: 700,
                                        cursor: 'pointer'
                                      }}
                                    >
                                      Fail
                                    </button>
                                  </div>
                                )}
                                {isFailed && (
                                  <button
                                    onClick={() => {
                                      const rest = settlementOverview?.restaurants?.find((r: any) => r.restaurantId === s.restaurantId);
                                      if (rest) {
                                        if (rest.bankVerificationStatus !== 'verified') {
                                          alert('Please verify partner bank details before retrying payout.');
                                          setVerifyBankModalRest(rest);
                                        } else {
                                          setInitiateModalRest(rest);
                                        }
                                      } else {
                                        alert('Partner pending balance restored. You can initiate a new payout batch from the Partner Balances tab.');
                                      }
                                    }}
                                    style={{
                                      padding: '4px 8px',
                                      borderRadius: '6px',
                                      border: '1px solid #ea580c',
                                      background: '#fff7ed',
                                      color: '#ea580c',
                                      fontSize: '11px',
                                      fontWeight: 700,
                                      cursor: 'pointer'
                                    }}
                                  >
                                    Retry Payout
                                  </button>
                                )}
                              </td>
                            </tr>
                          );
                        })
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ===================================================================== */}
      {/* SUB-TAB 3: BILL & FEE CONFIGURATION                                    */}
      {/* ===================================================================== */}
      {activeSubTab === 'config' && (
        <div style={{ maxWidth: '780px', background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '16px', padding: '24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '8px' }}>
            <Sliders size={20} color="#ea580c" />
            <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Food Order Bill & Fee Settings</h3>
          </div>
          <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '20px' }}>
            Configure authoritative platform fees, restaurant packaging charges, delivery rules, and taxes applied to customer checkout.
          </p>

          <form onSubmit={handleSaveConfig} style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Default Restaurant Commission (%)
                </label>
                <input
                  type="number"
                  step="0.1"
                  value={config.defaultCommissionRate}
                  onChange={e => setConfig({ ...config, defaultCommissionRate: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Platform cut from restaurant GMV.</span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Default Restaurant Packaging Charges (₹)
                </label>
                <input
                  type="number"
                  value={config.defaultPackagingFee !== undefined ? config.defaultPackagingFee : 10}
                  onChange={e => setConfig({ ...config, defaultPackagingFee: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Decided & charged by the restaurant (e.g. ₹10).</span>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Base Platform Convenience Fee (₹)
                </label>
                <input
                  type="number"
                  value={config.platformFee}
                  onChange={e => setConfig({ ...config, platformFee: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Original convenience fee before discount (e.g. ₹15).</span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Discounted Platform Fee Charged (₹)
                </label>
                <input
                  type="number"
                  value={config.discountedPlatformFee !== undefined ? config.discountedPlatformFee : 9}
                  onChange={e => setConfig({ ...config, discountedPlatformFee: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Actual fee charged to customer (e.g. ~~₹15~~ ₹9).</span>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Base Delivery Partner Fee (₹)
                </label>
                <input
                  type="number"
                  value={config.deliveryBaseFee}
                  onChange={e => setConfig({ ...config, deliveryBaseFee: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Base fee for delivery distance up to 3 km.</span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Delivery Per-Km Fee beyond 3 km (₹/km)
                </label>
                <input
                  type="number"
                  value={config.deliveryPerKmFee !== undefined ? config.deliveryPerKmFee : 8}
                  onChange={e => setConfig({ ...config, deliveryPerKmFee: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Additional charge per km beyond 3 km.</span>
              </div>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Food GST & Taxes Rate (%)
                </label>
                <input
                  type="number"
                  step="0.1"
                  value={config.taxRatePercent}
                  onChange={e => setConfig({ ...config, taxRatePercent: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Applicable GST on food subtotal + packaging.</span>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Minimum Order Amount (₹)
                </label>
                <input
                  type="number"
                  value={config.minOrderAmount || 0}
                  onChange={e => setConfig({ ...config, minOrderAmount: parseFloat(e.target.value) || 0 })}
                  style={{ width: '100%', padding: '10px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '14px' }}
                />
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>0 for no minimum restriction.</span>
              </div>
            </div>

            {/* Cash Rounding Toggle */}
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              padding: '12px 16px',
              borderRadius: '8px',
              background: 'rgba(234, 88, 12, 0.06)',
              border: '1px solid rgba(234, 88, 12, 0.2)'
            }}>
              <div>
                <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-main)' }}>
                  Cash Round Off for Cash on Delivery (COD)
                </div>
                <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '2px' }}>
                  When enabled, round COD order payable to nearest rupee (e.g. ₹167.07 → ₹167). Online payments pay exact decimal paise.
                </div>
              </div>
              <input
                type="checkbox"
                checked={config.cashRoundingEnabled !== false}
                onChange={e => setConfig({ ...config, cashRoundingEnabled: e.target.checked })}
                style={{ width: '18px', height: '18px', cursor: 'pointer', accentColor: '#ea580c' }}
              />
            </div>

            <button
              type="submit"
              style={{
                marginTop: '10px',
                padding: '12px 20px',
                background: '#ea580c',
                color: '#fff',
                border: 'none',
                borderRadius: '8px',
                fontWeight: 700,
                fontSize: '14px',
                cursor: 'pointer'
              }}
            >
              Save Fee & Bill Settings
            </button>
          </form>
        </div>
      )}

      {/* ===================================================================== */}
      {/* SUB-TAB 4: FOOD COUPONS & OFFERS MANAGEMENT                           */}
      {/* ===================================================================== */}
      {activeSubTab === 'coupons' && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Food Coupons & Promotional Offers</h3>
              <p style={{ margin: '4px 0 0', fontSize: '13px', color: 'var(--text-muted)' }}>
                Manage checkout coupons, percentage discounts, flat savings, and free delivery offers.
              </p>
            </div>
            <button
              onClick={() => {
                setEditingCoupon(null);
                setCouponFormData({
                  code: '',
                  title: '',
                  description: '',
                  discountType: 'percentage',
                  discountValue: 50,
                  minOrderAmount: 99,
                  maxDiscountAmount: 70,
                  freeDelivery: false,
                  restaurantId: '',
                  validTill: new Date(Date.now() + 180 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
                  isActive: true
                });
                setIsAddCouponModalOpen(true);
              }}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: '8px',
                padding: '10px 18px',
                background: '#ea580c',
                color: '#fff',
                border: 'none',
                borderRadius: '8px',
                fontWeight: 700,
                fontSize: '13px',
                cursor: 'pointer'
              }}
            >
              <Plus size={16} /> Create New Food Coupon
            </button>
          </div>

          {/* Coupons Table */}
          <div style={{ background: 'var(--card-bg)', border: '1px solid var(--border-color)', borderRadius: '14px', overflow: 'hidden' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left', fontSize: '13px' }}>
              <thead>
                <tr style={{ background: 'rgba(0,0,0,0.02)', borderBottom: '1px solid var(--border-color)', color: 'var(--text-muted)' }}>
                  <th style={{ padding: '12px 16px' }}>COUPON CODE</th>
                  <th style={{ padding: '12px 16px' }}>TITLE & OFFER</th>
                  <th style={{ padding: '12px 16px' }}>DISCOUNT TYPE</th>
                  <th style={{ padding: '12px 16px' }}>VALUE</th>
                  <th style={{ padding: '12px 16px' }}>MIN ORDER</th>
                  <th style={{ padding: '12px 16px' }}>MAX DISCOUNT</th>
                  <th style={{ padding: '12px 16px' }}>STATUS</th>
                  <th style={{ padding: '12px 16px', textAlign: 'right' }}>ACTIONS</th>
                </tr>
              </thead>
              <tbody>
                {coupons.length === 0 ? (
                  <tr>
                    <td colSpan={8} style={{ padding: '30px', textAlign: 'center', color: 'var(--text-muted)' }}>
                      No food coupons configured. Click "Create New Food Coupon" to add one.
                    </td>
                  </tr>
                ) : (
                  coupons.map((c: any) => (
                    <tr key={c._id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '12px 16px' }}>
                        <span style={{
                          fontFamily: 'monospace',
                          fontWeight: 800,
                          fontSize: '12.5px',
                          padding: '3px 8px',
                          borderRadius: '6px',
                          background: 'rgba(234, 88, 12, 0.12)',
                          color: '#ea580c',
                          border: '1px solid rgba(234, 88, 12, 0.3)'
                        }}>
                          {c.code}
                        </span>
                      </td>
                      <td style={{ padding: '12px 16px' }}>
                        <div style={{ fontWeight: 700, color: 'var(--text-main)' }}>{c.title}</div>
                        <div style={{ fontSize: '11.5px', color: 'var(--text-muted)' }}>{c.description || '—'}</div>
                      </td>
                      <td style={{ padding: '12px 16px', textTransform: 'capitalize' }}>
                        {c.discountType === 'free_delivery' || c.freeDelivery ? 'Free Delivery' : c.discountType}
                      </td>
                      <td style={{ padding: '12px 16px', fontWeight: 700 }}>
                        {c.discountType === 'percentage' ? `${c.discountValue}% OFF` : `₹${c.discountValue} FLAT`}
                      </td>
                      <td style={{ padding: '12px 16px' }}>₹{c.minOrderAmount || 0}</td>
                      <td style={{ padding: '12px 16px' }}>{c.maxDiscountAmount ? `₹${c.maxDiscountAmount}` : 'Unlimited'}</td>
                      <td style={{ padding: '12px 16px' }}>
                        <button
                          type="button"
                          onClick={() => handleToggleCouponStatus(c)}
                          style={{
                            padding: '3px 10px',
                            borderRadius: '12px',
                            border: 'none',
                            fontSize: '11px',
                            fontWeight: 800,
                            cursor: 'pointer',
                            background: c.isActive ? '#dcfce7' : '#fee2e2',
                            color: c.isActive ? '#15803d' : '#b91c1c'
                          }}
                        >
                          {c.isActive ? 'ACTIVE' : 'INACTIVE'}
                        </button>
                      </td>
                      <td style={{ padding: '12px 16px', textAlign: 'right' }}>
                        <button
                          type="button"
                          onClick={() => {
                            setEditingCoupon(c);
                            setCouponFormData({
                              code: c.code,
                              title: c.title,
                              description: c.description || '',
                              discountType: c.discountType || 'percentage',
                              discountValue: c.discountValue || 0,
                              minOrderAmount: c.minOrderAmount || 0,
                              maxDiscountAmount: c.maxDiscountAmount || 0,
                              freeDelivery: Boolean(c.freeDelivery),
                              restaurantId: c.restaurantId || '',
                              validTill: c.validTill ? new Date(c.validTill).toISOString().split('T')[0] : '',
                              isActive: c.isActive !== false
                            });
                            setIsAddCouponModalOpen(true);
                          }}
                          style={{
                            padding: '4px 8px',
                            background: 'transparent',
                            border: '1px solid var(--border-color)',
                            borderRadius: '6px',
                            cursor: 'pointer',
                            marginRight: '6px',
                            color: 'var(--text-main)'
                          }}
                        >
                          <Edit size={13} />
                        </button>
                        <button
                          type="button"
                          onClick={() => handleDeleteCoupon(c._id, c.code)}
                          style={{
                            padding: '4px 8px',
                            background: 'transparent',
                            border: '1px solid #fee2e2',
                            borderRadius: '6px',
                            cursor: 'pointer',
                            color: '#ef4444'
                          }}
                        >
                          <Trash2 size={13} />
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL: ADD / EDIT FOOD COUPON                                         */}
      {/* ===================================================================== */}
      {isAddCouponModalOpen && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.7)',
          backdropFilter: 'blur(6px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1200,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            color: 'var(--text-main)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '560px',
            padding: '24px',
            boxShadow: '0 25px 50px rgba(0,0,0,0.5)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '18px' }}>
              <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>
                {editingCoupon ? `Edit Coupon: ${editingCoupon.code}` : 'Create New Food Coupon'}
              </h3>
              <button
                type="button"
                onClick={() => setIsAddCouponModalOpen(false)}
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveCoupon} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Coupon Code</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. TAKEOFF50ON99"
                  value={couponFormData.code}
                  onChange={e => setCouponFormData({ ...couponFormData, code: e.target.value.toUpperCase() })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontWeight: 700, fontFamily: 'monospace' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Display Title</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. Save ₹69.50 with 'TAKEOFF50ON99'"
                  value={couponFormData.title}
                  onChange={e => setCouponFormData({ ...couponFormData, title: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Description</label>
                <input
                  type="text"
                  placeholder="e.g. 50% OFF up to ₹70 on orders above ₹99"
                  value={couponFormData.description}
                  onChange={e => setCouponFormData({ ...couponFormData, description: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)' }}
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Discount Type</label>
                  <select
                    value={couponFormData.discountType}
                    onChange={e => setCouponFormData({ ...couponFormData, discountType: e.target.value })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--card-bg)', color: 'var(--text-main)' }}
                  >
                    <option value="percentage">Percentage (%)</option>
                    <option value="flat">Flat Amount (₹)</option>
                    <option value="free_delivery">Free Delivery</option>
                  </select>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    {couponFormData.discountType === 'percentage' ? 'Discount Percentage (%)' : 'Discount Amount (₹)'}
                  </label>
                  <input
                    type="number"
                    required
                    value={couponFormData.discountValue}
                    onChange={e => setCouponFormData({ ...couponFormData, discountValue: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)' }}
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Minimum Order (₹)</label>
                  <input
                    type="number"
                    value={couponFormData.minOrderAmount}
                    onChange={e => setCouponFormData({ ...couponFormData, minOrderAmount: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)' }}
                  />
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Max Discount Cap (₹)</label>
                  <input
                    type="number"
                    placeholder="0 for uncapped"
                    value={couponFormData.maxDiscountAmount}
                    onChange={e => setCouponFormData({ ...couponFormData, maxDiscountAmount: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)' }}
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>Valid Till Date</label>
                  <input
                    type="date"
                    value={couponFormData.validTill}
                    onChange={e => setCouponFormData({ ...couponFormData, validTill: e.target.value })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)' }}
                  />
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '22px' }}>
                  <input
                    type="checkbox"
                    id="coupon_active_chk"
                    checked={couponFormData.isActive}
                    onChange={e => setCouponFormData({ ...couponFormData, isActive: e.target.checked })}
                    style={{ width: '18px', height: '18px', accentColor: '#ea580c' }}
                  />
                  <label htmlFor="coupon_active_chk" style={{ fontSize: '13px', fontWeight: 700, cursor: 'pointer' }}>
                    Active & Available
                  </label>
                </div>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '10px' }}>
                <button
                  type="button"
                  onClick={() => setIsAddCouponModalOpen(false)}
                  style={{ padding: '10px 16px', background: 'transparent', border: '1px solid var(--border-color)', borderRadius: '8px', color: 'var(--text-muted)', cursor: 'pointer' }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  style={{ padding: '10px 20px', background: '#ea580c', color: '#fff', border: 'none', borderRadius: '8px', fontWeight: 700, cursor: 'pointer' }}
                >
                  {editingCoupon ? 'Update Coupon' : 'Create Coupon'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 1: ADD / EDIT RESTAURANT (Picture 1 functional controls)        */}
      {/* ===================================================================== */}
      {isAddEditRestModalOpen && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.8)',
          backdropFilter: 'blur(8px)',
          WebkitBackdropFilter: 'blur(8px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1100,
          padding: '20px'
        }}>
          <div style={{
            background: '#0f172a',
            color: '#f8fafc',
            border: '1px solid #334155',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '680px',
            maxHeight: '92vh',
            overflowY: 'auto',
            boxShadow: '0 25px 60px rgba(0,0,0,0.8)',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '18px' }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>
                  {isEditingRest ? `Edit Restaurant: ${restFormData.name}` : 'Add New Restaurant Partner'}
                </h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Configure restaurant details, cover image, cuisines, and platform commission.
                </div>
              </div>
              <button 
                onClick={() => setIsAddEditRestModalOpen(false)} 
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveRestaurant}>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Restaurant Name *
                  </label>
                  <input
                    type="text"
                    required
                    value={restFormData.name}
                    onChange={e => setRestFormData({ ...restFormData, name: e.target.value })}
                    placeholder="e.g. Chutneys Flavours"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Owner Name
                  </label>
                  <input
                    type="text"
                    value={restFormData.ownerName}
                    onChange={e => setRestFormData({ ...restFormData, ownerName: e.target.value })}
                    placeholder="e.g. Venkatesh Rao"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Contact Phone *
                  </label>
                  <input
                    type="text"
                    required
                    value={restFormData.phone}
                    onChange={e => setRestFormData({ ...restFormData, phone: e.target.value })}
                    placeholder="e.g. 9849054321"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    FSSAI Licence Number
                  </label>
                  <input
                    type="text"
                    value={restFormData.fssaiNumber}
                    onChange={e => setRestFormData({ ...restFormData, fssaiNumber: e.target.value })}
                    placeholder="e.g. 13619012000567"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
              </div>

              <div style={{ marginBottom: '14px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                  <label style={{ fontSize: '12px', fontWeight: 700 }}>
                    Full Address *
                  </label>
                  <button
                    type="button"
                    onClick={() => handleGeocodeAddress()}
                    disabled={isGeocoding}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px',
                      background: '#f0f9ff',
                      border: '1px solid #bae6fd',
                      color: '#0369a1',
                      padding: '3px 8px',
                      borderRadius: '6px',
                      cursor: isGeocoding ? 'not-allowed' : 'pointer',
                      fontSize: '11px',
                      fontWeight: 700
                    }}
                    title="Detect GPS latitude & longitude from the address above"
                  >
                    <MapPin size={11} /> {isGeocoding ? 'Detecting GPS...' : 'Auto-Detect GPS'}
                  </button>
                </div>
                <input
                  type="text"
                  required
                  value={restFormData.address}
                  onChange={e => setRestFormData({ ...restFormData, address: e.target.value })}
                  placeholder="e.g. Cyber Towers Road, Hitec City, Madhapur, Hyderabad"
                  style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                />
              </div>

              {/* Exact GPS Coordinates for Distance & Delivery Fee Calculation */}
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px', background: 'rgba(2, 132, 199, 0.04)', padding: '10px 12px', borderRadius: '8px', border: '1px dashed #bae6fd' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '11.5px', fontWeight: 700, color: '#0369a1', marginBottom: '4px' }}>
                    Latitude (GPS)
                  </label>
                  <input
                    type="number"
                    step="any"
                    value={restFormData.lat !== undefined ? restFormData.lat : ''}
                    onChange={e => setRestFormData({ ...restFormData, lat: parseFloat(e.target.value) || 0 })}
                    placeholder="e.g. 17.5230"
                    style={{ width: '100%', padding: '7px 10px', borderRadius: '6px', border: '1px solid #bae6fd', background: 'var(--card-bg)', color: 'var(--text-main)', fontSize: '12.5px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '11.5px', fontWeight: 700, color: '#0369a1', marginBottom: '4px' }}>
                    Longitude (GPS)
                  </label>
                  <input
                    type="number"
                    step="any"
                    value={restFormData.lng !== undefined ? restFormData.lng : ''}
                    onChange={e => setRestFormData({ ...restFormData, lng: parseFloat(e.target.value) || 0 })}
                    placeholder="e.g. 78.4222"
                    style={{ width: '100%', padding: '7px 10px', borderRadius: '6px', border: '1px solid #bae6fd', background: 'var(--card-bg)', color: 'var(--text-main)', fontSize: '12.5px' }}
                  />
                </div>
                <div style={{ gridColumn: 'span 2', fontSize: '10.5px', color: '#64748b' }}>
                  Used for real-time customer distance calculation (Haversine km) and dynamic delivery partner fees.
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Cuisines (comma-separated)
                  </label>
                  <input
                    type="text"
                    value={restFormData.cuisines}
                    onChange={e => setRestFormData({ ...restFormData, cuisines: e.target.value })}
                    placeholder="e.g. South Indian, Breakfast, Pure Veg, Snacks"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Opening Hours
                  </label>
                  <input
                    type="text"
                    value={restFormData.openingHours}
                    onChange={e => setRestFormData({ ...restFormData, openingHours: e.target.value })}
                    placeholder="e.g. 07:00 AM - 10:30 PM"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '14px', marginBottom: '14px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Commission Rate (%)
                  </label>
                  <input
                    type="number"
                    value={restFormData.commissionRate}
                    onChange={e => setRestFormData({ ...restFormData, commissionRate: e.target.value })}
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Delivery Fee (₹)
                  </label>
                  <input
                    type="number"
                    value={restFormData.deliveryFee}
                    onChange={e => setRestFormData({ ...restFormData, deliveryFee: e.target.value })}
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Approval Status
                  </label>
                  <select
                    value={restFormData.status}
                    onChange={e => setRestFormData({ ...restFormData, status: e.target.value })}
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--card-bg)', color: 'var(--text-main)', fontSize: '13px' }}
                  >
                    <option value="approved">Approved</option>
                    <option value="pending">Pending</option>
                    <option value="suspended">Suspended</option>
                  </select>
                </div>
              </div>

              {/* Image Upload & Preview */}
              <div style={{ marginBottom: '18px', padding: '12px', border: '1px dashed var(--border-color)', borderRadius: '10px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Restaurant Profile & Cover Image
                </label>
                <div style={{ display: 'flex', gap: '14px', alignItems: 'center' }}>
                  <img
                    src={restFormData.imageUrl}
                    alt="Preview"
                    style={{ width: '70px', height: '70px', borderRadius: '8px', objectFit: 'cover', border: '1px solid var(--border-color)' }}
                  />
                  <div style={{ flex: 1 }}>
                    <input
                      type="file"
                      accept="image/*"
                      onChange={e => handleImageFileChange(e, 'restaurant')}
                      style={{ fontSize: '12px', marginBottom: '6px' }}
                    />
                    <input
                      type="text"
                      placeholder="Or paste image URL"
                      value={restFormData.imageUrl}
                      onChange={e => setRestFormData({ ...restFormData, imageUrl: e.target.value })}
                      style={{ width: '100%', padding: '6px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', fontSize: '11.5px', background: 'transparent', color: 'var(--text-main)' }}
                    />
                    {isUploadingImage && <span style={{ fontSize: '11px', color: '#ea580c' }}>Uploading image to server...</span>}
                  </div>
                </div>
              </div>

              {/* Toggles */}
              <div style={{ display: 'flex', gap: '20px', marginBottom: '20px' }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '13px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={restFormData.isOpen}
                    onChange={e => setRestFormData({ ...restFormData, isOpen: e.target.checked })}
                  />
                  <strong>Store Open Now</strong> (Accepting live orders)
                </label>
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '13px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={restFormData.isVegOnly}
                    onChange={e => setRestFormData({ ...restFormData, isVegOnly: e.target.checked })}
                  />
                  <strong>Pure Veg Restaurant</strong>
                </label>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                <button
                  type="button"
                  onClick={() => setIsAddEditRestModalOpen(false)}
                  style={{
                    padding: '8px 18px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'transparent',
                    color: 'var(--text-main)',
                    fontWeight: 600,
                    cursor: 'pointer'
                  }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  style={{
                    padding: '8px 22px',
                    borderRadius: '8px',
                    border: 'none',
                    background: '#ea580c',
                    color: '#fff',
                    fontWeight: 700,
                    cursor: 'pointer'
                  }}
                >
                  {isEditingRest ? 'Save Changes' : 'Create Restaurant'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 2: MANAGE MENU & EDITABLE RATES (Picture 2 UX!)                 */}
      {/* ===================================================================== */}
      {isManageMenuModalOpen && activeRestaurantForMenu && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.8)',
          backdropFilter: 'blur(8px)',
          WebkitBackdropFilter: 'blur(8px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1100,
          padding: '20px'
        }}>
          <div style={{
            background: '#0f172a',
            color: '#f8fafc',
            border: '1px solid #334155',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '920px',
            maxHeight: '92vh',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden',
            boxShadow: '0 25px 60px rgba(0,0,0,0.8)'
          }}>
            {/* Modal Header */}
            <div style={{ padding: '20px 24px', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <MenuIcon size={20} color="#ea580c" />
                  <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>
                    {activeRestaurantForMenu.name} — Menu & Rate Management
                  </h3>
                </div>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                  Adjust dish rates (-₹50, -₹10, +₹10, +₹50), toggle in-stock inventory, and add new items in real time.
                </div>
              </div>
              <button 
                onClick={() => setIsManageMenuModalOpen(false)} 
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Picture 2 Style Bulk Price Adjustment Bar */}
            <div style={{ 
              padding: '12px 24px', 
              background: 'rgba(0,0,0,0.02)', 
              borderBottom: '1px solid var(--border-color)',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              flexWrap: 'wrap',
              gap: '10px'
            }}>
              {/* Category Filter & Search */}
              <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)' }}>CATEGORY:</span>
                <select
                  value={menuFilterCategory}
                  onChange={e => setMenuFilterCategory(e.target.value)}
                  style={{
                    padding: '6px 10px',
                    borderRadius: '6px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--card-bg)',
                    fontSize: '12px',
                    fontWeight: 600,
                    color: 'var(--text-main)'
                  }}
                >
                  <option value="All">All Categories</option>
                  {(activeRestaurantForMenu.categories || ['South Indian', 'Biryani', 'Snacks', 'Desserts', 'Beverages']).map((cat: string) => (
                    <option key={cat} value={cat}>{cat}</option>
                  ))}
                </select>

                <input
                  type="text"
                  placeholder="Filter dishes..."
                  value={menuSearchQuery}
                  onChange={e => setMenuSearchQuery(e.target.value)}
                  style={{
                    padding: '6px 10px',
                    borderRadius: '6px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--card-bg)',
                    fontSize: '12px',
                    width: '160px',
                    color: 'var(--text-main)'
                  }}
                />
              </div>

              {/* Bulk Action Buttons directly implementing Picture 2 Reference */}
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                <span style={{ fontSize: '11px', fontWeight: 800, color: 'var(--text-muted)' }}>
                  BULK ACTION FOR {menuFilterCategory.toUpperCase()}:
                </span>
                
                {/* +10% All Tasks (Picture 2 reference) */}
                <button
                  onClick={() => handleRequestBulkPreview({
                    percentDelta: 10,
                    title: `+10% Rate Adjustment Across ${menuFilterCategory === 'All' ? 'All Dishes' : menuFilterCategory}`
                  })}
                  disabled={bulkPreviewLoading}
                  style={{
                    padding: '5px 10px',
                    borderRadius: '20px',
                    border: '1px solid #86efac',
                    background: '#dcfce7',
                    color: '#15803d',
                    fontSize: '11px',
                    fontWeight: 800,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                  title="Increase all dishes by 10%"
                >
                  +10% All Tasks
                </button>

                {/* -10% All Tasks (Picture 2 reference) */}
                <button
                  onClick={() => handleRequestBulkPreview({
                    percentDelta: -10,
                    title: `-10% Rate Adjustment Across ${menuFilterCategory === 'All' ? 'All Dishes' : menuFilterCategory}`
                  })}
                  disabled={bulkPreviewLoading}
                  style={{
                    padding: '5px 10px',
                    borderRadius: '20px',
                    border: '1px solid #fecdd3',
                    background: '#fff1f2',
                    color: '#be123c',
                    fontSize: '11px',
                    fontWeight: 800,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                  title="Decrease all dishes by 10%"
                >
                  -10% All Tasks
                </button>

                {/* +₹20 All Tasks (Picture 2 reference) */}
                <button
                  onClick={() => handleRequestBulkPreview({
                    delta: 20,
                    title: `+₹20 Rate Adjustment Across ${menuFilterCategory === 'All' ? 'All Dishes' : menuFilterCategory}`
                  })}
                  disabled={bulkPreviewLoading}
                  style={{
                    padding: '5px 10px',
                    borderRadius: '20px',
                    border: '1px solid #86efac',
                    background: '#dcfce7',
                    color: '#15803d',
                    fontSize: '11px',
                    fontWeight: 800,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                  title="Increase all dishes by ₹20"
                >
                  +₹20 All Tasks
                </button>

                {/* Reset Category (Picture 2 reference) */}
                <button
                  onClick={() => handleRequestBulkPreview({
                    delta: 0,
                    title: `Reset & Verify Tariff Line for ${menuFilterCategory === 'All' ? 'All Dishes' : menuFilterCategory}`
                  })}
                  disabled={bulkPreviewLoading}
                  style={{
                    padding: '5px 10px',
                    borderRadius: '20px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--card-bg)',
                    color: 'var(--text-muted)',
                    fontSize: '11px',
                    fontWeight: 700,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px'
                  }}
                  title="Preview tariff verification"
                >
                  ↺ Reset Category
                </button>

                {/* Add Item Button */}
                <button
                  onClick={handleOpenAddDish}
                  style={{
                    marginLeft: '8px',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px',
                    background: '#ea580c',
                    color: '#fff',
                    border: 'none',
                    padding: '6px 14px',
                    borderRadius: '8px',
                    fontWeight: 800,
                    fontSize: '12px',
                    cursor: 'pointer',
                    boxShadow: '0 2px 6px rgba(234, 88, 12, 0.3)'
                  }}
                >
                  <Plus size={14} /> + Add Task
                </button>
              </div>
            </div>

            {/* Sub-header: Authorized Tasks count (Picture 2 reference) */}
            <div style={{ padding: '8px 24px', background: 'rgba(0,0,0,0.01)', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)' }}>
                Authorized Tasks & Food Service Line Tariffs ({filteredMenuItems.length} dishes):
              </div>
              <div style={{ fontSize: '11px', color: '#16a34a', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '4px' }}>
                <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: '#16a34a' }}></span>
                Realtime Synced with Mobile Consoles
              </div>
            </div>

            {/* Menu Items List with Picture 2 Rate Modifiers */}
            <div style={{ flex: 1, overflowY: 'auto', padding: '16px 24px' }}>
              {loadingMenu ? (
                <div style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  Loading menu items...
                </div>
              ) : filteredMenuItems.length === 0 ? (
                <div style={{ padding: '40px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  No dishes found. Tap <strong>+ Add Task</strong> above to add dishes to this restaurant.
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {filteredMenuItems.map(item => {
                    const isSavingThis = savingItemPriceId === item.itemId;
                    const isSavedThis = savedItemIds[item.itemId] === true;

                    return (
                      <div
                        key={item.itemId}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'space-between',
                          padding: '12px 16px',
                          background: '#1e293b',
                          color: '#f8fafc',
                          border: isSavedThis ? '1.5px solid #16a34a' : '1px solid #334155',
                          borderRadius: '10px',
                          gap: '14px',
                          flexWrap: 'wrap',
                          transition: 'border-color 0.3s'
                        }}
                      >
                        {/* Checkmark & Dish Info (Picture 2 reference) */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flex: 1, minWidth: '240px' }}>
                          <div style={{
                            width: '24px',
                            height: '24px',
                            borderRadius: '50%',
                            background: '#dcfce7',
                            color: '#15803d',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            fontSize: '13px',
                            fontWeight: 900,
                            flexShrink: 0
                          }}>
                            ✓
                          </div>

                          <img
                            src={item.imageUrl || 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=800&auto=format&fit=crop&q=80'}
                            alt={item.name}
                            style={{ width: '46px', height: '46px', borderRadius: '8px', objectFit: 'cover', flexShrink: 0 }}
                          />

                          <div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '6px', flexWrap: 'wrap' }}>
                              <span style={{ fontSize: '11px' }}>{item.isVeg ? '🟢' : '🔴'}</span>
                              <span style={{ fontWeight: 800, fontSize: '13.5px', color: 'var(--text-main)' }}>{item.name}</span>
                              <span style={{ fontSize: '10px', background: 'rgba(0,0,0,0.06)', padding: '2px 6px', borderRadius: '4px', fontWeight: 600 }}>
                                {item.category}
                              </span>
                              {item.isBestseller && (
                                <span style={{ background: '#fef3c7', color: '#b45309', padding: '2px 6px', borderRadius: '4px', fontSize: '10px', fontWeight: 800 }}>
                                  ★ Bestseller
                                </span>
                              )}
                              {item.isRecommended && (
                                <span style={{ background: '#eff6ff', color: '#1d4ed8', padding: '2px 6px', borderRadius: '4px', fontSize: '10px', fontWeight: 800 }}>
                                  Recommended
                                </span>
                              )}
                            </div>

                            {item.description && (
                              <div style={{ fontSize: '11.5px', color: 'var(--text-muted)', marginTop: '2px', maxWidth: '400px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                                {item.description}
                              </div>
                            )}

                            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', fontSize: '11px', color: 'var(--text-muted)', marginTop: '3px' }}>
                              <span>⏱ {item.prepTime || '20 mins'}</span>
                              <span>★ {item.rating || 4.8} rating</span>
                              <span style={{ color: '#16a34a', fontWeight: 700 }}>Partner Rate: ₹{item.price}</span>
                            </div>
                          </div>
                        </div>

                        {/* Stock Switch */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <button
                            onClick={() => handleToggleItemStock(item.itemId, item.isAvailable)}
                            style={{
                              padding: '4px 10px',
                              borderRadius: '12px',
                              border: 'none',
                              fontSize: '10.5px',
                              fontWeight: 800,
                              cursor: 'pointer',
                              background: item.isAvailable ? '#dcfce7' : '#fee2e2',
                              color: item.isAvailable ? '#166534' : '#b91c1c'
                            }}
                            title="Toggle stock availability"
                          >
                            {item.isAvailable ? 'IN STOCK' : 'OUT OF STOCK'}
                          </button>
                        </div>

                        {/* Picture 2 Style Rate Editing Controls (-50, -10, [Price], +10, +50, Save) */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                          {/* -₹50 / -₹10 */}
                          <button
                            onClick={() => handleAdjustItemPrice(item.itemId, -50)}
                            style={{
                              padding: '5px 7px',
                              borderRadius: '6px',
                              border: '1px solid #fecdd3',
                              background: '#fff1f2',
                              color: '#be123c',
                              fontWeight: 800,
                              fontSize: '11px',
                              cursor: 'pointer'
                            }}
                            title="Decrease price by ₹50"
                          >
                            -₹50
                          </button>

                          {/* -₹10 */}
                          <button
                            onClick={() => handleAdjustItemPrice(item.itemId, -10)}
                            style={{
                              padding: '5px 7px',
                              borderRadius: '6px',
                              border: '1px solid #fecdd3',
                              background: '#fff1f2',
                              color: '#be123c',
                              fontWeight: 800,
                              fontSize: '11px',
                              cursor: 'pointer'
                            }}
                            title="Decrease price by ₹10"
                          >
                            -₹10
                          </button>

                          {/* Editable Rate Box */}
                          <div style={{
                            display: 'flex',
                            alignItems: 'center',
                            border: '1.5px solid var(--border-color)',
                            borderRadius: '6px',
                            padding: '3px 8px',
                            background: 'var(--card-bg)'
                          }}>
                            <span style={{ fontSize: '13px', fontWeight: 800, color: 'var(--text-muted)', marginRight: '2px' }}>₹</span>
                            <input
                              type="number"
                              value={item.price}
                              onChange={e => handleManualPriceChange(item.itemId, parseFloat(e.target.value) || 0)}
                              onBlur={e => handleSaveItemPrice(item.itemId, parseFloat(e.target.value) || 0)}
                              onKeyDown={e => e.key === 'Enter' && handleSaveItemPrice(item.itemId, item.price)}
                              style={{
                                width: '56px',
                                border: 'none',
                                outline: 'none',
                                background: 'transparent',
                                fontWeight: 800,
                                fontSize: '13.5px',
                                color: 'var(--text-main)',
                                textAlign: 'center'
                              }}
                            />
                          </div>

                          {/* +₹10 */}
                          <button
                            onClick={() => handleAdjustItemPrice(item.itemId, 10)}
                            style={{
                              padding: '5px 7px',
                              borderRadius: '6px',
                              border: '1px solid #bbf7d0',
                              background: '#f0fdf4',
                              color: '#15803d',
                              fontWeight: 800,
                              fontSize: '11px',
                              cursor: 'pointer'
                            }}
                            title="Increase price by ₹10"
                          >
                            +₹10
                          </button>

                          {/* +₹50 */}
                          <button
                            onClick={() => handleAdjustItemPrice(item.itemId, 50)}
                            style={{
                              padding: '5px 7px',
                              borderRadius: '6px',
                              border: '1px solid #bbf7d0',
                              background: '#f0fdf4',
                              color: '#15803d',
                              fontWeight: 800,
                              fontSize: '11px',
                              cursor: 'pointer'
                            }}
                            title="Increase price by ₹50"
                          >
                            +₹50
                          </button>

                          {/* Save Price Button */}
                          <button
                            onClick={() => handleSaveItemPrice(item.itemId, item.price)}
                            disabled={isSavingThis}
                            style={{
                              padding: '5px 9px',
                              borderRadius: '6px',
                              border: isSavedThis ? '1px solid #16a34a' : '1px solid #cbd5e1',
                              background: isSavedThis ? '#16a34a' : '#f8fafc',
                              color: isSavedThis ? '#ffffff' : '#334155',
                              fontWeight: 700,
                              fontSize: '11px',
                              cursor: 'pointer',
                              display: 'flex',
                              alignItems: 'center',
                              gap: '3px'
                            }}
                            title="Save updated rate to backend"
                          >
                            {isSavingThis ? (
                              <RefreshCw size={12} className="spin" />
                            ) : isSavedThis ? (
                              <>✓ Saved</>
                            ) : (
                              <>Save</>
                            )}
                          </button>
                        </div>

                        {/* Edit / Delete Buttons */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                          <button
                            onClick={() => handleOpenEditDish(item)}
                            style={{
                              background: 'transparent',
                              border: 'none',
                              color: '#3b82f6',
                              cursor: 'pointer',
                              padding: '4px'
                            }}
                            title="Edit dish details"
                          >
                            <Edit size={14} />
                          </button>
                          <button
                            onClick={() => handleDeleteMenuItem(item.itemId, item.name)}
                            style={{
                              background: 'transparent',
                              border: 'none',
                              color: '#ef4444',
                              cursor: 'pointer',
                              padding: '4px'
                            }}
                            title="Delete dish"
                          >
                            <Trash2 size={14} />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* BULK RATE PREVIEW MODAL (Picture 2 Preview & Safety Guardrail)         */}
      {/* ===================================================================== */}
      {isBulkPreviewModalOpen && bulkPreviewData && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.85)',
          backdropFilter: 'blur(10px)',
          WebkitBackdropFilter: 'blur(10px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1300,
          padding: '20px'
        }}>
          <div style={{
            background: '#0f172a',
            color: '#f8fafc',
            border: '1px solid #334155',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '640px',
            maxHeight: '85vh',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden',
            boxShadow: '0 25px 60px rgba(0,0,0,0.85)'
          }}>
            <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border-color, #1e293b)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '16px', fontWeight: 800 }}>
                  Confirm Bulk Rate Adjustment
                </h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                  {bulkPreviewData.title}
                </div>
              </div>
              <button 
                onClick={() => { setIsBulkPreviewModalOpen(false); setBulkPreviewData(null); }}
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={18} />
              </button>
            </div>

            <div style={{ 
              padding: '14px 20px', 
              background: 'rgba(59, 130, 246, 0.12)', 
              borderBottom: '1px solid rgba(59, 130, 246, 0.25)', 
              fontSize: '12px', 
              color: '#93c5fd',
              lineHeight: 1.5
            }}>
              Review the proposed rates below. Changes will be saved directly to the database and broadcasted in real time to the Customer App and Partner Console:
            </div>

            <div style={{ flex: 1, overflowY: 'auto', padding: '12px 20px' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '12px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-muted)' }}>
                    <th style={{ padding: '8px 6px', fontWeight: 700 }}>DISH NAME</th>
                    <th style={{ padding: '8px 6px', fontWeight: 700 }}>CATEGORY</th>
                    <th style={{ padding: '8px 6px', fontWeight: 700, textAlign: 'right' }}>CURRENT</th>
                    <th style={{ padding: '8px 6px', fontWeight: 700, textAlign: 'right' }}>NEW RATE</th>
                    <th style={{ padding: '8px 6px', fontWeight: 700, textAlign: 'right' }}>CHANGE</th>
                  </tr>
                </thead>
                <tbody>
                  {bulkPreviewData.items.map((it: any) => (
                    <tr key={it.itemId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '8px 6px', fontWeight: 700 }}>{it.name}</td>
                      <td style={{ padding: '8px 6px', color: 'var(--text-muted)' }}>{it.category}</td>
                      <td style={{ padding: '8px 6px', textAlign: 'right' }}>₹{it.currentPrice}</td>
                      <td style={{ padding: '8px 6px', textAlign: 'right', fontWeight: 800, color: '#16a34a' }}>₹{it.newPrice}</td>
                      <td style={{ padding: '8px 6px', textAlign: 'right', fontWeight: 700, color: it.change >= 0 ? '#16a34a' : '#dc2626' }}>
                        {it.change >= 0 ? `+₹${it.change}` : `-₹${Math.abs(it.change)}`}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            <div style={{ padding: '16px 20px', borderTop: '1px solid var(--border-color)', display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => { setIsBulkPreviewModalOpen(false); setBulkPreviewData(null); }}
                style={{
                  padding: '8px 16px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmBulkAdjust}
                disabled={bulkPreviewLoading}
                style={{
                  padding: '8px 20px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#16a34a',
                  color: '#fff',
                  fontWeight: 700,
                  cursor: 'pointer'
                }}
              >
                {bulkPreviewLoading ? 'Saving...' : `Confirm & Apply Changes (${bulkPreviewData.affectedCount} items)`}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Floating Red Error Banner (Picture 2 reference / Section 11 Fix) */}
      {priceUpdateError && (
        <div style={{
          position: 'fixed',
          bottom: '24px',
          right: '24px',
          background: '#dc2626',
          color: '#ffffff',
          padding: '12px 20px',
          borderRadius: '10px',
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
          boxShadow: '0 8px 24px rgba(220, 38, 38, 0.4)',
          zIndex: 9999,
          fontSize: '13px',
          fontWeight: 700
        }}>
          <AlertTriangle size={18} />
          <span>{priceUpdateError}</span>
          <button 
            onClick={() => setPriceUpdateError('')} 
            style={{ background: 'transparent', border: 'none', color: '#fff', cursor: 'pointer', marginLeft: '8px' }}
          >
            <X size={14} />
          </button>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 3: ADD / EDIT DISH                                              */}
      {/* ===================================================================== */}
      {isDishModalOpen && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.8)',
          backdropFilter: 'blur(8px)',
          WebkitBackdropFilter: 'blur(8px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1200,
          padding: '20px'
        }}>
          <div style={{
            background: '#0f172a',
            color: '#f8fafc',
            border: '1px solid #334155',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '520px',
            maxHeight: '90vh',
            overflowY: 'auto',
            padding: '24px',
            boxShadow: '0 25px 60px rgba(0,0,0,0.8)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <h3 style={{ margin: 0, fontSize: '17px', fontWeight: 800 }}>
                {isEditingDish ? 'Edit Dish Details' : 'Add New Dish to Menu'}
              </h3>
              <button 
                onClick={() => setIsDishModalOpen(false)} 
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveDish}>
              <div style={{ marginBottom: '14px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                  Dish Name *
                </label>
                <input
                  type="text"
                  required
                  value={dishFormData.name}
                  onChange={e => setDishFormData({ ...dishFormData, name: e.target.value })}
                  placeholder="e.g. Guntur Spicy Idli (4 pcs)"
                  style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '12px', marginBottom: '14px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Category *
                  </label>
                  <input
                    type="text"
                    required
                    value={dishFormData.category}
                    onChange={e => setDishFormData({ ...dishFormData, category: e.target.value })}
                    placeholder="e.g. South Indian"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Base Price (₹) *
                  </label>
                  <input
                    type="number"
                    required
                    min="0"
                    value={dishFormData.price}
                    onChange={e => setDishFormData({ ...dishFormData, price: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Discount Price (₹)
                  </label>
                  <input
                    type="number"
                    min="0"
                    placeholder="Optional"
                    value={dishFormData.discountPrice || ''}
                    onChange={e => setDishFormData({ ...dishFormData, discountPrice: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
              </div>

              <div style={{ marginBottom: '14px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                  Description
                </label>
                <textarea
                  rows={2}
                  value={dishFormData.description}
                  onChange={e => setDishFormData({ ...dishFormData, description: e.target.value })}
                  placeholder="Describe ingredients, portion size, spice level..."
                  style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                />
              </div>

              {/* Photo Upload & Preview */}
              <div style={{ marginBottom: '16px', padding: '12px', border: '1px dashed var(--border-color)', borderRadius: '10px' }}>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                  Dish Photo
                </label>
                <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
                  <img
                    src={dishFormData.imageUrl || 'https://images.unsplash.com/photo-1589301760014-d929f3979dbc?w=800&auto=format&fit=crop&q=80'}
                    alt="Preview"
                    style={{ width: '60px', height: '60px', borderRadius: '8px', objectFit: 'cover' }}
                  />
                  <div style={{ flex: 1 }}>
                    <input
                      type="file"
                      accept="image/*"
                      onChange={e => handleImageFileChange(e, 'dish')}
                      style={{ fontSize: '11px', marginBottom: '4px' }}
                    />
                    <input
                      type="text"
                      placeholder="Or enter image URL"
                      value={dishFormData.imageUrl}
                      onChange={e => setDishFormData({ ...dishFormData, imageUrl: e.target.value })}
                      style={{ width: '100%', padding: '6px 8px', borderRadius: '6px', border: '1px solid var(--border-color)', fontSize: '11px', background: 'transparent', color: 'var(--text-main)' }}
                    />
                  </div>
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', marginBottom: '14px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Prep Time (e.g. 20 mins)
                  </label>
                  <input
                    type="text"
                    value={dishFormData.prepTime || '20 mins'}
                    onChange={e => setDishFormData({ ...dishFormData, prepTime: e.target.value })}
                    placeholder="20 mins"
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '4px' }}>
                    Stock Status
                  </label>
                  <select
                    value={dishFormData.isAvailable ? 'true' : 'false'}
                    onChange={e => setDishFormData({ ...dishFormData, isAvailable: e.target.value === 'true' })}
                    style={{ width: '100%', padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--card-bg)', color: 'var(--text-main)', fontSize: '13px' }}
                  >
                    <option value="true">In Stock (Available)</option>
                    <option value="false">Out of Stock</option>
                  </select>
                </div>
              </div>

              <div style={{ display: 'flex', gap: '20px', flexWrap: 'wrap', marginBottom: '20px' }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={dishFormData.isVeg}
                    onChange={e => setDishFormData({ ...dishFormData, isVeg: e.target.checked })}
                  />
                  <strong>Vegetarian (🟢)</strong>
                </label>
                <label style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={Boolean(dishFormData.isBestseller)}
                    onChange={e => setDishFormData({ ...dishFormData, isBestseller: e.target.checked })}
                  />
                  <strong>Mark as Bestseller (★)</strong>
                </label>
                <label style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', cursor: 'pointer' }}>
                  <input
                    type="checkbox"
                    checked={Boolean(dishFormData.isRecommended)}
                    onChange={e => setDishFormData({ ...dishFormData, isRecommended: e.target.checked })}
                  />
                  <strong>Recommended</strong>
                </label>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                <button
                  type="button"
                  onClick={() => setIsDishModalOpen(false)}
                  style={{
                    padding: '8px 16px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'transparent',
                    fontWeight: 600,
                    cursor: 'pointer'
                  }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  style={{
                    padding: '8px 20px',
                    borderRadius: '8px',
                    border: 'none',
                    background: '#ea580c',
                    color: '#fff',
                    fontWeight: 700,
                    cursor: 'pointer'
                  }}
                >
                  {isEditingDish ? 'Save Dish' : 'Add Dish'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 4: RESTAURANT SPECIFIC ORDERS                                   */}
      {/* ===================================================================== */}
      {isRestOrdersModalOpen && activeRestaurantForOrders && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.6)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1000,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '780px',
            maxHeight: '90vh',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden'
          }}>
            <div style={{ padding: '18px 24px', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>
                  Orders at {activeRestaurantForOrders.name}
                </h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Total {restaurantOrders.length} bookings recorded.
                </div>
              </div>
              <button 
                onClick={() => setIsRestOrdersModalOpen(false)} 
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            <div style={{ flex: 1, overflowY: 'auto', padding: '16px 24px' }}>
              {loadingRestOrders ? (
                <div style={{ padding: '30px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  Loading orders...
                </div>
              ) : restaurantOrders.length === 0 ? (
                <div style={{ padding: '30px', textAlign: 'center', color: 'var(--text-muted)' }}>
                  No customer orders placed for this restaurant yet.
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {restaurantOrders.map(o => (
                    <div 
                      key={o.orderId}
                      style={{ 
                        padding: '12px 16px', 
                        border: '1px solid var(--border-color)', 
                        borderRadius: '10px',
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        gap: '12px'
                      }}
                    >
                      <div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                          <span style={{ fontWeight: 800, fontFamily: 'monospace', color: '#ea580c' }}>{o.orderId}</span>
                          {getOrderStatusBadge(o.orderStatus)}
                          <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            {new Date(o.createdAt).toLocaleString()}
                          </span>
                          {(o.customerOtp || o.deliveryOtp) && (
                            <span style={{ fontSize: '10.5px', fontFamily: 'monospace', fontWeight: 800, background: 'rgba(37,99,235,0.12)', color: '#38bdf8', padding: '1px 6px', borderRadius: '4px', border: '1px solid rgba(59,130,246,0.3)' }}>
                              Cust OTP: {o.customerOtp || o.deliveryOtp}
                            </span>
                          )}
                          {o.restaurantOtp && (
                            <span style={{ fontSize: '10.5px', fontFamily: 'monospace', fontWeight: 800, background: 'rgba(217,119,6,0.12)', color: '#fbbf24', padding: '1px 6px', borderRadius: '4px', border: '1px solid rgba(245,158,11,0.3)' }}>
                              Rest OTP: {o.restaurantOtp}
                            </span>
                          )}
                        </div>
                        <div style={{ fontSize: '12px', marginTop: '4px' }}>
                          <strong>{o.customerName}</strong> ({o.customerPhone}) • {(o.items || []).map((i: any) => `${i.quantity}x ${i.name}`).join(', ')}
                        </div>
                      </div>
                      <div style={{ textAlign: 'right' }}>
                        <div style={{ fontSize: '15px', fontWeight: 800, color: 'var(--text-main)' }}>₹{o.totalAmount}</div>
                        <button
                          onClick={() => {
                            setIsRestOrdersModalOpen(false);
                            setSelectedOrder(o);
                          }}
                          style={{
                            marginTop: '4px',
                            background: '#ffedd5',
                            border: '1px solid #fed7aa',
                            color: '#c2410c',
                            padding: '4px 8px',
                            borderRadius: '6px',
                            fontSize: '11px',
                            fontWeight: 700,
                            cursor: 'pointer'
                          }}
                        >
                          View Details
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 5: ORDER DETAILS MODAL                                          */}
      {/* ===================================================================== */}
      {selectedOrder && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.8)',
          backdropFilter: 'blur(8px)',
          WebkitBackdropFilter: 'blur(8px)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1200,
          padding: '20px'
        }}>
          <div style={{
            background: '#0f172a',
            color: '#f8fafc',
            border: '1px solid #334155',
            borderRadius: '16px',
            boxShadow: '0 25px 60px rgba(0,0,0,0.8)',
            width: '100%',
            maxWidth: '560px',
            maxHeight: '90vh',
            overflowY: 'auto',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Order #{selectedOrder.orderId}</h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Placed on {new Date(selectedOrder.placedAt || selectedOrder.createdAt).toLocaleString()}
                </div>
              </div>
              <button 
                onClick={() => setSelectedOrder(null)} 
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            <div style={{ marginBottom: '14px', padding: '12px', background: 'rgba(0,0,0,0.03)', borderRadius: '8px' }}>
              <div style={{ fontWeight: 700, fontSize: '13px', color: '#ea580c' }}>RESTAURANT: {selectedOrder.restaurantName}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>📍 Pickup from: {selectedOrder.restaurantAddress}</div>
              {selectedOrder.restaurantLatLng && selectedOrder.restaurantLatLng.lat && selectedOrder.restaurantLatLng.lng && (
                <div style={{ fontSize: '11px', color: '#ea580c', marginTop: '3px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <span>GPS: {Number(selectedOrder.restaurantLatLng.lat).toFixed(4)}, {Number(selectedOrder.restaurantLatLng.lng).toFixed(4)}</span>
                  <a
                    href={`https://www.google.com/maps/dir/?api=1&destination=${selectedOrder.restaurantLatLng.lat},${selectedOrder.restaurantLatLng.lng}`}
                    target="_blank"
                    rel="noreferrer"
                    style={{ color: '#2563eb', textDecoration: 'underline', fontWeight: 600 }}
                  >
                    ↗ Open Restaurant Location Map
                  </a>
                </div>
              )}
              {selectedOrder.restaurantLocationDetails && (
                <div style={{ fontSize: '11px', color: '#16a34a', marginTop: '4px' }}>Entrance / Pickup: {selectedOrder.restaurantLocationDetails}</div>
              )}
            </div>

            <div style={{ marginBottom: '14px', padding: '12px', background: 'rgba(0,0,0,0.03)', borderRadius: '8px' }}>
              <div style={{ fontWeight: 700, fontSize: '13px' }}>CUSTOMER: {selectedOrder.customerName} ({selectedOrder.customerPhone})</div>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>📍 Delivery to: {selectedOrder.deliveryAddress}</div>
              {selectedOrder.deliveryLatLng && selectedOrder.deliveryLatLng.lat && selectedOrder.deliveryLatLng.lng && (
                <div style={{ fontSize: '11px', color: '#2563eb', marginTop: '3px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <span>GPS: {Number(selectedOrder.deliveryLatLng.lat).toFixed(4)}, {Number(selectedOrder.deliveryLatLng.lng).toFixed(4)}</span>
                  <a
                    href={`https://www.google.com/maps/dir/?api=1&destination=${selectedOrder.deliveryLatLng.lat},${selectedOrder.deliveryLatLng.lng}`}
                    target="_blank"
                    rel="noreferrer"
                    style={{ color: '#ea580c', textDecoration: 'underline', fontWeight: 600 }}
                  >
                    ↗ Open Google Maps Navigation
                  </a>
                </div>
              )}
              {selectedOrder.deliveryInstructions && (
                <div style={{ fontSize: '11px', color: '#ea580c', marginTop: '4px' }}>Note: {selectedOrder.deliveryInstructions}</div>
              )}
            </div>

            {/* Handover & Delivery Verification OTPs */}
            <div style={{ marginBottom: '16px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' }}>
              {/* Customer OTP Card */}
              <div style={{
                background: 'rgba(37, 99, 235, 0.08)',
                border: '1px solid rgba(59, 130, 246, 0.3)',
                borderRadius: '10px',
                padding: '12px 14px'
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                  <div style={{ fontSize: '11px', fontWeight: 700, color: '#93c5fd', display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <ShieldCheck size={14} color="#38bdf8" /> CUSTOMER OTP
                  </div>
                  <span style={{
                    fontSize: '10px',
                    fontWeight: 700,
                    padding: '2px 6px',
                    borderRadius: '4px',
                    background: (selectedOrder.customerOtpVerified || selectedOrder.orderStatus === 'delivered') ? '#052e16' : '#2e1065',
                    color: (selectedOrder.customerOtpVerified || selectedOrder.orderStatus === 'delivered') ? '#4ade80' : '#c084fc',
                    border: `1px solid ${(selectedOrder.customerOtpVerified || selectedOrder.orderStatus === 'delivered') ? '#166534' : '#6b21a8'}`
                  }}>
                    {(selectedOrder.customerOtpVerified || selectedOrder.orderStatus === 'delivered') ? '✓ Verified' : 'Pending Delivery'}
                  </span>
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: '20px', fontWeight: 900, fontFamily: 'monospace', letterSpacing: '2px', color: '#38bdf8' }}>
                    {selectedOrder.customerOtp || selectedOrder.deliveryOtp || '—'}
                  </span>
                  {(selectedOrder.customerOtp || selectedOrder.deliveryOtp) && (
                    <button
                      type="button"
                      onClick={() => copyToClipboard(selectedOrder.customerOtp || selectedOrder.deliveryOtp, 'modal_cust')}
                      style={{
                        background: 'transparent',
                        border: '1px solid rgba(56, 189, 248, 0.3)',
                        borderRadius: '4px',
                        padding: '3px 8px',
                        color: copiedKey === 'modal_cust' ? '#22c55e' : '#38bdf8',
                        cursor: 'pointer',
                        fontSize: '11px',
                        fontWeight: 700,
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px'
                      }}
                    >
                      {copiedKey === 'modal_cust' ? <Check size={12} /> : <Copy size={12} />}
                      {copiedKey === 'modal_cust' ? 'Copied' : 'Copy'}
                    </button>
                  )}
                </div>
                <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginTop: '4px' }}>
                  Shared by customer with delivery pilot at doorstep
                </div>
              </div>

              {/* Restaurant OTP Card */}
              <div style={{
                background: 'rgba(217, 119, 6, 0.08)',
                border: '1px solid rgba(245, 158, 11, 0.3)',
                borderRadius: '10px',
                padding: '12px 14px'
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '6px' }}>
                  <div style={{ fontSize: '11px', fontWeight: 700, color: '#fde68a', display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <Store size={14} color="#fbbf24" /> RESTAURANT OTP
                  </div>
                  <span style={{
                    fontSize: '10px',
                    fontWeight: 700,
                    padding: '2px 6px',
                    borderRadius: '4px',
                    background: (selectedOrder.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(selectedOrder.orderStatus)) ? '#052e16' : '#451a03',
                    color: (selectedOrder.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(selectedOrder.orderStatus)) ? '#4ade80' : '#fbbf24',
                    border: `1px solid ${(selectedOrder.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(selectedOrder.orderStatus)) ? '#166534' : '#92400e'}`
                  }}>
                    {(selectedOrder.restaurantOtpVerified || ['picked_up', 'out_for_delivery', 'delivered'].includes(selectedOrder.orderStatus)) ? '✓ Verified' : 'Pending Pickup'}
                  </span>
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                  <span style={{ fontSize: '20px', fontWeight: 900, fontFamily: 'monospace', letterSpacing: '2px', color: '#fbbf24' }}>
                    {selectedOrder.restaurantOtp || '—'}
                  </span>
                  {selectedOrder.restaurantOtp && (
                    <button
                      type="button"
                      onClick={() => copyToClipboard(selectedOrder.restaurantOtp, 'modal_rest')}
                      style={{
                        background: 'transparent',
                        border: '1px solid rgba(251, 191, 36, 0.3)',
                        borderRadius: '4px',
                        padding: '3px 8px',
                        color: copiedKey === 'modal_rest' ? '#22c55e' : '#fbbf24',
                        cursor: 'pointer',
                        fontSize: '11px',
                        fontWeight: 700,
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px'
                      }}
                    >
                      {copiedKey === 'modal_rest' ? <Check size={12} /> : <Copy size={12} />}
                      {copiedKey === 'modal_rest' ? 'Copied' : 'Copy'}
                    </button>
                  )}
                </div>
                <div style={{ fontSize: '10.5px', color: 'var(--text-muted)', marginTop: '4px' }}>
                  Shared by restaurant kitchen with pilot at pickup
                </div>
              </div>
            </div>

            {/* Items */}
            <div style={{ marginBottom: '16px' }}>
              <div style={{ fontWeight: 700, fontSize: '13px', marginBottom: '8px' }}>ITEMS ORDERED:</div>
              {(selectedOrder.items || []).map((item: any, idx: number) => (
                <div key={idx} style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', padding: '6px 0', borderBottom: '1px dashed var(--border-color)' }}>
                  <div>
                    <span>{item.isVeg ? '🟢' : '🔴'} </span>
                    <strong>{item.quantity}x</strong> {item.name}
                  </div>
                  <div>₹{item.price * item.quantity}</div>
                </div>
              ))}
            </div>

            {/* Bill Details Breakdown Card */}
            <div style={{
              marginBottom: '16px',
              background: 'rgba(234, 88, 12, 0.04)',
              border: '1.5px solid rgba(234, 88, 12, 0.25)',
              borderRadius: '12px',
              padding: '14px'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                <span style={{ fontWeight: 800, fontSize: '13px', color: '#ea580c' }}>BILL DETAILS & FINANCIAL SNAPSHOT</span>
                <span style={{
                  fontSize: '11px',
                  fontWeight: 800,
                  padding: '2px 8px',
                  borderRadius: '6px',
                  background: selectedOrder.paymentStatus === 'paid' ? '#dcfce7' : '#fef3c7',
                  color: selectedOrder.paymentStatus === 'paid' ? '#15803d' : '#b45309',
                  border: `1px solid ${selectedOrder.paymentStatus === 'paid' ? '#86efac' : '#fde68a'}`
                }}>
                  {selectedOrder.paymentMethod?.toUpperCase()} • {selectedOrder.paymentStatus?.toUpperCase()}
                </span>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', fontSize: '12.5px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Item Subtotal</span>
                  <span style={{ fontWeight: 600 }}>₹{selectedOrder.subtotal || 0}</span>
                </div>
                {selectedOrder.packagingFee !== undefined && selectedOrder.packagingFee > 0 && (
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ color: 'var(--text-muted)' }}>Restaurant Packaging Charges</span>
                    <span style={{ fontWeight: 600 }}>₹{selectedOrder.packagingFee}</span>
                  </div>
                )}
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Delivery Partner Fee</span>
                  <span style={{ fontWeight: 600 }}>
                    {selectedOrder.isPlatinumDelivery || selectedOrder.fundingSource === 'staydriv_platform' ? (
                      <>
                        <span style={{ textDecoration: 'line-through', color: 'var(--text-muted)', marginRight: '6px' }}>
                          ₹{selectedOrder.originalDeliveryFee || ((selectedOrder.deliveryFee || 0) + (selectedOrder.deliveryDiscount || 0))}
                        </span>
                        <span style={{ color: '#16a34a', fontWeight: 800 }}>₹0 (Platinum Free)</span>
                      </>
                    ) : selectedOrder.deliveryDiscount > 0 ? (
                      <>
                        <span style={{ textDecoration: 'line-through', color: 'var(--text-muted)', marginRight: '6px' }}>
                          ₹{(selectedOrder.deliveryFee || 0) + (selectedOrder.deliveryDiscount || 0)}
                        </span>
                        <span style={{ color: '#16a34a', fontWeight: 700 }}>FREE</span>
                      </>
                    ) : (
                      `₹${selectedOrder.deliveryFee || 0}`
                    )}
                  </span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>Platform Convenience Fee</span>
                  <span style={{ fontWeight: 600 }}>₹{selectedOrder.platformFee || 0}</span>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: 'var(--text-muted)' }}>GST & Restaurant Taxes</span>
                  <span style={{ fontWeight: 600 }}>₹{selectedOrder.taxes || 0}</span>
                </div>

                {selectedOrder.couponDiscount > 0 && (
                  <div style={{ display: 'flex', justifyContent: 'space-between', color: '#2563eb' }}>
                    <span style={{ fontWeight: 600 }}>Coupon ({selectedOrder.couponCode || 'APPLIED'})</span>
                    <span style={{ fontWeight: 700 }}>-₹{selectedOrder.couponDiscount}</span>
                  </div>
                )}

                {selectedOrder.membershipDiscount > 0 && (
                  <div style={{ display: 'flex', justifyContent: 'space-between', color: '#16a34a' }}>
                    <span style={{ fontWeight: 600 }}>StayDriv Platinum Food Pass</span>
                    <span style={{ fontWeight: 700 }}>-₹{selectedOrder.membershipDiscount}</span>
                  </div>
                )}

                {selectedOrder.cashRoundOff !== undefined && selectedOrder.cashRoundOff !== 0 && (
                  <div style={{ display: 'flex', justifyContent: 'space-between', color: 'var(--text-muted)' }}>
                    <span>Cash Round Off (COD)</span>
                    <span style={{ fontWeight: 600 }}>
                      {selectedOrder.cashRoundOff > 0 ? `+₹${selectedOrder.cashRoundOff}` : `-₹${Math.abs(selectedOrder.cashRoundOff)}`}
                    </span>
                  </div>
                )}

                <div style={{ height: '1px', background: 'var(--border-color)', margin: '4px 0' }} />

                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '14px', fontWeight: 800 }}>
                  <span>Final Payable (To Pay)</span>
                  <span style={{ color: '#ea580c', fontSize: '16px' }}>₹{selectedOrder.finalPayable || selectedOrder.totalAmount || 0}</span>
                </div>

                {selectedOrder.totalSavings > 0 && (
                  <div style={{
                    marginTop: '6px',
                    padding: '6px 10px',
                    borderRadius: '6px',
                    background: 'rgba(37, 99, 235, 0.08)',
                    color: '#2563eb',
                    fontSize: '11.5px',
                    fontWeight: 700,
                    textAlign: 'center'
                  }}>
                    🎉 Customer saved ₹{selectedOrder.totalSavings} on this order!
                  </div>
                )}
              </div>
            </div>

            {/* PLATINUM DELIVERY & STAYDRIV FUNDED SETTLEMENT AUDIT CARD */}
            <div style={{
              marginBottom: '16px',
              background: selectedOrder.isPlatinumDelivery ? 'linear-gradient(135deg, rgba(15, 23, 42, 0.95), rgba(30, 41, 59, 0.95))' : 'rgba(0,0,0,0.03)',
              border: selectedOrder.isPlatinumDelivery ? '1.5px solid #38bdf8' : '1px solid var(--border-color)',
              borderRadius: '12px',
              padding: '14px',
              color: selectedOrder.isPlatinumDelivery ? '#f8fafc' : 'inherit'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                  <Award size={16} color={selectedOrder.isPlatinumDelivery ? '#38bdf8' : '#ea580c'} />
                  <span style={{ fontWeight: 800, fontSize: '12.5px', color: selectedOrder.isPlatinumDelivery ? '#38bdf8' : 'var(--text-main)', letterSpacing: '0.4px' }}>
                    {selectedOrder.isPlatinumDelivery ? 'PLATINUM BENEFIT & PLATFORM SETTLEMENT AUDIT' : 'DELIVERY FARE & PILOT SETTLEMENT'}
                  </span>
                </div>
                <span style={{
                  fontSize: '10px',
                  fontWeight: 800,
                  padding: '2px 8px',
                  borderRadius: '6px',
                  background: selectedOrder.isPlatinumDelivery ? 'rgba(56, 189, 248, 0.2)' : 'rgba(0,0,0,0.06)',
                  color: selectedOrder.isPlatinumDelivery ? '#7dd3fc' : 'var(--text-muted)',
                  border: `1px solid ${selectedOrder.isPlatinumDelivery ? '#38bdf8' : 'var(--border-color)'}`
                }}>
                  {selectedOrder.fundingSource === 'staydriv_platform' || selectedOrder.isPlatinumDelivery ? 'STAYDRIV PLATFORM-FUNDED' : 'CUSTOMER FUNDED'}
                </span>
              </div>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', fontSize: '12px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Customer Membership Verification</span>
                  <strong style={{ color: selectedOrder.isPlatinumDelivery ? '#4ade80' : 'var(--text-main)' }}>
                    {selectedOrder.isPlatinumDelivery ? '✓ Active Platinum Member (Verified)' : 'Standard / Non-Platinum'}
                  </strong>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Delivery Route Distance</span>
                  <span style={{ fontWeight: 600 }}>
                    {selectedOrder.deliveryDistanceKm !== undefined ? `${selectedOrder.deliveryDistanceKm} km` : (selectedOrder.distanceKm ? `${selectedOrder.distanceKm} km` : 'Standard ~2.5 km')}
                  </span>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Pricing Model (Bike Booking Formula)</span>
                  <span style={{ fontFamily: 'monospace', fontSize: '11px', color: selectedOrder.isPlatinumDelivery ? '#cbd5e1' : 'var(--text-muted)' }}>
                    ₹20 base + ₹10/km
                  </span>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Calculated Delivery Fare</span>
                  <span style={{ fontWeight: 600 }}>
                    ₹{selectedOrder.originalDeliveryFee || ((selectedOrder.deliveryFee || 0) + (selectedOrder.deliveryDiscount || 0))}
                  </span>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Customer Delivery Charge</span>
                  <span style={{ fontWeight: 700, color: selectedOrder.isPlatinumDelivery ? '#4ade80' : 'inherit' }}>
                    {selectedOrder.isPlatinumDelivery ? '₹0 (100% Free Delivery)' : `₹${selectedOrder.customerDeliveryFee || selectedOrder.deliveryFee || 0}`}
                  </span>
                </div>

                {selectedOrder.isPlatinumDelivery && (
                  <div style={{ display: 'flex', justifyContent: 'space-between', color: '#38bdf8' }}>
                    <span style={{ fontWeight: 600 }}>Platinum Delivery Discount</span>
                    <span style={{ fontWeight: 700 }}>
                      -₹{selectedOrder.staydrivFundedDeliveryAmount || selectedOrder.originalDeliveryFee || selectedOrder.deliveryFee}
                    </span>
                  </div>
                )}

                <div style={{ height: '1px', background: selectedOrder.isPlatinumDelivery ? 'rgba(255,255,255,0.1)' : 'var(--border-color)', margin: '4px 0' }} />

                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>StayDriv Platform-Funded Expense</span>
                  <span style={{ fontWeight: 700, color: selectedOrder.isPlatinumDelivery ? '#f59e0b' : 'var(--text-muted)' }}>
                    ₹{selectedOrder.staydrivFundedDeliveryAmount || (selectedOrder.isPlatinumDelivery ? (selectedOrder.originalDeliveryFee || selectedOrder.deliveryFee) : 0)}
                  </span>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div>
                    <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Pilot Delivery Earnings (Protected)</span>
                    <div style={{ fontSize: '10px', color: '#4ade80' }}>*Pilot never bears the loss for Platinum discounts</div>
                  </div>
                  <span style={{ fontWeight: 900, color: '#22c55e', fontSize: '14px' }}>
                    ₹{selectedOrder.pilotEarnings || selectedOrder.pilotDeliveryFee || selectedOrder.originalDeliveryFee || selectedOrder.deliveryFee || 0}
                  </span>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: '2px' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Pilot Wallet Settlement Status</span>
                  <span style={{
                    fontWeight: 700,
                    fontSize: '11px',
                    color: selectedOrder.orderStatus === 'delivered' ? '#4ade80' : '#fbbf24'
                  }}>
                    {selectedOrder.orderStatus === 'delivered' ? '✓ Credited to Pilot Available Wallet Balance' : 'Pending Delivery OTP Handover'}
                  </span>
                </div>

                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span style={{ color: selectedOrder.isPlatinumDelivery ? '#94a3b8' : 'var(--text-muted)' }}>Financial Ledger Entry</span>
                  <span style={{ fontFamily: 'monospace', fontSize: '10.5px', color: selectedOrder.isPlatinumDelivery ? '#7dd3fc' : 'var(--text-muted)' }}>
                    {selectedOrder.isPlatinumDelivery ? 'PLATFORM_FUNDED_DELIVERY_EXPENSE' : 'CUSTOMER_FOOD_DELIVERY_COLLECTIONS'}
                  </span>
                </div>
              </div>
            </div>

            {/* Return Order Details Card (when delivery failed or returning to kitchen) */}
            {(selectedOrder.isReturnActive || selectedOrder.orderStatus.includes('return') || selectedOrder.orderStatus === 'delivery_failed_reported' || selectedOrder.returnReason) && (
              <div style={{
                marginBottom: '16px',
                background: 'rgba(239, 68, 68, 0.08)',
                border: '1.5px solid rgba(239, 68, 68, 0.35)',
                borderRadius: '10px',
                padding: '14px'
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: '#f87171', fontWeight: 800, fontSize: '13px' }}>
                    <AlertTriangle size={16} /> RETURN / FAILED DELIVERY AUDIT
                  </div>
                  <span style={{
                    fontSize: '11px',
                    fontWeight: 700,
                    padding: '2px 8px',
                    borderRadius: '6px',
                    background: selectedOrder.orderStatus === 'returned_to_restaurant' ? '#052e16' : '#450a0a',
                    color: selectedOrder.orderStatus === 'returned_to_restaurant' ? '#4ade80' : '#fca5a5',
                    border: `1px solid ${selectedOrder.orderStatus === 'returned_to_restaurant' ? '#166534' : '#991b1b'}`
                  }}>
                    {selectedOrder.orderStatus === 'returned_to_restaurant' ? '✓ Handover Completed' : 'Return In Transit'}
                  </span>
                </div>

                <div style={{ fontSize: '12px', color: '#fca5a5', marginBottom: '4px' }}>
                  <strong>Failure Reason:</strong> {selectedOrder.returnReason || 'Delivery partner reported delivery failed'}
                </div>
                {selectedOrder.returnNotes && (
                  <div style={{ fontSize: '11.5px', color: 'var(--text-muted)', marginBottom: '8px' }}>
                    <strong>Pilot Notes:</strong> {selectedOrder.returnNotes}
                  </div>
                )}
                {selectedOrder.deliveryPartnerName && (
                  <div style={{ fontSize: '11.5px', color: '#93c5fd', marginBottom: '8px' }}>
                    <strong>Returning Pilot:</strong> {selectedOrder.deliveryPartnerName} ({selectedOrder.deliveryPartnerPhone})
                  </div>
                )}

                {/* Return OTP */}
                {selectedOrder.returnOtp && (
                  <div style={{
                    marginTop: '8px',
                    padding: '10px 12px',
                    background: 'rgba(16, 185, 129, 0.1)',
                    border: '1px solid rgba(16, 185, 129, 0.3)',
                    borderRadius: '8px',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between'
                  }}>
                    <div>
                      <div style={{ fontSize: '10.5px', fontWeight: 800, color: '#34d399' }}>RETURN VERIFICATION OTP</div>
                      <div style={{ fontSize: '18px', fontWeight: 900, fontFamily: 'monospace', letterSpacing: '2px', color: '#6ee7b7' }}>
                        {selectedOrder.returnOtp}
                      </div>
                    </div>
                    <button
                      type="button"
                      onClick={() => copyToClipboard(selectedOrder.returnOtp, 'modal_ret_otp')}
                      style={{
                        background: 'transparent',
                        border: '1px solid rgba(52, 211, 153, 0.4)',
                        borderRadius: '6px',
                        padding: '4px 10px',
                        color: copiedKey === 'modal_ret_otp' ? '#22c55e' : '#34d399',
                        cursor: 'pointer',
                        fontSize: '11.5px',
                        fontWeight: 700,
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px'
                      }}
                    >
                      {copiedKey === 'modal_ret_otp' ? <Check size={12} /> : <Copy size={12} />}
                      {copiedKey === 'modal_ret_otp' ? 'Copied' : 'Copy Return OTP'}
                    </button>
                  </div>
                )}

                {/* Return Handover Verification Status & Timestamp */}
                <div style={{
                  marginTop: '10px',
                  padding: '8px 10px',
                  background: 'rgba(0,0,0,0.2)',
                  borderRadius: '6px',
                  fontSize: '11.5px',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center'
                }}>
                  <span>Return OTP Verification:</span>
                  <span style={{
                    fontWeight: 700,
                    color: selectedOrder.returnOtpVerified ? '#4ade80' : '#fbbf24'
                  }}>
                    {selectedOrder.returnOtpVerified ? '✓ Verified by Kitchen' : 'Pending Kitchen Handover'}
                  </span>
                </div>
                {selectedOrder.returnedAt && (
                  <div style={{ marginTop: '4px', fontSize: '11px', color: '#94a3b8' }}>
                    Returned to kitchen on: {new Date(selectedOrder.returnedAt).toLocaleString()}
                  </div>
                )}
              </div>
            )}

            {/* Order Call Initiation History Audit */}
            {selectedOrder.callHistory && selectedOrder.callHistory.length > 0 && (
              <div style={{
                marginBottom: '16px',
                background: 'rgba(59, 130, 246, 0.06)',
                border: '1px solid rgba(59, 130, 246, 0.3)',
                borderRadius: '10px',
                padding: '12px 14px'
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '6px', color: '#60a5fa', fontWeight: 800, fontSize: '13px', marginBottom: '8px' }}>
                  <Phone size={15} /> ORDER CALL INITIATION LOG ({selectedOrder.callHistory.length})
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                  {selectedOrder.callHistory.map((call: any, cIdx: number) => (
                    <div key={cIdx} style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      fontSize: '11.5px',
                      padding: '6px 10px',
                      background: 'rgba(0,0,0,0.25)',
                      borderRadius: '6px',
                      border: '1px solid rgba(255,255,255,0.06)'
                    }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <span style={{
                          padding: '2px 6px',
                          borderRadius: '4px',
                          fontSize: '10px',
                          fontWeight: 800,
                          textTransform: 'uppercase',
                          background: call.callerRole === 'customer' ? '#1e3a8a' : (call.callerRole === 'pilot' ? '#064e3b' : '#7c2d12'),
                          color: call.callerRole === 'customer' ? '#93c5fd' : (call.callerRole === 'pilot' ? '#6ee7b7' : '#fed7aa')
                        }}>
                          {call.callerRole}
                        </span>
                        <span>➔ called <strong>{call.targetRole}</strong> ({call.targetPhone || 'Device Dialer'})</span>
                      </div>
                      <span style={{ color: '#94a3b8', fontSize: '10.5px' }}>
                        {new Date(call.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Price breakdown */}
            <div style={{ fontSize: '12px', borderTop: '1px solid var(--border-color)', paddingTop: '10px', marginBottom: '20px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <span>Item Subtotal:</span>
                <span>₹{selectedOrder.subtotal}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <span>Delivery Charge:</span>
                <span>₹{selectedOrder.deliveryFee}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <span>Platform Fee:</span>
                <span>₹{selectedOrder.platformFee}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <span>Taxes & GST:</span>
                <span>₹{selectedOrder.taxes}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 800, fontSize: '14px', marginTop: '6px', borderTop: '1px solid var(--border-color)', paddingTop: '6px' }}>
                <span>Grand Total:</span>
                <span style={{ color: '#ea580c' }}>₹{selectedOrder.totalAmount}</span>
              </div>
            </div>

            {/* Delivery Pilot Assignment Card (Strict Bike & Scooty Only) */}
            <div style={{
              marginBottom: '20px',
              padding: '16px',
              background: 'rgba(16, 185, 129, 0.05)',
              border: '1.5px solid rgba(16, 185, 129, 0.3)',
              borderRadius: '12px'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <div style={{ background: '#dcfce7', padding: '6px', borderRadius: '8px', color: '#16a34a' }}>
                    <Bike size={18} />
                  </div>
                  <div>
                    <h4 style={{ margin: 0, fontSize: '14px', fontWeight: 800, color: 'var(--text-main)' }}>
                      Delivery Pilot Assignment (Bike & Scooty Only)
                    </h4>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                      Restricted to verified 2-wheelers • Auto Rickshaw & Cars strictly excluded
                    </span>
                  </div>
                </div>
                {selectedOrder.deliveryPartnerId ? (
                  <span style={{
                    padding: '3px 8px',
                    borderRadius: '6px',
                    background: '#dcfce7',
                    color: '#166534',
                    border: '1px solid #86efac',
                    fontSize: '11px',
                    fontWeight: 800
                  }}>
                    ✓ PILOT ASSIGNED
                  </span>
                ) : (
                  <span style={{
                    padding: '3px 8px',
                    borderRadius: '6px',
                    background: '#fef3c7',
                    color: '#b45309',
                    border: '1px solid #fde68a',
                    fontSize: '11px',
                    fontWeight: 800
                  }}>
                    ⏳ UNASSIGNED
                  </span>
                )}
              </div>

              {/* Current Assigned Pilot Info */}
              {selectedOrder.deliveryPartnerId ? (
                <div style={{
                  background: 'var(--card-bg)',
                  border: '1px solid var(--border-color)',
                  borderRadius: '8px',
                  padding: '12px',
                  marginBottom: '12px',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center'
                }}>
                  <div>
                    <div style={{ fontWeight: 800, fontSize: '13.5px', color: 'var(--text-main)' }}>
                      {selectedOrder.deliveryPartnerName || 'Assigned Delivery Pilot'}
                    </div>
                    <div style={{ fontSize: '11.5px', color: 'var(--text-muted)', marginTop: '2px' }}>
                      Phone: <strong style={{ color: '#2563eb' }}>{selectedOrder.deliveryPartnerPhone || selectedOrder.deliveryPartnerId}</strong>
                    </div>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: '5px',
                      background: '#dcfce7',
                      color: '#166534',
                      padding: '4px 10px',
                      borderRadius: '6px',
                      fontWeight: 800,
                      fontSize: '11.5px'
                    }}>
                      <Bike size={14} /> {selectedOrder.deliveryPartnerVehicleType || 'Bike'} (Eligible 2-Wheeler)
                    </div>
                  </div>
                </div>
              ) : (
                <div style={{
                  background: 'rgba(245, 158, 11, 0.08)',
                  border: '1px dashed rgba(245, 158, 11, 0.4)',
                  borderRadius: '8px',
                  padding: '10px 14px',
                  marginBottom: '12px',
                  fontSize: '12px',
                  color: '#d97706'
                }}>
                  ℹ️ No delivery pilot is currently assigned to this food order. Assign an eligible Bike or Scooty pilot below:
                </div>
              )}

              {/* Manual Pilot Assignment Controls */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <label style={{ fontSize: '11.5px', fontWeight: 700, color: 'var(--text-main)' }}>
                  {selectedOrder.deliveryPartnerId ? 'Reassign to another Bike/Scooty Pilot:' : 'Select Bike/Scooty Pilot to Assign:'}
                </label>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <select
                    value={selectedPilotToAssign}
                    onChange={e => {
                      setSelectedPilotToAssign(e.target.value);
                      setPilotAssignError('');
                    }}
                    style={{
                      flex: 1,
                      padding: '8px 12px',
                      borderRadius: '8px',
                      border: '1px solid var(--border-color)',
                      background: 'var(--card-bg)',
                      color: 'var(--text-main)',
                      fontSize: '12.5px'
                    }}
                  >
                    <option value="">-- Choose Approved 2-Wheeler Pilot ({eligiblePilots.length} available) --</option>
                    {eligiblePilots.map((p: any) => (
                      <option key={p._id || p.pilotId} value={p._id || p.pilotId}>
                        {p.name} ({p.phoneNumber}) — {p.canonicalVehicle === 'scooty' ? '🛵 Scooty' : '🏍️ Bike'} {p.isOnline ? '🟢 Online' : '⚪ Offline'}
                      </option>
                    ))}
                  </select>
                  <button
                    type="button"
                    onClick={() => handleManualAssignPilot(selectedOrder.orderId)}
                    disabled={assigningPilot || !selectedPilotToAssign}
                    style={{
                      padding: '8px 16px',
                      borderRadius: '8px',
                      border: 'none',
                      background: assigningPilot || !selectedPilotToAssign ? '#64748b' : '#10b981',
                      color: '#ffffff',
                      fontWeight: 700,
                      fontSize: '12.5px',
                      cursor: assigningPilot || !selectedPilotToAssign ? 'not-allowed' : 'pointer',
                      whiteSpace: 'nowrap'
                    }}
                  >
                    {assigningPilot ? 'Assigning...' : 'Assign Pilot'}
                  </button>
                </div>

                {/* Validation Error Message */}
                {pilotAssignError && (
                  <div style={{
                    marginTop: '4px',
                    padding: '8px 12px',
                    background: '#fee2e2',
                    border: '1px solid #fecaca',
                    borderRadius: '6px',
                    color: '#b91c1c',
                    fontSize: '12px',
                    fontWeight: 600,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '6px'
                  }}>
                    <AlertTriangle size={14} />
                    <span>{pilotAssignError}</span>
                  </div>
                )}

                {/* Success Message */}
                {pilotAssignSuccess && (
                  <div style={{
                    marginTop: '4px',
                    padding: '8px 12px',
                    background: '#dcfce7',
                    border: '1px solid #bbf7d0',
                    borderRadius: '6px',
                    color: '#15803d',
                    fontSize: '12px',
                    fontWeight: 600,
                    display: 'flex',
                    alignItems: 'center',
                    gap: '6px'
                  }}>
                    <CheckCircle2 size={14} />
                    <span>{pilotAssignSuccess}</span>
                  </div>
                )}
              </div>
            </div>

            {/* Admin Status Override */}
            <div>
              <div style={{ fontSize: '12px', fontWeight: 700, marginBottom: '8px' }}>OVERRIDE STATUS:</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px' }}>
                {['accepted', 'preparing', 'ready_for_pickup', 'out_for_delivery', 'delivered', 'return_to_restaurant', 'returned_to_restaurant', 'cancelled'].map(st => (
                  <button
                    key={st}
                    onClick={() => handleUpdateOrderStatus(selectedOrder.orderId, st)}
                    style={{
                      padding: '6px 12px',
                      borderRadius: '6px',
                      border: '1px solid var(--border-color)',
                      background: selectedOrder.orderStatus === st ? '#ea580c' : 'var(--card-bg)',
                      color: selectedOrder.orderStatus === st ? '#fff' : 'var(--text-main)',
                      fontSize: '11px',
                      fontWeight: 700,
                      cursor: 'pointer'
                    }}
                  >
                    Mark {st.replace(/_/g, ' ')}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 6: COMPLETE RESTAURANT APPLICATION DETAILS & KYC INSPECTION     */}
      {/* ===================================================================== */}
      {isAppDetailsModalOpen && selectedApp && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.7)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1150,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '880px',
            maxHeight: '92vh',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden'
          }}>
            {/* Header */}
            <div style={{ padding: '20px 24px', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                <img
                  src={selectedApp.imageUrl || 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=800&auto=format&fit=crop&q=80'}
                  alt={selectedApp.name}
                  style={{ width: '48px', height: '48px', borderRadius: '10px', objectFit: 'cover', border: '1px solid var(--border-color)' }}
                />
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>{selectedApp.name}</h3>
                    <span style={{
                      padding: '3px 8px',
                      borderRadius: '12px',
                      fontSize: '11px',
                      fontWeight: 800,
                      background: 
                        selectedApp.status === 'approved' ? '#dcfce7' : 
                        (selectedApp.status === 'pending' ? '#ffedd5' : 
                        (selectedApp.status === 'action_required' ? '#fef3c7' : '#fee2e2')),
                      color: 
                        selectedApp.status === 'approved' ? '#166534' : 
                        (selectedApp.status === 'pending' ? '#c2410c' : 
                        (selectedApp.status === 'action_required' ? '#b45309' : '#b91c1c'))
                    }}>
                      {String(selectedApp.status || 'PENDING').toUpperCase()}
                    </span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                    <span>Partner ID: <strong style={{ fontFamily: 'monospace' }}>{selectedApp.restaurantId}</strong></span>
                    <button
                      onClick={() => copyToClipboard(selectedApp.restaurantId, 'modal_id')}
                      style={{ background: 'transparent', border: 'none', cursor: 'pointer', padding: '1px', color: copiedKey === 'modal_id' ? '#16a34a' : 'var(--text-muted)' }}
                    >
                      {copiedKey === 'modal_id' ? <Check size={12} /> : <Copy size={12} />}
                    </button>
                    <span>• Submitted: {selectedApp.createdAt ? new Date(selectedApp.createdAt).toLocaleDateString() : 'N/A'}</span>
                  </div>
                </div>
              </div>
              <button 
                onClick={() => setIsAppDetailsModalOpen(false)} 
                style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Content Body */}
            <div style={{ flex: 1, overflowY: 'auto', padding: '20px 24px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
              {/* Alert Status Banners */}
              {selectedApp.status === 'action_required' && (
                <div style={{ background: '#fef3c7', border: '1px solid #fde68a', color: '#b45309', padding: '12px 16px', borderRadius: '10px', fontSize: '13px' }}>
                  <strong>⚠️ Correction Requested from Partner:</strong>
                  <div style={{ marginTop: '4px' }}>{selectedApp.actionRequiredNotes || 'Missing required compliance documents.'}</div>
                </div>
              )}
              {selectedApp.status === 'rejected' && (
                <div style={{ background: '#fee2e2', border: '1px solid #fecaca', color: '#b91c1c', padding: '12px 16px', borderRadius: '10px', fontSize: '13px' }}>
                  <strong>🚫 Application Rejected:</strong>
                  <div style={{ marginTop: '4px' }}>{selectedApp.rejectionReason || 'Documents or details failed verification.'}</div>
                </div>
              )}
              {selectedApp.status === 'approved' && (
                <div style={{ background: '#dcfce7', border: '1px solid #bbf7d0', color: '#166534', padding: '12px 16px', borderRadius: '10px', fontSize: '13px' }}>
                  <strong>✓ Application Approved:</strong>
                  <div style={{ marginTop: '4px' }}>Approved by {selectedApp.approvedBy || 'Admin Operations'} on {selectedApp.approvedAt ? new Date(selectedApp.approvedAt).toLocaleString() : 'Record'}.</div>
                </div>
              )}

              {/* Grid 2 Columns */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))', gap: '20px' }}>
                {/* Column 1: Restaurant & Contact Profile */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                  <div style={{ background: 'rgba(0,0,0,0.02)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
                    <div style={{ fontSize: '13px', fontWeight: 800, color: '#ea580c', marginBottom: '12px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Store size={15} /> RESTAURANT & OWNER PROFILE
                    </div>
                    
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', fontSize: '12.5px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Owner Full Name:</span>
                        <strong>{selectedApp.ownerName || 'N/A'}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Registered Phone:</span>
                        <strong style={{ color: '#2563eb' }}>{selectedApp.phone}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Email Address:</span>
                        <strong>{selectedApp.email || 'Not provided'}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Operating Hours:</span>
                        <span>{selectedApp.openingHours || '10:00 AM - 11:00 PM'}</span>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Commission Cut:</span>
                        <strong style={{ color: '#ea580c' }}>{selectedApp.commissionRate || 15}%</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Base Delivery Fee:</span>
                        <span>₹{selectedApp.deliveryFee || 30}</span>
                      </div>
                      <div style={{ marginTop: '4px' }}>
                        <span style={{ color: 'var(--text-muted)', display: 'block', marginBottom: '2px' }}>Restaurant Physical Address:</span>
                        <div style={{ background: 'var(--card-bg)', padding: '8px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', fontSize: '12px', lineHeight: '1.4' }}>
                          <MapPin size={12} style={{ display: 'inline', marginRight: '4px', color: '#ea580c' }} />
                          {selectedApp.address}
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Cuisines & Tags */}
                  <div style={{ background: 'rgba(0,0,0,0.02)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
                    <div style={{ fontSize: '13px', fontWeight: 800, color: 'var(--text-main)', marginBottom: '8px' }}>
                      CUISINES & MENU CATEGORIES
                    </div>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                      {(selectedApp.cuisines || []).map((c: string) => (
                        <span key={c} style={{ fontSize: '11px', background: 'rgba(234, 88, 12, 0.08)', color: '#ea580c', border: '1px solid rgba(234, 88, 12, 0.2)', padding: '3px 8px', borderRadius: '6px', fontWeight: 600 }}>
                          {c}
                        </span>
                      ))}
                    </div>
                  </div>

                  {/* Bank & Settlement Details */}
                  <div style={{ background: 'rgba(0,0,0,0.02)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
                    <div style={{ fontSize: '13px', fontWeight: 800, color: '#16a34a', marginBottom: '10px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <DollarSign size={15} /> SETTLEMENT & BANKING DETAILS
                    </div>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', fontSize: '12px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Bank Account No:</span>
                        <strong style={{ fontFamily: 'monospace' }}>{selectedApp.bankAccount || 'Pending Submission'}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>IFSC Code:</span>
                        <strong style={{ fontFamily: 'monospace' }}>{selectedApp.bankIfsc || 'Pending Submission'}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Account Holder:</span>
                        <strong>{selectedApp.bankHolderName || selectedApp.ownerName || 'N/A'}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Settlement UPI ID:</span>
                        <strong style={{ color: '#2563eb' }}>{selectedApp.upiId || 'Pending'}</strong>
                      </div>
                    </div>
                  </div>
                </div>

                {/* Column 2: Documents & Compliance Verification */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                  {/* FSSAI License */}
                  <div style={{ background: 'rgba(0,0,0,0.02)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                      <div style={{ fontSize: '13px', fontWeight: 800, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <FileText size={15} color="#ea580c" /> FSSAI FOOD LICENSE
                      </div>
                      <span style={{
                        padding: '2px 8px',
                        borderRadius: '10px',
                        fontSize: '10.5px',
                        fontWeight: 700,
                        background: selectedApp.fssaiDocUrl ? '#dcfce7' : '#fee2e2',
                        color: selectedApp.fssaiDocUrl ? '#166534' : '#b91c1c'
                      }}>
                        {selectedApp.fssaiDocUrl ? 'DOCUMENT UPLOADED' : 'MISSING DOCUMENT'}
                      </span>
                    </div>

                    <div style={{ fontSize: '12px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>License Number:</span>
                        <strong style={{ fontFamily: 'monospace' }}>{selectedApp.fssaiNumber || 'Not provided'}</strong>
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>Validity / Expiry:</span>
                        <span>{selectedApp.fssaiValidity ? new Date(selectedApp.fssaiValidity).toLocaleDateString() : 'Not Specified'}</span>
                      </div>
                      {selectedApp.fssaiDocUrl ? (
                        <button
                          onClick={() => setPreviewDoc({ label: `${selectedApp.name} - FSSAI Food License Certificate`, url: selectedApp.fssaiDocUrl })}
                          style={{
                            marginTop: '6px',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            gap: '6px',
                            background: '#f0fdf4',
                            border: '1px solid #bbf7d0',
                            color: '#15803d',
                            padding: '7px 12px',
                            borderRadius: '6px',
                            fontSize: '11.5px',
                            fontWeight: 700,
                            cursor: 'pointer'
                          }}
                        >
                          <ZoomIn size={13} /> Inspect Uploaded FSSAI Certificate
                        </button>
                      ) : (
                        <div style={{ fontSize: '11px', color: '#94a3b8', fontStyle: 'italic', marginTop: '4px' }}>
                          No document file uploaded during registration.
                        </div>
                      )}
                    </div>
                  </div>

                  {/* GST Registration */}
                  <div style={{ background: 'rgba(0,0,0,0.02)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                      <div style={{ fontSize: '13px', fontWeight: 800, color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '6px' }}>
                        <FileText size={15} color="#2563eb" /> GSTIN REGISTRATION
                      </div>
                      <span style={{
                        padding: '2px 8px',
                        borderRadius: '10px',
                        fontSize: '10.5px',
                        fontWeight: 700,
                        background: selectedApp.gstDocUrl ? '#dcfce7' : '#f1f5f9',
                        color: selectedApp.gstDocUrl ? '#166534' : '#64748b'
                      }}>
                        {selectedApp.gstDocUrl ? 'DOCUMENT UPLOADED' : (selectedApp.gstNumber ? 'NUMBER ONLY' : 'OPTIONAL')}
                      </span>
                    </div>

                    <div style={{ fontSize: '12px', display: 'flex', flexDirection: 'column', gap: '6px' }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <span style={{ color: 'var(--text-muted)' }}>GSTIN Number:</span>
                        <strong style={{ fontFamily: 'monospace' }}>{selectedApp.gstNumber || 'Not provided'}</strong>
                      </div>
                      {selectedApp.gstDocUrl && (
                        <button
                          onClick={() => setPreviewDoc({ label: `${selectedApp.name} - GSTIN Certificate`, url: selectedApp.gstDocUrl })}
                          style={{
                            marginTop: '6px',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            gap: '6px',
                            background: '#eff6ff',
                            border: '1px solid #bfdbfe',
                            color: '#1d4ed8',
                            padding: '7px 12px',
                            borderRadius: '6px',
                            fontSize: '11.5px',
                            fontWeight: 700,
                            cursor: 'pointer'
                          }}
                        >
                          <ZoomIn size={13} /> Inspect Uploaded GSTIN Certificate
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Review Audit History */}
                  <div style={{ background: 'rgba(0,0,0,0.02)', border: '1px solid var(--border-color)', borderRadius: '12px', padding: '16px' }}>
                    <div style={{ fontSize: '13px', fontWeight: 800, color: 'var(--text-main)', marginBottom: '8px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <Clock size={15} color="#6d28d9" /> AUDIT TRAIL & DECISION TIMELINE
                    </div>
                    <div style={{ fontSize: '12px', display: 'flex', flexDirection: 'column', gap: '8px' }}>
                      <div style={{ borderLeft: '2px solid #cbd5e1', paddingLeft: '8px' }}>
                        <div style={{ fontWeight: 700 }}>Application Registered</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                          {selectedApp.createdAt ? new Date(selectedApp.createdAt).toLocaleString() : 'Registration'}
                        </div>
                      </div>

                      {(selectedApp.reviewHistory || []).map((h: any, idx: number) => (
                        <div key={idx} style={{ borderLeft: `2px solid ${h.action === 'approved' ? '#16a34a' : (h.action === 'rejected' ? '#dc2626' : '#ea580c')}`, paddingLeft: '8px' }}>
                          <div style={{ fontWeight: 700, textTransform: 'capitalize' }}>
                            {h.action} by {h.adminName || 'Admin'}
                          </div>
                          <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                            {new Date(h.timestamp).toLocaleString()}
                          </div>
                          {h.notes && (
                            <div style={{ fontSize: '11.5px', marginTop: '2px' }}>
                              Note: {h.notes}
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Footer Action Bar */}
            <div style={{ padding: '16px 24px', borderTop: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(0,0,0,0.02)' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                Status: <strong>{String(selectedApp.status || 'PENDING').toUpperCase()}</strong>
              </div>
              <div style={{ display: 'flex', gap: '10px' }}>
                <button
                  type="button"
                  onClick={() => setIsAppDetailsModalOpen(false)}
                  style={{
                    padding: '8px 16px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'transparent',
                    color: 'var(--text-main)',
                    fontWeight: 600,
                    cursor: 'pointer',
                    fontSize: '13px'
                  }}
                >
                  Close
                </button>

                {selectedApp.status !== 'approved' && (
                  <>
                    <button
                      type="button"
                      onClick={() => handleRequestCorrection(selectedApp)}
                      style={{
                        padding: '8px 16px',
                        borderRadius: '8px',
                        border: '1px solid #fde68a',
                        background: '#fef3c7',
                        color: '#b45309',
                        fontWeight: 700,
                        cursor: 'pointer',
                        fontSize: '13px',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '6px'
                      }}
                    >
                      <AlertTriangle size={14} /> Request Correction
                    </button>

                    <button
                      type="button"
                      onClick={() => handleReject(selectedApp)}
                      style={{
                        padding: '8px 16px',
                        borderRadius: '8px',
                        border: 'none',
                        background: '#ef4444',
                        color: '#fff',
                        fontWeight: 700,
                        cursor: 'pointer',
                        fontSize: '13px',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '6px'
                      }}
                    >
                      <X size={14} /> Reject Application
                    </button>

                    <button
                      type="button"
                      onClick={() => handleApprove(selectedApp)}
                      style={{
                        padding: '8px 20px',
                        borderRadius: '8px',
                        border: 'none',
                        background: '#16a34a',
                        color: '#fff',
                        fontWeight: 700,
                        cursor: 'pointer',
                        fontSize: '13px',
                        display: 'flex',
                        alignItems: 'center',
                        gap: '6px',
                        boxShadow: '0 2px 6px rgba(22, 163, 74, 0.3)'
                      }}
                    >
                      <Check size={14} /> Approve Restaurant
                    </button>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 7: CONFIRM RESTAURANT APPROVAL DIALOG                           */}
      {/* ===================================================================== */}
      {isApproveModalOpen && restaurantToApprove && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.7)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1300,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '520px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
              <div style={{ background: '#dcfce7', padding: '10px', borderRadius: '50%', color: '#16a34a' }}>
                <CheckCircle2 size={24} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Approve Restaurant Application</h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Confirm administrative verification and onboarding</div>
              </div>
            </div>

            <div style={{ background: 'rgba(0,0,0,0.03)', padding: '14px', borderRadius: '10px', marginBottom: '16px', fontSize: '13px' }}>
              <div style={{ fontWeight: 800, fontSize: '15px', color: 'var(--text-main)', marginBottom: '4px' }}>
                {restaurantToApprove.name}
              </div>
              <div style={{ color: 'var(--text-muted)', fontSize: '12px', marginBottom: '4px' }}>
                Partner ID: <strong style={{ fontFamily: 'monospace' }}>{restaurantToApprove.restaurantId}</strong>
              </div>
              <div style={{ color: 'var(--text-muted)', fontSize: '12px' }}>
                Mobile: <strong>{restaurantToApprove.phone}</strong> • Owner: <strong>{restaurantToApprove.ownerName || 'Partner'}</strong>
              </div>
            </div>

            <p style={{ fontSize: '13px', color: 'var(--text-muted)', lineHeight: '1.4', marginBottom: '16px' }}>
              By approving this application, the restaurant partner will be notified, their dashboard in the Restaurant Partner App will be unlocked, and the restaurant will become eligible to publish dishes and accept food orders on StayDriv.
            </p>

            <div style={{ marginBottom: '20px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                Approval Remarks / Operational Note
              </label>
              <input
                type="text"
                value={approveNotes}
                onChange={e => setApproveNotes(e.target.value)}
                placeholder="e.g. FSSAI & KYC verified. Ready for live kitchen orders."
                style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setIsApproveModalOpen(false)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmApprove}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#16a34a',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13.5px',
                  cursor: 'pointer',
                  boxShadow: '0 2px 6px rgba(22, 163, 74, 0.3)'
                }}
              >
                Confirm & Approve
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 8: REJECT RESTAURANT APPLICATION DIALOG                         */}
      {/* ===================================================================== */}
      {isRejectModalOpen && restaurantToReject && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.7)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1300,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '520px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
              <div style={{ background: '#fee2e2', padding: '10px', borderRadius: '50%', color: '#ef4444' }}>
                <XCircle size={24} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Reject Restaurant Application</h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Specify the reason why this application cannot be accepted</div>
              </div>
            </div>

            <div style={{ background: 'rgba(0,0,0,0.03)', padding: '12px', borderRadius: '10px', marginBottom: '16px', fontSize: '13px' }}>
              <strong>{restaurantToReject.name}</strong> (Partner ID: <span style={{ fontFamily: 'monospace' }}>{restaurantToReject.restaurantId}</span>)
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                Mandatory Rejection Reason *
              </label>
              <textarea
                required
                rows={4}
                value={rejectionReason}
                onChange={e => setRejectionReason(e.target.value)}
                placeholder="Explain why the application is rejected (e.g. Invalid FSSAI certificate, address location mismatch, unserviceable commercial kitchen)..."
                style={{ width: '100%', padding: '10px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
              />
              <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>This reason will be visible to the partner in the Restaurant Partner App.</span>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setIsRejectModalOpen(false)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmReject}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#ef4444',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13.5px',
                  cursor: 'pointer'
                }}
              >
                Confirm Rejection
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 9: REQUEST CORRECTION DIALOG                                    */}
      {/* ===================================================================== */}
      {isCorrectionModalOpen && restaurantForCorrection && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.7)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1300,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '520px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '16px' }}>
              <div style={{ background: '#fef3c7', padding: '10px', borderRadius: '50%', color: '#b45309' }}>
                <AlertTriangle size={24} />
              </div>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Request Application Correction</h3>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Ask the restaurant partner to fix specific details or re-upload documents</div>
              </div>
            </div>

            <div style={{ background: 'rgba(0,0,0,0.03)', padding: '12px', borderRadius: '10px', marginBottom: '16px', fontSize: '13px' }}>
              <strong>{restaurantForCorrection.name}</strong> (Partner ID: <span style={{ fontFamily: 'monospace' }}>{restaurantForCorrection.restaurantId}</span>)
            </div>

            <div style={{ marginBottom: '20px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, marginBottom: '6px' }}>
                Required Corrections / Missing Documents *
              </label>
              <textarea
                required
                rows={4}
                value={correctionNotes}
                onChange={e => setCorrectionNotes(e.target.value)}
                placeholder="e.g. The uploaded FSSAI certificate is blurry. Please upload a clear color copy showing license number and expiry date."
                style={{ width: '100%', padding: '10px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '13px' }}
              />
              <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>The partner's application status will update to 'Action Required' with these instructions.</span>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setIsCorrectionModalOpen(false)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleConfirmCorrection}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#ea580c',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13.5px',
                  cursor: 'pointer'
                }}
              >
                Send Request
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL: VERIFY RESTAURANT BANK DETAILS                                  */}
      {/* ===================================================================== */}
      {verifyBankModalRest && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.75)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1350,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '540px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <ShieldCheck size={22} color="#1e60ff" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Verify Beneficiary Bank Account</h3>
              </div>
              <button onClick={() => setVerifyBankModalRest(null)} style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                <X size={20} />
              </button>
            </div>

            <div style={{ background: 'var(--bg-main)', borderRadius: '12px', padding: '16px', marginBottom: '18px', display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '12.5px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Restaurant:</span>
                <span style={{ fontWeight: 800, color: 'var(--text-main)' }}>{verifyBankModalRest.name} ({verifyBankModalRest.restaurantId})</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Account Holder Name:</span>
                <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>{verifyBankModalRest.accountHolderName || verifyBankModalRest.bankHolderName || 'N/A'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Bank Name & Type:</span>
                <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>{verifyBankModalRest.bankName || 'Bank'} ({verifyBankModalRest.accountType || 'Current'})</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Account Number:</span>
                <span style={{ fontWeight: 800, color: '#1e60ff', fontFamily: 'monospace' }}>{verifyBankModalRest.bankAccountMasked || '••••••••'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>IFSC Code:</span>
                <span style={{ fontWeight: 700, fontFamily: 'monospace', color: 'var(--text-main)' }}>{verifyBankModalRest.bankIfsc || 'N/A'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>UPI ID:</span>
                <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>{verifyBankModalRest.upiId || 'N/A'}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Current Status:</span>
                <span style={{ fontWeight: 800, textTransform: 'uppercase', color: verifyBankModalRest.bankVerificationStatus === 'verified' ? '#16a34a' : '#ea580c' }}>
                  {verifyBankModalRest.bankVerificationStatus || 'UNVERIFIED'}
                </span>
              </div>
            </div>

            <div style={{ marginBottom: '18px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '6px' }}>
                Rejection Reason (required only if rejecting):
              </label>
              <input
                type="text"
                placeholder="e.g. Account name mismatch or invalid IFSC branch"
                value={bankRejectionReason}
                onChange={(e) => setBankRejectionReason(e.target.value)}
                style={{
                  width: '100%',
                  padding: '10px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--bg-main)',
                  color: 'var(--text-main)',
                  fontSize: '13px'
                }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setVerifyBankModalRest(null)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={settlementActionLoading}
                onClick={() => {
                  if (!bankRejectionReason.trim()) {
                    alert('Please enter a rejection reason.');
                    return;
                  }
                  handleVerifyBankDetails(verifyBankModalRest.restaurantId, 'rejected', bankRejectionReason.trim());
                }}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid #ef4444',
                  background: 'transparent',
                  color: '#ef4444',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Reject Details
              </button>
              <button
                type="button"
                disabled={settlementActionLoading}
                onClick={() => handleVerifyBankDetails(verifyBankModalRest.restaurantId, 'verified')}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#16a34a',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Approve & Mark Verified
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL: INITIATE RESTAURANT PAYOUT BATCH                                */}
      {/* ===================================================================== */}
      {initiateModalRest && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.75)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1350,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '500px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <DollarSign size={22} color="#ea580c" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Initiate Restaurant Payout</h3>
              </div>
              <button onClick={() => setInitiateModalRest(null)} style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                <X size={20} />
              </button>
            </div>

            <div style={{ background: 'var(--bg-main)', borderRadius: '12px', padding: '16px', marginBottom: '18px', display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '12.5px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Restaurant Partner:</span>
                <span style={{ fontWeight: 800, color: 'var(--text-main)' }}>{initiateModalRest.name}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Delivered Orders Count:</span>
                <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>{initiateModalRest.completedOrdersCount || 0}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Total Gross Sales:</span>
                <span style={{ fontWeight: 700, color: 'var(--text-main)' }}>₹{(initiateModalRest.totalSales || 0).toLocaleString('en-IN')}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Platform Fee ({initiateModalRest.commissionRate || 15}%):</span>
                <span style={{ fontWeight: 700, color: '#f59e0b' }}>-₹{(initiateModalRest.platformCommissionAmount || 0).toLocaleString('en-IN')}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', borderTop: '1px solid var(--border-color)', paddingTop: '8px' }}>
                <span style={{ fontWeight: 800, color: 'var(--text-main)' }}>Net Payable Amount:</span>
                <span style={{ fontWeight: 900, color: '#ea580c', fontSize: '16px', fontFamily: 'monospace' }}>
                  ₹{(initiateModalRest.pendingSettlement || 0).toLocaleString('en-IN')}
                </span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text-muted)' }}>
                <span>Beneficiary:</span>
                <span>{initiateModalRest.bankName || 'Bank'} ({initiateModalRest.bankAccountMasked || '••••••••'})</span>
              </div>
            </div>

            <div style={{ marginBottom: '18px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '6px' }}>
                Payout Remarks / Notes (optional):
              </label>
              <input
                type="text"
                placeholder="e.g. Weekly restaurant settlement batch #W42"
                value={initiateNotes}
                onChange={(e) => setInitiateNotes(e.target.value)}
                style={{
                  width: '100%',
                  padding: '10px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--bg-main)',
                  color: 'var(--text-main)',
                  fontSize: '13px'
                }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setInitiateModalRest(null)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={settlementActionLoading}
                onClick={() => handleInitiateSettlement(initiateModalRest.restaurantId, initiateNotes)}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#ea580c',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Confirm & Initiate Settlement
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL: CONFIRM PAYOUT & ENTER BANK UTR NUMBER                          */}
      {/* ===================================================================== */}
      {confirmPayoutModalSettlement && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.75)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1350,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '520px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <CheckCircle2 size={22} color="#16a34a" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Record Bank Transfer (UTR)</h3>
              </div>
              <button onClick={() => setConfirmPayoutModalSettlement(null)} style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                <X size={20} />
              </button>
            </div>

            <div style={{ background: 'var(--bg-main)', borderRadius: '12px', padding: '16px', marginBottom: '18px', display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '12.5px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Settlement ID:</span>
                <span style={{ fontWeight: 800, fontFamily: 'monospace', color: 'var(--text-main)' }}>#{confirmPayoutModalSettlement.settlementId}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Restaurant Partner:</span>
                <span style={{ fontWeight: 800, color: 'var(--text-main)' }}>{confirmPayoutModalSettlement.restaurantName}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)' }}>Net Payout Amount:</span>
                <span style={{ fontWeight: 900, color: '#16a34a', fontSize: '16px', fontFamily: 'monospace' }}>
                  ₹{(confirmPayoutModalSettlement.netPayable || 0).toLocaleString('en-IN')}
                </span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text-muted)' }}>
                <span>Beneficiary Account:</span>
                <span>{confirmPayoutModalSettlement.beneficiaryAccount?.bankName || 'Bank'} ({confirmPayoutModalSettlement.beneficiaryAccount?.accountNumberMasked || '••••••••'})</span>
              </div>
            </div>

            <div style={{ marginBottom: '14px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: 'var(--text-main)', marginBottom: '6px' }}>
                Bank UTR / Transaction Reference Number <span style={{ color: '#ef4444' }}>*</span>:
              </label>
              <input
                type="text"
                placeholder="e.g. AXIS261020000042 or CMS987213456"
                value={payoutUtrInput}
                onChange={(e) => setPayoutUtrInput(e.target.value)}
                style={{
                  width: '100%',
                  padding: '10px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--bg-main)',
                  color: 'var(--text-main)',
                  fontSize: '13px',
                  fontFamily: 'monospace',
                  fontWeight: 700
                }}
              />
              <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px', display: 'block' }}>
                Mandatory reference number from your bank or payment gateway. Will be recorded in the double-entry financial ledger.
              </span>
            </div>

            <div style={{ marginBottom: '18px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, color: 'var(--text-muted)', marginBottom: '6px' }}>
                Remarks / Notes (optional):
              </label>
              <input
                type="text"
                placeholder="e.g. NEFT transfer processed successfully"
                value={payoutRemarksInput}
                onChange={(e) => setPayoutRemarksInput(e.target.value)}
                style={{
                  width: '100%',
                  padding: '10px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--bg-main)',
                  color: 'var(--text-main)',
                  fontSize: '13px'
                }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setConfirmPayoutModalSettlement(null)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={settlementActionLoading}
                onClick={() => handleConfirmPayout(confirmPayoutModalSettlement.settlementId, payoutUtrInput, payoutRemarksInput)}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#16a34a',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Confirm Payout & Record in Ledger
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL: MARK SETTLEMENT AS FAILED                                       */}
      {/* ===================================================================== */}
      {failPayoutModalSettlement && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.75)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1350,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '480px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <XCircle size={22} color="#ef4444" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Mark Settlement Failed</h3>
              </div>
              <button onClick={() => setFailPayoutModalSettlement(null)} style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                <X size={20} />
              </button>
            </div>

            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '16px' }}>
              The payout for <strong>{failPayoutModalSettlement.restaurantName}</strong> of <strong>₹{failPayoutModalSettlement.netPayable}</strong> will be marked as failed. The funds will be safely retained in the partner's pending balance for re-settlement.
            </p>

            <div style={{ marginBottom: '18px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: 'var(--text-main)', marginBottom: '6px' }}>
                Failure Reason <span style={{ color: '#ef4444' }}>*</span>:
              </label>
              <input
                type="text"
                placeholder="e.g. Beneficiary account frozen or invalid branch IFSC"
                value={payoutFailReasonInput}
                onChange={(e) => setPayoutFailReasonInput(e.target.value)}
                style={{
                  width: '100%',
                  padding: '10px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'var(--bg-main)',
                  color: 'var(--text-main)',
                  fontSize: '13px'
                }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setFailPayoutModalSettlement(null)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={settlementActionLoading}
                onClick={() => handleFailPayout(failPayoutModalSettlement.settlementId, payoutFailReasonInput)}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#ef4444',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Mark as Failed
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL: EDIT COMMISSION RATE                                           */}
      {/* ===================================================================== */}
      {editCommissionRest && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.75)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1350,
          padding: '20px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '440px',
            padding: '24px'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <Percent size={22} color="#f59e0b" />
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Update Commission Rate</h3>
              </div>
              <button onClick={() => setEditCommissionRest(null)} style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                <X size={20} />
              </button>
            </div>

            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '16px' }}>
              Update platform fee percentage for <strong>{editCommissionRest.name}</strong>.
            </p>

            <div style={{ marginBottom: '18px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 700, color: 'var(--text-main)', marginBottom: '6px' }}>
                Platform Commission Percentage (%):
              </label>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <input
                  type="number"
                  min="0"
                  max="50"
                  step="0.5"
                  value={commissionInput}
                  onChange={(e) => setCommissionInput(parseFloat(e.target.value) || 0)}
                  style={{
                    flex: 1,
                    padding: '10px 12px',
                    borderRadius: '8px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--bg-main)',
                    color: 'var(--text-main)',
                    fontSize: '14px',
                    fontWeight: 700
                  }}
                />
                <span style={{ fontWeight: 800, fontSize: '16px', color: 'var(--text-main)' }}>%</span>
              </div>
              <span style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px', display: 'block' }}>
                Standard rate is 15.0%. Permissible range is 0.0% to 50.0%.
              </span>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                type="button"
                onClick={() => setEditCommissionRest(null)}
                style={{
                  padding: '9px 18px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color)',
                  background: 'transparent',
                  color: 'var(--text-main)',
                  fontWeight: 600,
                  cursor: 'pointer'
                }}
              >
                Cancel
              </button>
              <button
                type="button"
                disabled={settlementActionLoading}
                onClick={() => handleUpdateCommission(editCommissionRest.restaurantId, commissionInput)}
                style={{
                  padding: '9px 22px',
                  borderRadius: '8px',
                  border: 'none',
                  background: '#f59e0b',
                  color: '#fff',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer'
                }}
              >
                Save Commission Rate
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ===================================================================== */}
      {/* MODAL 10: DOCUMENT LIGHTBOX PREVIEW MODAL                             */}
      {/* ===================================================================== */}
      {previewDoc && (
        <div style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.85)',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          zIndex: 1400,
          padding: '24px'
        }}>
          <div style={{
            background: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '720px',
            maxHeight: '90vh',
            display: 'flex',
            flexDirection: 'column',
            overflow: 'hidden'
          }}>
            <div style={{ padding: '16px 20px', borderBottom: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <FileCheck size={18} color="#16a34a" />
                <h4 style={{ margin: 0, fontSize: '15px', fontWeight: 800 }}>{previewDoc.label}</h4>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                <a
                  href={previewDoc.url}
                  target="_blank"
                  rel="noreferrer"
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '4px',
                    fontSize: '12px',
                    color: '#2563eb',
                    fontWeight: 600,
                    textDecoration: 'none',
                    padding: '4px 8px',
                    borderRadius: '6px',
                    background: '#eff6ff'
                  }}
                >
                  <ExternalLink size={12} /> Open Full
                </a>
                <button
                  onClick={() => setPreviewDoc(null)}
                  style={{ background: 'transparent', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
                >
                  <X size={20} />
                </button>
              </div>
            </div>

            <div style={{ flex: 1, overflowY: 'auto', padding: '20px', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#0b0f19' }}>
              <img
                src={previewDoc.url}
                alt={previewDoc.label}
                style={{ maxWidth: '100%', maxHeight: '68vh', objectFit: 'contain', borderRadius: '8px', boxShadow: '0 4px 20px rgba(0,0,0,0.5)' }}
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default FoodOrdersRestaurants;

