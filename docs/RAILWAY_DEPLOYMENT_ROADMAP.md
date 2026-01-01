# Railway Deployment & Production Readiness Roadmap 🚂

**Project:** POS & Inventory System  
**Target Platform:** Railway.app  
**Created:** January 1, 2026  
**Status:** In Progress

---

## 📋 Overview

This roadmap provides a strict, phase-by-phase guide for deploying the POS & Inventory backend to Railway and configuring the Flutter mobile app for seamless communication with the deployed backend. APK distribution will be direct (no app stores).

**Key Objectives:**
1. ✅ Clean up Heroku configurations
2. Deploy PostgreSQL backend to Railway
3. Configure Flutter app with production API endpoint
4. Merge all Git branches to master
5. Build and distribute production APK
6. Verify end-to-end production functionality

---

## 🎯 Phase 1: Pre-Deployment Cleanup ✅

**Goal:** Remove Heroku configurations and consolidate development branches

### Tasks:
- [x] **1.1** Delete Heroku-specific files
  - [x] Remove `backend/Procfile`
  - [x] Remove `backend/runtime.txt`
  - Status: Complete ✅

- [x] **1.2** Clean up outdated documentation
  - [x] Remove `docs/roadmap.md` (superseded)
  - [x] Remove `docs/remaining_roadmap.md` (superseded)
  - [x] Remove `docs/offline_sync_roadmap.md` (superseded)
  - [x] Remove `docs/offline_first_roadmap.md` (superseded)
  - [x] Remove `docs/flutter_sync_plan.md` (superseded)
  - [x] Remove `docs/PR_DRAFT.md` (draft)
  - [x] Remove `docs/store-switching-roadmap.md` (completed)
  - [x] Remove `docs/store-role-scope-roadmap.md` (completed)
  - [x] Remove `docs/ui_screens_subroadmap.md` (completed)
  - [x] Remove `docs/sync_recovery_roadmap.md` (completed)
  - [x] Remove `docs/OFFLINE_FIRST_AUDIT_REPORT.md` (audit complete)
  - Status: Complete ✅

- [ ] **1.3** Clean local PostgreSQL database
  - [ ] Connect to local PostgreSQL database
  - [ ] Delete all data from tables (products, stores, users, transactions, etc.)
  - [ ] Keep only the default superadmin user
  - [ ] Verify database is clean and ready for production
  - Command:
    ```bash
    cd backend
    python scripts/prune_sqlite.py --replace --keep-superadmin
    # Or for PostgreSQL:
    python -c "
    from src.database import SessionLocal, engine
    from src.models import User, Product, Store, Sale, SaleItem, InventoryLog, Change
    from sqlalchemy import text
    
    db = SessionLocal()
    try:
        # Delete all data except superadmin user
        db.query(SaleItem).delete()
        db.query(Sale).delete()
        db.query(InventoryLog).delete()
        db.query(Change).delete()
        db.query(Product).delete()
        db.query(Store).filter(Store.name != 'Default Store').delete()
        db.query(User).filter(User.username != 'superadmin').delete()
        
        # Reset sequences if needed
        db.execute(text('ALTER SEQUENCE users_id_seq RESTART WITH 2'))
        db.execute(text('ALTER SEQUENCE products_id_seq RESTART WITH 1'))
        db.execute(text('ALTER SEQUENCE stores_id_seq RESTART WITH 2'))
        
        db.commit()
        print('Database cleaned successfully!')
    except Exception as e:
        db.rollback()
        print(f'Error: {e}')
    finally:
        db.close()
    "
    ```
  - Status: Pending ⏳

- [ ] **1.4** Merge Git branches to master
  - [ ] Merge `feat/sync-offline` to master
  - [ ] Merge `feat/sync-replay-migrations` to master
  - [ ] Delete merged feature branches
  - [ ] Push consolidated master to origin
  - Status: Pending ⏳

**Acceptance Criteria:**
- ✅ No Heroku files exist in repository
- ✅ Outdated roadmaps removed
- ⏳ Local database cleaned (only superadmin remains)
- ⏳ All feature branches merged to master
- ⏳ Clean Git history with no dangling branches

---

## 🚀 Phase 2: Railway Backend Deployment

**Goal:** Deploy backend API with PostgreSQL to Railway

