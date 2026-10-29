import React, { useState, useEffect } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  Plus, Tag, RefreshCw, X, Check, Edit2, Trash2, Eye, Upload, 
  Video, Image as ImageIcon, ExternalLink, Smartphone, AlertTriangle, 
  Calendar, BarChart2, ArrowUp, ArrowDown, Sparkles, UtensilsCrossed, Home
} from 'lucide-react';
import { PromoCode } from '../data/mockData';

interface Promotion {
  _id?: string;
  promotionId: string;
  title: string;
  description?: string;
  offerText?: string;
  buttonLabel?: string;
  mediaType: 'image' | 'gif' | 'video';
  mediaUrl: string;
  thumbnailUrl?: string;
  targetScreen: 'home' | 'food' | 'both';
  destinationType: 'none' | 'food_screen' | 'restaurant' | 'membership' | 'ride_screen' | 'parcel_screen' | 'external_url' | 'food' | 'ride' | 'parcel';
  destinationId?: string;
  destinationUrl?: string;
  startAt: string;
  endAt?: string | null;
  displayOrder: number;
  isActive: boolean;
  clicksCount?: number;
  impressionsCount?: number;
  createdAt?: string;
  updatedAt?: string;
}

const API_BASE = '/api/promotions';

export const getPromotionStatus = (p: Promotion): { key: 'active' | 'scheduled' | 'inactive' | 'expired'; label: string; color: string; bg: string; dot: string } => {
  if (!p.isActive) {
    return { key: 'inactive', label: 'Inactive', color: '#64748b', bg: '#f1f5f9', dot: '#94a3b8' };
  }
  const now = Date.now();
  const start = p.startAt ? new Date(p.startAt).getTime() : 0;
  const end = p.endAt ? new Date(p.endAt).getTime() : null;
  if (start > now) {
    return { key: 'scheduled', label: 'Scheduled', color: '#2563eb', bg: '#eff6ff', dot: '#3b82f6' };
  }
  if (end && end < now) {
    return { key: 'expired', label: 'Expired', color: '#b91c1c', bg: '#fee2e2', dot: '#ef4444' };
  }
  return { key: 'active', label: 'Active', color: '#15803d', bg: '#dcfce7', dot: '#16a34a' };
};

interface PromosProps {
  initialTab?: 'banners' | 'coupons';
}

