import { useEffect, useRef, useState } from "react";
import { X, Send, Loader2, MessageCircle, Paperclip } from "lucide-react";
import { sendMessage, subscribeMessages, uploadChatAttachment } from "../../services/chatService";
import Avatar from "./Avatar";

export default function ChatWindow({ chatId, currentUser, otherName, otherPhoto, onClose }) {
  const [messages, setMessages] = useState([]);
  const [text,     setText]     = useState("");
  const [file,     setFile]     = useState(null);
  const [sending,  setSending]  = useState(false);
  const bottomRef = useRef(null);
  const fileRef = useRef(null);

  useEffect(() => {
    const unsub = subscribeMessages(chatId, setMessages);
    return unsub;
  }, [chatId]);

  // Auto-scroll to latest message
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const submit = async (e) => {
    e.preventDefault();
    if ((!text.trim() && !file) || sending) return;
    setSending(true);
    try {
      let attachment = null;
      if (file) attachment = await uploadChatAttachment(file, chatId);
      await sendMessage(chatId, {
        senderId:   currentUser.id,
        senderName: currentUser.name,
        text,
        attachment,
      });
      setText("");
      setFile(null);
    } finally {
      setSending(false);
    }
  };

  const fmt = (ts) => {
    if (!ts) return "";
    const d = ts.toDate ? ts.toDate() : new Date(ts);
    return d.toLocaleTimeString("en-PH", { hour: "2-digit", minute: "2-digit" });
  };

  return (
    <div className="fixed bottom-6 right-6 z-50 flex flex-col w-80 sm:w-96 bg-white rounded-2xl border-2 border-brand-200 shadow-strong overflow-hidden animate-slide-up">
      {/* Header */}
      <div className="flex items-center justify-between bg-brand-800 px-4 py-3">
        <div className="flex items-center gap-2">
          <Avatar
            photo={otherPhoto}
            name={otherName}
            className="h-8 w-8 rounded-xl"
            textClassName="text-xs"
          />
          <div>
            <p className="text-sm font-bold text-white">{otherName}</p>
            <p className="text-xs text-brand-300">AgriLink Chat</p>
          </div>
        </div>
        <button onClick={onClose} className="text-brand-300 hover:text-white transition-colors">
          <X size={18} />
        </button>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3 bg-slate-50" style={{ maxHeight: 360 }}>
        {messages.length === 0 && (
          <div className="text-center py-8">
            <MessageCircle size={28} className="mx-auto text-slate-300 mb-2" />
            <p className="text-xs text-slate-400">No messages yet. Say hi!</p>
          </div>
        )}
        {messages.map((m) => {
          const isMe = m.senderId === currentUser.id;
          return (
            <div key={m.id} className={`flex ${isMe ? "justify-end" : "justify-start"}`}>
              <div className={`max-w-[75%] rounded-2xl px-3 py-2 ${
                isMe
                  ? "bg-brand-700 text-white rounded-br-sm"
                  : "bg-white border-2 border-slate-100 text-slate-800 rounded-bl-sm"
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
                      <video controls className="max-h-48 rounded-lg border border-white/20">
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
                  {fmt(m.timestamp)}
                </p>
              </div>
            </div>
          );
        })}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={submit} className="flex items-center gap-2 border-t-2 border-slate-100 px-3 py-2.5 bg-white">
        <input
          ref={fileRef}
          type="file"
          className="hidden"
          onChange={(e) => setFile(e.target.files?.[0] || null)}
        />
        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          className="grid h-9 w-9 place-items-center rounded-xl border-2 border-slate-200 text-slate-500 hover:border-brand-300 hover:text-brand-700 transition-colors"
          title="Attach file"
        >
          <Paperclip size={15} />
        </button>
        <input
          className="flex-1 rounded-xl border-2 border-slate-200 bg-slate-50 px-3 py-2 text-sm focus:border-brand-500 focus:outline-none focus:ring-2 focus:ring-brand-100 transition"
          placeholder="Type a message…"
          value={text}
          onChange={(e) => setText(e.target.value)}
          disabled={sending}
          autoFocus
        />
        <button
          type="submit"
          disabled={(!text.trim() && !file) || sending}
          className="grid h-9 w-9 place-items-center rounded-xl bg-brand-700 text-white hover:bg-brand-800 disabled:opacity-40 transition-colors"
        >
          {sending
            ? <Loader2 size={15} className="animate-spin" />
            : <Send size={15} />
          }
        </button>
      </form>
    </div>
  );
}
