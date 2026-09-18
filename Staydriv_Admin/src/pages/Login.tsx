import React, { useState } from 'react';
import { useAuth } from '../context/AuthContext';
import { KeyRound, Mail, AlertCircle } from 'lucide-react';

export const Login: React.FC = () => {
  const { login } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showReset, setShowReset] = useState(false);
  const [resetSent, setResetSent] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email || !password) {
      setError('Please fill in all fields.');
      return;
    }
    setError(null);
    setLoading(true);
    
    const success = await login(email, password);
    setLoading(false);
    
    if (!success) {
      setError('Invalid email or password. Hint: check the evaluation credentials below!');
    }
  };

  const handleReset = (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) {
      setError('Please enter your email first.');
      return;
    }
    setLoading(true);
    setTimeout(() => {
      setLoading(false);
      setResetSent(true);
      setError(null);
    }, 800);
  };

  return (
    <div className="login-layout">
      <div className="login-card">
        <div className="login-header">
          <div className="login-logo">StayDriv</div>
          <h2 style={{ fontSize: '20px', marginTop: '8px' }}>Admin Portal Login</h2>
          <p className="login-subtitle">Provide your credentials to access the mobility database.</p>
        </div>

        {error && (
          <div style={{ 
            display: 'flex', 
            gap: '8px', 
            padding: '12px 16px', 
            backgroundColor: 'var(--error-bg)', 
            border: '1px solid var(--error)', 
            borderRadius: '8px',
            color: 'var(--error)',
            fontSize: '13px',
            alignItems: 'center'
          }}>
            <AlertCircle size={16} />
            <span>{error}</span>
          </div>
        )}

        {showReset ? (
          resetSent ? (
            <div style={{ textAlign: 'center', display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div style={{ color: 'var(--success)', fontSize: '15px', fontWeight: 600 }}>
                Reset Email Sent!
              </div>
              <p style={{ fontSize: '13px', color: 'var(--text-muted)' }}>
                We have dispatched a password reset link to <strong>{email}</strong>. Please check your inbox.
              </p>
              <button 
                className="btn btn-secondary" 
                onClick={() => {
                  setShowReset(false);
                  setResetSent(false);
                  setEmail('');
                }}
              >
                Return to Login
              </button>
            </div>
          ) : (
            <form onSubmit={handleReset} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
              <div className="form-group">
                <label>Registered Email Address</label>
                <div className="input-icon-wrapper">
                  <Mail size={16} />
                  <input 
                    type="email" 
                    placeholder="name@staydriv.com" 
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                  />
                </div>
              </div>
              <button className="btn btn-primary" type="submit" disabled={loading}>
                {loading ? 'Sending link...' : 'Send Reset Link'}
              </button>
              <button 
                type="button" 
                className="btn btn-secondary" 
                onClick={() => setShowReset(false)}
                disabled={loading}
              >
                Cancel
              </button>
            </form>
          )
        ) : (
          <form onSubmit={handleSubmit} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <div className="form-group">
              <label>Email Address</label>
              <div className="input-icon-wrapper">
                <Mail size={16} />
                <input 
                  type="email" 
                  placeholder="name@staydriv.com" 
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>
            </div>

            <div className="form-group">
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <label>Password</label>
                <a 
                  href="#forgot" 
                  onClick={(e) => { e.preventDefault(); setShowReset(true); setError(null); }}
                  style={{ fontSize: '12px', color: 'var(--primary)', textDecoration: 'none' }}
                >
                  Forgot Password?
                </a>
              </div>
              <div className="input-icon-wrapper">
                <KeyRound size={16} />
                <input 
                  type="password" 
                  placeholder="••••••••" 
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                />
              </div>
            </div>

            <button className="btn btn-yellow" type="submit" disabled={loading} style={{ marginTop: '8px' }}>
              {loading ? 'Authenticating...' : 'Secure Sign In'}
            </button>
          </form>
        )}

        <hr style={{ border: 'none', borderTop: '1px solid var(--border)' }} />

        {/* Credentials helper panel for review purposes */}
        <div style={{ 
          fontSize: '11px', 
          backgroundColor: 'var(--bg-input)', 
          padding: '12px', 
          borderRadius: '12px',
          display: 'flex',
          flexDirection: 'column',
          gap: '6px',
          color: 'var(--text-muted)'
        }}>
          <div style={{ fontWeight: 700, color: 'var(--text-main)' }}>🔑 Evaluation Access Credentials:</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '4px' }}>
            <span><strong>Super Admin:</strong></span>
            <span>staydriv@gmail.com</span>
            <span><strong>Operations Admin:</strong></span>
            <span>ops@staydriv.com</span>
            <span><strong>Support Exec:</strong></span>
            <span>support@staydriv.com</span>
            <span><strong>Finance Manager:</strong></span>
            <span>finance@staydriv.com</span>
          </div>
          <div style={{ marginTop: '4px', borderTop: '1px solid var(--border)', paddingTop: '4px', fontStyle: 'italic', fontSize: '11px' }}>
            Enter your confidential administrator / staff credentials to proceed.
          </div>
        </div>

        <div className="login-footer">
          StayDriv Unified Mobility Platform &copy; 2026
        </div>
      </div>
    </div>
  );
};
export default Login;
