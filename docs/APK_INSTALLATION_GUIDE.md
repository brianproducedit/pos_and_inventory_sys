# POS & Inventory System - APK Installation Guide

**Version:** 1.0.0  
**Last Updated:** January 1, 2026

---

## 📱 System Requirements

- **Android Version:** 5.0 (Lollipop) or higher
- **Storage:** At least 100 MB free space
- **Internet:** Required for initial setup and sync
- **Offline Support:** Full offline functionality after initial sync

---

## 📥 Download APK

### Official Download Link

Download the latest release from:
- **GitHub Releases:** [https://github.com/YOUR_USERNAME/pos_and_inventory_sys/releases](https://github.com/YOUR_USERNAME/pos_and_inventory_sys/releases)

**Current Version:** 1.0.0 (Build 1)  
**File Size:** 57.3 MB  
**Application ID:** com.pos.inventory

---

## 🔧 Installation Steps

### Step 1: Enable "Install from Unknown Sources"

Since this APK is not distributed through Google Play Store, you need to allow installation from unknown sources:

#### For Android 8.0 and above:
1. Go to **Settings** → **Apps & notifications** (or **Applications**)
2. Tap **Special app access** → **Install unknown apps**
3. Select the browser or file manager you'll use to install the APK
4. Enable **Allow from this source**

#### For Android 7.1.1 and below:
1. Go to **Settings** → **Security**
2. Enable **Unknown sources**
3. Tap **OK** when prompted

### Step 2: Download the APK

1. Open the download link on your Android device
2. Download `app-release.apk` (57.3 MB)
3. Wait for the download to complete

### Step 3: Install the APK

1. Open your device's **Downloads** folder or notification tray
2. Tap on `app-release.apk`
3. If prompted, confirm you trust the source
4. Tap **Install**
5. Wait for installation to complete (may take 10-30 seconds)
6. Tap **Open** to launch the app

---

## 🔐 First-Time Setup

### Initial Login

1. **Launch the app** from your home screen or app drawer
2. **Enter credentials:**
   - **Username:** (provided by admin)
   - **Password:** (provided by admin)

3. **Select Store:**
   - Choose your store from the list
   - This will be your default working store

4. **Wait for Initial Sync:**
   - The app will download products, inventory, and settings
   - This may take 1-2 minutes depending on data size
   - **Ensure stable internet connection**

5. **Grant Permissions (if prompted):**
   - **Storage:** Required for offline database
   - **Network:** Required for sync operations

---

## ✅ Verifying Installation

After installation, verify everything works:

1. **Login Success:** You should see the main dashboard
2. **Products Loaded:** Navigate to Products screen - should show your inventory
3. **Offline Mode:** Enable airplane mode - app should still function
4. **Online Sync:** Disable airplane mode - changes should sync automatically

---

## 🔄 Updating the App

When a new version is released:

1. **Download the new APK** from the same GitHub Releases link
2. **Install over the existing app** (no need to uninstall first)
3. **Your data will be preserved** - local database is maintained
4. **Log in again if required**

---

## ⚠️ Troubleshooting

### Issue: "App not installed" Error

**Causes:**
- Incompatible Android version
- Corrupted download
- Insufficient storage

**Solutions:**
1. Verify your Android version is 5.0+
2. Re-download the APK
3. Clear some storage space (need 100 MB free)
4. Restart your device and try again

### Issue: "Installation Blocked"

**Cause:** Security settings preventing installation

**Solution:**
1. Go to **Settings** → **Security**
2. Enable **Unknown sources** (or app-specific permissions on Android 8+)
3. Try installation again

### Issue: App Crashes on Launch

**Causes:**
- Incomplete installation
- Conflicting app
- Device incompatibility

**Solutions:**
1. Uninstall and reinstall the app
2. Clear app cache: **Settings** → **Apps** → **POS Inventory** → **Clear Cache**
3. Restart device
4. Contact support if issue persists

### Issue: Cannot Login

**Causes:**
- No internet connection
- Incorrect credentials
- Backend server down

**Solutions:**
1. Check internet connection
2. Verify username and password
3. Contact admin for credential reset
4. Check backend status at: https://backend-production-5388.up.railway.app/docs

### Issue: Sync Not Working

**Causes:**
- No internet connection
- Backend unreachable
- Auth token expired

**Solutions:**
1. Check internet connection
2. Log out and log back in (refreshes token)
3. Verify backend is online
4. Check sync settings in app

---

## 🔒 Security Notes

### APK Signature

This APK is signed with our official release key. Your device will show a warning for first-time installations because it's not from Google Play Store. This is normal and safe.

**Signature Details:**
- **Alias:** pos-key
- **Algorithm:** RSA 2048-bit
- **Validity:** 10,000 days

### Data Security

- **Passwords:** Stored securely using SHA-256 hashing
- **Auth Tokens:** Encrypted using flutter_secure_storage
- **Database:** SQLite with encryption (SQLCipher)
- **Network:** All communication over HTTPS

---

## 📞 Support

### Need Help?

If you encounter any issues during installation or usage:

1. **Check FAQ:** [docs/support_faq.md](support_faq.md)
2. **Email Support:** support@yourcompany.com
3. **Report Bug:** [GitHub Issues](https://github.com/YOUR_USERNAME/pos_and_inventory_sys/issues)

### Uninstalling the App

To remove the app from your device:

1. Go to **Settings** → **Apps**
2. Find **POS Inventory**
3. Tap **Uninstall**
4. Confirm removal

**Note:** This will delete all local data. Ensure data is synced before uninstalling.

---

## 📋 Version History

### Version 1.0.0 (Build 1) - January 1, 2026
- Initial production release
- Full offline-first functionality
- Multi-store support
- Real-time sync with Railway backend
- Analytics and reporting

---

## 🎯 Next Steps

After successful installation:

1. **Complete training** on POS features
2. **Test offline mode** by creating a few transactions
3. **Verify sync** by checking data on another device
4. **Explore analytics** dashboard
5. **Contact support** if you have questions

---

**Backend API:** https://backend-production-5388.up.railway.app  
**Documentation:** [docs/user_guide_offline_usage.md](user_guide_offline_usage.md)

---

*For developers and technical documentation, see [ENVIRONMENT_SETUP.md](../flutter_app/mobile/ENVIRONMENT_SETUP.md)*
