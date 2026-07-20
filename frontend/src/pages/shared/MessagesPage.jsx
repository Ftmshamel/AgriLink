import { useEffect, useRef, useState } from "react";
import { MessageCircle, Send, Loader2, Search, Paperclip } from "lucide-react";
import { useAuth } from "../../contexts/AuthContext";
import { useDb } from "../../contexts/useDb";
import { db } from "../../services/db";
import {
  subscribeUserChats, subscribeMessages, sendMessage, uploadChatAttachment,
} from "../../services/chatService";
import Avatar from "../../components/ui/Avatar";

export default function MessagesPage() {
  const { user } = useAuth();
  const users = useDb(() => db.listUsers(), []);

  const [chats,      setChats]      = useState([]);
  const [activeChat, setActiveChat] = useState(null);
  const [messages,   setMessages]   = useState([]);
  const [text,       setText]       = useState("");
  const [file,       setFile]       = useState(null);
  const [sending,    setSending]    = useState(false);
  const [search,     setSearch]     = useState("");
  const bottomRef = useRef(null);
  const fileRef = useRef(null);

  // Load all chats for this user
  useEffect(() => {
    const unsub = subscribeUserChats(user.id, setChats);
    return unsub;
  }, [user.id]);

  // Load messages for active chat
  const activeChatId = activeChat?.id ?? null;
  useEffect(() => {
    if (!activeChatId) { setMessages([]); return; } // eslint-disable-line react-hooks/set-state-in-effect
    const unsub = subscribeMessages(activeChatId, setMessages);
    return unsub;
  }, [activeChatId]);

  // Auto-scroll to latest message
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const submit = async (e) => {
    e.preventDefault();
    if ((!text.trim() && !file) || !activeChat || sending) return;
    setSending(true);
    try {
      let attachment = null;
      if (file) attachment = await uploadChatAttachment(file, activeChat.id);
      await sendMessage(activeChat.id, {
        senderId:   user.id,
        senderName: user.name,
        text,
        attachment,
      });
      setText("");
      setFile(null);
    } finally {
      setSending(false);
    }
  };

  const fmtTime = (ts) => {
    if (!ts) return "";
    const d = ts.toDate ? ts.toDate() : new Date(ts);
    return d.toLocaleTimeString("en-PH", { hour: "2-digit", minute: "2-digit" });
  };

  const fmtDay = (ts) => {
    if (!ts) return "";
    const d = ts.toDate ? ts.toDate() : new Date(ts);
    return d.toLocaleDateString("en-PH", { month: "short", day: "numeric" });
  };

  const otherName = (chat) =>
    user.id === chat.buyerId ? chat.farmerName : chat.buyerName;
  const otherUser = (chat) =>
    users.find((u) => u.id === (user.id === chat.buyerId ? chat.farmerId : chat.buyerId));

  const filtered = chats.filter((c) =>
    search ? otherName(c).toLowerCase().includes(search.toLowerCase()) : true,
  );

  return (
    <div className="flex-1 flex flex-col space-y-4">
      <div className="border-l-4 border-brand-600 pl-4">
        <h1 className="font-display text-2xl font-extrabold text-slate-900">Messages</h1>
        <p className="text-sm text-slate-500">Real-time chat with your buyers and farmers.</p>
      </div>

      <div className="flex-1 grid lg:grid-cols-5 gap-4 min-h-0">

        {/* ── Chat list ── */}
        <aside className="lg:col-span-2 card overflow-hidden flex flex-col">
          <div className="border-b-2 border-slate-100 px-4 py-3 bg-brand-50">
            <p className="text-xs font-bold uppercase tracking-widest text-brand-700 mb-2">
              {chats.length} conversation{chats.length !== 1 ? "s" : ""}
            </p>
            <div className="relative">
              <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                className="input py-1.5 pl-8 text-xs"
                placeholder="Search…"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>

          <div className="flex-1 overflow-y-auto divide-y divide-slate-100">
            {filtered.length === 0 && (
              <div className="flex flex-col items-center justify-center py-16 text-center px-4">
                <MessageCircle size={28} className="text-slate-300 mb-2" />
                <p className="text-sm text-slate-500">No conversations yet.</p>
                <p className="text-xs text-slate-400 mt-1">
                  Start a chat from an order in your Orders page.
                </p>
              </div>
            )}
            {filtered.map((chat) => {
              const isActive = activeChat?.id === chat.id;
              return (
                <button
                  key={chat.id}
                  onClick={() => setActiveChat(chat)}
                  className={`w-full text-left px-4 py-3 flex items-center gap-3 transition-colors border-l-4 ${
                    isActive
                      ? "bg-brand-50 border-l-brand-600"
                      : "hover:bg-slate-50 border-l-transparent"
                  }`}
                >
                  <Avatar
                    user={otherUser(chat)}
                    name={otherName(chat)}
                    className="h-10 w-10 rounded-xl"
                  />
                  <div className="min-w-0 flex-1">
                    <p className="font-bold text-slate-900 truncate text-sm">{otherName(chat)}</p>
                    {chat.orderCrop && (
                      <p className="text-xs text-brand-600 truncate">re: {chat.orderCrop}</p>
                    )}
                    {chat.lastMessage && (
                      <p className="text-xs text-slate-400 truncate">{chat.lastMessage}</p>
                    )}
                  </div>
                  {chat.lastAt && (
                    <span className="text-xs text-slate-400 shrink-0">{fmtDay(chat.lastAt)}</span>
                  )}
                </button>
              );
            })}
          </div>
        </aside>

        {/* ── Chat window ── */}
        <section className="lg:col-span-3 card overflow-hidden flex flex-col">
          {!activeChat ? (
            <div className="flex-1 flex flex-col items-center justify-center text-center p-8">
              <div className="grid h-20 w-20 place-items-center rounded-2xl bg-brand-50 text-brand-400 mb-4">
                <MessageCircle size={36} />
              </div>
              <p className="font-bold text-slate-700">Select a conversation</p>
              <p className="text-sm text-slate-400 mt-1">
                Choose a chat from the left to start messaging.
              </p>
            </div>
          ) : (
            <>
              {/* Header */}
              <div className="bg-brand-800 px-5 py-3 flex items-center gap-3">
                <Avatar
                  user={otherUser(activeChat)}
                  name={otherName(activeChat)}
                  className="h-9 w-9 rounded-xl"
                />
                <div>
                  <p className="font-bold text-white text-sm">{otherName(activeChat)}</p>
                  {activeChat.orderCrop && (
                    <p className="text-xs text-brand-300">Order: {activeChat.orderCrop}</p>
                  )}
                </div>
              </div>

              {/* Messages */}
              <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3 bg-slate-50">
                {messages.length === 0 && (
                  <div className="flex h-full flex-col items-center justify-center text-center py-10">
                    <MessageCircle size={24} className="text-slate-300 mb-2" />
                    <p className="text-xs text-slate-400">No messages yet. Say hi!</p>
                  </div>
                )}
                {messages.map((m) => {
                  const isMe = m.senderId === user.id;
                  return (
                    <div key={m.id} className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
                      <div className={`max-w-[72%] rounded-2xl px-4 py-2.5 ${
                        isMe
                          ? "bg-brand-700 text-white rounded-br-sm"
                          : "bg-white border-2 border-slate-100 text-slate-800 rounded-bl-sm shadow-sm"
                      }`}>
                        {!isMe && (
                          <p className="text-xs font-bold mb-0.5 text-brand-600">{m.senderName}</p>
                        )}
                        <p className="text-sm leading-relaxed">{m.text}</p>
                        {m.attachment?.url && (
                          <div className="mt-2">
                            {m.attachment.type?.startsWith("image/") ? (
                              <a href={m.attachment.url} target="_blank" rel="noreferrer">
                                <img
                                  src={m.attachment.url}
                                  alt={m.attachment.name || "attachment"}
                                  className="max-h-40 rounded-lg border border-white/20 object-contain bg-black/5"
                                />
                              </a>
                            ) : m.attachment.type?.startsWith("video/") ? (
                              <video controls className="max-h-52 rounded-lg border border-white/20">
                                <source src={m.attachment.url} type={m.attachment.type} />
                              </video>
                            ) : (
                              <a
                                href={m.attachment.url}
                                target="_blank"
                                rel="noreferrer"
                                className={`inline-flex items-center gap-1 rounded-md px-2 py-1 text-xs font-semibold ${
                                  isMe ? "bg-white/20 text-white" : "bg-slate-100 text-slate-700"
                                }`}
                              >
                                <Paperclip size={12} />
                                {m.attachment.name || "Open attachment"}
                              </a>
                            )}
                          </div>
                        )}
                        <p className={`text-xs mt-1 ${isMe ? "text-brand-300" : "text-slate-400"}`}>
                          {fmtTime(m.timestamp)}
                        </p>
                      </div>
                    </div>
                  );
                })}
                <div ref={bottomRef} />
              </div>

              {/* Input */}
              <form onSubmit={submit} className="flex items-center gap-2 border-t-2 border-slate-100 px-4 py-3 bg-white">
                <input
                  ref={fileRef}
                  type="file"
                  className="hidden"
                  onChange={(e) => setFile(e.target.files?.[0] || null)}
                />
                <button
                  type="button"
                  onClick={() => fileRef.current?.click()}
                  className="grid h-10 w-10 place-items-center rounded-xl border-2 border-slate-200 text-slate-500 hover:border-brand-300 hover:text-brand-700 transition-colors"
                  title="Attach file"
                >
                  <Paperclip size={16} />
                </button>
                <input
                  className="flex-1 rounded-xl border-2 border-slate-200 bg-slate-50 px-4 py-2.5 text-sm focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-100 transition"
                  placeholder="Type a message…"
                  value={text}
                  onChange={(e) => setText(e.target.value)}
                  disabled={sending}
                />
                <button
                  type="submit"
                  disabled={(!text.trim() && !file) || sending}
                  className="grid h-10 w-10 place-items-center rounded-xl bg-brand-700 text-white hover:bg-brand-800 disabled:opacity-40 transition-colors"
                >
                  {sending
                    ? <Loader2 size={16} className="animate-spin" />
                    : <Send size={16} />
                  }
                </button>
              </form>
            </>
          )}
        </section>
      </div>
    </div>
  );
}
