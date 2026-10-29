import React, { useState, useEffect } from 'react';
import {
  UtensilsCrossed, Sparkles, Plus, Edit2, Edit3, Trash2, CheckCircle2,
  XCircle, Search, Download, RefreshCw, Eye, ShieldCheck, Menu,
  TrendingUp, Users, DollarSign, Tag, Clock, ArrowRight, X, AlertTriangle, ToggleLeft, ToggleRight
} from 'lucide-react';

interface Benefit {
  benefitId: string;
  title: string;
  description: string;
  icon: string;
  type: 'discount_percentage' | 'fixed_discount' | 'free_delivery' | 'restaurant_special';
  value: number;
  minimumOrderValue: number;
  maxDiscountLimit: number;
  fundedBy: 'staydriv' | 'restaurant' | 'split';
  staydrivSharePercent: number;
  restaurantSharePercent: number;
  isEnabled: boolean;
  eligibleRestaurantIds?: string[];
}

interface Plan {
  planId: string;
  planType: 'monthly' | 'quarterly' | 'platinum';
  name: string;
  tagline: string;
  description: string;
  price: number;
  originalPrice: number;
  validityDays: number;
  validityMonths: number;
  minOrderAmount?: number;
  deliveryRadiusKm?: number;
  maxDiscountPercent?: number;
  participatingRestaurantIds?: string[];
  excludedRestaurantIds?: string[];
  version: number;
  isActive: boolean;
  isPublished: boolean;
  draftPrice?: number;
  draftOriginalPrice?: number;
  isArchived?: boolean;
  benefits: Benefit[];
  termsAndConditions: string[];
}

interface Subscription {
  membershipId: string;
  customerId: string;
  customerName: string;
  customerPhone: string;
  planId: string;
  planType: 'monthly' | 'quarterly' | 'platinum';
  planName: string;
  pricePaid: number;
  status: 'active' | 'expired' | 'cancelled' | 'pending';
  startDate: string;
  endDate: string;
  paymentStatus: string;
  paymentMethod?: string;
  transactionId: string;
  gatewayOrderId?: string;
  gatewayPaymentId?: string;
  totalDiscountAvailed: number;
  ordersCount: number;
  createdAt: string;
}

interface PartnerRestaurant {
  restaurantId: string;
  name: string;
  address?: string;
  rating?: number;
  isMembershipEnrolled?: boolean;
  membershipDiscountPercent?: number;
  membershipFundingType?: string;
}

