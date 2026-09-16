import React, { useState } from 'react';
import { useDatabase } from '../context/DatabaseContext';
import { useAuth } from '../context/AuthContext';
import { Search, Send, User, MessageSquare, AlertTriangle, ShieldCheck, CheckCircle2, X } from 'lucide-react';

export const Support: React.FC = () => {
  const { supportTickets, replyToSupportTicket } = useDatabase();
  const { user } = useAuth();
  
  const [selectedTicketId, setSelectedTicketId] = useState<string | null>(
    supportTickets.length > 0 ? supportTickets[0].ticketId : null
  );
  const [replyText, setReplyText] = useState('');
  const [searchTerm, setSearchTerm] = useState('');

  const activeTicket = supportTickets.find(t => t.ticketId === selectedTicketId);

  // Filtered List
  const filteredTickets = supportTickets.filter(t => 
    t.ticketId.toLowerCase().includes(searchTerm.toLowerCase()) ||
    t.creatorName.toLowerCase().includes(searchTerm.toLowerCase()) ||
    t.subject.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const handleSendReply = (e: React.FormEvent) => {
    e.preventDefault();
    if (!replyText.trim() || !selectedTicketId) return;

    replyToSupportTicket(selectedTicketId, replyText.trim());
    setReplyText('');
  };

  const getCategoryColor = (cat: string) => {
    switch (cat) {
      case 'safety': return '#ef4444';
      case 'payment_issue': return '#fbbf24';
      case 'app_bug': return '#06b6d4';
      default: return '#3b82f6';
    }
  };

  return (
    <div className="page-container">
      <div>
        <h2>Customer & Partner Support</h2>
        <p style={{ color: 'var(--text-muted)', fontSize: '14px' }}>Resolve client complaints, audit driver tickets, and participate in chat resolutions.</p>
      </div>

      <div className="ticket-container">
        
        {/* Left Side: Ticket search & scroll list */}
        <div className="ticket-list">
          <div style={{ padding: '12px', borderBottom: '1px solid var(--border)' }}>
            <div className="input-icon-wrapper">
              <Search size={14} />
              <input 
                type="text" 
                placeholder="Search ticket IDs, creators..." 
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                style={{ padding: '8px 10px 8px 30px', fontSize: '12px', width: '100%' }}
              />
            </div>
          </div>
          
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {filteredTickets.map(ticket => (
              <div 
                key={ticket.ticketId}
                className={`ticket-item ${selectedTicketId === ticket.ticketId ? 'active' : ''}`}
                onClick={() => setSelectedTicketId(ticket.ticketId)}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '4px' }}>
                  <span style={{ fontWeight: 700, fontSize: '13px' }}>{ticket.ticketId}</span>
                  <span className={`badge badge-${ticket.status}`} style={{ fontSize: '10px' }}>
                    {ticket.status}
                  </span>
                </div>
                
                <div style={{ fontWeight: 600, fontSize: '13px', color: 'var(--text-main)' }}>{ticket.subject}</div>
                
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '11px', marginTop: '6px', color: 'var(--text-muted)' }}>
                  <span>{ticket.creatorName} ({ticket.creatorRole})</span>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
                    <div style={{ width: '6px', height: '6px', borderRadius: '50%', backgroundColor: getCategoryColor(ticket.category) }} />
                    <span style={{ textTransform: 'capitalize' }}>{ticket.category.replace('_', ' ')}</span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Right Side: Conversation Workspace */}
        <div className="chat-console">
          {activeTicket ? (
            <>
              {/* Chat Header details */}
              <div style={{ padding: '16px 24px', borderBottom: '1px solid var(--border)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', backgroundColor: 'var(--bg-card)' }}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                    <h3 style={{ fontSize: '15px' }}>{activeTicket.subject}</h3>
                    <span className={`badge badge-${activeTicket.status}`} style={{ fontSize: '10px' }}>
                      {activeTicket.status}
                    </span>
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)', marginTop: '2px' }}>
                    Ticket created by {activeTicket.creatorName} ({activeTicket.creatorRole}) • Cat: {activeTicket.category.replace('_', ' ')}
                  </div>
                </div>
                {activeTicket.status !== 'resolved' && (
                  <button 
                    className="btn btn-success btn-sm"
                    onClick={() => replyToSupportTicket(activeTicket.ticketId, "[Platform Support Agent marked this complaint ticket as RESOLVED]")}
                  >
                    <CheckCircle2 size={14} />
                    <span>Resolve Ticket</span>
                  </button>
                )}
              </div>

              {/* Chat messages stream */}
              <div className="chat-messages">
                {/* Initial Description */}
                <div style={{ display: 'flex', gap: '10px', backgroundColor: 'var(--bg-card)', padding: '14px', borderRadius: '12px', border: '1px solid var(--border)', fontSize: '13px', marginBottom: '10px' }}>
                  <AlertTriangle size={18} style={{ color: 'var(--warning)', flexShrink: 0 }} />
                  <div>
                    <strong>Creator Initial Description:</strong>
                    <p style={{ marginTop: '4px', color: 'var(--text-main)', lineHeight: 1.4 }}>{activeTicket.message}</p>
                  </div>
                </div>

                {activeTicket.chatHistory.map((chat, idx) => {
                  const isAgent = chat.senderId === user?.uid || chat.senderName.includes('Support') || chat.senderName.includes('Agent');
                  return (
                    <div 
                      key={idx}
                      className={`chat-bubble ${isAgent ? 'bubble-sent' : 'bubble-received'}`}
                    >
                      <div style={{ fontSize: '10px', opacity: 0.8, fontWeight: 700, marginBottom: '2px' }}>
                        {chat.senderName}
                      </div>
                      <div>{chat.message}</div>
                      <div style={{ fontSize: '9px', opacity: 0.7, textAlign: 'right', marginTop: '4px' }}>
                        {new Date(chat.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Chat Input Console */}
              {activeTicket.status !== 'resolved' ? (
                <form onSubmit={handleSendReply} className="chat-input-area">
                  <input 
                    type="text" 
                    placeholder="Type support reply message and hit Send..." 
                    value={replyText}
                    onChange={(e) => setReplyText(e.target.value)}
                    style={{ flex: 1 }}
                    required
                  />
                  <button type="submit" className="btn btn-primary">
                    <Send size={14} />
                    <span>Send</span>
                  </button>
                </form>
              ) : (
                <div style={{ padding: '16px', backgroundColor: 'var(--bg-input)', borderTop: '1px solid var(--border)', textAlign: 'center', fontSize: '13px', color: 'var(--text-muted)', fontWeight: 500 }}>
                  🟢 This complaint ticket has been marked as RESOLVED.
                </div>
              )}
            </>
          ) : (
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '12px', color: 'var(--text-muted)' }}>
              <MessageSquare size={36} />
              <span>Select a support ticket from the queue list to start resolving.</span>
            </div>
          )}
        </div>

      </div>
    </div>
  );
};
export default Support;
