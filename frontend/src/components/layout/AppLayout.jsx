import { NavLink, Outlet, useNavigate } from "react-router-dom";
import {
  LayoutDashboard,
  Sprout,
  ShoppingBasket,
  ClipboardList,
  MapPin,
  TrendingUp,
  ShieldCheck,
  LogOut,
  BadgeCheck,
  AlertCircle,
  Bell,
  MessageCircle,
  BarChart3,
  RefreshCw,
} from "lucide-react";
import Logo from "../ui/Logo";
import Avatar from "../ui/Avatar";
import ConfirmationModal from "../ui/ConfirmationModal";
import { useState } from "react";
import { useAuth } from "../../contexts/AuthContext";
import { ROLES, ROLE_LABELS } from "../../lib/constants";

const NAV = {
  [ROLES.FARMER]: [
    { to: "/farmer", label: "Dashboard", icon: LayoutDashboard, end: true },
    { to: "/farmer/plant", label: "List Crops", icon: Sprout },
    { to: "/farmer/orders", label: "Orders", icon: ClipboardList },
    { to: "/farmer/analytics", label: "Analytics", icon: BarChart3 },
    { to: "/farmer/messages", label: "Messages", icon: MessageCircle },
    { to: "/farmer/profile", label: "Farm Profile", icon: MapPin },
  ],
  [ROLES.BUYER]: [
    { to: "/buyer", label: "Marketplace", icon: ShoppingBasket, end: true },
    { to: "/buyer/orders", label: "My Orders", icon: ClipboardList },
    { to: "/buyer/messages", label: "Messages", icon: MessageCircle },
    { to: "/buyer/notifications", label: "Notifications", icon: Bell },
    { to: "/buyer/profile", label: "Profile", icon: MapPin },
  ],
  [ROLES.ADMIN]: [
    { to: "/admin", label: "Overview", icon: LayoutDashboard, end: true },
    { to: "/admin/users", label: "Users", icon: ShieldCheck },
    { to: "/admin/transactions", label: "Transactions", icon: ClipboardList },
    { to: "/admin/market", label: "Market Data", icon: TrendingUp },
    { to: "/admin/profile", label: "Profile", icon: MapPin },
  ],
};

export default function AppLayout() {
  const { user, logout } = useAuth();
  const navigate = useNavigate();

  const items = NAV[user.role] || [];

  if (!user) return null;

  const [logoutOpen, setLogoutOpen] = useState(false);
  const confirmLogout = () => setLogoutOpen(true);
  const doLogout = () => {
    setLogoutOpen(false);
    logout();
    navigate("/login", { replace: true });
  };

  return (
    <div className="h-screen flex overflow-hidden bg-slate-50">
      {/* ── Sidebar ── */}
      <aside className="hidden lg:flex w-64 shrink-0 flex-col bg-brand-800 overflow-y-auto">
        {/* Logo */}
        <div className="px-5 py-5 border-b border-brand-700">
          <Logo light />
        </div>

        {/* Role pill */}
        <div className="px-4 pt-4 pb-2">
          <span className="inline-block rounded-lg bg-brand-700 px-3 py-1 text-xs font-bold uppercase tracking-widest text-brand-200">
            {ROLE_LABELS[user.role]}
          </span>
        </div>

        {/* Nav items */}
        <nav className="flex-1 px-3 py-2 space-y-0.5">
          {items.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                `flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                  isActive
                    ? "bg-brand-600 text-white shadow-soft"
                    : "text-brand-200 hover:bg-brand-700 hover:text-white"
                }`
              }
            >
              <Icon size={18} />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>

        {/* User info + logout */}
        <div className="px-3 py-4 border-t border-brand-700 space-y-3">
          <div className="flex items-center gap-3 px-3">
            <Avatar user={user} />
            <div className="min-w-0">
              <div className="truncate text-sm font-semibold text-white">
                {user.name}
              </div>
              <div className="truncate text-xs text-brand-300">
                {user.email}
              </div>
            </div>
          </div>
          <>
            <button
              onClick={confirmLogout}
              className="flex w-full items-center gap-3 px-3 py-2 rounded-xl text-sm font-semibold text-brand-200 hover:bg-red-900/60 hover:text-red-300 transition-colors"
            >
              <LogOut size={16} />
              Log out
            </button>
            <ConfirmationModal
              open={logoutOpen}
              title="Log out"
              message="Log out of your AgriLink account?"
              confirmLabel="Log out"
              cancelLabel="Stay logged in"
              onConfirm={doLogout}
              onClose={() => setLogoutOpen(false)}
            />
          </>
        </div>
      </aside>

      {/* ── Main ── */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Top header */}
        <header className="sticky top-0 z-30 border-b-2 border-slate-200 bg-white">
          <div className="flex items-center justify-between gap-3 px-4 py-3 lg:px-6">
            <div className="lg:hidden">
              <Logo />
            </div>
            <div className="hidden lg:block">
              <div className="text-xs font-bold uppercase tracking-widest text-slate-400">
                {ROLE_LABELS[user.role]} workspace
              </div>
              <div className="font-display text-lg font-bold text-slate-900">
                Welcome back, {user.name?.split(" ")[0] || "friend"}
              </div>
            </div>

            <div className="flex items-center gap-3">
              {user.verified ? (
                <span className="badge-green hidden sm:inline-flex">
                  <BadgeCheck size={13} /> Verified
                </span>
              ) : (
                <span
                  className="badge-amber hidden sm:inline-flex"
                  title="Awaiting admin verification"
                >
                  <AlertCircle size={13} /> Pending
                </span>
              )}
              <div className="flex items-center gap-2">
                <Avatar user={user} />
                <div className="hidden sm:block leading-tight">
                  <div className="text-sm font-semibold text-slate-900">
                    {user.name}
                  </div>
                  <div className="text-xs text-slate-500">{user.email}</div>
                </div>
              </div>
            </div>
          </div>

          {/* Mobile nav */}
          <nav className="lg:hidden flex gap-1.5 overflow-x-auto px-3 pb-2.5">
            {items.map(({ to, label, icon: Icon, end }) => (
              <NavLink
                key={to}
                to={to}
                end={end}
                className={({ isActive }) =>
                  `flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold whitespace-nowrap transition ${
                    isActive
                      ? "bg-brand-700 text-white"
                      : "bg-slate-100 text-slate-600 hover:bg-slate-200"
                  }`
                }
              >
                <Icon size={13} />
                {label}
              </NavLink>
            ))}
            <button
              onClick={confirmLogout}
              className="ml-auto flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-semibold bg-red-100 text-red-700"
            >
              <LogOut size={13} /> Logout
            </button>
          </nav>
        </header>

        <main className="flex-1 overflow-y-auto flex flex-col px-4 py-5 sm:py-6 lg:px-6 lg:py-8 animate-fade-in">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
