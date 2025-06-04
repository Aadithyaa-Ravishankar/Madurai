# Madurai - Ward Information System

A Flutter application that provides detailed information about the wards of Madurai city, including ward boundaries, councillor details, and local facilities.

## Features

- Interactive map showing all wards of Madurai
- Detailed ward information including:
  - Ward boundaries and areas
  - Population statistics
  - Local facilities and amenities
  - Councillor information with contact details
- Search functionality to find specific wards
- Responsive UI with smooth animations
- Dark mode support
- Location-based services

## Technical Details

### Built With

- Flutter 3.32.1
- Google Maps Flutter
- Supabase for backend services
- Geolocator for location services
- Various Flutter packages for enhanced functionality

### Dependencies

Key dependencies include:
- `google_maps_flutter`: ^2.5.3
- `supabase_flutter`: ^2.3.4
- `geolocator`: ^10.1.0
- `flutter_polyline_points`: ^2.0.0
- `flutter_dotenv`: ^5.1.0
- `image_picker`: ^1.0.7
- `geocoding`: ^2.1.1
- And more (see pubspec.yaml for complete list)

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / Xcode
- Google Maps API Key
- Supabase Account

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/madurai.git
```

2. Install dependencies:
```bash
flutter pub get
```

3. Create a `.env` file in the root directory with the following variables:
```
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE=your_supabase_service_role
GOOGLE_MAPS_API_KEY=your_google_maps_api_key
```

4. Run the app:
```bash
flutter run
```

## Project Structure

```
lib/
├── config/           # Configuration files
├── data/            # Data models and constants
├── screens/         # UI screens
├── services/        # Business logic and services
└── main.dart        # Entry point
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Madurai Municipal Corporation for ward data
- Google Maps Platform
- Supabase for backend services
- Flutter community for various packages and support
