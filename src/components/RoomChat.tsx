import React, { useState, useEffect, useRef } from 'react';
import { MessageCircle, X, Send, Heart, Smile } from 'lucide-react';
import { useGame } from '../context/GameContext';
import { useAuth } from '../context/AuthContext';

const QUICK_REACTIONS = ['❤️', '😘', '🔥', '🥺', '😂', '💍', '💖', '👏'];

export const RoomChat: React.FC = () => {
  const { room, messages, sendMessage, partner } = useGame();
  const { user } = useAuth();

  const [isOpen, setIsOpen] = useState(false);
  const [inputText, setInputText] = useState('');
  const [unreadCount, setUnreadCount] = useState(0);
  const [sending, setSending] = useState(false);

  const messagesEndRef = useRef<HTMLDivElement | null>(null);
  const lastSeenLengthRef = useRef<number>(messages.length);

  // Auto-scroll and unread badge tracking when new messages arrive
  useEffect(() => {
    if (isOpen) {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
      setUnreadCount(0);
      lastSeenLengthRef.current = messages.length;
    } else {
      if (messages.length > lastSeenLengthRef.current) {
        const incomingFromPartner = messages
          .slice(lastSeenLengthRef.current)
          .filter((m) => m.user_id !== user?.id);

        if (incomingFromPartner.length > 0) {
          setUnreadCount((prev) => prev + incomingFromPartner.length);
        }
        lastSeenLengthRef.current = messages.length;
      }
    }
  }, [messages, isOpen, user?.id]);

  const handleOpen = () => {
    setIsOpen(true);
    setUnreadCount(0);
    lastSeenLengthRef.current = messages.length;
  };

  const handleSend = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const text = inputText.trim();
    if (!text || sending) return;

    setInputText('');
    setSending(true);
    await sendMessage(text);
    setSending(false);
  };

  const handleQuickReaction = async (emoji: string) => {
    if (sending) return;
    setSending(true);
    await sendMessage(emoji);
    setSending(false);
  };

  if (!room) return null;

  return (
    <>
      {/* Floating Toggle Button */}
      {/* Floating Toggle Button (Guaranteed Perfect Circle) */}
      {!isOpen && (
        <button
          type="button"
          onClick={handleOpen}
          aria-label="Open couple chat"
          className="fixed bottom-6 right-6 z-50 w-14 h-14 rounded-full aspect-square bg-slate-900 border-2 border-rose-500/80 hover:border-rose-400 text-rose-400 hover:text-white hover:bg-rose-600 shadow-2xl shadow-rose-950/80 hover:shadow-rose-600/50 hover:scale-110 active:scale-95 transition-all flex items-center justify-center cursor-pointer group relative backdrop-blur-md"
        >
          <MessageCircle className="w-6 h-6 group-hover:scale-110 transition-transform" />
          
          {/* Notification Dot Badge over Chat Icon */}
          {unreadCount > 0 && (
            <span className="absolute -top-1 -right-1 flex h-4 w-4">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-4 w-4 bg-amber-400 border-2 border-slate-950 shadow-md"></span>
            </span>
          )}
        </button>
      )}

      {/* Floating Chat Modal */}
      {isOpen && (
        <div className="fixed bottom-6 right-6 z-50 w-[92vw] sm:w-96 max-h-[560px] h-[75vh] flex flex-col rounded-3xl bg-slate-900/95 border border-rose-500/40 shadow-2xl backdrop-blur-xl overflow-hidden animate-in fade-in slide-in-from-bottom-4 duration-200">
          {/* Header */}
          <div className="px-5 py-4 border-b border-slate-800 bg-slate-950/60 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-full bg-gradient-to-tr from-pink-500 to-rose-600 flex items-center justify-center text-white font-bold text-sm shadow-md">
                {partner?.display_name?.charAt(0).toUpperCase() || <Heart className="w-4 h-4" />}
              </div>
              <div className="text-left">
                <h4 className="text-sm font-bold text-white flex items-center gap-1.5 leading-none">
                  <span>{partner?.display_name || 'Partner Chat'}</span>
                  <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
                </h4>
                <span className="text-[11px] text-slate-400 mt-0.5 block">
                  Private Couple Room
                </span>
              </div>
            </div>

            <button
              type="button"
              onClick={() => setIsOpen(false)}
              className="p-1.5 rounded-xl hover:bg-slate-800 text-slate-400 hover:text-white transition-colors cursor-pointer"
              title="Close chat"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Messages Feed */}
          <div className="flex-1 overflow-y-auto p-4 space-y-3 text-left">
            {messages.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center text-center p-6 text-slate-400 space-y-2">
                <div className="p-3 rounded-2xl bg-rose-500/10 text-rose-400">
                  <Smile className="w-8 h-8" />
                </div>
                <p className="text-sm font-semibold text-slate-200">Say something sweet!</p>
                <p className="text-xs text-slate-500 max-w-xs">
                  Your messages are real-time, private, and seen only by you and your partner.
                </p>
              </div>
            ) : (
              messages.map((msg) => {
                const isMe = msg.user_id === user?.id;
                const formattedTime = new Date(msg.created_at).toLocaleTimeString([], {
                  hour: '2-digit',
                  minute: '2-digit',
                });

                return (
                  <div
                    key={msg.id}
                    className={`flex flex-col ${isMe ? 'items-end' : 'items-start'}`}
                  >
                    <span className="text-[10px] text-slate-500 px-1 mb-0.5">
                      {isMe ? 'You' : msg.display_name} • {formattedTime}
                    </span>
                    <div
                      className={`max-w-[82%] px-4 py-2.5 rounded-2xl text-sm break-words ${
                        isMe
                          ? 'bg-gradient-to-r from-pink-500 to-rose-600 text-white rounded-tr-sm shadow-md shadow-rose-900/30'
                          : 'bg-slate-800 border border-slate-700/80 text-slate-100 rounded-tl-sm'
                      }`}
                    >
                      {msg.message}
                    </div>
                  </div>
                );
              })
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Quick Reaction Bar */}
          <div className="px-3 py-1.5 bg-slate-950/40 border-t border-slate-800/80 flex items-center justify-between gap-1 overflow-x-auto scrollbar-none">
            {QUICK_REACTIONS.map((emoji) => (
              <button
                key={emoji}
                type="button"
                onClick={() => handleQuickReaction(emoji)}
                disabled={sending}
                className="text-lg p-1.5 rounded-xl hover:bg-slate-800/90 active:scale-125 transition-all cursor-pointer shrink-0"
                title={`Send ${emoji}`}
              >
                {emoji}
              </button>
            ))}
          </div>

          {/* Input Form */}
          <form
            onSubmit={handleSend}
            className="p-3 bg-slate-950/80 border-t border-slate-800 flex items-center gap-2"
          >
            <input
              type="text"
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder="Whisper a sweet message..."
              disabled={sending}
              maxLength={300}
              className="flex-1 px-4 py-2.5 rounded-xl bg-slate-900 border border-slate-700/80 focus:border-rose-400 text-white placeholder-slate-500 text-sm focus:outline-none focus:ring-1 focus:ring-rose-400 transition-colors"
            />
            <button
              type="submit"
              disabled={!inputText.trim() || sending}
              className="p-2.5 rounded-xl bg-gradient-to-r from-pink-500 to-rose-600 hover:from-pink-600 hover:to-rose-700 text-white shadow-md shadow-rose-600/30 disabled:opacity-40 disabled:cursor-not-allowed transition-all cursor-pointer flex items-center justify-center shrink-0"
              title="Send message"
            >
              <Send className="w-4 h-4" />
            </button>
          </form>
        </div>
      )}
    </>
  );
};
