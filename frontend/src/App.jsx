import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AuthProvider, useAuth } from "./contexts/AuthContext";
import { ToastProvider } from "./contexts/ToastContext";

import Landing  from "./pages/Landing";
import Login    from "./pages/Login";
import Register from "./pages/Register";

import AppLayout       from "./components/layout/AppLayout";
import ProtectedRoute  from "./components/layout/ProtectedRoute";

import FarmerDashboard from "./pages/farmer/FarmerDashboard";
import FarmerPlant     from "./pages/farmer/FarmerPlant";
import FarmerOrders    from "./pages/farmer/FarmerOrders";
import FarmerProfile   from "./pages/farmer/FarmerProfile";
import FarmerAnalytics from "./pages/farmer/FarmerAnalytics";

import BuyerMarketplace from "./pages/buyer/BuyerMarketplace";
import BuyerOrders      from "./pages/buyer/BuyerOrders";
import BuyerProfile     from "./pages/buyer/BuyerProfile";

import AdminOverview     from "./pages/admin/AdminOverview";
import AdminUsers        from "./pages/admin/AdminUsers";
import AdminTransactions from "./pages/admin/AdminTransactions";
import AdminMarket       from "./pages/admin/AdminMarket";
import AdminProfile      from "./pages/admin/AdminProfile";
import MessagesPage      from "./pages/shared/MessagesPage";
import NotificationsPage from "./pages/shared/NotificationsPage";

import { ROLES } from "./lib/constants";

function RootRedirect() {
  const { user, loading } = useAuth();
  if (loading) return null;
  if (!user) return <Landing />;
  return <Navigate to={`/${user.role}`} replace />;
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <ToastProvider>
        <Routes>
          <Route path="/"         element={<RootRedirect />} />
          <Route path="/login"    element={<Login />} />
          <Route path="/register" element={<Register />} />

          {/* Farmer */}
          <Route
            path="/farmer"
            element={
              <ProtectedRoute roles={[ROLES.FARMER]}>
                <AppLayout />
              </ProtectedRoute>
            }
          >
            <Route index                   element={<FarmerDashboard />} />
            <Route path="plant"            element={<FarmerPlant />} />
            <Route path="orders"           element={<FarmerOrders />} />
            <Route path="analytics"        element={<FarmerAnalytics />} />
            <Route path="messages"         element={<MessagesPage />} />
            <Route path="profile"          element={<FarmerProfile />} />
          </Route>

          {/* Buyer */}
          <Route
            path="/buyer"
            element={
              <ProtectedRoute roles={[ROLES.BUYER]}>
                <AppLayout />
              </ProtectedRoute>
            }
          >
            <Route index                   element={<BuyerMarketplace />} />
            <Route path="orders"           element={<BuyerOrders />} />
            <Route path="messages"         element={<MessagesPage />} />
            <Route path="notifications"    element={<NotificationsPage />} />
            <Route path="profile"          element={<BuyerProfile />} />
          </Route>

          {/* Admin */}
          <Route
            path="/admin"
            element={
              <ProtectedRoute roles={[ROLES.ADMIN]}>
                <AppLayout />
              </ProtectedRoute>
            }
          >
            <Route index               element={<AdminOverview />} />
            <Route path="users"        element={<AdminUsers />} />
            <Route path="transactions" element={<AdminTransactions />} />
            <Route path="market"       element={<AdminMarket />} />
            <Route path="profile"      element={<AdminProfile />} />
          </Route>

          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
        </ToastProvider>
      </AuthProvider>
    </BrowserRouter>
  );
}
