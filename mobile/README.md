# AgriLink Mobile

Flutter mobile application for two roles:

- Consumer: account access, marketplace, crop details, cart, checkout, orders, and live delivery.
- Rider: account access, delivery overview, pooled orders, batch acceptance, pickup checklist, and navigation.

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
