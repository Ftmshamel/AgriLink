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
- Cloud-backed account and marketplace data

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

## Run the application

```powershell
cd mobile
flutter pub get
flutter run
```

Select an available Android emulator or connected Android device when prompted.
