import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { 
  FileText, Download, Calendar, Filter, CheckCircle2, 
  Table, Database, Layers, ArrowDownToLine 
} from 'lucide-react';

interface ReportTypeOption {
  id: string;
  title: string;
  description: string;
  category: string;
  fields: string;
}

const REPORT_OPTIONS: ReportTypeOption[] = [
  {
    id: 'ledger',
    title: 'Double-Entry Financial Ledger Journal',
    description: 'Complete audit log of all balanced debits and credits across customer collections, commissions, and pilot payouts.',
    category: 'Finance & Accounting',
    fields: 'Ledger ID, Txn ID, Type, Booking ID, Debit A/C, Credit A/C, Amount, Timestamp'
  },
  {
    id: 'commission',
    title: 'Platform Commission & Booking Breakdown',
    description: 'Itemized booking revenue, vehicle category, platform commission %, GST deductions, and net pilot earnings.',
    category: 'Revenue & Operations',
    fields: 'Booking ID, Customer Fare, Platform Commission, GST Tax, Pilot Net, Vehicle Type, Status'
  },
  {
    id: 'withdrawals',
    title: 'Pilot Withdrawal & Payout Ledger',
    description: 'Chronological history of all pilot bank payouts, beneficiary IFSCs, bank UTRs, and approval audit timestamps.',
    category: 'Treasury & Payouts',
    fields: 'Request ID, Pilot ID, Bank Name, Masked A/C, IFSC, Amount, Status, UTR, Approved By'
  },
  {
    id: 'rides',
    title: 'Ride & Delivery Booking Archive',
    description: 'Full record of all customer trip requests, pickup & drop locations, service types, and ride durations.',
    category: 'Fleet Operations',
    fields: 'Booking ID, Service Type, Customer Name, Pilot Name, Fare, Distance, Payment Mode, Status'
  },
  {
    id: 'pilots',
    title: 'Pilot Fleet & Wallet Directory',
    description: 'Master list of registered pilots, vehicle numbers, verification status, and live wallet balances.',
    category: 'Fleet Operations',
    fields: 'Pilot ID, Name, Phone, Vehicle Type, Plate Number, Wallet Balance, Lifetime Earnings, KYC Status'
  }
];

export const ReportsExports: React.FC = () => {
  const { exportReport } = useDatabase();
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [downloadingId, setDownloadingId] = useState<string | null>(null);

  const handleDownload = async (id: string) => {
    setDownloadingId(id);
    try {
      await exportReport(id);
    } catch (err: any) {
      alert(`Export failed: ${err.message}`);
    } finally {
      setDownloadingId(null);
    }
  };

  const filteredReports = REPORT_OPTIONS.filter(r => 
    selectedCategory === 'all' || r.category.toLowerCase().includes(selectedCategory.toLowerCase())
  );

  return (
    <div className="page-container">
      {/* Top Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <h2>Statutory Reports & Real Data Exports</h2>
            <span style={{ 
              display: 'inline-flex', 
              alignItems: 'center', 
              gap: '6px', 
              padding: '4px 10px', 
              borderRadius: '20px', 
              fontSize: '11px', 
              fontWeight: 700, 
              background: 'rgba(16, 185, 129, 0.15)', 
              color: 'var(--success)' 
            }}>
              <CheckCircle2 size={12} />
              REAL DATABASE RECORDS
            </span>
          </div>
          <p style={{ color: 'var(--text-muted)', fontSize: '13px', marginTop: '4px' }}>
            Generate and export genuine CSV spreadsheets from live database collections for tax compliance, accounting audits, and operations review.
          </p>
        </div>
      </div>

      {/* Category Tabs */}
      <div style={{ display: 'flex', gap: '10px', borderBottom: '1px solid var(--border)', paddingBottom: '12px' }}>
        {['all', 'Finance & Accounting', 'Treasury & Payouts', 'Revenue & Operations', 'Fleet Operations'].map(cat => (
          <button
            key={cat}
            className={`btn btn-sm ${selectedCategory === cat ? 'btn-primary' : 'btn-secondary'}`}
            onClick={() => setSelectedCategory(cat)}
            style={{ textTransform: 'capitalize' }}
          >
            {cat === 'all' ? 'All Reports' : cat}
          </button>
        ))}
      </div>

      {/* Reports Grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(340px, 1fr))', gap: '20px' }}>
        {filteredReports.map(report => (
          <div key={report.id} className="card" style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '10px' }}>
                <span className="badge badge-info" style={{ fontSize: '10px' }}>{report.category}</span>
                <span style={{ color: 'var(--text-muted)', fontSize: '11px' }}>Format: CSV / UTF-8</span>
              </div>
              <h3 style={{ fontSize: '16px', marginBottom: '8px' }}>{report.title}</h3>
              <p style={{ color: 'var(--text-muted)', fontSize: '12px', lineHeight: '1.4', marginBottom: '14px' }}>
                {report.description}
              </p>
              <div style={{ fontSize: '11px', color: 'var(--text-muted)', background: 'var(--bg-input)', padding: '8px 10px', borderRadius: '6px' }}>
                <strong>Fields:</strong> {report.fields}
              </div>
            </div>

            <div style={{ marginTop: '20px', paddingTop: '14px', borderTop: '1px solid var(--border)' }}>
              <button 
                className="btn btn-primary"
                onClick={() => handleDownload(report.id)}
                disabled={downloadingId === report.id}
                style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px' }}
              >
                <ArrowDownToLine size={16} />
                <span>{downloadingId === report.id ? 'Generating CSV...' : 'Download Live CSV Export'}</span>
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default ReportsExports;
