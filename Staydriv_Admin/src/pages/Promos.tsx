import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { Plus, Tag, RefreshCw, X, Check, Edit2 } from 'lucide-react';
import { PromoCode } from '../data/mockData';

export const Promos: React.FC = () => {
  const { promoCodes, createPromoCode, togglePromoCode } = useDatabase();
  const [showModal, setShowModal] = useState(false);
  const [editingPromo, setEditingPromo] = useState<PromoCode | null>(null);

  // Form states
  const [code, setCode] = useState('');
  const [discountPercent, setDiscountPercent] = useState<number>(10);
  const [maxDiscount, setMaxDiscount] = useState<number>(50);
  const [minBooking, setMinBooking] = useState<number>(100);
  const [expiry, setExpiry] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!code || !expiry) {
      alert("Please fill in code and expiry date!");
      return;
    }

    await createPromoCode({
      code: code.toUpperCase().trim(),
      discountPercentage: discountPercent,
      maxDiscount,
      minBookingValue: minBooking,
      expiryDate: expiry,
      status: 'active'
    });

    // Reset Form
    setCode('');
    setDiscountPercent(10);
    setMaxDiscount(50);
    setMinBooking(100);
    setExpiry('');
    setShowModal(false);
    alert("New promo code published!");
  };

  return (
    <div className="page-container">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2>Promo & Coupon Codes</h2>
          <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Configure platform promotional offers, discount bounds, and audit usage campaigns.</p>
        </div>
        <button className="btn btn-primary" onClick={() => setShowModal(true)}>
          <Plus size={16} />
          <span>Create Coupon</span>
        </button>
      </div>

      {/* Promos Table */}
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

      {/* Create Promo Modal */}
      {showModal && (
        <div className="modal-overlay">
          <div className="modal-content" style={{ maxWidth: '480px' }}>
            <div className="modal-header">
              <h3 style={{ fontSize: '18px' }}>Create New Promo Code</h3>
              <button 
                className="btn btn-secondary btn-icon" 
                onClick={() => setShowModal(false)}
                style={{ width: '32px', height: '32px' }}
              >
                <X size={14} />
              </button>
            </div>
            <form onSubmit={handleSubmit}>
              <div className="modal-body">
                <div className="form-group">
                  <label>Coupon Code Name</label>
                  <input 
                    type="text" 
                    placeholder="e.g. STAYDRIV50" 
                    value={code}
                    onChange={(e) => setCode(e.target.value.toUpperCase())}
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
                      value={expiry}
                      onChange={(e) => setExpiry(e.target.value)}
                      required
                    />
                  </div>
                </div>
              </div>
              <div className="modal-footer">
                <button type="button" className="btn btn-secondary" onClick={() => setShowModal(false)}>Cancel</button>
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
