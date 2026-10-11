# AgriLink Mobile

AgriLink is a Flutter mobile application that connects consumers, farmers,
riders, and superadministrators in one agricultural marketplace.

## Mobile features

- Consumer product browsing, ordering, and delivery tracking
- Farmer crop, inventory, and order management
- Rider delivery pool, active trips, and status updates
- Superadministrator verification and platform monitoring
- Role-based registration, authentication, and navigation
- Password recovery through an emailed one-time code
- Farmer and rider requirement uploads held for superadmin approval
- Live weather from Open-Meteo for harvest planning and delivery safety
- Verified proof of delivery: geofence, buyer code, photo, and buyer receipt
- AgriLink Wallet: cash in through Xendit, pay from the balance, get refunds
- Same-day or scheduled delivery, with cancellation up to 5 days before
- In-app notification inbox for every role
- Cloud-backed account and marketplace data

## API integration

AgriLink has no application server. The Flutter client calls Cloud Firestore's
REST API for all data — create, read, update, delete, and server-side queries
— plus four services that need no API key: Open-Meteo for forecasts and town
search, OSRM for road routing, and OpenStreetMap for map tiles. Every request is
built, decoded, and error-handled on the device.

## Weather integration

The Farmer and Rider dashboards show live conditions for the location the
account pinned at signup, using the free [Open-Meteo](https://open-meteo.com)
API — no API key or account is needed, so it runs straight from source. The
outlook page adds a 7-day forecast and a town search.

## Wallet, scheduling, and refunds

Consumers can pay with GCash/online through Xendit as before, or from their
**AgriLink Wallet**. The wallet is a ledger in `mobileWalletTransactions`:
the balance is the sum of its entries, which are never edited or deleted.

- **Cash in** opens a Xendit invoice. The wallet is credited only after the
  payments worker reports the invoice paid, for the amount Xendit holds, and
  only once per invoice. A cash-in paid after the buyer left the app is
  picked up the next time the wallet opens.
- **Refunds always go to the wallet**, however the order was paid. Each order
  can be refunded once.
- **No withdrawals** — wallet funds can only be spent in AgriLink.
- Without `AGRILINK_PAYMENTS_URL`, cash-in adds clearly labelled demo funds so
  the flow can be shown without a payment gateway.

The checkout delivers to the address pinned on the profile, or the buyer can
pin another one for that order only. At checkout the buyer picks **Same day** or a **scheduled date** (up to 60
days ahead). Riders deliver from 6:00 AM, and the same-day cutoff is 6:00 PM:
an order placed from 6:00 PM to midnight is delivered the next day, while one
placed between midnight and 6:00 AM is still same-day, starting at 6:00 AM.
Same-day (and next-day) orders are final. A scheduled order can be cancelled by
the buyer until 5 days before delivery, as long as no rider has it; the stock
goes back on the listing. The farm can cancel any order before pickup, and
the buyer is refunded the same way. Riders only see a scheduled order in the
pool on its delivery day.

## Manual payments without a gateway

Until the Xendit worker is deployed, the GCash option asks the buyer for a
reference number. Tell them where to send the money by building with:

```powershell
flutter run `
  --dart-define=AGRILINK_GCASH_NUMBER=09XXXXXXXXX `
  --dart-define=AGRILINK_GCASH_NAME="AgriLink Payments"
```

Without these the checkout says no payment account is set up and points the
buyer to the wallet instead.

## Delivery pricing, payouts, and ratings

Riders drive four-wheelers from farm to town and usually return empty, so the
per-kilometre rate follows the price of diesel: the rider's 80% share covers
diesel both ways plus a margin. With diesel at ₱95/L and a van doing 10 km/L
that is ₱19/km of fuel, ₱24/km to the rider, ₱30/km to the buyer, plus a ₱250
base fare and ₱1.50/kg. The superadmin updates these under **Delivery
pricing** as pump prices move; orders already placed keep their fee.

Every buyer pays the full solo trip fee at checkout, and checkout says
whether other orders are already heading to the same town on that day (and
suggests days that have some). When a rider takes a pooled trip, it is priced
once and split in proportion to what each buyer paid; nobody pays more than
they were charged, and the difference goes back to each buyer's wallet. The
rider is paid their share of that one trip.

The superadmin's **Payouts** page lists what each farmer (produce price) and
rider (delivery share) is owed for delivered orders; after sending the money
by GCash/Maya they record the reference, and the farmer and rider see paid vs
awaiting amounts in their profiles. Riders must add a payout number before
going online.

After confirming receipt, buyers rate the farm and the rider 1–5. Averages
show on the product page and on the farmer and rider profiles. Superadmins
can resolve a dispute with a refund to the buyer's wallet (capped at what the
order cost, once per report), suspend accounts with a recorded reason, search
every order, and review all wallet activity.

