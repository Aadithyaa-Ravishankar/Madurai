# Madurai City Ward Information App

A Flutter application that displays ward-wise information for Madurai city, including ward boundaries, councillor details, and ward-specific information.

## Prerequisites

- Flutter SDK (version 3.0.0 or higher)
- Dart SDK (version 3.0.0 or higher)
- Xcode (for iOS development)
- Android Studio (for Android development)
- Google Maps API key
- Supabase account

## Setup Instructions

### 1. Clone the Repository

```bash
git clone <repository-url>
cd madurai
```

### 2. Environment Setup

Create a `.env` file in the root directory with the following structure:

```env
# Supabase Configuration
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_anon_key
SUPABASE_SERVICE_ROLE=your_supabase_service_role

# Google Maps Configuration
GOOGLE_MAPS_API_KEY=your_google_maps_api_key
```

### 3. Supabase Setup

1. Create a new project in Supabase
2. Set up the following tables in your Supabase database:

#### Profiles Table
```sql
create table profiles (
  id uuid references auth.users on delete cascade,
  updated_at timestamp with time zone,
  username text unique,
  full_name text,
  avatar_url text,
  ward_number text,
  primary key (id)
);

-- Enable Row Level Security
alter table profiles enable row level security;

-- Create policies
create policy "Public profiles are viewable by everyone."
  on profiles for select
  using ( true );

create policy "Users can insert their own profile."
  on profiles for insert
  with check ( auth.uid() = id );

create policy "Users can update own profile."
  on profiles for update
  using ( auth.uid() = id );
```

#### Complaints Table
```sql
create table complaints (
  id uuid default uuid_generate_v4() primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  user_id uuid references auth.users not null,
  ward_number text not null,
  title text not null,
  description text,
  status text default 'pending',
  image_urls text[],
  location_lat double precision,
  location_lng double precision
);

-- Enable Row Level Security
alter table complaints enable row level security;

-- Create policies
create policy "Users can view their own complaints"
  on complaints for select
  using (auth.uid() = user_id);

create policy "Users can create their own complaints"
  on complaints for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own complaints"
  on complaints for update
  using (auth.uid() = user_id);
```

### 4. Required Assets

Place the following files in the `assets` directory:

1. `assets/madurai_wards.geojson` - GeoJSON file containing ward boundaries
2. `assets/councillor.html` - HTML file containing councillor information
3. `assets/images/image-1.png` - App logo/icon
4. `assets/images/image-2.png` - Additional app image

### 5. iOS Setup

1. Open `ios/Runner.xcworkspace` in Xcode
2. Add your Google Maps API key to `ios/Runner/AppDelegate.swift`
3. Update the bundle identifier in Xcode
4. Enable necessary capabilities:
   - Location Services
   - Camera
   - Photo Library
   - Microphone

### 6. Android Setup

1. Open `android/app/build.gradle`
2. Update the `applicationId` to your desired package name
3. Add your Google Maps API key to `android/app/src/main/AndroidManifest.xml`
4. Enable necessary permissions in `AndroidManifest.xml`:
   - Location
   - Camera
   - Internet
   - Storage

### 7. Install Dependencies

```bash
flutter pub get
```

### 8. Run the App

```bash
flutter run
```

## Features

- Interactive ward map with boundaries
- Ward-wise information display
- Councillor details
- User authentication
- Complaint submission system
- Location-based ward detection
- Search functionality

## Dependencies

The app uses the following main dependencies:

- `flutter_dotenv`: ^5.1.0
- `supabase_flutter`: ^2.3.4
- `google_maps_flutter`: ^2.5.3
- `geolocator`: ^10.1.0
- `flutter_polyline_points`: ^2.0.0
- `image_picker`: ^1.0.7
- `geocoding`: ^2.1.1
- `uuid`: ^4.3.3
- `intl`: ^0.19.0
- `video_player`: ^2.8.2
- `permission_handler`: ^11.3.0
- `app_links`: ^3.4.1

## Project Structure

```
lib/
├── config/
│   ├── env.dart
│   └── supabase_config.dart
├── Screens/
│   ├── login.dart
│   ├── profile.dart
│   └── splash_screen.dart
├── services/
│   └── map_service.dart
├── data/
│   └── ward_data.dart
└── main.dart
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support, email [your-email] or open an issue in the repository.
