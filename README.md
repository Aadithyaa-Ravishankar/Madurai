# Madurai Ward Information App

A Flutter application that displays ward-wise information for Madurai city, including ward boundaries and ward-specific information.

---

## Prerequisites

- Flutter SDK (3.0.0 or higher)
- Dart SDK (3.0.0 or higher)
- Xcode (for iOS development)
- Android Studio (for Android development)
- Google Maps API key
- Supabase account

---

## Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/Aadithyaa-Ravishankar/Madurai.git
cd Madurai
```

---

### 2. Saving API Keys (Google Maps & Supabase)

**For production builds, keys are stored in `lib/config/config.dart` as constants.**

Create a file at `lib/config/config.dart` with the following content:

```dart
class Config {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
  static const String supabaseServiceRole = 'YOUR_SUPABASE_SERVICE_ROLE';
  static const String googleMapsApiKey = 'YOUR_GOOGLE_MAPS_API_KEY';
}
```

Replace the placeholder values with your actual keys.

---

### 3. Supabase Setup

#### a. Create a Supabase Project

1. Go to [Supabase](https://app.supabase.com/) and create a new project.
2. Get your Supabase URL and Anon/Public API Key from the project settings.

#### b. Database Tables

**Profiles Table:**
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

alter table profiles enable row level security;

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

**Complaints Table:**
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

alter table complaints enable row level security;

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

---

### 4. Required Assets

Place the following files in the `assets` directory:

- `assets/madurai_wards.geojson` — GeoJSON file containing ward boundaries
- `assets/images/image-1.png` — App logo/icon
- `assets/images/image-2.png` — Additional app image

Make sure your `pubspec.yaml` includes these assets:

```yaml
flutter:
  assets:
    - assets/images/image-1.png
    - assets/images/image-2.png
    - assets/madurai_wards.geojson
```

---

### 5. iOS Setup

1. Open `ios/Runner.xcworkspace` in Xcode.
2. In `ios/Runner/AppDelegate.swift`, set the Google Maps API key:
   ```swift
   GMSServices.provideAPIKey(Config.googleMapsApiKey)
   ```
3. Update the bundle identifier in Xcode.
4. Enable necessary capabilities:
   - Location Services
   - Camera
   - Photo Library
   - Microphone

---

### 6. Android Setup

1. Open `android/app/build.gradle.kts` and set your applicationId if needed.
2. In `android/app/src/main/AndroidManifest.xml`, add your Google Maps API key:
   ```xml
   <meta-data android:name="com.google.android.geo.API_KEY"
              android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
   ```
3. Enable necessary permissions in `AndroidManifest.xml`:
   - Location
   - Camera
   - Internet
   - Storage

---

### 7. Install Dependencies

```bash
flutter pub get
```

---

### 8. Run the App

```bash
flutter run
```

---

## Project Structure

```
lib/
├── config/           # Configuration files (config.dart, env.dart, supabase_config.dart)
├── data/             # Data models and constants
├── screens/          # UI screens
├── services/         # Business logic and services
└── main.dart         # Entry point
```

---

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

