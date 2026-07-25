# AgriLink Mobile

Flutter mobile application for four roles:

- Consumer: account access, marketplace, crop details, cart, checkout, orders, and live delivery.
- Farmer: crop listings, price and stock management, incoming orders, and rider-pool dispatch.
- Rider: account access, delivery overview, pooled orders, batch acceptance, pickup checklist, and navigation.
- Superadmin: registration verification, transaction and fulfillment monitoring, and dispute management.

Public registration is available only for Consumers, Farmers, and Riders.
Superadmins use the separate **Platform staff access** entry on the login page;
their accounts are provisioned internally.

Accounts and sessions persist locally on the device. Marketplace and delivery
content currently uses local seed data until the shared cloud backend is configured.

## Run

Install Flutter, then run from this directory:

```powershell
flutter create . --platforms=android,web
flutter pub get
flutter run
```

Choose Chrome for a quick browser demo or an Android emulator/device for a mobile demo.