### Prerequisites:
- Railway account (sign up at https://railway.app)
- Railway CLI installed: `npm i -g @railway/cli`
- Backend code on master branch

### Tasks:

- [ ] **2.1** Install Railway CLI
  ```bash
  npm i -g @railway/cli
  ```
  - Verify: `railway --version`
  - Status: Pending ⏳

- [ ] **2.2** Login to Railway
  ```bash
  railway login
  ```
  - Opens browser for authentication
  - Status: Pending ⏳

- [ ] **2.3** Initialize Railway project
  ```bash
  cd backend
  railway init
  ```
  - Project name: `pos-inventory-backend`
  - Status: Pending ⏳

- [ ] **2.4** Add PostgreSQL database
  ```bash
  railway add --plugin postgresql
  ```
  - Railway auto-provisions database
  - `DATABASE_URL` automatically injected
  - Status: Pending ⏳

- [ ] **2.5** Configure environment variables
  ```bash
  # Generate secure secret key
  railway variables set SECRET_KEY=$(python -c "import secrets; print(secrets.token_urlsafe(32))")
  
  # Set admin credentials
  railway variables set DEFAULT_SUPERADMIN_USERNAME=admin
  railway variables set DEFAULT_SUPERADMIN_PASSWORD=YourSecurePassword123!
  
  # Set environment
  railway variables set ENVIRONMENT=production
  ```
  - Status: Pending ⏳

- [ ] **2.6** Deploy backend
  ```bash
  railway up
  ```
  - Railway detects `requirements.txt`
  - Builds and deploys automatically
  - Status: Pending ⏳

- [ ] **2.7** Run database migrations
  ```bash
  railway run python -m alembic upgrade head
  ```
  - Applies all migrations to PostgreSQL
  - Status: Pending ⏳

- [ ] **2.8** Initialize database with admin user
  ```bash
  railway run python init_db.py
  ```
  - Creates superadmin user
  - Status: Pending ⏳

- [ ] **2.9** Get public domain
  ```bash
  railway domain
  ```
  - Copy the Railway domain (e.g., `pos-inventory-backend-production.up.railway.app`)
  - Status: Pending ⏳

- [ ] **2.10** Test backend health
  ```bash
  curl https://your-railway-domain.up.railway.app/docs
  ```
  - Should return FastAPI docs page
  - Status: Pending ⏳

**Acceptance Criteria:**
- ⏳ Backend deployed and accessible
- ⏳ PostgreSQL database running
- ⏳ Migrations applied successfully
- ⏳ Admin user exists and can login
- ⏳ `/docs` endpoint accessible

**Railway Resources:**
- Dashboard: https://railway.app/dashboard
- Docs: https://docs.railway.com/guides/deployments
- PostgreSQL Guide: https://docs.railway.com/guides/postgresql

---

## 📱 Phase 3: Flutter App Configuration

**Goal:** Configure Flutter app to communicate with Railway backend

### Tasks:

- [ ] **3.1** Update API base URL
  - File: `flutter_app/mobile/lib/data/remote/postgres_api_service.dart`
  - Find: `static const String baseUrl = 'http://192.168.49.1:8000';` (or similar localhost URL)
  - Replace with: `static const String baseUrl = 'https://your-railway-domain.up.railway.app';`
  - Status: Pending ⏳

- [ ] **3.2** Update HTTP client for production
  - Ensure HTTPS is enabled
  - Remove development-only proxy settings
  - Verify SSL certificate validation enabled
  - Status: Pending ⏳

- [ ] **3.3** Update environment configuration
  - Create `flutter_app/mobile/lib/config/environment.dart`:
    ```dart
    class Environment {
      static const String apiBaseUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://your-railway-domain.up.railway.app',
      );
      
      static const bool isProduction = bool.fromEnvironment(
        'IS_PRODUCTION',
        defaultValue: true,
      );
    }
    ```
  - Status: Pending ⏳

- [ ] **3.4** Test API connectivity
  - Run Flutter app in development
  - Verify login works with Railway backend
  - Verify sync operations work
  - Test offline → online sync
  - Status: Pending ⏳

**Acceptance Criteria:**
- ⏳ Flutter app connects to Railway backend
- ⏳ Authentication works
- ⏳ Sync operations successful
- ⏳ Offline mode functions correctly

---

## 🔧 Phase 4: Production APK Build

**Goal:** Build production-ready APK for direct distribution

### Prerequisites:
- Android SDK installed
- Flutter configured for release builds
- Signing key generated (for production)

### Tasks:

- [ ] **4.1** Clean Flutter project
  ```bash
  cd flutter_app/mobile
  flutter clean
  flutter pub get
  ```
  - Status: Pending ⏳

- [ ] **4.2** Generate signing key (first time only)
  ```bash
  keytool -genkey -v -keystore ~/pos-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pos-key
  ```
  - Store password securely
  - Status: Pending ⏳

- [ ] **4.3** Configure signing in Android
  - Create `flutter_app/mobile/android/key.properties`:
    ```properties
    storePassword=your_keystore_password
    keyPassword=your_key_password
    keyAlias=pos-key
    storeFile=../../pos-release-key.jks
    ```
  - Update `flutter_app/mobile/android/app/build.gradle` with signing config
  - Status: Pending ⏳

- [ ] **4.4** Update app version
  - File: `flutter_app/mobile/pubspec.yaml`
  - Update: `version: 1.0.0+1` (semantic versioning)
  - Status: Pending ⏳

- [ ] **4.5** Build production APK
  ```bash
  flutter build apk --release --dart-define=API_BASE_URL=https://your-railway-domain.up.railway.app --dart-define=IS_PRODUCTION=true
  ```
  - Output: `build/app/outputs/flutter-apk/app-release.apk`
  - Status: Pending ⏳

- [ ] **4.6** Build split APKs (optional, smaller file sizes)
  ```bash
  flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://your-railway-domain.up.railway.app
  ```
  - Generates: `app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk`, `app-x86_64-release.apk`
  - Status: Pending ⏳

- [ ] **4.7** Test release APK
  - Install on physical Android device
  - Test login, sync, offline mode
  - Verify no development artifacts
  - Status: Pending ⏳

**Acceptance Criteria:**
- ⏳ APK builds successfully
- ⏳ App signed with release key
- ⏳ All features work in release mode
- ⏳ No debug logging visible

---

## 📦 Phase 5: APK Distribution

**Goal:** Distribute APK directly to users (no app stores)

### Distribution Methods:

- [ ] **5.1** Setup distribution infrastructure
  
  **Option A: GitHub Releases (Recommended)**
  - [ ] Create GitHub release
  - [ ] Upload APK as release asset
  - [ ] Add release notes
  - [ ] Share download link
  
  **Option B: Firebase App Distribution**
  - [ ] Setup Firebase project
  - [ ] Add testers/users
  - [ ] Upload APK via CLI
  - [ ] Users notified automatically
  
  **Option C: Direct file sharing**
  - [ ] Upload to secure cloud storage (Google Drive, Dropbox)
  - [ ] Generate shareable link
  - [ ] Distribute link to users
  
  - Status: Pending ⏳

- [ ] **5.2** Create installation guide
  - Document: `docs/APK_INSTALLATION_GUIDE.md`
  - Include:
    - How to enable "Install from Unknown Sources"
    - Download instructions
    - Installation steps
    - Troubleshooting
  - Status: Pending ⏳

- [ ] **5.3** Setup update notification system (optional)
  - Implement in-app update checker
  - Notify users of new versions
  - Link to latest APK
  - Status: Pending ⏳

**Acceptance Criteria:**
- ⏳ APK available for download
- ⏳ Installation guide published
- ⏳ Users can successfully install
- ⏳ Update mechanism in place

---

## ✅ Phase 6: End-to-End Verification

**Goal:** Verify complete production setup

### Test Scenarios:

- [ ] **6.1** Backend health checks
  - [ ] `/docs` endpoint accessible
  - [ ] `/api/users/me` returns user data (with auth)
  - [ ] `/api/products` returns products
  - [ ] `/api/sync/changes` returns changes
  - Status: Pending ⏳

- [ ] **6.2** Mobile app functionality
  - [ ] Fresh install login works
  - [ ] Create product syncs to backend
  - [ ] Offline changes queue properly
  - [ ] Online sync resolves queue
  - [ ] Analytics load correctly
  - Status: Pending ⏳

- [ ] **6.3** Multi-device sync test
  - [ ] Login on Device A
  - [ ] Create product on Device A
  - [ ] Sync Device A
  - [ ] Login on Device B
  - [ ] Verify product appears on Device B
  - Status: Pending ⏳

- [ ] **6.4** Offline resilience test
  - [ ] Enable airplane mode
  - [ ] Create/edit products offline
  - [ ] Disable airplane mode
  - [ ] Verify auto-sync completes
  - [ ] Verify no data loss
  - Status: Pending ⏳

- [ ] **6.5** Load testing
  - [ ] Test with 100+ products
  - [ ] Test with 50+ sync queue items
  - [ ] Verify acceptable performance
  - Status: Pending ⏳

**Acceptance Criteria:**
- ⏳ All test scenarios pass
- ⏳ No data loss or corruption
- ⏳ Performance acceptable
- ⏳ Error handling graceful

---

## 📊 Phase 7: Monitoring & Maintenance

**Goal:** Setup production monitoring and maintenance procedures

### Tasks:

- [ ] **7.1** Railway monitoring
  - [ ] Setup usage alerts (CPU, memory, bandwidth)
  - [ ] Configure deployment notifications
  - [ ] Review Railway logs regularly
  - Status: Pending ⏳

- [ ] **7.2** Backend logging
  - [ ] Ensure structured logging in production
  - [ ] Monitor error rates via Railway logs
  - [ ] Setup log aggregation (optional: Papertrail, Logtail)
  - Status: Pending ⏳

- [ ] **7.3** Database backups
  - [ ] Enable Railway automatic backups
  - [ ] Test backup restoration
  - [ ] Document backup/restore procedure
  - Status: Pending ⏳

- [ ] **7.4** Update procedures
  - [ ] Document backend deployment process
  - [ ] Document APK build & distribution process
  - [ ] Create rollback procedure
  - Status: Pending ⏳

- [ ] **7.5** User support
  - [ ] Create support email/channel
  - [ ] Document common issues in `docs/support_faq.md`
  - [ ] Train support staff
  - Status: Pending ⏳

**Acceptance Criteria:**
- ⏳ Monitoring alerts configured
- ⏳ Backup strategy in place
- ⏳ Update procedures documented
- ⏳ Support channel established

---

## 📈 Success Metrics

Track these metrics post-deployment:

- **Uptime:** Target 99.5%+
- **API Response Time:** < 500ms average
- **Sync Success Rate:** > 95%
- **Crash-Free Rate:** > 99%
- **User Satisfaction:** Gather feedback

---

## 🚨 Rollback Plan

If critical issues arise:

1. **Backend Issues:**
   ```bash
   railway rollback
   ```
   - Reverts to previous deployment

2. **App Issues:**
   - Distribute previous APK version
   - Update download links

3. **Database Issues:**
   - Restore from Railway backup
   - Document in incident report

---

## 📚 Reference Documentation

### Created/Updated Docs:
- ✅ `docs/RAILWAY_DEPLOYMENT_ROADMAP.md` - This roadmap
- ⏳ `docs/APK_INSTALLATION_GUIDE.md` - User installation guide
- ⏳ `docs/PRODUCTION_RUNBOOK.md` - Operations guide
- ⏳ `docs/CHANGELOG.md` - Version history

### Existing Docs (Keep):
- `docs/backup_recovery_procedures.md` - Backup procedures
- `docs/CHANGELOG.md` - Version history
- `docs/client_sync_design.md` - Sync architecture
- `docs/developer_guide_offline_first.md` - Developer guide
- `docs/ENVIRONMENT_SETUP.md` - Development setup
- `docs/offline_strategies.md` - Offline patterns
- `docs/support_faq.md` - User support
- `docs/sync_api_spec.md` - API documentation
- `docs/sync_runbook.md` - Sync operations
- `docs/user_guide_offline_usage.md` - User guide

### Railway Documentation:
- Deployment Guide: https://docs.railway.com/guides/deployments
- PostgreSQL Setup: https://docs.railway.com/guides/postgresql
- Environment Variables: https://docs.railway.com/reference/variables
- CLI Reference: https://docs.railway.com/reference/cli-api

---

## ✅ Completion Checklist

Before marking deployment complete, verify:

- [ ] All phases marked complete
- [ ] Backend accessible and healthy
- [ ] Flutter app connects successfully
- [ ] APK distributed and tested
- [ ] All branches merged to master
- [ ] Documentation updated
- [ ] Monitoring configured
- [ ] Team trained on operations
- [ ] Support process established
- [ ] Success metrics baseline recorded

---

## 🎉 Post-Deployment

After successful deployment:

1. **Celebrate!** 🎊
2. Schedule post-mortem meeting
3. Document lessons learned
4. Update roadmap for future features
5. Begin user onboarding
6. Monitor metrics closely for first week

---

**Next Step:** Begin Phase 1.3 - Merge Git branches to master

**Last Updated:** January 1, 2026
