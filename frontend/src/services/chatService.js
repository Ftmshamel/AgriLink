// Real-time chat service using a dedicated Firestore top-level collection.
// Separate from the agriData adapter — uses Firebase directly.

import {
  collection, doc, addDoc, onSnapshot, query,
  orderBy, serverTimestamp, setDoc, getDoc, updateDoc,
} from "firebase/firestore";
import { db as firestore } from "./firebase";
import { app, isFirebaseConfigured } from "./firebase";
import { getStorage, ref, uploadBytes, getDownloadURL } from "firebase/storage";

const CHATS = "chats";
let storage = null;
if (isFirebaseConfigured && app) storage = getStorage(app);

// Build a stable chat ID from two user IDs (sorted so order doesn't matter)
export const chatId = (idA, idB) => [idA, idB].sort().join("__");

// Get or create the chat document for a buyer-farmer pair
export async function ensureChat({ buyerId, buyerName, farmerId, farmerName, orderId, orderCrop }) {
  if (!firestore) throw new Error("Firebase not configured");
  const id  = chatId(buyerId, farmerId);
  const ref = doc(firestore, CHATS, id);
  const snap = await getDoc(ref);
  if (!snap.exists()) {
    await setDoc(ref, {
      id,
      buyerId,
      buyerName,
      farmerId,
      farmerName,
      orderId:   orderId   || null,
      orderCrop: orderCrop || null,
      lastMessage: null,
      lastAt:      null,
      createdAt:   serverTimestamp(),
    });
  }
  return id;
}

// Send a message to a chat
export async function sendMessage(cid, { senderId, senderName, text, attachment = null }) {
  if (!firestore) throw new Error("Firebase not configured");
  const msgRef = collection(firestore, CHATS, cid, "messages");
  await addDoc(msgRef, {
    senderId,
    senderName,
    text:      (text || "").trim(),
    attachment,
    timestamp: serverTimestamp(),
  });
  // Update last message preview on the parent doc
  await updateDoc(doc(firestore, CHATS, cid), {
    lastMessage: attachment?.name ? `Attachment: ${attachment.name}` : (text || "").trim().slice(0, 80),
    lastAt:      serverTimestamp(),
  });
}

// Upload any attachment (image/video/file) for chat
export async function uploadChatAttachment(file, chatIdValue) {
  if (!file) return null;
  // Firebase path if configured
  if (storage) {
    const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");
    const path = `chat-attachments/${chatIdValue}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${safeName}`;
    const r = ref(storage, path);
    await uploadBytes(r, file, { contentType: file.type || "application/octet-stream" });
    const url = await getDownloadURL(r);
    return {
      kind: "firebase",
      path,
      url,
      name: file.name,
      type: file.type || "application/octet-stream",
      size: file.size || 0,
    };
  }
  // Local fallback as data URL
  const dataUrl = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
  return {
    kind: "data-url",
    path: null,
    url: dataUrl,
    name: file.name,
    type: file.type || "application/octet-stream",
    size: file.size || 0,
  };
}

// Subscribe to messages in a chat — returns unsubscribe fn
export function subscribeMessages(cid, callback) {
  if (!firestore) return () => {};
  const q = query(
    collection(firestore, CHATS, cid, "messages"),
    orderBy("timestamp", "asc"),
  );
  return onSnapshot(q, (snap) => {
    const msgs = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    callback(msgs);
  });
}

// Subscribe to all chats for a user (buyer or farmer)
export function subscribeUserChats(userId, callback) {
  if (!firestore) return () => {};
  // We query both sides since chatId is composite — listen to the whole collection
  // and filter client-side (small enough for a marketplace)
  return onSnapshot(collection(firestore, CHATS), (snap) => {
    const chats = snap.docs
      .map((d) => ({ id: d.id, ...d.data() }))
      .filter((c) => c.buyerId === userId || c.farmerId === userId)
      .sort((a, b) => (b.lastAt?.seconds ?? 0) - (a.lastAt?.seconds ?? 0));
    callback(chats);
  });
}