export const Promos: React.FC<PromosProps> = ({ initialTab = 'banners' }) => {
  const { promoCodes, createPromoCode, togglePromoCode } = useDatabase();
  const [activeTab, setActiveTab] = useState<'banners' | 'coupons'>(() => {
    if (window.location.hash === '#customer-banners' || window.location.hash === '#banners') return 'banners';
    if (window.location.hash === '#coupons') return 'coupons';
    return initialTab;
  });

  // -------------------------------------------------------------
  // BANNERS STATE
  // -------------------------------------------------------------
  const [promotions, setPromotions] = useState<Promotion[]>([]);
  const [loadingPromos, setLoadingPromos] = useState(false);
  const [promoStats, setPromoStats] = useState({
    total: 0,
    activeCount: 0,
    inactiveCount: 0,
    homeCount: 0,
    foodCount: 0,
    bothCount: 0,
    totalImpressions: 0,
    totalClicks: 0
  });

  // Filters
  const [screenFilter, setScreenFilter] = useState<'all' | 'home' | 'food' | 'both'>('all');
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'scheduled' | 'inactive' | 'expired'>('all');
  const [searchQuery, setSearchQuery] = useState('');

  // Modals
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false);
  const [editingPromotion, setEditingPromotion] = useState<Promotion | null>(null);
  const [previewPromotion, setPreviewPromotion] = useState<Promotion | null>(null);
  const [deletingPromotion, setDeletingPromotion] = useState<Promotion | null>(null);
  const [previewScreenContext, setPreviewScreenContext] = useState<'home' | 'food'>('home');

  // Form State
  const [formTitle, setFormTitle] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formOfferText, setFormOfferText] = useState('');
  const [formButtonLabel, setFormButtonLabel] = useState('');
  const [formMediaType, setFormMediaType] = useState<'image' | 'gif' | 'video'>('image');
  const [formMediaUrl, setFormMediaUrl] = useState('');
  const [formTargetScreen, setFormTargetScreen] = useState<'home' | 'food' | 'both'>('both');
  const [formDestType, setFormDestType] = useState<'none' | 'food_screen' | 'restaurant' | 'membership' | 'ride_screen' | 'parcel_screen' | 'external_url'>('none');
  const [formDestId, setFormDestId] = useState('');
  const [formDestUrl, setFormDestUrl] = useState('');
  const [formStartAt, setFormStartAt] = useState(new Date().toISOString().split('T')[0]);
  const [formEndAt, setFormEndAt] = useState('');
  const [formNoExpiry, setFormNoExpiry] = useState(true);
  const [formDisplayOrder, setFormDisplayOrder] = useState(0);
  const [formIsActive, setFormIsActive] = useState(true);
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploadPreview, setUploadPreview] = useState<string>('');
  const [uploadError, setUploadError] = useState<string>('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  // -------------------------------------------------------------
  // COUPONS STATE
  // -------------------------------------------------------------
  const [showCouponModal, setShowCouponModal] = useState(false);
  const [couponCode, setCouponCode] = useState('');
  const [discountPercent, setDiscountPercent] = useState<number>(10);
  const [maxDiscount, setMaxDiscount] = useState<number>(50);
  const [minBooking, setMinBooking] = useState<number>(100);
  const [couponExpiry, setCouponExpiry] = useState('');

  // Fetch Promotions from Backend
  const fetchPromotions = async () => {
    setLoadingPromos(true);
    try {
      const res = await fetch(`${API_BASE}/admin/all`);
      const data = await res.json();
      if (data.success && Array.isArray(data.promotions)) {
        setPromotions(data.promotions);
        if (data.stats) {
          setPromoStats(data.stats);
        }
      }
    } catch (err) {
      console.error('[PROMOS] Failed to fetch promotions:', err);
    } finally {
      setLoadingPromos(false);
    }
  };

  useEffect(() => {
    fetchPromotions();
  }, []);

  // Handle Hash Changes
  useEffect(() => {
    const handleHash = () => {
      if (window.location.hash === '#customer-banners' || window.location.hash === '#banners') {
        setActiveTab('banners');
      } else if (window.location.hash === '#coupons') {
        setActiveTab('coupons');
      }
    };
    window.addEventListener('hashchange', handleHash);
    return () => window.removeEventListener('hashchange', handleHash);
  }, []);

  // Filtered promotions
  const filteredPromotions = promotions.filter(p => {
    if (screenFilter !== 'all' && p.targetScreen !== screenFilter && p.targetScreen !== 'both') return false;
    if (statusFilter !== 'all') {
      const status = getPromotionStatus(p).key;
      if (status !== statusFilter) return false;
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      const matchTitle = p.title.toLowerCase().includes(q);
      const matchDesc = (p.description || '').toLowerCase().includes(q);
      const matchOffer = (p.offerText || '').toLowerCase().includes(q);
      const matchDest = (p.destinationId || p.destinationUrl || '').toLowerCase().includes(q);
      if (!matchTitle && !matchDesc && !matchOffer && !matchDest) return false;
    }
    return true;
  });

  // Handle File Selection with Live Preview & Validation
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setUploadError('');
    if (!e.target.files || e.target.files.length === 0) return;
    const file = e.target.files[0];

    const ext = file.name.split('.').pop()?.toLowerCase() || '';
    const allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'mp4'];
    if (!allowed.includes(ext)) {
      setUploadError(`Unsupported file format .${ext}. Allowed formats: JPG, JPEG, PNG, WebP, GIF, MP4.`);
      return;
    }

    let detectedType: 'image' | 'gif' | 'video' = 'image';
    if (ext === 'gif') detectedType = 'gif';
    else if (ext === 'mp4' || file.type.includes('video')) detectedType = 'video';

    // File size limits
    const maxMb = detectedType === 'video' || detectedType === 'gif' ? 25 : 10;
    if (file.size > maxMb * 1024 * 1024) {
      setUploadError(`File size (${(file.size / (1024 * 1024)).toFixed(1)}MB) exceeds limit of ${maxMb}MB.`);
      return;
    }

    setUploadFile(file);
    setFormMediaType(detectedType);

    // Live preview
    const reader = new FileReader();
    reader.onload = () => {
      setUploadPreview(reader.result as string);
    };
    reader.readAsDataURL(file);
  };

  // Open Form for New Promotion
  const handleOpenCreateModal = () => {
    setEditingPromotion(null);
    setFormTitle('');
    setFormDescription('');
    setFormOfferText('');
    setFormButtonLabel('');
    setFormMediaType('image');
    setFormMediaUrl('');
    setFormTargetScreen('both');
    setFormDestType('none');
    setFormDestId('');
    setFormDestUrl('');
    setFormStartAt(new Date().toISOString().split('T')[0]);
    setFormEndAt('');
    setFormNoExpiry(true);
    setFormDisplayOrder(promotions.length);
    setFormIsActive(true);
    setUploadFile(null);
    setUploadPreview('');
    setUploadError('');
    setIsUploadModalOpen(true);
  };

  // Open Form for Editing
  const handleOpenEditModal = (p: Promotion) => {
    setEditingPromotion(p);
    setFormTitle(p.title);
    setFormDescription(p.description || '');
    setFormOfferText(p.offerText || '');
    setFormButtonLabel(p.buttonLabel || '');
    setFormMediaType(p.mediaType);
    setFormMediaUrl(p.mediaUrl);
    setFormTargetScreen(p.targetScreen);
    setFormDestType((p.destinationType as any) || 'none');
    setFormDestId(p.destinationId || '');
    setFormDestUrl(p.destinationUrl || '');
    setFormStartAt(p.startAt ? new Date(p.startAt).toISOString().split('T')[0] : new Date().toISOString().split('T')[0]);
    if (p.endAt) {
      setFormEndAt(new Date(p.endAt).toISOString().split('T')[0]);
      setFormNoExpiry(false);
    } else {
      setFormEndAt('');
      setFormNoExpiry(true);
    }
    setFormDisplayOrder(p.displayOrder || 0);
    setFormIsActive(p.isActive);
    setUploadFile(null);
    setUploadPreview(p.mediaUrl);
    setUploadError('');
    setIsUploadModalOpen(true);
  };

  // Save / Publish Promotion
  const handleSavePromotion = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formTitle.trim()) {
      alert('Please provide a title for the promotion banner.');
      return;
    }

    setIsSubmitting(true);
    setUploadError('');

    try {
      let finalMediaUrl = formMediaUrl.trim();

      // If user uploaded a new local file, upload to backend first
      if (uploadFile && uploadPreview) {
        const uploadRes = await fetch(`${API_BASE}/admin/upload`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            mediaData: uploadPreview,
            fileName: uploadFile.name,
            mimeType: uploadFile.type
          })
        });
        const uploadData = await uploadRes.json();
        if (!uploadData.success) {
          throw new Error(uploadData.message || 'File upload failed');
        }
        finalMediaUrl = uploadData.url;
      }

      if (!finalMediaUrl) {
        throw new Error('Please select a media file to upload or enter a direct media URL.');
      }

      const payload = {
        title: formTitle.trim(),
        description: formDescription.trim(),
        offerText: formOfferText.trim(),
        buttonLabel: formButtonLabel.trim(),
        mediaType: formMediaType,
        mediaUrl: finalMediaUrl,
        targetScreen: formTargetScreen,
        destinationType: formDestType,
        destinationId: formDestType === 'restaurant' ? formDestId.trim() : '',
        destinationUrl: formDestType === 'external_url' ? formDestUrl.trim() : '',
        startAt: formStartAt ? new Date(formStartAt).toISOString() : new Date().toISOString(),
        endAt: formNoExpiry || !formEndAt ? null : new Date(formEndAt).toISOString(),
        displayOrder: Number(formDisplayOrder) || 0,
        isActive: formIsActive
      };

      if (editingPromotion) {
        const res = await fetch(`${API_BASE}/admin/${editingPromotion.promotionId}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (!data.success) throw new Error(data.message || 'Failed to update promotion');
      } else {
        const res = await fetch(`${API_BASE}/admin/create`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (!data.success) throw new Error(data.message || 'Failed to create promotion');
      }

      setIsUploadModalOpen(false);
      fetchPromotions();
    } catch (err: any) {
      console.error('[PROMOS] Save error:', err);
      setUploadError(err.message || 'Error occurred while saving promotion');
    } finally {
      setIsSubmitting(false);
    }
  };

  // Toggle Active/Inactive
  const handleToggleStatus = async (p: Promotion) => {
    try {
      const res = await fetch(`${API_BASE}/admin/${p.promotionId}/status`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isActive: !p.isActive })
      });
      const data = await res.json();
      if (data.success) {
        setPromotions(prev => prev.map(item => item.promotionId === p.promotionId ? { ...item, isActive: !item.isActive } : item));
      }
    } catch (err) {
      console.error('[PROMOS] Failed to toggle status:', err);
    }
  };

  // Reorder Promotions (Move Up / Down)
  const handleMoveOrder = async (index: number, direction: 'up' | 'down') => {
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= filteredPromotions.length) return;

    const currentItem = filteredPromotions[index];
    const targetItem = filteredPromotions[targetIndex];

    const currentOrder = currentItem.displayOrder;
    const targetOrder = targetItem.displayOrder;

    // Swap displayOrder values
    const newItems = [
      { id: currentItem.promotionId, displayOrder: targetOrder },
      { id: targetItem.promotionId, displayOrder: currentOrder }
    ];

    try {
      await fetch(`${API_BASE}/admin/reorder`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: newItems })
      });
      fetchPromotions();
    } catch (err) {
      console.error('[PROMOS] Failed to reorder:', err);
    }
  };

  // Confirm Delete
  const handleConfirmDelete = async () => {
    if (!deletingPromotion) return;
    try {
      const res = await fetch(`${API_BASE}/admin/${deletingPromotion.promotionId}`, {
        method: 'DELETE'
      });
      const data = await res.json();
      if (data.success) {
        setPromotions(prev => prev.filter(p => p.promotionId !== deletingPromotion.promotionId));
        setDeletingPromotion(null);
      }
    } catch (err) {
      console.error('[PROMOS] Failed to delete:', err);
    }
  };

  // Handle Coupon Submit
  const handleCouponSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!couponCode || !couponExpiry) {
      alert("Please fill in code and expiry date!");
      return;
    }

    await createPromoCode({
      code: couponCode.toUpperCase().trim(),
      discountPercentage: discountPercent,
      maxDiscount,
      minBookingValue: minBooking,
      expiryDate: couponExpiry,
      status: 'active'
    });

    setCouponCode('');
    setDiscountPercent(10);
    setMaxDiscount(50);
    setMinBooking(100);
    setCouponExpiry('');
    setShowCouponModal(false);
    alert("New promo code published!");
  };

  return (
    <div className="page-container">
      {/* Top Header & Section Switcher */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ fontSize: '12px', fontWeight: 800, color: 'var(--primary)', letterSpacing: '1px', textTransform: 'uppercase' }}>
              Marketing & Promotions
            </span>
          </div>
          <h2 style={{ margin: '4px 0 6px 0', fontSize: '24px', fontWeight: 800, color: 'var(--text-main)' }}>
            Customer App Banners & Promotions
          </h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px', margin: 0 }}>
            Upload routine posters, promotional banners, animated GIFs, and video advertisements displayed dynamically in StayDriv Customer Home and Food Order Now screens.
          </p>
        </div>

        {/* Tab Switcher Pills */}
        <div style={{ display: 'flex', background: 'var(--bg-card, #ffffff)', padding: '4px', borderRadius: '10px', border: '1px solid var(--border-color, #e2e8f0)', gap: '4px' }}>
          <button
            onClick={() => { setActiveTab('banners'); window.location.hash = '#customer-banners'; }}
            style={{
              padding: '8px 16px',
              fontSize: '13px',
              fontWeight: 700,
              borderRadius: '8px',
              border: 'none',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              backgroundColor: activeTab === 'banners' ? 'var(--primary, #ea580c)' : 'transparent',
              color: activeTab === 'banners' ? '#ffffff' : 'var(--text-muted, #64748b)',
              transition: 'all 0.15s ease'
            }}
          >
            <ImageIcon size={15} />
            <span>Customer App Banners</span>
            <span style={{
              backgroundColor: activeTab === 'banners' ? 'rgba(255,255,255,0.25)' : 'var(--border-color, #e2e8f0)',
              color: activeTab === 'banners' ? '#ffffff' : 'var(--text-main, #0f172a)',
              fontSize: '11px',
              padding: '1px 6px',
              borderRadius: '10px',
              fontWeight: 800
            }}>
              {promotions.length}
            </span>
          </button>

          <button
            onClick={() => { setActiveTab('coupons'); window.location.hash = '#coupons'; }}
            style={{
              padding: '8px 16px',
              fontSize: '13px',
              fontWeight: 700,
              borderRadius: '8px',
              border: 'none',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              backgroundColor: activeTab === 'coupons' ? 'var(--primary, #ea580c)' : 'transparent',
              color: activeTab === 'coupons' ? '#ffffff' : 'var(--text-muted, #64748b)',
              transition: 'all 0.15s ease'
            }}
          >
            <Tag size={15} />
            <span>Promo & Coupon Codes</span>
            <span style={{
              backgroundColor: activeTab === 'coupons' ? 'rgba(255,255,255,0.25)' : 'var(--border-color, #e2e8f0)',
              color: activeTab === 'coupons' ? '#ffffff' : 'var(--text-main, #0f172a)',
              fontSize: '11px',
              padding: '1px 6px',
              borderRadius: '10px',
              fontWeight: 800
            }}>
              {promoCodes.length}
            </span>
          </button>
        </div>
      </div>

      {/* ======================================================== */}
      {/* SECTION 1: CUSTOMER APP BANNERS */}
      {/* ======================================================== */}
      {activeTab === 'banners' && (
        <>
          {/* Summary Metric Cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '14px', marginBottom: '20px' }}>
            <div style={{ background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '12px', padding: '14px 18px', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted, #64748b)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                <ImageIcon size={14} color="#6366f1" />
                <span>Total Promotions</span>
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: 'var(--text-main, #0f172a)' }}>
                {promoStats.total}
              </div>
              <div style={{ fontSize: '11px', color: '#16a34a', fontWeight: 600, marginTop: '2px' }}>
                {promoStats.activeCount} currently active
              </div>
            </div>

            <div style={{ background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '12px', padding: '14px 18px', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted, #64748b)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                <Home size={14} color="#3b82f6" />
                <span>Customer Home Screen</span>
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: '#1e40af' }}>
                {promoStats.homeCount}
              </div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted, #64748b)', marginTop: '2px' }}>
                Below header, above ride cards
              </div>
            </div>

            <div style={{ background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '12px', padding: '14px 18px', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted, #64748b)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                <UtensilsCrossed size={14} color="#ea580c" />
                <span>Food Order Now Screen</span>
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: '#c2410c' }}>
                {promoStats.foodCount}
              </div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted, #64748b)', marginTop: '2px' }}>
                Below search, above categories
              </div>
            </div>

            <div style={{ background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '12px', padding: '14px 18px', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted, #64748b)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                <Eye size={14} color="#059669" />
                <span>Customer Impressions</span>
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: '#065f46' }}>
                {promoStats.totalImpressions.toLocaleString('en-IN')}
              </div>
              <div style={{ fontSize: '11px', color: 'var(--text-muted, #64748b)', marginTop: '2px' }}>
                Platform carousel views
              </div>
            </div>

            <div style={{ background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '12px', padding: '14px 18px', boxShadow: '0 1px 3px rgba(0,0,0,0.04)' }}>
              <div style={{ fontSize: '12px', color: 'var(--text-muted, #64748b)', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}>
                <BarChart2 size={14} color="#d97706" />
                <span>Customer Clicks & CTR</span>
              </div>
              <div style={{ fontSize: '24px', fontWeight: 800, marginTop: '6px', color: '#92400e' }}>
                {promoStats.totalClicks.toLocaleString('en-IN')}
              </div>
              <div style={{ fontSize: '11px', color: '#d97706', fontWeight: 700, marginTop: '2px' }}>
                CTR: {promoStats.totalImpressions > 0 ? ((promoStats.totalClicks / promoStats.totalImpressions) * 100).toFixed(1) : 0}%
              </div>
            </div>
          </div>

          {/* Action & Filter Bar */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px', flexWrap: 'wrap', gap: '12px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap' }}>
              {/* Screen Filter */}
              <div style={{ display: 'flex', alignItems: 'center', background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '8px', padding: '4px 8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', marginRight: '6px' }}>Screen:</span>
                <select
                  value={screenFilter}
                  onChange={(e) => setScreenFilter(e.target.value as any)}
                  style={{ border: 'none', background: 'transparent', fontSize: '13px', fontWeight: 600, outline: 'none', cursor: 'pointer' }}
                >
                  <option value="all">All Screens</option>
                  <option value="home">Home Screen Only</option>
                  <option value="food">Food Order Now Only</option>
                  <option value="both">Both Screens (Global)</option>
                </select>
              </div>

              {/* Status Filter */}
              <div style={{ display: 'flex', alignItems: 'center', background: '#fff', border: '1px solid var(--border-color, #e2e8f0)', borderRadius: '8px', padding: '4px 8px' }}>
                <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', marginRight: '6px' }}>Status:</span>
                <select
                  value={statusFilter}
                  onChange={(e) => setStatusFilter(e.target.value as any)}
                  style={{ border: 'none', background: 'transparent', fontSize: '13px', fontWeight: 600, outline: 'none', cursor: 'pointer' }}
                >
                  <option value="all">All Statuses</option>
                  <option value="active">Active Only</option>
                  <option value="scheduled">Scheduled Only</option>
                  <option value="expired">Expired Only</option>
                  <option value="inactive">Inactive Only</option>
                </select>
              </div>

              {/* Search Bar */}
              <input
                type="text"
                placeholder="Search promotions by title or destination..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                style={{
                  padding: '7px 12px',
                  borderRadius: '8px',
                  border: '1px solid var(--border-color, #e2e8f0)',
                  fontSize: '13px',
                  width: '260px',
                  outline: 'none',
                  background: '#fff'
                }}
              />
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
              <button
                className="btn btn-secondary"
                onClick={fetchPromotions}
                disabled={loadingPromos}
                style={{ display: 'flex', alignItems: 'center', gap: '6px', height: '38px' }}
              >
                <RefreshCw size={14} className={loadingPromos ? 'spin' : ''} />
                <span>Refresh</span>
              </button>

              <button
                className="btn btn-primary"
                onClick={handleOpenCreateModal}
                style={{ display: 'flex', alignItems: 'center', gap: '6px', height: '38px', fontWeight: 700 }}
              >
                <Plus size={16} />
                <span>Upload New Promotion</span>
              </button>
            </div>
          </div>

          {/* Table of Promotions */}
          <div className="table-wrapper" style={{ boxShadow: '0 1px 3px rgba(0,0,0,0.04)', borderRadius: '12px', overflow: 'hidden' }}>
            <table>
              <thead>
                <tr>
                  <th style={{ width: '45px', textAlign: 'center' }}>Order</th>
                  <th style={{ width: '220px' }}>Media & Preview</th>
                  <th>Title & Description</th>
                  <th>Target Screen</th>
                  <th>Destination</th>
                  <th>Schedule</th>
                  <th style={{ textAlign: 'center' }}>Views / Clicks</th>
                  <th style={{ textAlign: 'center' }}>Status</th>
                  <th style={{ textAlign: 'right', width: '170px' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {loadingPromos ? (
                  <tr>
                    <td colSpan={9} style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
                      <RefreshCw size={24} className="spin" style={{ margin: '0 auto 8px auto', display: 'block' }} />
                      Loading promotional banners...
                    </td>
                  </tr>
                ) : filteredPromotions.length === 0 ? (
                  <tr>
                    <td colSpan={9} style={{ textAlign: 'center', padding: '48px 20px', color: 'var(--text-muted)' }}>
                      <ImageIcon size={40} style={{ margin: '0 auto 12px auto', display: 'block', opacity: 0.35 }} />
                      <div style={{ fontSize: '16px', fontWeight: 700, color: 'var(--text-main)' }}>No promotional banners found</div>
                      <div style={{ fontSize: '13px', marginTop: '4px' }}>Click "Upload New Promotion" to publish posters, GIFs, or videos to the Customer App.</div>
                    </td>
                  </tr>
                ) : (
                  filteredPromotions.map((p, index) => {
                    const isVideo = p.mediaType === 'video';
                    const isGif = p.mediaType === 'gif';

                    return (
                      <tr key={p.promotionId}>
                        {/* Display Order with Up/Down buttons */}
                        <td style={{ textAlign: 'center' }}>
                          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '2px' }}>
                            <button
                              onClick={() => handleMoveOrder(index, 'up')}
                              disabled={index === 0}
                              style={{ border: 'none', background: 'transparent', cursor: index === 0 ? 'default' : 'pointer', padding: '1px', opacity: index === 0 ? 0.2 : 0.7 }}
                              title="Move Up"
                            >
                              <ArrowUp size={12} />
                            </button>
                            <span style={{ fontSize: '12px', fontWeight: 800, fontFamily: 'monospace', color: 'var(--text-main)' }}>
                              #{p.displayOrder}
                            </span>
                            <button
                              onClick={() => handleMoveOrder(index, 'down')}
                              disabled={index === filteredPromotions.length - 1}
                              style={{ border: 'none', background: 'transparent', cursor: index === filteredPromotions.length - 1 ? 'default' : 'pointer', padding: '1px', opacity: index === filteredPromotions.length - 1 ? 0.2 : 0.7 }}
                              title="Move Down"
                            >
                              <ArrowDown size={12} />
                            </button>
                          </div>
                        </td>

                        {/* Media Preview Thumbnail */}
                        <td>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                            <div 
                              onClick={() => { setPreviewPromotion(p); setPreviewScreenContext(p.targetScreen === 'food' ? 'food' : 'home'); }}
                              style={{
                                width: '90px',
                                height: '52px',
                                borderRadius: '8px',
                                overflow: 'hidden',
                                position: 'relative',
                                background: '#0f172a',
                                border: '1px solid #cbd5e1',
                                cursor: 'pointer',
                                flexShrink: 0
                              }}
                            >
                              {isVideo ? (
                                <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#1e293b' }}>
                                  <Video size={20} color="#94a3b8" />
                                </div>
                              ) : (
                                <img
                                  src={p.mediaUrl}
                                  alt={p.title}
                                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                                  onError={(e) => {
                                    (e.target as HTMLElement).style.display = 'none';
                                  }}
                                />
                              )}
                              {/* Media Type Badge Overlay */}
                              <span style={{
                                position: 'absolute',
                                bottom: '3px',
                                right: '3px',
                                fontSize: '9px',
                                fontWeight: 800,
                                padding: '1px 4px',
                                borderRadius: '4px',
                                backgroundColor: isVideo ? '#ef4444' : isGif ? '#8b5cf6' : '#0284c7',
                                color: '#fff'
                              }}>
                                {p.mediaType.toUpperCase()}
                              </span>
                            </div>
                            <div style={{ fontSize: '11px', color: 'var(--text-muted)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '110px' }}>
                              {p.mediaUrl.split('/').pop()?.substring(0, 20)}...
                            </div>
                          </div>
                        </td>

                        {/* Title & Description */}
                        <td>
                          <div style={{ fontWeight: 700, fontSize: '14px', color: 'var(--text-main)' }}>{p.title}</div>
                          {p.description && (
                            <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px', maxWidth: '280px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {p.description}
                            </div>
                          )}
                          <div style={{ fontSize: '10px', color: '#94a3b8', marginTop: '3px', fontFamily: 'monospace' }}>
                            ID: {p.promotionId}
                          </div>
                        </td>

                        {/* Target Screen Badge */}
                        <td>
                          {p.targetScreen === 'home' && (
                            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#eff6ff', color: '#1d4ed8', border: '1px solid #bfdbfe', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                              <Home size={12} />
                              Home Screen
                            </span>
                          )}
                          {p.targetScreen === 'food' && (
                            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#fff7ed', color: '#c2410c', border: '1px solid #fed7aa', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                              <UtensilsCrossed size={12} />
                              Food Order Now
                            </span>
                          )}
                          {p.targetScreen === 'both' && (
                            <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: '#f5f3ff', color: '#6d28d9', border: '1px solid #ddd6fe', padding: '3px 8px', borderRadius: '6px', fontSize: '11px', fontWeight: 700 }}>
                              <Sparkles size={12} />
                              Both Screens
                            </span>
                          )}
                        </td>

                        {/* Destination Action */}
                        <td>
                          {p.destinationType === 'none' && (
                            <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Display Only</span>
                          )}
                          {p.destinationType === 'food_screen' && (
                            <span style={{ fontSize: '12px', color: '#c2410c', fontWeight: 600 }}>→ Food Screen</span>
                          )}
                          {p.destinationType === 'restaurant' && (
                            <span style={{ fontSize: '12px', color: '#15803d', fontWeight: 600 }}>→ Restaurant: {p.destinationId || 'Partner'}</span>
                          )}
                          {p.destinationType === 'membership' && (
                            <span style={{ fontSize: '12px', color: '#7c3aed', fontWeight: 600 }}>→ Food Pass</span>
                          )}
                          {p.destinationType === 'external_url' && (
                            <a
                              href={p.destinationUrl}
                              target="_blank"
                              rel="noreferrer"
                              style={{ fontSize: '12px', color: '#2563eb', fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: '3px' }}
                            >
                              <span>External Link</span>
                              <ExternalLink size={11} />
                            </a>
                          )}
                        </td>

                        {/* Schedule & Dates */}
                        <td>
                          <div style={{ fontSize: '12px', color: 'var(--text-main)', display: 'flex', alignItems: 'center', gap: '4px' }}>
                            <Calendar size={12} color="#64748b" />
                            <span>{new Date(p.startAt).toLocaleDateString('en-IN')}</span>
                          </div>
                          <div style={{ fontSize: '11px', color: p.endAt ? 'var(--text-muted)' : '#059669', marginTop: '2px' }}>
                            {p.endAt ? `Until ${new Date(p.endAt).toLocaleDateString('en-IN')}` : 'Always Active (No expiry)'}
                          </div>
                        </td>

                        {/* Views & Clicks */}
                        <td style={{ textAlign: 'center' }}>
                          <div style={{ fontSize: '13px', fontWeight: 800, color: 'var(--text-main)' }}>
                            {(p.impressionsCount || 0).toLocaleString('en-IN')} views
                          </div>
                          <div style={{ fontSize: '11px', color: '#ea580c', fontWeight: 700, marginTop: '2px' }}>
                            {(p.clicksCount || 0).toLocaleString('en-IN')} clicks
                          </div>
                        </td>

                        {/* Status Toggle */}
                        <td style={{ textAlign: 'center' }}>
                          {(() => {
                            const st = getPromotionStatus(p);
                            return (
                              <button
                                onClick={() => handleToggleStatus(p)}
                                title="Click to toggle status"
                                style={{
                                  padding: '4px 10px',
                                  borderRadius: '20px',
                                  border: 'none',
                                  fontSize: '11px',
                                  fontWeight: 800,
                                  cursor: 'pointer',
                                  backgroundColor: st.bg,
                                  color: st.color,
                                  display: 'inline-flex',
                                  alignItems: 'center',
                                  gap: '4px'
                                }}
                              >
                                <span style={{ width: '6px', height: '6px', borderRadius: '50%', backgroundColor: st.dot }}></span>
                                {st.label}
                              </button>
                            );
                          })()}
                        </td>

                        {/* Action Buttons */}
                        <td style={{ textAlign: 'right' }}>
                          <div style={{ display: 'flex', gap: '6px', justifyContent: 'flex-end' }}>
                            <button
                              className="btn btn-sm btn-secondary"
                              onClick={() => { setPreviewPromotion(p); setPreviewScreenContext(p.targetScreen === 'food' ? 'food' : 'home'); }}
                              title="Live Mobile Preview"
                              style={{ padding: '6px 8px' }}
                            >
                              <Eye size={13} />
                            </button>

                            <button
                              className="btn btn-sm btn-secondary"
                              onClick={() => handleOpenEditModal(p)}
                              title="Edit Promotion"
                              style={{ padding: '6px 8px' }}
                            >
                              <Edit2 size={13} />
                            </button>

                            <button
                              className="btn btn-sm btn-danger"
                              onClick={() => setDeletingPromotion(p)}
                              title="Delete Promotion"
                              style={{ padding: '6px 8px' }}
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
        </>
      )}

      {/* ======================================================== */}
      {/* SECTION 2: PROMO & COUPON CODES */}
      {/* ======================================================== */}
      {activeTab === 'coupons' && (
        <>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
            <div>
              <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>Ride & Delivery Promo Codes</h3>
              <p style={{ margin: '2px 0 0 0', fontSize: '13px', color: 'var(--text-muted)' }}>Configure coupon discounts applicable to StayDriv Bike, Auto, Car, Parcel & Delivery rides.</p>
            </div>
            <button className="btn btn-primary" onClick={() => setShowCouponModal(true)}>
              <Plus size={16} />
              <span>Create Coupon</span>
            </button>
          </div>

          <div className="table-wrapper">
            <table>
              <thead>
                <tr>
                  <th>Campaign Code</th>
                  <th>Discount Percentage</th>
                  <th>Limits (Min Booking / Max Discount)</th>
                  <th>Expiry Date</th>
                  <th>Usage Count</th>
                  <th>Status</th>
                  <th style={{ textAlign: 'right' }}>Actions</th>
                </tr>
              </thead>
              <tbody>
                {promoCodes.map(promo => (
                  <tr key={promo.code}>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                        <Tag size={16} style={{ color: 'var(--primary)' }} />
                        <span style={{ fontWeight: 700, fontFamily: 'monospace', fontSize: '15px' }}>{promo.code}</span>
                      </div>
                    </td>
                    <td style={{ fontWeight: 600 }}>{promo.discountPercentage}% OFF</td>
                    <td>
                      <div>Min Ride: ₹{promo.minBookingValue}</div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Max Discount: ₹{promo.maxDiscount}</div>
                    </td>
                    <td>{new Date(promo.expiryDate).toLocaleDateString('en-IN')}</td>
                    <td style={{ fontWeight: 700 }}>{promo.usageCount} times</td>
                    <td>
                      <span className={`badge ${promo.status === 'active' ? 'badge-active' : 'badge-suspended'}`}>
                        {promo.status}
                      </span>
                    </td>
                    <td style={{ textAlign: 'right' }}>
                      <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                        <button 
                          className={`btn btn-sm ${promo.status === 'active' ? 'btn-danger' : 'btn-success'}`}
                          onClick={() => togglePromoCode(promo.code)}
                        >
                          {promo.status === 'active' ? 'Deactivate' : 'Activate'}
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {/* ======================================================== */}
      {/* MODAL 1: UPLOAD / EDIT PROMOTION */}
      {/* ======================================================== */}
      {isUploadModalOpen && (
        <div className="modal-overlay" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1050 }}>
          <div className="modal-content" style={{ maxWidth: '640px', width: '92%', maxHeight: '90vh', overflowY: 'auto' }}>
            <div className="modal-header" style={{ padding: '16px 20px', borderBottom: '1px solid var(--border-color, #e2e8f0)' }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 800 }}>
                  {editingPromotion ? 'Edit Promotion Banner' : 'Upload New Promotion Banner'}
                </h3>
                <p style={{ margin: '2px 0 0 0', fontSize: '12px', color: 'var(--text-muted)' }}>
                  Set up posters, GIF animations, or video ads for StayDriv Customer screens.
                </p>
              </div>
              <button 
                className="btn btn-secondary btn-icon" 
                onClick={() => setIsUploadModalOpen(false)}
                style={{ width: '32px', height: '32px' }}
              >
                <X size={15} />
              </button>
            </div>

            <form onSubmit={handleSavePromotion}>
              <div className="modal-body" style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: '16px' }}>
                {uploadError && (
                  <div style={{ padding: '10px 14px', borderRadius: '8px', background: '#fef2f2', border: '1px solid #fecaca', color: '#b91c1c', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <AlertTriangle size={16} />
                    <span>{uploadError}</span>
                  </div>
                )}

                {/* Section A: Media Upload or URL */}
                <div style={{ background: '#f8fafc', padding: '14px', borderRadius: '10px', border: '1px solid #e2e8f0' }}>
                  <label style={{ display: 'block', fontSize: '13px', fontWeight: 700, marginBottom: '8px', color: 'var(--text-main)' }}>
                    Promotion Media (Image, GIF, or Video) <span style={{ color: '#ef4444' }}>*</span>
                  </label>

                  {/* File Upload Box */}
                  <div style={{ border: '2px dashed #cbd5e1', borderRadius: '8px', padding: '16px', textAlign: 'center', background: '#ffffff', marginBottom: '10px' }}>
                    <input
                      type="file"
                      id="promoMediaFileInput"
                      accept=".jpg,.jpeg,.png,.webp,.gif,.mp4"
                      onChange={handleFileChange}
                      style={{ display: 'none' }}
                    />
                    <label htmlFor="promoMediaFileInput" style={{ cursor: 'pointer', display: 'inline-block' }}>
                      <Upload size={28} color="var(--primary)" style={{ margin: '0 auto 6px auto', display: 'block' }} />
                      <span style={{ fontSize: '13px', fontWeight: 700, color: 'var(--primary)' }}>
                        {uploadFile ? uploadFile.name : 'Click to Browse File or Drag & Drop'}
                      </span>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                        Supports JPG, PNG, WebP, animated GIF, and MP4 video (max 25MB).
                      </div>
                    </label>
                  </div>

                  {/* OR Media URL */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginTop: '6px' }}>
                    <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>OR URL:</span>
                    <input
                      type="url"
                      placeholder="https://dk60tgl9yds4p.cloudfront.net/uploads/poster.jpg"
                      value={formMediaUrl}
                      onChange={(e) => {
                        setFormMediaUrl(e.target.value);
                        setUploadPreview(e.target.value);
                      }}
                      style={{
                        flex: 1,
                        padding: '7px 10px',
                        borderRadius: '6px',
                        border: '1px solid #cbd5e1',
                        fontSize: '12px'
                      }}
                    />
                  </div>

                  {/* Live Media Preview Box */}
                  {uploadPreview && (
                    <div style={{ marginTop: '12px', padding: '8px', background: '#0f172a', borderRadius: '8px', textAlign: 'center' }}>
                      <div style={{ fontSize: '11px', color: '#94a3b8', marginBottom: '4px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <span>Media Live Preview</span>
                        <span style={{ textTransform: 'uppercase', fontWeight: 700, color: '#38bdf8' }}>{formMediaType}</span>
                      </div>
                      {formMediaType === 'video' ? (
                        <video
                          src={uploadPreview}
                          controls
                          muted
                          style={{ maxWidth: '100%', maxHeight: '180px', borderRadius: '6px' }}
                        />
                      ) : (
                        <img
                          src={uploadPreview}
                          alt="Banner Preview"
                          style={{ maxWidth: '100%', maxHeight: '180px', objectFit: 'contain', borderRadius: '6px' }}
                          onError={() => setUploadError('Could not load image from provided URL.')}
                        />
                      )}
                    </div>
                  )}
                </div>

                {/* Section B: Promotion Title & Description */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                  <div className="form-group">
                    <label style={{ fontSize: '13px', fontWeight: 700 }}>
                      Promotion Title <span style={{ color: '#ef4444' }}>*</span>
                    </label>
                    <input
                      type="text"
                      placeholder="e.g. Grand Festive Feast, Dussehra Special"
                      value={formTitle}
                      onChange={(e) => setFormTitle(e.target.value)}
                      required
                      style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div className="form-group">
                    <label style={{ fontSize: '13px', fontWeight: 700 }}>
                      Offer / Discount Text (Zomato-Style Bold Banner Text)
                    </label>
                    <input
                      type="text"
                      placeholder="e.g. ₹150 OFF & MORE, Flat 50% Off, Free Delivery"
                      value={formOfferText}
                      onChange={(e) => setFormOfferText(e.target.value)}
                      style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px', fontWeight: 700, color: '#b91c1c' }}
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: '12px' }}>
                  <div className="form-group">
                    <label style={{ fontSize: '13px', fontWeight: 700 }}>
                      Description / Subtitle (Optional)
                    </label>
                    <input
                      type="text"
                      placeholder="e.g. Valid on all restaurant orders above ₹149. Limited time offer."
                      value={formDescription}
                      onChange={(e) => setFormDescription(e.target.value)}
                      style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>

                  <div className="form-group">
                    <label style={{ fontSize: '13px', fontWeight: 700 }}>
                      CTA Button Label
                    </label>
                    <input
                      type="text"
                      placeholder="e.g. Order now, Book now"
                      value={formButtonLabel}
                      onChange={(e) => setFormButtonLabel(e.target.value)}
                      style={{ width: '100%', padding: '9px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px' }}
                    />
                  </div>
                </div>

                {/* Section C: Target Screen Selector */}
                <div className="form-group">
                  <label style={{ fontSize: '13px', fontWeight: 700, marginBottom: '6px', display: 'block' }}>
                    Target Customer Screen <span style={{ color: '#ef4444' }}>*</span>
                  </label>
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '10px' }}>
                    <div
                      onClick={() => setFormTargetScreen('home')}
                      style={{
                        padding: '10px',
                        borderRadius: '8px',
                        border: formTargetScreen === 'home' ? '2px solid #2563eb' : '1px solid #cbd5e1',
                        background: formTargetScreen === 'home' ? '#eff6ff' : '#fff',
                        cursor: 'pointer',
                        textAlign: 'center'
                      }}
                    >
                      <Home size={18} color="#2563eb" style={{ margin: '0 auto 4px auto', display: 'block' }} />
                      <div style={{ fontSize: '12px', fontWeight: 700, color: '#1e3a8a' }}>Home Screen</div>
                      <div style={{ fontSize: '10px', color: '#64748b' }}>Above Ride Cards</div>
                    </div>

                    <div
                      onClick={() => setFormTargetScreen('food')}
                      style={{
                        padding: '10px',
                        borderRadius: '8px',
                        border: formTargetScreen === 'food' ? '2px solid #ea580c' : '1px solid #cbd5e1',
                        background: formTargetScreen === 'food' ? '#fff7ed' : '#fff',
                        cursor: 'pointer',
                        textAlign: 'center'
                      }}
                    >
                      <UtensilsCrossed size={18} color="#ea580c" style={{ margin: '0 auto 4px auto', display: 'block' }} />
                      <div style={{ fontSize: '12px', fontWeight: 700, color: '#9a3412' }}>Food Order Now</div>
                      <div style={{ fontSize: '10px', color: '#64748b' }}>Above Categories</div>
                    </div>

                    <div
                      onClick={() => setFormTargetScreen('both')}
                      style={{
                        padding: '10px',
                        borderRadius: '8px',
                        border: formTargetScreen === 'both' ? '2px solid #7c3aed' : '1px solid #cbd5e1',
                        background: formTargetScreen === 'both' ? '#f5f3ff' : '#fff',
                        cursor: 'pointer',
                        textAlign: 'center'
                      }}
                    >
                      <Sparkles size={18} color="#7c3aed" style={{ margin: '0 auto 4px auto', display: 'block' }} />
                      <div style={{ fontSize: '12px', fontWeight: 700, color: '#5b21b6' }}>Both Screens</div>
                      <div style={{ fontSize: '10px', color: '#64748b' }}>Platform Global</div>
                    </div>
                  </div>
                </div>

                {/* Section D: Click Action Destination */}
                <div style={{ background: '#f8fafc', padding: '14px', borderRadius: '10px', border: '1px solid #e2e8f0' }}>
                  <label style={{ display: 'block', fontSize: '13px', fontWeight: 700, marginBottom: '6px' }}>
                    Click Destination Action
                  </label>
                  <select
                    value={formDestType}
                    onChange={(e) => setFormDestType(e.target.value as any)}
                    style={{ width: '100%', padding: '8px 10px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '13px', marginBottom: '8px' }}
                  >
                    <option value="none">No Action (Non-clickable poster / routine display)</option>
                    <option value="food_screen">Navigate to Food Order Now Screen</option>
                    <option value="restaurant">Navigate to Specific Restaurant</option>
                    <option value="membership">Navigate to Food Membership Pass Page</option>
                    <option value="ride_screen">Navigate to Ride Booking Screen (Bike / Auto / Car)</option>
                    <option value="parcel_screen">Navigate to Parcel Booking Screen</option>
                    <option value="external_url">Open External Approved Web Link</option>
                  </select>

                  {formDestType === 'restaurant' && (
                    <input
                      type="text"
                      placeholder="Enter Restaurant ID or Name"
                      value={formDestId}
                      onChange={(e) => setFormDestId(e.target.value)}
                      style={{ width: '100%', padding: '7px 10px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '12px' }}
                    />
                  )}

                  {formDestType === 'external_url' && (
                    <input
                      type="url"
                      placeholder="https://staydriv.com/offers"
                      value={formDestUrl}
                      onChange={(e) => setFormDestUrl(e.target.value)}
                      style={{ width: '100%', padding: '7px 10px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '12px' }}
                    />
                  )}
                </div>

                {/* Live Zomato Banner Preview Box in Form */}
                <div style={{ background: '#f8fafc', padding: '14px', borderRadius: '12px', border: '1px solid #e2e8f0' }}>
                  <div style={{ fontSize: '12px', fontWeight: 800, marginBottom: '8px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                    <span style={{ color: '#0f172a' }}>Live Customer App Banner Preview (Zomato Style)</span>
                    <span style={{ fontSize: '11px', color: '#64748b' }}>Target: {formTargetScreen === 'both' ? 'Home & Food' : formTargetScreen === 'food' ? 'Food Order Now' : 'Home'}</span>
                  </div>

                  <div style={{
                    position: 'relative',
                    height: '168px',
                    borderRadius: '18px',
                    overflow: 'hidden',
                    boxShadow: '0 4px 14px rgba(0,0,0,0.12)',
                    background: '#1e293b'
                  }}>
                    {uploadPreview ? (
                      formMediaType === 'video' ? (
                        <video src={uploadPreview} style={{ width: '100%', height: '100%', objectFit: 'cover' }} muted loop autoPlay />
                      ) : (
                        <img src={uploadPreview} alt="Preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      )
                    ) : (
                      <div style={{ width: '100%', height: '100%', background: 'linear-gradient(135deg, #1e40af, #3b82f6)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: '13px' }}>
                        Upload artwork or enter URL to preview
                      </div>
                    )}

                    {/* Gradient Overlay */}
                    <div style={{
                      position: 'absolute',
                      inset: 0,
                      background: 'linear-gradient(to bottom, transparent 35%, rgba(0,0,0,0.75) 100%)'
                    }} />

                    {/* Media Type Badge */}
                    {(formMediaType === 'video' || formMediaType === 'gif') && (
                      <div style={{
                        position: 'absolute',
                        top: '10px',
                        right: '10px',
                        background: formMediaType === 'video' ? '#ef4444' : '#7c3aed',
                        color: '#fff',
                        fontSize: '10px',
                        fontWeight: 900,
                        padding: '3px 8px',
                        borderRadius: '6px',
                        boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
                      }}>
                        {formMediaType.toUpperCase()}
                      </div>
                    )}

                    {/* Content & CTA */}
                    <div style={{
                      position: 'absolute',
                      bottom: '12px',
                      left: '14px',
                      right: '14px',
                      display: 'flex',
                      alignItems: 'flex-end',
                      justifyContent: 'space-between',
                      gap: '12px'
                    }}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        {formOfferText && (
                          <div style={{ color: '#ffe4e6', fontWeight: 900, fontSize: '16px', letterSpacing: '-0.3px', textShadow: '0 2px 4px rgba(0,0,0,0.8)' }}>
                            {formOfferText}
                          </div>
                        )}
                        <div style={{ color: '#fff', fontWeight: 800, fontSize: formOfferText ? '12px' : '14px', textShadow: '0 2px 4px rgba(0,0,0,0.8)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                          {formTitle || 'Promotion Title'}
                        </div>
                        {formDescription && (
                          <div style={{ color: 'rgba(255,255,255,0.9)', fontSize: '10.5px', textShadow: '0 1px 3px rgba(0,0,0,0.8)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {formDescription}
                          </div>
                        )}
                      </div>

                      {(formButtonLabel || formDestType !== 'none') && (
                        <div style={{
                          background: 'rgba(0,0,0,0.85)',
                          color: '#fff',
                          borderRadius: '20px',
                          padding: '6px 12px',
                          border: '1px solid rgba(255,255,255,0.25)',
                          fontSize: '11px',
                          fontWeight: 800,
                          whiteSpace: 'nowrap',
                          display: 'flex',
                          alignItems: 'center',
                          gap: '4px',
                          boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
                        }}>
                          <span>{formButtonLabel || (formTargetScreen === 'food' ? 'Order now' : 'Book now')}</span>
                          <span style={{ fontSize: '9px' }}>›</span>
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {/* Section E: Dates & Priority */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '12px' }}>
                  <div className="form-group">
                    <label style={{ fontSize: '12px', fontWeight: 700 }}>Start Date</label>
                    <input
                      type="date"
                      value={formStartAt}
                      onChange={(e) => setFormStartAt(e.target.value)}
                      style={{ width: '100%', padding: '7px 8px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '12px' }}
                    />
                  </div>

                  <div className="form-group">
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <label style={{ fontSize: '12px', fontWeight: 700 }}>End Date</label>
                      <label style={{ fontSize: '10px', color: 'var(--text-muted)', cursor: 'pointer' }}>
                        <input
                          type="checkbox"
                          checked={formNoExpiry}
                          onChange={(e) => setFormNoExpiry(e.target.checked)}
                          style={{ marginRight: '3px' }}
                        />
                        Ongoing
                      </label>
                    </div>
                    <input
                      type="date"
                      value={formEndAt}
                      onChange={(e) => {
                        setFormEndAt(e.target.value);
                        setFormNoExpiry(false);
                      }}
                      disabled={formNoExpiry}
                      style={{ width: '100%', padding: '7px 8px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '12px', opacity: formNoExpiry ? 0.4 : 1 }}
                    />
                  </div>

                  <div className="form-group">
                    <label style={{ fontSize: '12px', fontWeight: 700 }}>Display Priority (0 = Top)</label>
                    <input
                      type="number"
                      min="0"
                      max="100"
                      value={formDisplayOrder}
                      onChange={(e) => setFormDisplayOrder(parseInt(e.target.value) || 0)}
                      style={{ width: '100%', padding: '7px 8px', borderRadius: '6px', border: '1px solid #cbd5e1', fontSize: '12px' }}
                    />
                  </div>
                </div>

                {/* Status Toggle */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', paddingTop: '4px' }}>
                  <input
                    type="checkbox"
                    id="formIsActiveCheckbox"
                    checked={formIsActive}
                    onChange={(e) => setFormIsActive(e.target.checked)}
                    style={{ width: '16px', height: '16px', cursor: 'pointer' }}
                  />
                  <label htmlFor="formIsActiveCheckbox" style={{ fontSize: '13px', fontWeight: 700, cursor: 'pointer' }}>
                    Publish as Active (Visible immediately in Customer App)
                  </label>
                </div>
              </div>

              <div className="modal-footer" style={{ padding: '14px 20px', borderTop: '1px solid var(--border-color, #e2e8f0)', display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setIsUploadModalOpen(false)}
                  disabled={isSubmitting}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="btn btn-primary"
                  disabled={isSubmitting}
                  style={{ display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 700 }}
                >
                  {isSubmitting ? (
                    <>
                      <RefreshCw size={14} className="spin" />
                      <span>Saving...</span>
                    </>
                  ) : (
                    <>
                      <Check size={16} />
                      <span>{editingPromotion ? 'Update Promotion' : 'Publish Promotion'}</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ======================================================== */}
      {/* MODAL 2: LIVE MOBILE PHONE SCREEN PREVIEW */}
      {/* ======================================================== */}
      {previewPromotion && (
        <div className="modal-overlay" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1060 }}>
          <div className="modal-content" style={{ maxWidth: '420px', width: '92%', borderRadius: '24px', overflow: 'hidden', padding: 0, border: '4px solid #1e293b', boxShadow: '0 25px 50px -12px rgba(0,0,0,0.35)' }}>
            {/* Phone Top Notch */}
            <div style={{ background: '#0f172a', padding: '10px 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#fff' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                <Smartphone size={14} color="#38bdf8" />
                <span style={{ fontSize: '12px', fontWeight: 800 }}>StayDriv Mobile Simulator</span>
              </div>
              <button 
                onClick={() => setPreviewPromotion(null)}
                style={{ background: 'transparent', border: 'none', color: '#94a3b8', cursor: 'pointer' }}
              >
                <X size={16} />
              </button>
            </div>

            {/* Screen Context Switcher */}
            <div style={{ display: 'flex', background: '#f1f5f9', borderBottom: '1px solid #e2e8f0' }}>
              <button
                onClick={() => setPreviewScreenContext('home')}
                style={{
                  flex: 1,
                  padding: '10px',
                  border: 'none',
                  fontSize: '12px',
                  fontWeight: 800,
                  cursor: 'pointer',
                  background: previewScreenContext === 'home' ? '#ffffff' : 'transparent',
                  color: previewScreenContext === 'home' ? '#2563eb' : '#64748b',
                  borderBottom: previewScreenContext === 'home' ? '2px solid #2563eb' : 'none'
                }}
              >
                Home Screen View
              </button>
              <button
                onClick={() => setPreviewScreenContext('food')}
                style={{
                  flex: 1,
                  padding: '10px',
                  border: 'none',
                  fontSize: '12px',
                  fontWeight: 800,
                  cursor: 'pointer',
                  background: previewScreenContext === 'food' ? '#ffffff' : 'transparent',
                  color: previewScreenContext === 'food' ? '#ea580c' : '#64748b',
                  borderBottom: previewScreenContext === 'food' ? '2px solid #ea580c' : 'none'
                }}
              >
                Food Order Now View
              </button>
            </div>

            {/* Phone Screen Mockup Content */}
            <div style={{ background: '#f8fafc', padding: '16px', maxHeight: '560px', overflowY: 'auto' }}>
              {previewScreenContext === 'home' ? (
                <div>
                  {/* Home Header Mockup */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                    <div style={{ width: '32px', height: '32px', borderRadius: '50%', background: '#dbeafe', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <span style={{ fontSize: '13px' }}>👤</span>
                    </div>
                    <div style={{ fontWeight: 900, fontSize: '18px', color: '#1e40af', letterSpacing: '-0.5px' }}>
                      StayDriv
                    </div>
                    <div style={{ display: 'flex', gap: '8px' }}>
                      <span style={{ fontSize: '14px' }}>🔗</span>
                      <span style={{ fontSize: '14px' }}>🔔</span>
                    </div>
                  </div>

                  {/* PROMOTIONAL CAROUSEL BANNER IN HOME (ZOMATO STYLE) */}
                  <div style={{ marginBottom: '18px' }}>
                    <div style={{
                      position: 'relative',
                      height: '168px',
                      borderRadius: '18px',
                      overflow: 'hidden',
                      boxShadow: '0 4px 14px rgba(0,0,0,0.12)',
                      background: '#1e293b'
                    }}>
                      {previewPromotion.mediaType === 'video' ? (
                        <video
                          src={previewPromotion.mediaUrl}
                          controls
                          autoPlay
                          muted
                          loop
                          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                        />
                      ) : (
                        <img
                          src={previewPromotion.mediaUrl}
                          alt={previewPromotion.title}
                          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                        />
                      )}

                      {/* Gradient Overlay */}
                      <div style={{
                        position: 'absolute',
                        inset: 0,
                        background: 'linear-gradient(to bottom, transparent 35%, rgba(0,0,0,0.75) 100%)'
                      }} />

                      {/* Media Badge */}
                      {(previewPromotion.mediaType === 'video' || previewPromotion.mediaType === 'gif') && (
                        <div style={{
                          position: 'absolute',
                          top: '10px',
                          right: '10px',
                          background: previewPromotion.mediaType === 'video' ? '#ef4444' : '#7c3aed',
                          color: '#fff',
                          fontSize: '10px',
                          fontWeight: 900,
                          padding: '3px 8px',
                          borderRadius: '6px',
                          boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
                        }}>
                          {previewPromotion.mediaType.toUpperCase()}
                        </div>
                      )}

                      {/* Content & CTA */}
                      <div style={{
                        position: 'absolute',
                        bottom: '12px',
                        left: '14px',
                        right: '14px',
                        display: 'flex',
                        alignItems: 'flex-end',
                        justifyContent: 'space-between',
                        gap: '12px'
                      }}>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          {previewPromotion.offerText && (
                            <div style={{ color: '#ffe4e6', fontWeight: 900, fontSize: '16px', letterSpacing: '-0.3px', textShadow: '0 2px 4px rgba(0,0,0,0.8)' }}>
                              {previewPromotion.offerText}
                            </div>
                          )}
                          <div style={{ color: '#fff', fontWeight: 800, fontSize: previewPromotion.offerText ? '12px' : '14px', textShadow: '0 2px 4px rgba(0,0,0,0.8)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {previewPromotion.title}
                          </div>
                          {previewPromotion.description && (
                            <div style={{ color: 'rgba(255,255,255,0.9)', fontSize: '10.5px', textShadow: '0 1px 3px rgba(0,0,0,0.8)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {previewPromotion.description}
                            </div>
                          )}
                        </div>

                        {(previewPromotion.buttonLabel || previewPromotion.destinationType !== 'none') && (
                          <div style={{
                            background: 'rgba(0,0,0,0.85)',
                            color: '#fff',
                            borderRadius: '20px',
                            padding: '6px 12px',
                            border: '1px solid rgba(255,255,255,0.25)',
                            fontSize: '11px',
                            fontWeight: 800,
                            whiteSpace: 'nowrap',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '4px',
                            boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
                          }}>
                            <span>{previewPromotion.buttonLabel || 'Book now'}</span>
                            <span style={{ fontSize: '9px' }}>›</span>
                          </div>
                        )}
                      </div>
                    </div>
                    {/* Carousel Dots Indicator */}
                    <div style={{ display: 'flex', justifyContent: 'center', gap: '5px', marginTop: '8px' }}>
                      <span style={{ width: '20px', height: '6px', borderRadius: '3px', background: '#2563eb' }}></span>
                      <span style={{ width: '6px', height: '6px', borderRadius: '3px', background: '#cbd5e1' }}></span>
                      <span style={{ width: '6px', height: '6px', borderRadius: '3px', background: '#cbd5e1' }}></span>
                    </div>
                  </div>

                  {/* Service Cards Mockup below banner */}
                  <div style={{ fontSize: '13px', fontWeight: 800, color: '#0f172a', marginBottom: '8px' }}>
                    What do you need today?
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', marginBottom: '10px' }}>
                    <div style={{ background: '#ffffff', borderRadius: '12px', padding: '10px', border: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ fontSize: '20px' }}>🏍️</span>
                      <div>
                        <div style={{ fontSize: '12px', fontWeight: 800 }}>Bike Taxi</div>
                        <div style={{ fontSize: '9px', color: '#64748b' }}>Quick commutes</div>
                      </div>
                    </div>
                    <div style={{ background: '#ffffff', borderRadius: '12px', padding: '10px', border: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ fontSize: '20px' }}>🛺</span>
                      <div>
                        <div style={{ fontSize: '12px', fontWeight: 800 }}>Auto</div>
                        <div style={{ fontSize: '9px', color: '#64748b' }}>Fast & local</div>
                      </div>
                    </div>
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px' }}>
                    <div style={{ background: '#ffffff', borderRadius: '12px', padding: '10px', border: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ fontSize: '20px' }}>🚗</span>
                      <div>
                        <div style={{ fontSize: '12px', fontWeight: 800 }}>Car</div>
                        <div style={{ fontSize: '9px', color: '#64748b' }}>Comfortable rides</div>
                      </div>
                    </div>
                    <div style={{ background: '#ffffff', borderRadius: '12px', padding: '10px', border: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{ fontSize: '20px' }}>📦</span>
                      <div>
                        <div style={{ fontSize: '12px', fontWeight: 800 }}>Parcel</div>
                        <div style={{ fontSize: '9px', color: '#64748b' }}>Parcel & cargo</div>
                      </div>
                    </div>
                  </div>
                </div>
              ) : (
                <div>
                  {/* Food Order Now Header & Search Bar Mockup */}
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '10px' }}>
                    <div style={{ fontSize: '12px', fontWeight: 700, color: '#ea580c', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <span>📍 Current Location...</span>
                    </div>
                    <span style={{ fontSize: '13px' }}>🎟️ Food Pass</span>
                  </div>

                  <div style={{ background: '#ffffff', border: '1px solid #e2e8f0', borderRadius: '8px', padding: '8px 12px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '14px' }}>
                    <span style={{ fontSize: '12px', color: '#94a3b8' }}>Search restaurants or food...</span>
                    <span style={{ fontSize: '10px', fontWeight: 800, color: '#16a34a', background: '#dcfce7', padding: '2px 6px', borderRadius: '4px' }}>VEG</span>
                  </div>

                  {/* PROMOTIONAL CAROUSEL BANNER IN FOOD ORDER NOW (ZOMATO STYLE) */}
                  <div style={{ marginBottom: '18px' }}>
                    <div style={{
                      position: 'relative',
                      height: '168px',
                      borderRadius: '18px',
                      overflow: 'hidden',
                      boxShadow: '0 4px 14px rgba(0,0,0,0.12)',
                      background: '#1e293b'
                    }}>
                      {previewPromotion.mediaType === 'video' ? (
                        <video
                          src={previewPromotion.mediaUrl}
                          controls
                          autoPlay
                          muted
                          loop
                          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                        />
                      ) : (
                        <img
                          src={previewPromotion.mediaUrl}
                          alt={previewPromotion.title}
                          style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                        />
                      )}

                      {/* Gradient Overlay */}
                      <div style={{
                        position: 'absolute',
                        inset: 0,
                        background: 'linear-gradient(to bottom, transparent 35%, rgba(0,0,0,0.75) 100%)'
                      }} />

                      {/* Media Badge */}
                      {(previewPromotion.mediaType === 'video' || previewPromotion.mediaType === 'gif') && (
                        <div style={{
                          position: 'absolute',
                          top: '10px',
                          right: '10px',
                          background: previewPromotion.mediaType === 'video' ? '#ef4444' : '#7c3aed',
                          color: '#fff',
                          fontSize: '10px',
                          fontWeight: 900,
                          padding: '3px 8px',
                          borderRadius: '6px',
                          boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
                        }}>
                          {previewPromotion.mediaType.toUpperCase()}
                        </div>
                      )}

                      {/* Content & CTA */}
                      <div style={{
                        position: 'absolute',
                        bottom: '12px',
                        left: '14px',
                        right: '14px',
                        display: 'flex',
                        alignItems: 'flex-end',
                        justifyContent: 'space-between',
                        gap: '12px'
                      }}>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          {previewPromotion.offerText && (
                            <div style={{ color: '#ffe4e6', fontWeight: 900, fontSize: '16px', letterSpacing: '-0.3px', textShadow: '0 2px 4px rgba(0,0,0,0.8)' }}>
                              {previewPromotion.offerText}
                            </div>
                          )}
                          <div style={{ color: '#fff', fontWeight: 800, fontSize: previewPromotion.offerText ? '12px' : '14px', textShadow: '0 2px 4px rgba(0,0,0,0.8)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                            {previewPromotion.title}
                          </div>
                          {previewPromotion.description && (
                            <div style={{ color: 'rgba(255,255,255,0.9)', fontSize: '10.5px', textShadow: '0 1px 3px rgba(0,0,0,0.8)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                              {previewPromotion.description}
                            </div>
                          )}
                        </div>

                        {(previewPromotion.buttonLabel || previewPromotion.destinationType !== 'none') && (
                          <div style={{
                            background: 'rgba(0,0,0,0.85)',
                            color: '#fff',
                            borderRadius: '20px',
                            padding: '6px 12px',
                            border: '1px solid rgba(255,255,255,0.25)',
                            fontSize: '11px',
                            fontWeight: 800,
                            whiteSpace: 'nowrap',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '4px',
                            boxShadow: '0 2px 6px rgba(0,0,0,0.4)'
                          }}>
                            <span>{previewPromotion.buttonLabel || 'Order now'}</span>
                            <span style={{ fontSize: '9px' }}>›</span>
                          </div>
                        )}
                      </div>
                    </div>
                    {/* Carousel Dots */}
                    <div style={{ display: 'flex', justifyContent: 'center', gap: '5px', marginTop: '8px' }}>
                      <span style={{ width: '20px', height: '6px', borderRadius: '3px', background: '#ea580c' }}></span>
                      <span style={{ width: '6px', height: '6px', borderRadius: '3px', background: '#cbd5e1' }}></span>
                      <span style={{ width: '6px', height: '6px', borderRadius: '3px', background: '#cbd5e1' }}></span>
                    </div>
                  </div>

                  {/* Food Categories Mockup below banner */}
                  <div style={{ fontSize: '13px', fontWeight: 800, color: '#0f172a', marginBottom: '8px' }}>
                    What would you like to eat?
                  </div>
                  <div style={{ display: 'flex', gap: '8px', overflowX: 'auto', paddingBottom: '6px' }}>
                    {['All', 'Biryani', 'South Indian', 'Pizza', 'Burger'].map((cat, i) => (
                      <div key={cat} style={{ textAlign: 'center', flexShrink: 0 }}>
                        <div style={{ width: '48px', height: '48px', borderRadius: '50%', background: i === 0 ? '#ea580c' : '#ffffff', border: '1px solid #e2e8f0', display: 'flex', alignItems: 'center', justifyContent: 'center', color: i === 0 ? '#fff' : '#0f172a', fontSize: '18px' }}>
                          {i === 0 ? '🍴' : i === 1 ? '🍛' : i === 2 ? '🥞' : i === 3 ? '🍕' : '🍔'}
                        </div>
                        <div style={{ fontSize: '10px', marginTop: '4px', fontWeight: 700, color: i === 0 ? '#ea580c' : '#475569' }}>{cat}</div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div style={{ background: '#f1f5f9', padding: '12px 16px', display: 'flex', justifyContent: 'flex-end', borderTop: '1px solid #e2e8f0' }}>
              <button className="btn btn-secondary" onClick={() => setPreviewPromotion(null)}>
                Close Preview
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ======================================================== */}
      {/* MODAL 3: DELETE CONFIRMATION */}
      {/* ======================================================== */}
      {deletingPromotion && (
        <div className="modal-overlay" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1070 }}>
          <div className="modal-content" style={{ maxWidth: '420px', width: '90%', padding: '24px' }}>
            <div style={{ textAlign: 'center', marginBottom: '16px' }}>
              <div style={{ width: '48px', height: '48px', borderRadius: '50%', background: '#fee2e2', color: '#ef4444', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 12px auto' }}>
                <Trash2 size={24} />
              </div>
              <h3 style={{ margin: '0 0 6px 0', fontSize: '18px', fontWeight: 800 }}>Delete Promotion?</h3>
              <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)' }}>
                Are you sure you want to delete <strong>"{deletingPromotion.title}"</strong>?
              </p>
              <div style={{ marginTop: '10px', padding: '8px 12px', background: '#f8fafc', borderRadius: '6px', fontSize: '11px', color: '#64748b', textAlign: 'left' }}>
                ℹ️ <strong>Audit Note:</strong> A soft deletion will be performed so that historical impressions ({deletingPromotion.impressionsCount || 0}) and click logs are preserved for audits. The banner will immediately disappear from the Customer App.
              </div>
            </div>

            <div style={{ display: 'flex', gap: '10px', justifyContent: 'flex-end', marginTop: '16px' }}>
              <button className="btn btn-secondary" onClick={() => setDeletingPromotion(null)}>
                Cancel
              </button>
              <button className="btn btn-danger" onClick={handleConfirmDelete}>
                Delete Banner
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ======================================================== */}
      {/* MODAL 4: CREATE COUPON CODE */}
      {/* ======================================================== */}
      {showCouponModal && (
        <div className="modal-overlay">
          <div className="modal-content" style={{ maxWidth: '480px' }}>
            <div className="modal-header">
              <h3 style={{ fontSize: '18px' }}>Create New Promo Code</h3>
              <button 
                className="btn btn-secondary btn-icon" 
                onClick={() => setShowCouponModal(false)}
                style={{ width: '32px', height: '32px' }}
              >
                <X size={14} />
              </button>
            </div>
            <form onSubmit={handleCouponSubmit}>
              <div className="modal-body">
                <div className="form-group">
                  <label>Coupon Code Name</label>
                  <input 
                    type="text" 
                    placeholder="e.g. STAYDRIV50" 
                    value={couponCode}
                    onChange={(e) => setCouponCode(e.target.value.toUpperCase())}
                    required
                  />
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                  <div className="form-group">
                    <label>Discount Percentage (%)</label>
                    <input 
                      type="number" 
                      min="5" 
                      max="100" 
                      value={discountPercent}
                      onChange={(e) => setDiscountPercent(parseInt(e.target.value))}
                      required
                    />
                  </div>
                  <div className="form-group">
                    <label>Max Cap Discount (₹)</label>
                    <input 
                      type="number" 
                      min="10" 
                      value={maxDiscount}
                      onChange={(e) => setMaxDiscount(parseInt(e.target.value))}
                      required
                    />
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                  <div className="form-group">
                    <label>Min Ride Value (₹)</label>
                    <input 
                      type="number" 
                      min="0" 
                      value={minBooking}
                      onChange={(e) => setMinBooking(parseInt(e.target.value))}
                      required
                    />
                  </div>
                  <div className="form-group">
                    <label>Expiry Date</label>
                    <input 
                      type="date" 
                      value={couponExpiry}
                      onChange={(e) => setCouponExpiry(e.target.value)}
                      required
                    />
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-secondary" onClick={() => setShowCouponModal(false)}>Cancel</button>
                <button type="submit" className="btn btn-primary">Publish Coupon</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};

export default Promos;
