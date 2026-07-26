# AgriLink Mobile

AgriLink is a Flutter mobile application that connects consumers, farmers,
riders, and superadministrators in one agricultural marketplace.

## Mobile features

- Consumer product browsing, ordering, and delivery tracking
- Farmer crop, inventory, and order management
- Rider delivery pool, active trips, and status updates
- Superadministrator verification and platform monitoring
- Role-based registration, authentication, and navigation
- Cloud-backed account and marketplace data

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
