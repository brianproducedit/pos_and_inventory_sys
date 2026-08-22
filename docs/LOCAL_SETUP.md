# Local Setup Guide

This guide describes how to run the POS & Inventory system locally.

## Option 1: APK Demo Mode (No backend required)

The fastest way to review the application is to use the release APK in "Demo Mode".

1. Download the latest APK from [GitHub Releases](https://github.com/brianproducedit/pos_and_inventory_sys/releases).
2. Install it on your Android device (ensure "Install from unknown sources" is enabled).
3. The app will automatically seed sample stores, products, and users on first launch.
4. **Demo Credentials**:
   - Cashier: `demo` / `demo123`
   - Admin: `admin` / `demo123`
   - Superadmin: `superadmin` / `demo123`
5. You can safely turn on Airplane Mode to test the offline capabilities.

## Option 2: Full Stack (Flutter + Docker Compose)

To test the synchronization engine, you can run the backend locally.

### 1. Start the Backend
```bash
# Clone the repository
git clone https://github.com/brianproducedit/pos_and_inventory_sys.git
cd pos_and_inventory_sys

# Start Postgres and FastAPI
docker compose up --build
```
The API will be available at `http://localhost:8000`.

### 2. Run the Flutter App
Ensure you have Flutter installed.

```bash
cd flutter_app/mobile
flutter pub get

# Connect an Android emulator or device, then run:
flutter run --dart-define=DEMO_MODE=false --dart-define=BASE_URL=http://10.0.2.2:8000
```
*(Note: Use `10.0.2.2` for Android emulators to access localhost, or your computer's LAN IP for physical devices).*