export const FoodMembershipManagement: React.FC = () => {
  const [activeTab, setActiveTab] = useState<'plans' | 'subscribers' | 'restaurants' | 'analytics' | 'audit' | 'transactions'>('plans');

  // Plan management state
  const [plans, setPlans] = useState<Plan[]>([]);
  const [loadingPlans, setLoadingPlans] = useState(false);
  const [editingPlan, setEditingPlan] = useState<Plan | null>(null);

  // Benefit modal state
  const [selectedPlanIdForBenefit, setSelectedPlanIdForBenefit] = useState<string | null>(null);
  const [editingBenefit, setEditingBenefit] = useState<Benefit | null>(null);
  const [isBenefitModalOpen, setIsBenefitModalOpen] = useState(false);
  const [benefitForm, setBenefitForm] = useState<Partial<Benefit>>({
    title: '',
    description: '',
    type: 'discount_percentage',
    value: 20,
    minimumOrderValue: 199,
    maxDiscountLimit: 100,
    fundedBy: 'staydriv',
    staydrivSharePercent: 100,
    restaurantSharePercent: 0,
    isEnabled: true
  });

  // Preview modal state
  const [isPreviewModalOpen, setIsPreviewModalOpen] = useState(false);
  const [previewPlanType, setPreviewPlanType] = useState<'monthly' | 'quarterly'>('monthly');

  // Subscribed customers state
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [loadingSubs, setLoadingSubs] = useState(false);
  const [subStatusFilter, setSubStatusFilter] = useState('all');
  const [subPlanFilter, setSubPlanFilter] = useState('all');
  const [subSearchQuery, setSubSearchQuery] = useState('');
  const [selectedSubForCancel, setSelectedSubForCancel] = useState<Subscription | null>(null);
  const [cancelReason, setCancelReason] = useState('');
  const [refundAmount, setRefundAmount] = useState('0');

  // Payment Transactions & Gateway logs state
  const [transactions, setTransactions] = useState<any[]>([]);
  const [loadingTxns, setLoadingTxns] = useState(false);
  const [txnStatusFilter, setTxnStatusFilter] = useState('all');
  const [txnSearchQuery, setTxnSearchQuery] = useState('');

  // Analytics & Audit states
  const [analytics, setAnalytics] = useState<any>(null);
  const [auditLogs, setAuditLogs] = useState<any[]>([]);
  const [loadingAudit, setLoadingAudit] = useState(false);

  // Plan details view modal state
  const [selectedPlanDetails, setSelectedPlanDetails] = useState<any | null>(null);
  const [isDetailsModalOpen, setIsDetailsModalOpen] = useState(false);

  // Publish state
  const [isPublishing, setIsPublishing] = useState(false);
  const [publishSuccessMsg, setPublishSuccessMsg] = useState('');

  // Partner restaurants state
  const [restaurants, setRestaurants] = useState<PartnerRestaurant[]>([]);
  const [loadingRestaurants, setLoadingRestaurants] = useState(false);
  const [restaurantSearch, setRestaurantSearch] = useState('');

  useEffect(() => {
    fetchPlans();
    fetchAnalytics();
    fetchTransactions();
  }, []);

  useEffect(() => {
    if (activeTab === 'subscribers') {
      fetchSubscriptions();
    } else if (activeTab === 'audit') {
      fetchAuditLogs();
    } else if (activeTab === 'restaurants') {
      fetchRestaurants();
    } else if (activeTab === 'transactions') {
      fetchTransactions();
    }
  }, [activeTab, subStatusFilter, subPlanFilter, txnStatusFilter]);

  const fetchTransactions = async () => {
    setLoadingTxns(true);
    try {
      const params = new URLSearchParams();
      if (txnStatusFilter !== 'all') params.append('status', txnStatusFilter);
      if (txnSearchQuery) params.append('search', txnSearchQuery);
      const res = await fetch(`/api/food/membership/admin/transactions?${params.toString()}`);
      const data = await res.json();
      if (data.success && data.transactions) {
        setTransactions(data.transactions);
      }
    } catch (err) {
      console.error('Failed to load transactions:', err);
    } finally {
      setLoadingTxns(false);
    }
  };

  const fetchRestaurants = async () => {
    setLoadingRestaurants(true);
    try {
      const res = await fetch('/api/food/membership/admin/restaurants');
      const data = await res.json();
      if (data.success && data.restaurants) {
        setRestaurants(data.restaurants);
      }
    } catch (err) {
      console.error('Failed to load restaurants:', err);
    } finally {
      setLoadingRestaurants(false);
    }
  };

  const handleToggleRestaurantEnrollment = async (rest: PartnerRestaurant) => {
    try {
      const nextStatus = !rest.isMembershipEnrolled;
      const res = await fetch(`/api/food/membership/admin/restaurants/${rest.restaurantId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isMembershipEnrolled: nextStatus })
      });
      const data = await res.json();
      if (data.success) {
        fetchRestaurants();
      }
    } catch (err) {
      alert('Error updating restaurant: ' + err);
    }
  };

  const handleUpdateRestaurantDiscount = async (restaurantId: string, percent: number) => {
    try {
      const res = await fetch(`/api/food/membership/admin/restaurants/${restaurantId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ membershipDiscountPercent: percent })
      });
      const data = await res.json();
      if (data.success) {
        fetchRestaurants();
      }
    } catch (err) {
      alert('Error updating restaurant discount: ' + err);
    }
  };

  const fetchPlans = async () => {
    setLoadingPlans(true);
    try {
      const res = await fetch('/api/food/membership/admin/plans');
      const data = await res.json();
      if (data.success) {
        setPlans(data.plans || []);
      }
    } catch (err) {
      console.error('Failed to load plans:', err);
    } finally {
      setLoadingPlans(false);
    }
  };

  const fetchSubscriptions = async () => {
    setLoadingSubs(true);
    try {
      const params = new URLSearchParams();
      if (subStatusFilter !== 'all') params.append('status', subStatusFilter);
      if (subPlanFilter !== 'all') params.append('planType', subPlanFilter);
      if (subSearchQuery.trim()) params.append('search', subSearchQuery.trim());

      const res = await fetch(`/api/food/membership/admin/subscriptions?${params.toString()}`);
      const data = await res.json();
      if (data.success) {
        setSubscriptions(data.subscriptions || []);
      }
    } catch (err) {
      console.error('Failed to load subscriptions:', err);
    } finally {
      setLoadingSubs(false);
    }
  };

  const fetchAnalytics = async () => {
    try {
      const res = await fetch('/api/food/membership/admin/analytics');
      const data = await res.json();
      if (data.success) {
        setAnalytics(data.summary);
      }
    } catch (err) {
      console.error('Failed to load analytics:', err);
    }
  };

  const fetchAuditLogs = async () => {
    setLoadingAudit(true);
    try {
      const res = await fetch('/api/food/membership/admin/audit-logs');
      const data = await res.json();
      if (data.success) {
        setAuditLogs(data.logs || []);
      }
    } catch (err) {
      console.error('Failed to load audit logs:', err);
    } finally {
      setLoadingAudit(false);
    }
  };

  const handleSavePlanPrice = async (plan: Plan) => {
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${plan.planId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          price: plan.price,
          originalPrice: plan.originalPrice,
          validityDays: plan.validityDays,
          validityMonths: plan.validityMonths,
          name: plan.name,
          tagline: plan.tagline,
          description: plan.description,
          minOrderAmount: plan.minOrderAmount,
          deliveryRadiusKm: plan.deliveryRadiusKm,
          maxDiscountPercent: plan.maxDiscountPercent
        })
      });
      const data = await res.json();
      if (data.success) {
        setPublishSuccessMsg(`Pricing & rules for ${plan.name} saved! Remember to click "Publish Plans" to deploy live.`);
        setTimeout(() => setPublishSuccessMsg(''), 4000);
        fetchPlans();
        setEditingPlan(null);
      }
    } catch (err) {
      alert('Error updating plan: ' + err);
    }
  };

  const handleSaveDraftPrice = async (plan: Plan) => {
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${plan.planId}/draft`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          price: plan.price,
          originalPrice: plan.originalPrice,
          validityDays: plan.validityDays
        })
      });
      const data = await res.json();
      if (data.success) {
        setPublishSuccessMsg(`Draft saved for ${plan.name}! Changes will not be visible to customers until published.`);
        setTimeout(() => setPublishSuccessMsg(''), 4000);
        fetchPlans();
        setEditingPlan(null);
      }
    } catch (err) {
      alert('Error saving draft: ' + err);
    }
  };

  const handleViewPlanDetails = async (planId: string) => {
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${planId}/details`);
      const data = await res.json();
      if (data.success) {
        setSelectedPlanDetails(data);
        setIsDetailsModalOpen(true);
      }
    } catch (err) {
      console.error('Error fetching plan details:', err);
    }
  };

  const handleTogglePlanActive = async (planId: string) => {
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${planId}/toggle-active`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' }
      });
      const data = await res.json();
      if (data.success) {
        fetchPlans();
      }
    } catch (err) {
      alert('Error toggling plan: ' + err);
    }
  };

  const handleArchivePlan = async (plan: Plan) => {
    if (!confirm(`Are you sure you want to archive or deactivate "${plan.name}"? Existing active subscribers will retain their benefits until expiry.`)) {
      return;
    }
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${plan.planId}`, {
        method: 'DELETE'
      });
      const data = await res.json();
      if (data.success) {
        alert(data.message);
        fetchPlans();
      }
    } catch (err) {
      alert('Error archiving plan: ' + err);
    }
  };

  const handleOpenBenefitModal = (planId: string, benefit?: Benefit) => {
    setSelectedPlanIdForBenefit(planId);
    if (benefit) {
      setEditingBenefit(benefit);
      setBenefitForm({ ...benefit });
    } else {
      setEditingBenefit(null);
      setBenefitForm({
        title: '',
        description: '',
        type: 'discount_percentage',
        value: 20,
        minimumOrderValue: 199,
        maxDiscountLimit: 100,
        fundedBy: 'staydriv',
        staydrivSharePercent: 100,
        restaurantSharePercent: 0,
        isEnabled: true
      });
    }
    setIsBenefitModalOpen(true);
  };

  const handleSaveBenefit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedPlanIdForBenefit) return;

    try {
      if (editingBenefit) {
        // Update benefit
        const res = await fetch(`/api/food/membership/admin/plans/${selectedPlanIdForBenefit}/benefits/${editingBenefit.benefitId}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(benefitForm)
        });
        const data = await res.json();
        if (data.success) {
          setIsBenefitModalOpen(false);
          fetchPlans();
        }
      } else {
        // Add new benefit
        const res = await fetch(`/api/food/membership/admin/plans/${selectedPlanIdForBenefit}/benefits`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(benefitForm)
        });
        const data = await res.json();
        if (data.success) {
          setIsBenefitModalOpen(false);
          fetchPlans();
        }
      }
    } catch (err) {
      alert('Error saving benefit: ' + err);
    }
  };

  const handleToggleBenefit = async (planId: string, benefitId: string) => {
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${planId}/benefits/${benefitId}/toggle`, {
        method: 'PATCH'
      });
      const data = await res.json();
      if (data.success) {
        fetchPlans();
      }
    } catch (err) {
      alert('Failed to toggle benefit: ' + err);
    }
  };

  const handleDeleteBenefit = async (planId: string, benefitId: string) => {
    if (!confirm('Are you sure you want to remove this benefit from the plan?')) return;
    try {
      const res = await fetch(`/api/food/membership/admin/plans/${planId}/benefits/${benefitId}`, {
        method: 'DELETE'
      });
      const data = await res.json();
      if (data.success) {
        fetchPlans();
      }
    } catch (err) {
      alert('Failed to delete benefit: ' + err);
    }
  };

  const handlePublishAllPlans = async () => {
    const summary = prompt('Enter a short summary for this published version (optional):', 'Pricing and benefit adjustments');
    if (summary === null) return;

    setIsPublishing(true);
    try {
      const res = await fetch('/api/food/membership/admin/plans/publish', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ changeSummary: summary })
      });
      const data = await res.json();
      if (data.success) {
        setPublishSuccessMsg('All membership changes have been PUBLISHED! Customers see updated terms immediately.');
        setTimeout(() => setPublishSuccessMsg(''), 5000);
        fetchPlans();
      }
    } catch (err) {
      alert('Publish failed: ' + err);
    } finally {
      setIsPublishing(false);
    }
  };

  const handleCancelSubscription = async () => {
    if (!selectedSubForCancel) return;
    try {
      const res = await fetch(`/api/food/membership/admin/subscriptions/${selectedSubForCancel.membershipId}/cancel`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          reason: cancelReason || 'Customer requested cancellation',
          refundAmount: parseFloat(refundAmount) || 0
        })
      });
      const data = await res.json();
      if (data.success) {
        setSelectedSubForCancel(null);
        setCancelReason('');
        setRefundAmount('0');
        fetchSubscriptions();
        fetchAnalytics();
      }
    } catch (err) {
      alert('Cancellation failed: ' + err);
    }
  };

  const handleExportCSV = () => {
    window.open('/api/food/membership/admin/export?format=csv', '_blank');
  };

  return (
    <div className="page-container" style={{ padding: '24px', maxWidth: '1440px', margin: '0 auto' }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '24px', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '6px' }}>
            <div style={{ width: '42px', height: '42px', borderRadius: '10px', background: 'linear-gradient(135deg, #EA580C, #F97316)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
              <UtensilsCrossed size={22} />
            </div>
            <div>
              <h1 style={{ fontSize: '24px', fontWeight: 800, margin: 0, color: 'var(--text-main)' }}>Food Membership Management</h1>
              <p style={{ margin: 0, fontSize: '13px', color: 'var(--text-muted)' }}>
                Configurable subscription plans exclusively for <strong style={{ color: '#EA580C' }}>Food Order Now</strong>. Completely separate from ride booking.
              </p>
            </div>
          </div>
        </div>

        {/* Global Action Buttons */}
        <div style={{ display: 'flex', gap: '12px' }}>
          <button
            onClick={() => setIsPreviewModalOpen(true)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '10px 18px',
              borderRadius: '8px',
              border: '1px solid var(--border-color)',
              background: 'var(--bg-card)',
              color: 'var(--text-main)',
              cursor: 'pointer',
              fontWeight: 600,
              fontSize: '13px'
            }}
          >
            <Eye size={16} /> Live Customer Preview
          </button>
          <button
            onClick={handlePublishAllPlans}
            disabled={isPublishing}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              padding: '10px 20px',
              borderRadius: '8px',
              border: 'none',
              background: '#EA580C',
              color: '#fff',
              cursor: isPublishing ? 'not-allowed' : 'pointer',
              fontWeight: 700,
              fontSize: '13px',
              boxShadow: '0 2px 8px rgba(234, 88, 12, 0.4)'
            }}
          >
            <Sparkles size={16} /> {isPublishing ? 'Publishing...' : 'Publish Plans to App'}
          </button>
        </div>
      </div>

      {/* Success banner */}
      {publishSuccessMsg && (
        <div style={{ background: '#ecfdf5', border: '1px solid #10b981', color: '#065f46', padding: '12px 18px', borderRadius: '8px', marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '10px', fontSize: '14px', fontWeight: 600 }}>
          <CheckCircle2 size={18} color="#10b981" />
          <span>{publishSuccessMsg}</span>
        </div>
      )}

      {/* Top Metric Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px', marginBottom: '24px' }}>
        <div className="card" style={{ padding: '16px 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
            <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Active Subscribers</span>
            <Users size={18} color="#EA580C" />
          </div>
          <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--text-main)' }}>
            {analytics?.activeSubscribers || 0}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            {analytics?.monthlyCount || 0} Monthly • {analytics?.quarterlyCount || 0} Quarterly
          </div>
        </div>

        <div className="card" style={{ padding: '16px 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
            <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Membership Revenue</span>
            <DollarSign size={18} color="#10b981" />
          </div>
          <div style={{ fontSize: '24px', fontWeight: 800, color: '#10b981' }}>
            ₹{(analytics?.totalRevenue || 0).toLocaleString('en-IN')}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Gross subscription collections
          </div>
        </div>

        <div className="card" style={{ padding: '16px 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
            <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Member Food Discounts</span>
            <Tag size={18} color="#3b82f6" />
          </div>
          <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--text-main)' }}>
            ₹{(analytics?.totalDiscountsGiven || 0).toLocaleString('en-IN')}
          </div>
          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
            Across {analytics?.totalMemberOrders || 0} member orders
          </div>
        </div>

        <div className="card" style={{ padding: '16px 20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
            <span style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Active Plans</span>
            <Sparkles size={18} color="#eab308" />
          </div>
          <div style={{ fontSize: '24px', fontWeight: 800, color: 'var(--text-main)' }}>
            2 Plans
          </div>
          <div style={{ fontSize: '11px', color: '#10b981', marginTop: '4px', fontWeight: 600 }}>
            Active StayDriv Platinum
          </div>
        </div>
      </div>

      {/* Tabs navigation */}
      <div style={{ display: 'flex', borderBottom: '1px solid var(--border-color)', marginBottom: '24px', gap: '8px' }}>
        <button
          onClick={() => setActiveTab('plans')}
          style={{
            padding: '10px 20px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'plans' ? '3px solid #EA580C' : '3px solid transparent',
            color: activeTab === 'plans' ? '#EA580C' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer'
          }}
        >
          Membership Plans & Benefits
        </button>
        <button
          onClick={() => setActiveTab('subscribers')}
          style={{
            padding: '10px 20px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'subscribers' ? '3px solid #EA580C' : '3px solid transparent',
            color: activeTab === 'subscribers' ? '#EA580C' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer'
          }}
        >
          Subscribed Customers ({subscriptions.length || 0})
        </button>
        <button
          onClick={() => setActiveTab('restaurants')}
          style={{
            padding: '10px 20px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'restaurants' ? '3px solid #EA580C' : '3px solid transparent',
            color: activeTab === 'restaurants' ? '#EA580C' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer'
          }}
        >
          Partner Restaurants ({restaurants.length || 0})
        </button>
        <button
          onClick={() => setActiveTab('audit')}
          style={{
            padding: '10px 20px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'audit' ? '3px solid #EA580C' : '3px solid transparent',
            color: activeTab === 'audit' ? '#EA580C' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer'
          }}
        >
          Admin Audit Logs
        </button>
        <button
          onClick={() => setActiveTab('transactions')}
          style={{
            padding: '10px 20px',
            background: 'none',
            border: 'none',
            borderBottom: activeTab === 'transactions' ? '3px solid #EA580C' : '3px solid transparent',
            color: activeTab === 'transactions' ? '#EA580C' : 'var(--text-muted)',
            fontWeight: 700,
            fontSize: '14px',
            cursor: 'pointer'
          }}
        >
          Payment Transactions ({transactions.length || 0})
        </button>
      </div>

      {/* TAB 1: MEMBERSHIP PLANS & BENEFITS */}
      {activeTab === 'plans' && (
        <div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(480px, 1fr))', gap: '24px' }}>
            {plans.map((plan) => {
              const isPlatinum = plan.planType === 'platinum' || plan.planId === 'plan_platinum_3m';
              const isMonthly = plan.planType === 'monthly';
              return (
                <div
                  key={plan.planId}
                  className="card"
                  style={{
                    padding: '24px',
                    position: 'relative',
                    border: isPlatinum ? '2px solid #EAB308' : (isMonthly ? '2px solid rgba(234, 88, 12, 0.4)' : '2px solid rgba(59, 130, 246, 0.4)'),
                    background: isPlatinum ? 'linear-gradient(180deg, rgba(234, 179, 8, 0.04) 0%, rgba(0, 0, 0, 0) 100%)' : undefined
                  }}
                >
                  {/* Badge */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <span style={{
                        padding: '4px 10px',
                        borderRadius: '6px',
                        fontSize: '11px',
                        fontWeight: 800,
                        textTransform: 'uppercase',
                        background: isPlatinum ? 'linear-gradient(135deg, #F59E0B, #EAB308)' : (isMonthly ? 'rgba(234, 88, 12, 0.15)' : 'rgba(59, 130, 246, 0.15)'),
                        color: isPlatinum ? '#000' : (isMonthly ? '#EA580C' : '#3b82f6')
                      }}>
                        {isPlatinum ? '👑 PLATINUM FOOD MEMBERSHIP' : (isMonthly ? '1 Month Plan' : '3 Months Plan')}
                      </span>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        v{plan.version} • Published
                      </span>
                      <button
                        onClick={() => handleTogglePlanActive(plan.planId)}
                        title={plan.isActive ? 'Click to Deactivate' : 'Click to Activate'}
                        style={{
                          padding: '2px 8px',
                          borderRadius: '12px',
                          border: plan.isActive ? '1px solid #10b981' : '1px solid #94a3b8',
                          background: plan.isActive ? '#ecfdf5' : '#f1f5f9',
                          color: plan.isActive ? '#047857' : '#64748b',
                          fontSize: '10px',
                          fontWeight: 800,
                          cursor: 'pointer'
                        }}
                      >
                        {plan.isActive ? 'ACTIVE' : 'INACTIVE'}
                      </button>
                    </div>

                    {plan.draftPrice !== undefined && plan.draftPrice !== plan.price && (
                      <span style={{ fontSize: '11px', background: '#fef3c7', color: '#b45309', padding: '3px 8px', borderRadius: '4px', fontWeight: 700 }}>
                        Draft: ₹{plan.draftPrice} (Unpublished)
                      </span>
                    )}
                  </div>

                  <h2 style={{ fontSize: '20px', fontWeight: 800, color: 'var(--text-main)', marginBottom: '4px' }}>{plan.name}</h2>
                  <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '14px' }}>{plan.tagline}</p>

                  {/* Highlights banner for Platinum */}
                  {isPlatinum && (
                    <div style={{
                      background: 'rgba(234, 179, 8, 0.08)',
                      border: '1px solid rgba(234, 179, 8, 0.3)',
                      borderRadius: '8px',
                      padding: '10px 14px',
                      marginBottom: '16px',
                      fontSize: '12px',
                      color: 'var(--text-main)',
                      display: 'flex',
                      flexWrap: 'wrap',
                      gap: '12px'
                    }}>
                      <span><strong>Free Delivery:</strong> &gt; ₹{plan.minOrderAmount || 99} within {plan.deliveryRadiusKm || 7} km</span>
                      <span><strong>Extra Discount:</strong> Up to {plan.maxDiscountPercent || 30}% OFF</span>
                      <span><strong>Duration:</strong> {plan.validityMonths || 3} Months</span>
                    </div>
                  )}

                  {/* ACTION BUTTON STYLE */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap', marginBottom: '18px' }}>
                    {/* Green Pill Button: [ ≡ Manage Benefits ] */}
                    <button
                      onClick={() => handleOpenBenefitModal(plan.planId)}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px',
                        background: '#dcfce7',
                        color: '#15803d',
                        border: '1px solid #86efac',
                        borderRadius: '24px',
                        padding: '7px 16px',
                        fontWeight: 700,
                        fontSize: '13px',
                        cursor: 'pointer',
                        boxShadow: '0 1px 2px rgba(0,0,0,0.04)'
                      }}
                    >
                      <Menu size={16} /> Manage Benefits
                    </button>

                    {/* White Pill Button: [ 👁 View Details ] */}
                    <button
                      onClick={() => handleViewPlanDetails(plan.planId)}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px',
                        background: '#ffffff',
                        color: '#0f172a',
                        border: '1px solid #cbd5e1',
                        borderRadius: '24px',
                        padding: '7px 16px',
                        fontWeight: 700,
                        fontSize: '13px',
                        cursor: 'pointer',
                        boxShadow: '0 1px 2px rgba(0,0,0,0.04)'
                      }}
                    >
                      <Eye size={16} /> View Details
                    </button>

                    {/* Light Blue Pill Button: [ ✏ Edit ] */}
                    <button
                      onClick={() => setEditingPlan(editingPlan?.planId === plan.planId ? null : { ...plan })}
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        gap: '6px',
                        background: '#eff6ff',
                        color: '#1d4ed8',
                        border: '1px solid #bfdbfe',
                        borderRadius: '24px',
                        padding: '7px 16px',
                        fontWeight: 700,
                        fontSize: '13px',
                        cursor: 'pointer',
                        boxShadow: '0 1px 2px rgba(0,0,0,0.04)'
                      }}
                    >
                      <Edit3 size={15} /> Edit
                    </button>

                    {/* Red Trash Icon: [ 🗑 ] */}
                    <button
                      onClick={() => handleArchivePlan(plan)}
                      title="Archive or Delete Plan"
                      style={{
                        display: 'inline-flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        background: 'transparent',
                        color: '#ef4444',
                        border: 'none',
                        cursor: 'pointer',
                        padding: '6px',
                        borderRadius: '6px'
                      }}
                    >
                      <Trash2 size={18} />
                    </button>
                  </div>

                  {/* Price display / edit */}
                  {editingPlan?.planId === plan.planId ? (
                    <div style={{ background: 'var(--bg-main)', padding: '16px', borderRadius: '10px', marginBottom: '18px', border: '1px solid var(--border-color)' }}>
                      <h4 style={{ fontSize: '13px', fontWeight: 700, marginBottom: '12px' }}>Configure Subscription Rates & Eligibility</h4>
                      <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr 1fr', gap: '12px', marginBottom: '12px' }}>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Plan Name</label>
                          <input
                            type="text"
                            value={editingPlan.name}
                            onChange={(e) => setEditingPlan({ ...editingPlan, name: e.target.value })}
                            style={{ width: '100%', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)', fontWeight: 700 }}
                          />
                        </div>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Selling Price (₹)</label>
                          <input
                            type="number"
                            value={editingPlan.price}
                            onChange={(e) => setEditingPlan({ ...editingPlan, price: parseFloat(e.target.value) || 0 })}
                            style={{ width: '100%', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)', fontWeight: 700 }}
                          />
                        </div>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Original Price (₹)</label>
                          <input
                            type="number"
                            value={editingPlan.originalPrice}
                            onChange={(e) => setEditingPlan({ ...editingPlan, originalPrice: parseFloat(e.target.value) || 0 })}
                            style={{ width: '100%', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)' }}
                          />
                        </div>
                      </div>

                      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr 1fr', gap: '10px', marginBottom: '14px' }}>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Duration (Months)</label>
                          <input
                            type="number"
                            value={editingPlan.validityMonths || 3}
                            onChange={(e) => setEditingPlan({ ...editingPlan, validityMonths: parseInt(e.target.value, 10) || 1 })}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)' }}
                          />
                        </div>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Validity Days</label>
                          <input
                            type="number"
                            value={editingPlan.validityDays}
                            onChange={(e) => setEditingPlan({ ...editingPlan, validityDays: parseInt(e.target.value, 10) || 1 })}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)' }}
                          />
                        </div>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Min Order (₹)</label>
                          <input
                            type="number"
                            value={editingPlan.minOrderAmount !== undefined ? editingPlan.minOrderAmount : 99}
                            onChange={(e) => setEditingPlan({ ...editingPlan, minOrderAmount: parseFloat(e.target.value) || 0 })}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)' }}
                          />
                        </div>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Radius (km)</label>
                          <input
                            type="number"
                            value={editingPlan.deliveryRadiusKm !== undefined ? editingPlan.deliveryRadiusKm : 7}
                            onChange={(e) => setEditingPlan({ ...editingPlan, deliveryRadiusKm: parseFloat(e.target.value) || 1 })}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)' }}
                          />
                        </div>
                        <div>
                          <label style={{ display: 'block', fontSize: '11px', color: 'var(--text-muted)', marginBottom: '4px' }}>Max Extra Off (%)</label>
                          <input
                            type="number"
                            value={editingPlan.maxDiscountPercent !== undefined ? editingPlan.maxDiscountPercent : 30}
                            onChange={(e) => setEditingPlan({ ...editingPlan, maxDiscountPercent: parseFloat(e.target.value) || 0 })}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)' }}
                          />
                        </div>
                      </div>

                      <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
                        <button
                          onClick={() => handleSaveDraftPrice(editingPlan)}
                          style={{
                            padding: '8px 14px',
                            borderRadius: '6px',
                            border: '1px solid var(--border-color)',
                            background: 'var(--bg-card)',
                            color: 'var(--text-main)',
                            fontWeight: 700,
                            fontSize: '12px',
                            cursor: 'pointer'
                          }}
                        >
                          Save Draft
                        </button>
                        <button
                          onClick={() => handleSavePlanPrice(editingPlan)}
                          style={{
                            padding: '8px 16px',
                            borderRadius: '6px',
                            border: 'none',
                            background: '#EA580C',
                            color: '#fff',
                            fontWeight: 700,
                            fontSize: '12px',
                            cursor: 'pointer'
                          }}
                        >
                          Save & Publish Rate
                        </button>
                        <button
                          onClick={() => setEditingPlan(null)}
                          style={{
                            padding: '8px 12px',
                            borderRadius: '6px',
                            border: 'none',
                            background: 'transparent',
                            color: 'var(--text-muted)',
                            fontSize: '12px',
                            cursor: 'pointer'
                          }}
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: '10px', marginBottom: '20px' }}>
                      <span style={{ fontSize: '32px', fontWeight: 900, color: 'var(--text-main)' }}>₹{plan.price}</span>
                      {plan.originalPrice > plan.price && (
                        <span style={{ fontSize: '16px', color: 'var(--text-muted)', textDecoration: 'line-through' }}>₹{plan.originalPrice}</span>
                      )}
                      <span style={{ fontSize: '13px', color: 'var(--text-muted)' }}>/ {plan.validityDays} days</span>
                    </div>
                  )}

                  {/* Benefits Header */}
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '12px' }}>
                    <h3 style={{ fontSize: '14px', fontWeight: 700, color: 'var(--text-main)' }}>Configured Benefits ({plan.benefits.length})</h3>
                    <button
                      onClick={() => handleOpenBenefitModal(plan.planId)}
                      style={{
                        padding: '6px 12px',
                        borderRadius: '6px',
                        border: 'none',
                        background: 'rgba(234, 88, 12, 0.1)',
                        color: '#EA580C',
                        cursor: 'pointer',
                        fontSize: '12px',
                        fontWeight: 700,
                        display: 'flex',
                        alignItems: 'center',
                        gap: '6px'
                      }}
                    >
                      <Plus size={14} /> Add Benefit
                    </button>
                  </div>

                  {/* Benefit Cards List */}
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginBottom: '20px' }}>
                    {plan.benefits.map((b) => (
                      <div
                        key={b.benefitId}
                        style={{
                          padding: '12px 14px',
                          borderRadius: '8px',
                          background: b.isEnabled ? 'var(--bg-main)' : 'rgba(100, 116, 139, 0.08)',
                          border: '1px solid var(--border-color)',
                          opacity: b.isEnabled ? 1 : 0.6,
                          display: 'flex',
                          justifyContent: 'space-between',
                          alignItems: 'flex-start'
                        }}
                      >
                        <div style={{ flex: 1, paddingRight: '12px' }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '4px' }}>
                            <span style={{ fontWeight: 700, fontSize: '13px', color: 'var(--text-main)' }}>{b.title}</span>
                            <span style={{
                              fontSize: '10px',
                              fontWeight: 700,
                              padding: '2px 6px',
                              borderRadius: '4px',
                              background: b.fundedBy === 'staydriv' ? '#ecfdf5' : '#fef3c7',
                              color: b.fundedBy === 'staydriv' ? '#047857' : '#b45309'
                            }}>
                              Funded: {b.fundedBy.toUpperCase()}
                            </span>
                          </div>
                          <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: 0 }}>{b.description}</p>
                          <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '4px' }}>
                            Min Order: ₹{b.minimumOrderValue || 0} • Cap: {b.maxDiscountLimit ? `₹${b.maxDiscountLimit}` : 'None'}
                          </div>
                        </div>

                        {/* Actions for benefit */}
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <button
                            title={b.isEnabled ? 'Disable Benefit' : 'Enable Benefit'}
                            onClick={() => handleToggleBenefit(plan.planId, b.benefitId)}
                            style={{ background: 'none', border: 'none', cursor: 'pointer', color: b.isEnabled ? '#10b981' : '#94a3b8' }}
                          >
                            {b.isEnabled ? <ToggleRight size={22} /> : <ToggleLeft size={22} />}
                          </button>
                          <button
                            title="Edit Benefit"
                            onClick={() => handleOpenBenefitModal(plan.planId, b)}
                            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}
                          >
                            <Edit2 size={15} />
                          </button>
                          <button
                            title="Delete Benefit"
                            onClick={() => handleDeleteBenefit(plan.planId, b.benefitId)}
                            style={{ background: 'none', border: 'none', cursor: 'pointer', color: '#ef4444' }}
                          >
                            <Trash2 size={15} />
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>

                  {/* Terms & Conditions preview */}
                  <div>
                    <h4 style={{ fontSize: '12px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', marginBottom: '8px' }}>
                      Program Rules & Guarantees
                    </h4>
                    <ul style={{ paddingLeft: '18px', fontSize: '12px', color: 'var(--text-muted)', margin: 0, lineHeight: 1.6 }}>
                      <li>Strictly applicable to Food Order Now only. Zero ride discounts.</li>
                      <li>Existing subscribers retain their purchased terms until their subscription expires.</li>
                    </ul>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* TAB 2: SUBSCRIBED CUSTOMERS */}
      {activeTab === 'subscribers' && (
        <div className="card" style={{ padding: '20px' }}>
          {/* Filters & Search */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px', flexWrap: 'wrap', gap: '12px' }}>
            <div style={{ display: 'flex', gap: '12px', flex: 1, minWidth: '300px' }}>
              <div style={{ position: 'relative', flex: 1 }}>
                <Search size={16} style={{ position: 'absolute', left: '12px', top: '12px', color: 'var(--text-muted)' }} />
                <input
                  type="text"
                  placeholder="Search customer name, phone, membership ID, or transaction ID..."
                  value={subSearchQuery}
                  onChange={(e) => setSubSearchQuery(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && fetchSubscriptions()}
                  style={{ width: '100%', padding: '9px 12px 9px 36px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                />
              </div>

              <select
                value={subStatusFilter}
                onChange={(e) => setSubStatusFilter(e.target.value)}
                style={{ padding: '9px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
              >
                <option value="all">All Statuses</option>
                <option value="active">Active Members</option>
                <option value="expired">Expired</option>
                <option value="cancelled">Cancelled</option>
              </select>

              <select
                value={subPlanFilter}
                onChange={(e) => setSubPlanFilter(e.target.value)}
                style={{ padding: '9px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
              >
                <option value="all">All Plans</option>
                <option value="monthly">Monthly</option>
                <option value="quarterly">Quarterly</option>
              </select>
            </div>

            <div style={{ display: 'flex', gap: '8px' }}>
              <button
                onClick={fetchSubscriptions}
                style={{ padding: '9px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', cursor: 'pointer', fontSize: '13px', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}
              >
                <RefreshCw size={14} /> Refresh
              </button>
              <button
                onClick={handleExportCSV}
                style={{ padding: '9px 16px', borderRadius: '8px', border: 'none', background: '#10b981', color: '#fff', cursor: 'pointer', fontSize: '13px', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '6px' }}
              >
                <Download size={14} /> Export CSV
              </button>
            </div>
          </div>

          {/* Table */}
          {loadingSubs ? (
            <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>Loading subscriptions...</div>
          ) : subscriptions.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
              No subscriptions found matching the selected filter.
            </div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-muted)' }}>
                    <th style={{ padding: '12px' }}>Membership ID</th>
                    <th style={{ padding: '12px' }}>Customer</th>
                    <th style={{ padding: '12px' }}>Plan</th>
                    <th style={{ padding: '12px' }}>Razorpay Details</th>
                    <th style={{ padding: '12px' }}>Price Paid</th>
                    <th style={{ padding: '12px' }}>Validity</th>
                    <th style={{ padding: '12px' }}>Status</th>
                    <th style={{ padding: '12px' }}>Total Savings</th>
                    <th style={{ padding: '12px' }}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {subscriptions.map((s) => (
                    <tr key={s.membershipId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '12px', fontWeight: 700, color: '#EA580C' }}>{s.membershipId}</td>
                      <td style={{ padding: '12px' }}>
                        <div style={{ fontWeight: 600 }}>{s.customerName}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{s.customerPhone}</div>
                      </td>
                      <td style={{ padding: '12px' }}>
                        <span style={{
                          padding: '3px 8px',
                          borderRadius: '4px',
                          fontSize: '11px',
                          fontWeight: 700,
                          background: s.planType === 'platinum' || s.planName.toLowerCase().includes('platinum') ? '#fef3c7' : (s.planType === 'monthly' ? 'rgba(234, 88, 12, 0.1)' : 'rgba(59, 130, 246, 0.1)'),
                          color: s.planType === 'platinum' || s.planName.toLowerCase().includes('platinum') ? '#b45309' : (s.planType === 'monthly' ? '#EA580C' : '#3b82f6')
                        }}>
                          {s.planName}
                        </span>
                      </td>
                      <td style={{ padding: '12px' }}>
                        <div style={{ fontSize: '11px', fontFamily: 'monospace' }}>
                          <div style={{ color: 'var(--text-main)', fontWeight: 600 }}>ID: {s.gatewayOrderId || '-'}</div>
                          <div style={{ color: 'var(--text-muted)' }}>Pay: {s.gatewayPaymentId || s.transactionId || '-'}</div>
                        </div>
                      </td>
                      <td style={{ padding: '12px', fontWeight: 700 }}>₹{s.pricePaid}</td>
                      <td style={{ padding: '12px' }}>
                        <div>{s.startDate ? new Date(s.startDate).toLocaleDateString() : '-'} to</div>
                        <div style={{ fontWeight: 600 }}>{s.endDate ? new Date(s.endDate).toLocaleDateString() : '-'}</div>
                      </td>
                      <td style={{ padding: '12px' }}>
                        <span style={{
                          padding: '4px 10px',
                          borderRadius: '6px',
                          fontSize: '11px',
                          fontWeight: 700,
                          textTransform: 'uppercase',
                          background: s.status === 'active' ? '#ecfdf5' : (s.status === 'expired' ? '#f1f5f9' : '#fee2e2'),
                          color: s.status === 'active' ? '#047857' : (s.status === 'expired' ? '#64748b' : '#b91c1c')
                        }}>
                          {s.status}
                        </span>
                      </td>
                      <td style={{ padding: '12px', fontWeight: 700, color: '#10b981' }}>
                        ₹{s.totalDiscountAvailed || 0}
                      </td>
                      <td style={{ padding: '12px' }}>
                        {s.status === 'active' && (
                          <button
                            onClick={() => setSelectedSubForCancel(s)}
                            style={{
                              padding: '5px 10px',
                              borderRadius: '4px',
                              border: '1px solid #ef4444',
                              background: 'transparent',
                              color: '#ef4444',
                              fontSize: '11px',
                              fontWeight: 600,
                              cursor: 'pointer'
                            }}
                          >
                            Cancel / Refund
                          </button>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* TAB: PARTNER RESTAURANTS */}
      {activeTab === 'restaurants' && (
        <div className="card" style={{ padding: '24px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px', flexWrap: 'wrap', gap: '12px' }}>
            <div>
              <h3 style={{ fontSize: '18px', fontWeight: 800, margin: 0, color: 'var(--text-main)' }}>Participating Partner Restaurants</h3>
              <p style={{ fontSize: '13px', color: 'var(--text-muted)', margin: '4px 0 0 0' }}>Manage restaurants eligible for StayDriv Platinum Food Membership free delivery and extra discounts.</p>
            </div>
            <div style={{ display: 'flex', gap: '10px' }}>
              <input
                type="text"
                value={restaurantSearch}
                onChange={(e) => setRestaurantSearch(e.target.value)}
                placeholder="Search restaurant..."
                style={{ padding: '8px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
              />
              <button
                onClick={fetchRestaurants}
                style={{ padding: '8px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-card)', color: 'var(--text-main)', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 700 }}
              >
                <RefreshCw size={14} /> Refresh
              </button>
            </div>
          </div>

          {loadingRestaurants ? (
            <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>Loading restaurants...</div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-muted)' }}>
                    <th style={{ padding: '12px' }}>Restaurant</th>
                    <th style={{ padding: '12px' }}>Address</th>
                    <th style={{ padding: '12px' }}>Rating</th>
                    <th style={{ padding: '12px' }}>Platinum Enrolled</th>
                    <th style={{ padding: '12px' }}>Extra Member Discount (%)</th>
                    <th style={{ padding: '12px' }}>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {restaurants
                    .filter(r => !restaurantSearch || r.name.toLowerCase().includes(restaurantSearch.toLowerCase()) || r.restaurantId.toLowerCase().includes(restaurantSearch.toLowerCase()))
                    .map((r) => (
                    <tr key={r.restaurantId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '12px', fontWeight: 700, color: 'var(--text-main)' }}>
                        <div>{r.name}</div>
                        <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>{r.restaurantId}</div>
                      </td>
                      <td style={{ padding: '12px', color: 'var(--text-muted)' }}>{r.address || 'Hyderabad'}</td>
                      <td style={{ padding: '12px', fontWeight: 700 }}>⭐ {r.rating || 4.5}</td>
                      <td style={{ padding: '12px' }}>
                        <button
                          onClick={() => handleToggleRestaurantEnrollment(r)}
                          style={{
                            padding: '4px 10px',
                            borderRadius: '6px',
                            border: r.isMembershipEnrolled !== false ? '1px solid #10b981' : '1px solid #ef4444',
                            background: r.isMembershipEnrolled !== false ? '#ecfdf5' : '#fee2e2',
                            color: r.isMembershipEnrolled !== false ? '#047857' : '#b91c1c',
                            fontSize: '11px',
                            fontWeight: 700,
                            cursor: 'pointer'
                          }}
                        >
                          {r.isMembershipEnrolled !== false ? 'ENROLLED' : 'EXCLUDED'}
                        </button>
                      </td>
                      <td style={{ padding: '12px' }}>
                        <input
                          type="number"
                          defaultValue={r.membershipDiscountPercent || 10}
                          min={0}
                          max={30}
                          onBlur={(e) => handleUpdateRestaurantDiscount(r.restaurantId, parseFloat(e.target.value) || 0)}
                          style={{ width: '70px', padding: '6px 8px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontWeight: 700 }}
                        /> %
                      </td>
                      <td style={{ padding: '12px' }}>
                        <button
                          onClick={() => handleToggleRestaurantEnrollment(r)}
                          style={{ padding: '4px 10px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', fontSize: '11px', fontWeight: 600, cursor: 'pointer' }}
                        >
                          {r.isMembershipEnrolled !== false ? 'Exclude from Platinum' : 'Include in Platinum'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* TAB 3: AUDIT LOGS */}
      {activeTab === 'audit' && (
        <div className="card" style={{ padding: '20px' }}>
          <h3 style={{ fontSize: '16px', fontWeight: 700, marginBottom: '16px' }}>Administrative Change Logs</h3>
          {loadingAudit ? (
            <div style={{ textAlign: 'center', padding: '30px' }}>Loading audit logs...</div>
          ) : auditLogs.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '30px', color: 'var(--text-muted)' }}>No audit events recorded yet.</div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-muted)' }}>
                    <th style={{ padding: '10px' }}>Timestamp</th>
                    <th style={{ padding: '10px' }}>Action</th>
                    <th style={{ padding: '10px' }}>Admin</th>
                    <th style={{ padding: '10px' }}>Details</th>
                  </tr>
                </thead>
                <tbody>
                  {auditLogs.map((log) => (
                    <tr key={log.auditId} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '10px', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                        {new Date(log.createdAt).toLocaleString()}
                      </td>
                      <td style={{ padding: '10px' }}>
                        <span style={{ fontWeight: 700, color: '#EA580C', fontSize: '12px' }}>{log.action}</span>
                      </td>
                      <td style={{ padding: '10px', fontWeight: 600 }}>{log.adminName || 'Admin'}</td>
                      <td style={{ padding: '10px' }}>{log.details}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* TAB 5: PAYMENT TRANSACTIONS & GATEWAY LOGS */}
      {activeTab === 'transactions' && (
        <div className="card" style={{ padding: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px', flexWrap: 'wrap', gap: '12px' }}>
            <div>
              <h3 style={{ fontSize: '16px', fontWeight: 800, margin: 0, color: 'var(--text-main)' }}>Payment Transactions & Gateway Logs</h3>
              <p style={{ fontSize: '13px', color: 'var(--text-muted)', margin: '4px 0 0 0' }}>Real-time Razorpay audit ledger for StayDriv Platinum Food Membership.</p>
            </div>
            <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
              <select
                value={txnStatusFilter}
                onChange={(e) => setTxnStatusFilter(e.target.value)}
                style={{ padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
              >
                <option value="all">All Statuses</option>
                <option value="success">Success</option>
                <option value="failed">Failed / Cancelled</option>
                <option value="created">Pending / Created</option>
              </select>
              <input
                type="text"
                placeholder="Search phone, order ID..."
                value={txnSearchQuery}
                onChange={(e) => setTxnSearchQuery(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && fetchTransactions()}
                style={{ padding: '8px 12px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px', width: '200px' }}
              />
              <button
                onClick={fetchTransactions}
                style={{ padding: '8px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', cursor: 'pointer', fontSize: '13px', fontWeight: 600, display: 'flex', alignItems: 'center', gap: '6px' }}
              >
                <RefreshCw size={14} /> Refresh
              </button>
            </div>
          </div>

          {loadingTxns ? (
            <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>Loading payment transactions...</div>
          ) : transactions.length === 0 ? (
            <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>No transactions found matching criteria.</div>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid var(--border-color)', textAlign: 'left', color: 'var(--text-muted)' }}>
                    <th style={{ padding: '12px' }}>Transaction ID</th>
                    <th style={{ padding: '12px' }}>Customer Phone</th>
                    <th style={{ padding: '12px' }}>Gateway Order ID</th>
                    <th style={{ padding: '12px' }}>Payment ID</th>
                    <th style={{ padding: '12px' }}>Amount</th>
                    <th style={{ padding: '12px' }}>Status</th>
                    <th style={{ padding: '12px' }}>Failure Reason / Notes</th>
                    <th style={{ padding: '12px' }}>Timestamp</th>
                  </tr>
                </thead>
                <tbody>
                  {transactions.map((tx: any) => (
                    <tr key={tx.transactionId || tx._id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <td style={{ padding: '12px', fontFamily: 'monospace', fontWeight: 700, color: '#EA580C' }}>
                        {tx.transactionId}
                      </td>
                      <td style={{ padding: '12px', fontWeight: 600 }}>
                        {tx.customerPhone}
                      </td>
                      <td style={{ padding: '12px', fontFamily: 'monospace', fontSize: '12px', color: 'var(--text-main)' }}>
                        {tx.gatewayOrderId || '-'}
                      </td>
                      <td style={{ padding: '12px', fontFamily: 'monospace', fontSize: '12px', color: 'var(--text-muted)' }}>
                        {tx.gatewayPaymentId || '-'}
                      </td>
                      <td style={{ padding: '12px', fontWeight: 700 }}>
                        ₹{tx.amount || 1}
                      </td>
                      <td style={{ padding: '12px' }}>
                        <span style={{
                          padding: '3px 8px',
                          borderRadius: '4px',
                          fontSize: '11px',
                          fontWeight: 700,
                          textTransform: 'uppercase',
                          background: tx.paymentStatus === 'success' ? '#ecfdf5' : (tx.paymentStatus === 'failed' ? '#fee2e2' : '#eff6ff'),
                          color: tx.paymentStatus === 'success' ? '#047857' : (tx.paymentStatus === 'failed' ? '#b91c1c' : '#1d4ed8')
                        }}>
                          {tx.paymentStatus}
                        </span>
                      </td>
                      <td style={{ padding: '12px', color: tx.paymentStatus === 'failed' ? '#ef4444' : 'var(--text-muted)', fontSize: '12px' }}>
                        {tx.failureReason || (tx.paymentStatus === 'success' ? 'Payment Verified' : 'Order Created')}
                      </td>
                      <td style={{ padding: '12px', color: 'var(--text-muted)', fontSize: '12px', whiteSpace: 'nowrap' }}>
                        {new Date(tx.createdAt).toLocaleString()}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* MODAL 1: ADD / EDIT BENEFIT */}
      {isBenefitModalOpen && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '16px' }}>
          <div style={{ background: 'var(--bg-card)', borderRadius: '12px', width: '100%', maxWidth: '520px', padding: '24px', border: '1px solid var(--border-color)', boxShadow: '0 10px 25px rgba(0,0,0,0.4)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <h3 style={{ fontSize: '18px', fontWeight: 800, margin: 0 }}>
                {editingBenefit ? 'Edit Membership Benefit' : 'Add New Membership Benefit'}
              </h3>
              <button onClick={() => setIsBenefitModalOpen(false)} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
                <X size={20} />
              </button>
            </div>

            <form onSubmit={handleSaveBenefit} style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Benefit Title *</label>
                <input
                  type="text"
                  required
                  placeholder="e.g. 20% Food Order Discount"
                  value={benefitForm.title || ''}
                  onChange={(e) => setBenefitForm({ ...benefitForm, title: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                />
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Customer Description</label>
                <input
                  type="text"
                  placeholder="e.g. Save 20% on all qualifying food orders above ₹199"
                  value={benefitForm.description || ''}
                  onChange={(e) => setBenefitForm({ ...benefitForm, description: e.target.value })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                />
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Benefit Type</label>
                  <select
                    value={benefitForm.type}
                    onChange={(e) => setBenefitForm({ ...benefitForm, type: e.target.value as any })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                  >
                    <option value="discount_percentage">Discount Percentage (%)</option>
                    <option value="fixed_discount">Fixed Flat Discount (₹)</option>
                    <option value="free_delivery">Free Delivery</option>
                    <option value="restaurant_special">Restaurant Special Offer</option>
                  </select>
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Discount Value</label>
                  <input
                    type="number"
                    value={benefitForm.value ?? 20}
                    onChange={(e) => setBenefitForm({ ...benefitForm, value: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Min Order Value (₹)</label>
                  <input
                    type="number"
                    value={benefitForm.minimumOrderValue ?? 199}
                    onChange={(e) => setBenefitForm({ ...benefitForm, minimumOrderValue: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>

                <div>
                  <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Max Discount Cap (₹)</label>
                  <input
                    type="number"
                    placeholder="0 = No Cap"
                    value={benefitForm.maxDiscountLimit ?? 100}
                    onChange={(e) => setBenefitForm({ ...benefitForm, maxDiscountLimit: parseFloat(e.target.value) || 0 })}
                    style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                  />
                </div>
              </div>

              <div>
                <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Discount Funded By</label>
                <select
                  value={benefitForm.fundedBy}
                  onChange={(e) => setBenefitForm({ ...benefitForm, fundedBy: e.target.value as any })}
                  style={{ width: '100%', padding: '9px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
                >
                  <option value="staydriv">StayDriv (Platform Funded)</option>
                  <option value="restaurant">Restaurant Partner</option>
                  <option value="split">Split (Configured %)</option>
                </select>
              </div>

              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: '10px' }}>
                <button
                  type="button"
                  onClick={() => setIsBenefitModalOpen(false)}
                  style={{ padding: '9px 16px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', cursor: 'pointer' }}
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  style={{ padding: '9px 20px', borderRadius: '6px', border: 'none', background: '#EA580C', color: '#fff', fontWeight: 700, cursor: 'pointer' }}
                >
                  Save Benefit
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MODAL 2: LIVE CUSTOMER PREVIEW */}
      {isPreviewModalOpen && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '16px' }}>
          <div style={{ background: '#0F172A', borderRadius: '24px', width: '380px', height: '680px', padding: '20px', border: '6px solid #334155', boxShadow: '0 25px 50px rgba(0,0,0,0.8)', display: 'flex', flexDirection: 'column', color: '#fff' }}>
            {/* Phone Top Bar */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <div style={{ fontSize: '12px', fontWeight: 700, color: '#94A3B8' }}>StayDriv App Preview</div>
              <button onClick={() => setIsPreviewModalOpen(false)} style={{ background: 'none', border: 'none', color: '#fff', cursor: 'pointer' }}>
                <X size={18} />
              </button>
            </div>

            {/* Plan toggle */}
            <div style={{ display: 'flex', background: 'rgba(255,255,255,0.06)', borderRadius: '10px', padding: '4px', marginBottom: '16px' }}>
              <button
                onClick={() => setPreviewPlanType('monthly')}
                style={{ flex: 1, padding: '8px', borderRadius: '8px', border: 'none', background: previewPlanType === 'monthly' ? '#EA580C' : 'transparent', color: '#fff', fontWeight: 700, fontSize: '12px', cursor: 'pointer' }}
              >
                Monthly Plan
              </button>
              <button
                onClick={() => setPreviewPlanType('quarterly')}
                style={{ flex: 1, padding: '8px', borderRadius: '8px', border: 'none', background: previewPlanType === 'quarterly' ? '#EA580C' : 'transparent', color: '#fff', fontWeight: 700, fontSize: '12px', cursor: 'pointer' }}
              >
                Quarterly (Save More)
              </button>
            </div>

            {/* Mobile Plan Card */}
            {(() => {
              const selectedPlan = plans.find(p => p.planType === previewPlanType);
              if (!selectedPlan) return <div>No plan configured</div>;
              return (
                <div style={{ flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>
                  <div style={{ background: 'linear-gradient(135deg, #1E293B, #0F172A)', borderRadius: '16px', padding: '18px', border: '1px solid rgba(234, 88, 12, 0.4)', marginBottom: '14px' }}>
                    <div style={{ fontSize: '11px', fontWeight: 800, color: '#EA580C', textTransform: 'uppercase', letterSpacing: '0.5px', marginBottom: '4px' }}>
                      STAYDRIV FOOD PASS
                    </div>
                    <div style={{ fontSize: '20px', fontWeight: 900, marginBottom: '2px' }}>{selectedPlan.name}</div>
                    <div style={{ fontSize: '12px', color: '#94A3B8', marginBottom: '14px' }}>{selectedPlan.tagline}</div>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: '8px' }}>
                      <span style={{ fontSize: '28px', fontWeight: 900, color: '#EA580C' }}>₹{selectedPlan.price}</span>
                      {selectedPlan.originalPrice > selectedPlan.price && (
                        <span style={{ fontSize: '14px', color: '#64748B', textDecoration: 'line-through' }}>₹{selectedPlan.originalPrice}</span>
                      )}
                      <span style={{ fontSize: '12px', color: '#94A3B8' }}>/ {selectedPlan.validityDays} days</span>
                    </div>
                  </div>

                  <div style={{ fontSize: '13px', fontWeight: 800, marginBottom: '10px', color: '#CBD5E1' }}>Included Member Benefits</div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginBottom: '16px' }}>
                    {selectedPlan.benefits.filter(b => b.isEnabled).map(b => (
                      <div key={b.benefitId} style={{ display: 'flex', alignItems: 'center', gap: '10px', background: 'rgba(255,255,255,0.04)', padding: '10px 12px', borderRadius: '8px' }}>
                        <CheckCircle2 size={16} color="#10B981" />
                        <div>
                          <div style={{ fontSize: '12px', fontWeight: 700 }}>{b.title}</div>
                          <div style={{ fontSize: '10px', color: '#94A3B8' }}>{b.description}</div>
                        </div>
                      </div>
                    ))}
                  </div>

                  <div style={{ marginTop: 'auto', paddingTop: '12px' }}>
                    <button style={{ width: '100%', padding: '12px', borderRadius: '10px', border: 'none', background: '#EA580C', color: '#fff', fontWeight: 800, fontSize: '14px', cursor: 'pointer' }}>
                      Subscribe • ₹{selectedPlan.price}
                    </button>
                  </div>
                </div>
              );
            })()}
          </div>
        </div>
      )}

      {/* MODAL 3: CANCEL / REFUND SUBSCRIPTION */}
      {selectedSubForCancel && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '16px' }}>
          <div style={{ background: 'var(--bg-card)', borderRadius: '12px', width: '100%', maxWidth: '440px', padding: '24px', border: '1px solid var(--border-color)' }}>
            <h3 style={{ fontSize: '18px', fontWeight: 800, margin: '0 0 8px 0', color: '#ef4444' }}>
              Cancel Membership
            </h3>
            <p style={{ fontSize: '13px', color: 'var(--text-muted)', marginBottom: '16px' }}>
              Customer: <strong>{selectedSubForCancel.customerName}</strong> ({selectedSubForCancel.membershipId})
            </p>

            <div style={{ marginBottom: '14px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Cancellation Reason</label>
              <textarea
                rows={3}
                placeholder="Specify reason for administrative record..."
                value={cancelReason}
                onChange={(e) => setCancelReason(e.target.value)}
                style={{ width: '100%', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
              />
            </div>

            <div style={{ marginBottom: '18px' }}>
              <label style={{ display: 'block', fontSize: '12px', fontWeight: 600, marginBottom: '4px' }}>Refund Amount (₹)</label>
              <input
                type="number"
                value={refundAmount}
                onChange={(e) => setRefundAmount(e.target.value)}
                style={{ width: '100%', padding: '8px 12px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', fontSize: '13px' }}
              />
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px' }}>
              <button
                onClick={() => setSelectedSubForCancel(null)}
                style={{ padding: '8px 16px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'transparent', color: 'var(--text-main)', cursor: 'pointer' }}
              >
                Keep Active
              </button>
              <button
                onClick={handleCancelSubscription}
                style={{ padding: '8px 18px', borderRadius: '6px', border: 'none', background: '#ef4444', color: '#fff', fontWeight: 700, cursor: 'pointer' }}
              >
                Confirm Cancellation
              </button>
            </div>
          </div>
        </div>
      )}

      {/* MODAL 4: VIEW PLAN DETAILS (Picture 3 "View Details" action) */}
      {isDetailsModalOpen && selectedPlanDetails && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.6)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999, padding: '16px' }}>
          <div style={{ background: 'var(--bg-card)', borderRadius: '12px', width: '100%', maxWidth: '780px', maxHeight: '90vh', overflowY: 'auto', padding: '24px', border: '1px solid var(--border-color)', display: 'flex', flexDirection: 'column' }}>
            {/* Modal Header */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px', borderBottom: '1px solid var(--border-color)', paddingBottom: '14px' }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <h3 style={{ fontSize: '20px', fontWeight: 800, margin: 0, color: 'var(--text-main)' }}>
                    {selectedPlanDetails.plan?.name}
                  </h3>
                  <span style={{
                    padding: '3px 8px',
                    borderRadius: '12px',
                    fontSize: '11px',
                    fontWeight: 800,
                    textTransform: 'uppercase',
                    background: selectedPlanDetails.plan?.planType === 'monthly' ? 'rgba(234, 88, 12, 0.15)' : 'rgba(59, 130, 246, 0.15)',
                    color: selectedPlanDetails.plan?.planType === 'monthly' ? '#EA580C' : '#3b82f6'
                  }}>
                    {selectedPlanDetails.plan?.planType === 'monthly' ? 'Monthly Plan' : 'Quarterly Plan'}
                  </span>
                  <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                    Version {selectedPlanDetails.plan?.version || 1}
                  </span>
                </div>
                <p style={{ margin: '4px 0 0 0', fontSize: '12px', color: 'var(--text-muted)' }}>
                  ID: {selectedPlanDetails.plan?.planId} • Exclusively for Food Order Now
                </p>
              </div>
              <button
                onClick={() => { setIsDetailsModalOpen(false); setSelectedPlanDetails(null); }}
                style={{ background: 'none', border: 'none', color: 'var(--text-muted)', cursor: 'pointer', padding: '4px' }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Quick Metrics */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))', gap: '12px', marginBottom: '20px' }}>
              <div style={{ background: 'var(--bg-main)', padding: '12px 14px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Active Subscribers</div>
                <div style={{ fontSize: '20px', fontWeight: 800, color: '#10b981', marginTop: '4px' }}>
                  {selectedPlanDetails.stats?.activeSubscribers || 0}
                </div>
              </div>
              <div style={{ background: 'var(--bg-main)', padding: '12px 14px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Expired / Inactive</div>
                <div style={{ fontSize: '20px', fontWeight: 800, color: 'var(--text-muted)', marginTop: '4px' }}>
                  {selectedPlanDetails.stats?.expiredSubscribers || 0}
                </div>
              </div>
              <div style={{ background: 'var(--bg-main)', padding: '12px 14px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Gross Plan Revenue</div>
                <div style={{ fontSize: '20px', fontWeight: 800, color: '#EA580C', marginTop: '4px' }}>
                  ₹{(selectedPlanDetails.stats?.totalRevenue || 0).toLocaleString('en-IN')}
                </div>
              </div>
              <div style={{ background: 'var(--bg-main)', padding: '12px 14px', borderRadius: '8px', border: '1px solid var(--border-color)' }}>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Current Pricing</div>
                <div style={{ fontSize: '20px', fontWeight: 800, color: 'var(--text-main)', marginTop: '4px' }}>
                  ₹{selectedPlanDetails.plan?.price} <span style={{ fontSize: '12px', color: 'var(--text-muted)', fontWeight: 500 }}>/ {selectedPlanDetails.plan?.validityDays}d</span>
                </div>
              </div>
            </div>

            {/* Plan Info Card */}
            <div style={{ background: 'var(--bg-main)', padding: '16px', borderRadius: '8px', border: '1px solid var(--border-color)', marginBottom: '20px' }}>
              <h4 style={{ margin: '0 0 10px 0', fontSize: '13px', fontWeight: 800, color: 'var(--text-main)' }}>Plan Information</h4>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '10px', fontSize: '12px' }}>
                <div><strong style={{ color: 'var(--text-muted)' }}>Tagline:</strong> {selectedPlanDetails.plan?.tagline || '—'}</div>
                <div><strong style={{ color: 'var(--text-muted)' }}>Original MRP:</strong> ₹{selectedPlanDetails.plan?.originalPrice || '—'}</div>
                <div><strong style={{ color: 'var(--text-muted)' }}>Status:</strong> {selectedPlanDetails.plan?.isActive ? 'Active' : 'Inactive'}</div>
                <div><strong style={{ color: 'var(--text-muted)' }}>Published Status:</strong> {selectedPlanDetails.plan?.isPublished ? 'Published to App' : 'Draft'}</div>
                {selectedPlanDetails.plan?.draftPrice !== undefined && selectedPlanDetails.plan?.draftPrice !== selectedPlanDetails.plan?.price && (
                  <div style={{ color: '#b45309' }}><strong>Draft Price:</strong> ₹{selectedPlanDetails.plan?.draftPrice} (Not yet published)</div>
                )}
              </div>
            </div>

            {/* Configured Benefits */}
            <div style={{ marginBottom: '20px' }}>
              <h4 style={{ margin: '0 0 10px 0', fontSize: '13px', fontWeight: 800, color: 'var(--text-main)' }}>
                Configured Benefits ({selectedPlanDetails.plan?.benefits?.length || 0})
              </h4>
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                {selectedPlanDetails.plan?.benefits?.map((benefit: Benefit) => (
                  <div key={benefit.benefitId} style={{ background: 'var(--bg-main)', padding: '12px 14px', borderRadius: '8px', border: '1px solid var(--border-color)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div>
                      <div style={{ fontSize: '13px', fontWeight: 700, color: 'var(--text-main)' }}>
                        {benefit.title}
                        {!benefit.isEnabled && <span style={{ marginLeft: '8px', fontSize: '10px', color: '#ef4444', fontWeight: 800 }}>DISABLED</span>}
                      </div>
                      <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '2px' }}>{benefit.description}</div>
                      <div style={{ fontSize: '10px', color: '#64748b', marginTop: '4px' }}>
                        Min Order: ₹{benefit.minimumOrderValue} • Max Cap: {benefit.maxDiscountLimit ? `₹${benefit.maxDiscountLimit}` : 'None'} • Funded: {benefit.fundedBy} ({benefit.staydrivSharePercent}% StayDriv / {benefit.restaurantSharePercent}% Restaurant)
                      </div>
                    </div>
                    <span style={{ fontSize: '14px', fontWeight: 800, color: '#EA580C' }}>
                      {benefit.type === 'free_delivery' ? 'FREE' : benefit.type === 'discount_percentage' ? `${benefit.value}% OFF` : `₹${benefit.value} OFF`}
                    </span>
                  </div>
                ))}
              </div>
            </div>

            {/* Version History */}
            {selectedPlanDetails.plan?.versionHistory && selectedPlanDetails.plan.versionHistory.length > 0 && (
              <div style={{ marginBottom: '20px' }}>
                <h4 style={{ margin: '0 0 10px 0', fontSize: '13px', fontWeight: 800, color: 'var(--text-main)' }}>
                  Price & Benefit Change History
                </h4>
                <div style={{ maxHeight: '160px', overflowY: 'auto', border: '1px solid var(--border-color)', borderRadius: '8px' }}>
                  <table style={{ width: '100%', fontSize: '11px', borderCollapse: 'collapse' }}>
                    <thead style={{ background: 'var(--bg-main)', position: 'sticky', top: 0 }}>
                      <tr style={{ textAlign: 'left', borderBottom: '1px solid var(--border-color)' }}>
                        <th style={{ padding: '8px 12px' }}>Version</th>
                        <th style={{ padding: '8px 12px' }}>Selling Price</th>
                        <th style={{ padding: '8px 12px' }}>Original</th>
                        <th style={{ padding: '8px 12px' }}>Date</th>
                        <th style={{ padding: '8px 12px' }}>Summary</th>
                      </tr>
                    </thead>
                    <tbody>
                      {selectedPlanDetails.plan.versionHistory.map((vh: any, idx: number) => (
                        <tr key={idx} style={{ borderBottom: '1px solid var(--border-color)' }}>
                          <td style={{ padding: '8px 12px', fontWeight: 700 }}>v{vh.version}</td>
                          <td style={{ padding: '8px 12px', fontWeight: 700, color: '#EA580C' }}>₹{vh.price}</td>
                          <td style={{ padding: '8px 12px', color: 'var(--text-muted)' }}>₹{vh.originalPrice || '—'}</td>
                          <td style={{ padding: '8px 12px', color: 'var(--text-muted)' }}>
                            {vh.publishedAt ? new Date(vh.publishedAt).toLocaleDateString() : '—'}
                          </td>
                          <td style={{ padding: '8px 12px', color: 'var(--text-muted)' }}>{vh.summary || 'Price change'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {/* Modal Actions */}
            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '10px', marginTop: 'auto', paddingTop: '16px', borderTop: '1px solid var(--border-color)' }}>
              <button
                onClick={() => { setIsDetailsModalOpen(false); setSelectedPlanDetails(null); }}
                style={{ padding: '8px 18px', borderRadius: '6px', border: '1px solid var(--border-color)', background: 'var(--bg-main)', color: 'var(--text-main)', cursor: 'pointer', fontWeight: 600, fontSize: '13px' }}
              >
                Close
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default FoodMembershipManagement;
