# Sync Button Testing Guide

## How to Verify Sync is Actively Working with PostgreSQL

### 1. **Check Backend is Running**
```bash
cd backend
python -m uvicorn src.main:app --reload --host 0.0.0.0 --port 8000
```

### 2. **Verify PostgreSQL Connection**
```bash
# In backend directory
python -c "from src.database import engine; print('✅ PostgreSQL Connected' if engine.connect() else '❌ Connection Failed')"
```

### 3. **Test Sync Flow in Flutter App**

#### Method 1: Using the Sync Now Button
1. Open the app and login
2. Look for the **offline indicator banner** at the top (shows pending changes count)
3. Make a change (e.g., add/edit a product)
4. Click the **"Sync Now"** button in the banner
5. Watch for:
   - Pending count decreases to 0
   - Loading spinner appears briefly
   - No error messages

#### Method 2: Using App Bar Sync Icon
1. Look for the sync icon (🔄) in the top right of the app bar
2. If there are pending changes, you'll see a **badge with count**
3. Click the icon to trigger sync
4. Badge should disappear after successful sync

### 4. **Verify Changes in PostgreSQL**

**Check products table:**
```sql
-- Connect to PostgreSQL
psql -h localhost -U postgres -d pos_inventory_db

-- Check recent products
SELECT id, name, sku, stock_quantity, updated_at, created_at 
FROM products 
ORDER BY updated_at DESC 
LIMIT 10;

-- Check sync changes log
SELECT server_seq, entity_type, operation, entity_id, created_at 
FROM changes 
ORDER BY server_seq DESC 
LIMIT 20;
```

### 5. **Monitor Sync in Real-Time**

**Backend Logs:**
```bash
# Watch for sync requests in terminal
# You should see:
# - POST /api/sync/push requests
# - GET /api/sync/changes requests
# - "Applied X changes" messages
```

**Flutter App Debug Console:**
```
# Look for:
- "Sync completed successfully"
- "Pending count: X"
- Any sync errors
```

### 6. **Test Offline → Online Sync**

1. **Go offline:**
   - Turn off WiFi/mobile data
   - Or use Android emulator's network toggle

2. **Make changes offline:**
   - Add 2-3 products
   - Edit some existing products
   - Note the pending count increases

3. **Go back online:**
   - Enable network
   - App should **auto-sync** within 5 minutes (or click "Sync Now")
   - Verify pending count drops to 0

4. **Check PostgreSQL:**
   - All offline changes should appear in database

### 7. **Verify Sync Queue**

**Check local SQLite (on device/emulator):**
```bash
# Using adb for Android
adb shell run-as com.example.mobile

# Navigate to database
cd /data/data/com.example.mobile/databases/
sqlite3 pos_app.db

# Check sync queue
SELECT id, table_name, action, status, retry_count, created_at 
FROM sync_queue 
WHERE status = 'pending' 
ORDER BY created_at DESC;

# Check sync errors
SELECT * FROM sync_errors ORDER BY created_at DESC LIMIT 10;
```

### 8. **Common Issues**

| Issue | Cause | Solution |
|-------|-------|----------|
| "No internet connection" | Network disabled | Enable WiFi/data |
| Pending count stuck | Backend down | Check backend is running on port 8000 |
| 401 Unauthorized | Token expired | Re-login to app |
| Changes not appearing | Wrong BASE_URL | Verify `.env` has correct IP address |
| Sync button grayed out | Already syncing | Wait for current sync to complete |

### 9. **Expected Sync Performance**

- **Manual sync:** 1-5 seconds for <100 changes
- **Auto sync:** Every 5 minutes when online
- **Background sync:** Every 15 minutes (debug) or 6 hours (production)
- **Pending count update:** Every 10 seconds

## Verification Checklist

- [ ] Backend running and accessible at BASE_URL
- [ ] PostgreSQL connected (check DATABASE_URL)
- [ ] FEATURE_SYNC_ENABLED=true in backend .env
- [ ] App shows offline indicator when making changes
- [ ] "Sync Now" button appears and is clickable
- [ ] Pending count decreases after sync
- [ ] Changes appear in PostgreSQL `products` table
- [ ] Changes logged in PostgreSQL `changes` table
- [ ] No errors in backend logs
- [ ] No errors in `sync_errors` table

## Success Indicators

✅ **Sync is working if:**
1. You can add a product in the app
2. Click "Sync Now"
3. Product appears in PostgreSQL within 5 seconds
4. Pending count shows 0
5. No errors in logs

---

**Current Configuration Status:**
- Flutter BASE_URL: `http://192.168.49.130:8000` ✅
- Backend DATABASE_URL: `postgresql://postgres:***@localhost:5432/pos_inventory_db` ✅
- Sync Enabled: `true` ✅
- Sync endpoints: `/api/sync/push` and `/api/sync/changes` ✅