## Proof of delivery

A rider cannot mark a drop-off delivered on their word alone. **Verify &
confirm delivery** requires all of:

1. **Geofence** — a fresh GPS fix within 150 m of the buyer's pinned location.
   Fixes from a mock-location app are refused.
2. **Delivery code** — a 4-digit code generated when the rider accepts the
   trip and shown only on the buyer's tracking screen. The rider types it in
   at the door, so the buyer has to be there to hand it over.
3. **Photo** — taken with the camera (not the gallery) and stored in
   `mobileDeliveryProofs` with the GPS position and time. Firestore rules keep
   these photos read-only once written.

Once delivered, the buyer sees the photo and distance on the tracking screen
and can tap **I received my order** or report a problem. A report flags the
order as disputed, and the superadmin can open the same delivery proof from
**Active Disputes**.

## Account verification

Consumers are active as soon as they register. Farmers and riders are created
as `pending_review` and are held on the review screen until a superadmin
approves them in **Verification Queue**; the app then lets them straight into
their role shell without a new sign-in.

| Role     | Required at signup                                                   |
| -------- | -------------------------------------------------------------------- |
| Consumer | Pinned location. Business Permit is optional.                         |
| Farmer   | Pinned farm location, payout number, Barangay Certificate.            |
| Rider    | Pinned location, vehicle and public-service code, Professional Driver's License, Vehicle OR/CR, NBI or Police Clearance. |

Uploads are stored as base64 inside `mobileVerificationFiles` and must be under
750 KB each.

## Password reset email

Reset codes are mailed straight from the app, so a transactional provider is
supplied at build time. Without one the flow still runs and shows the code
on-screen, labelled as a development build.

```powershell
cd mobile
flutter run `
  --dart-define=AGRILINK_EMAIL_PROVIDER=brevo `
  --dart-define=AGRILINK_EMAIL_API_KEY=your-api-key `
  --dart-define=AGRILINK_EMAIL_SENDER=no-reply@agrilink.ph `
  --dart-define=AGRILINK_EMAIL_SENDER_NAME=AgriLink
```

`AGRILINK_EMAIL_PROVIDER` accepts `brevo`, `resend`, or `emailjs`. EmailJS also
needs `AGRILINK_EMAILJS_SERVICE_ID`, `AGRILINK_EMAILJS_TEMPLATE_ID`, and
`AGRILINK_EMAILJS_PUBLIC_KEY`.

## Firestore security rules

`firestore.rules` is what keeps reset codes unguessable — tickets can be fetched
by id but the collection cannot be listed. Deploy it before relying on the reset
flow:

```powershell
firebase deploy --only firestore:rules
```

## Project structure

```text
AgriLink/
└── mobile/
    ├── android/                 # Android platform configuration
    ├── assets/                  # Images and application resources
    ├── lib/
    │   ├── models/              # Application data models
    │   ├── screens/             # Pages and role-based screens
    │   ├── services/            # Authentication and database services
    │   ├── utils/               # Shared colors and utilities
    │   ├── widgets/             # Reusable interface components
    │   └── main.dart            # Application entry point
    ├── test/                    # Automated tests
    ├── tool/                    # Development utilities
    └── pubspec.yaml             # Flutter dependencies and assets
```

The root `flutter/` directory, when present locally, contains the Flutter SDK
used by the development environment and is not part of the application source.

## Notifications

Each role has a bell on its home screen with an unread count: buyers hear
about every step of their orders (including their delivery code and refunds),
farms about new orders, ratings and payouts, riders about packed orders
waiting and payouts, and superadmins about applications and disputes. The
inbox is built from the orders' own timelines, so it needs no server; true
push notifications to a closed app need Firebase Cloud Messaging and a sender
such as a Cloud Function.

## Release build

The app installs as `ph.agrilink.mobile`. To sign a release APK, create a
keystore and `mobile/android/key.properties` (both are git-ignored):

```powershell
keytool -genkey -v -keystore $env:USERPROFILE\agrilink-release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias agrilink
```

```properties
storePassword=<password>
keyPassword=<password>
keyAlias=agrilink
storeFile=C:\\Users\\<you>\\agrilink-release.jks
```

Then `flutter build apk --release`. Without `key.properties` the release
build is signed with the debug key. GitHub Actions
(`.github/workflows/mobile.yml`) runs `flutter analyze`, `flutter test` and a
release build on every push that touches `mobile/`, and keeps the APK as a
download.

## Run the application

```powershell
cd mobile
flutter pub get
flutter run
```

Select an available Android emulator or connected Android device when prompted.
