# APK Installation Guide

This guide explains how to install the offline-first POS & Inventory app on an Android device for demonstration purposes.

## 1. Download the APK

1. On your Android device, open a web browser.
2. Navigate to the project's GitHub Releases page:
   [https://github.com/brianproducedit/pos_and_inventory_sys/releases](https://github.com/brianproducedit/pos_and_inventory_sys/releases)
3. Under the latest release (e.g., `v1.0.0`), download the `app-release.apk` file.

## 2. Enable Installation from Unknown Sources

Android requires permission to install apps outside the Google Play Store.
- When you tap the downloaded APK, you may see a prompt: "For your security, your phone is not allowed to install unknown apps from this source."
- Tap **Settings** on the prompt.
- Toggle **Allow from this source** to ON.
- Go back and complete the installation.

## 3. Demo Mode Features

The APK is pre-configured in **Demo Mode**:
- It will automatically populate the local database on first launch with sample stores, products, and past sales.
- **No internet connection is required** after installation.
- You can safely put your device in **Airplane Mode** and the POS will continue to function fully.

## 4. Demo Login Credentials

Use any of the following pre-configured offline accounts:

| Role | Username | Password | Notes |
| --- | --- | --- | --- |
| **Cashier** | `demo` | `demo123` | Can process sales and view POS. |
| **Admin** | `admin` | `demo123` | Can manage local inventory and cashiers. |
| **Superadmin** | `superadmin`| `demo123` | Full access to all stores and system settings. |
