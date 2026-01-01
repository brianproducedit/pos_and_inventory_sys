# Sync Failure Recovery Runbook

## Overview
This runbook provides procedures for diagnosing and recovering from sync-related failures in the POS & Inventory system.

## Quick Health Check
Run the health dashboard to assess system status:
```bash
python scripts/sync_health_dashboard.py --url http://your-server:8000
```

## Common Issues and Solutions

### 1. Sync Service Disabled
**Symptoms:**
- Clients cannot sync data
- API returns 503 "Sync service is temporarily disabled"

**Diagnosis:**
```bash
curl http://your-server:8000/feature-flags | jq '.flags.SYNC_ENABLED'
```

**Solution:**
Enable sync via environment variable:
```bash
export FEATURE_SYNC_ENABLED=true
# Restart the application
```

### 2. High Conflict Rate
**Symptoms:**
- Many sync conflicts reported
- Clients showing conflict resolution dialogs

**Diagnosis:**
Check conflict metrics:
```bash
curl http://your-server:8000/metrics | grep sync_conflicts
```

**Solution:**
1. Review recent conflicts in audit logs
2. Check for data consistency issues
3. Consider temporary conflict resolution policy changes

### 3. Sync Queue Backlog
**Symptoms:**
- Increasing number of pending changes
- Sync operations taking longer

**Diagnosis:**
Check queue size:
```bash
curl http://your-server:8000/metrics | grep sync_queue_size
```

**Solution:**
1. Scale up database resources
2. Check for long-running transactions
3. Review sync batch sizes

### 4. Database Connection Issues
**Symptoms:**
- Sync operations failing with database errors
- High error rates in metrics

**Diagnosis:**
Check database connectivity:
```bash
# From application server
python -c "from src.database import get_db; db = next(get_db()); db.execute('SELECT 1'); print('DB OK')"
```

**Solution:**
1. Check database server status
2. Verify connection pool settings
3. Review database credentials

### 5. Client-Side Sync Failures
**Symptoms:**
- Individual clients cannot sync
- "Network error" or timeout messages

**Diagnosis:**
Check client logs and server access logs for the client ID.

**Solution:**
1. Verify client has network connectivity
2. Check client authentication status
3. Review client-side error logs
4. Consider client data reset if corruption suspected

## Emergency Procedures

### Complete Sync Service Shutdown
For emergency maintenance:
```bash
export FEATURE_SYNC_ENABLED=false
# Restart application
```

### Data Recovery from Backup
If data corruption is suspected:
1. Stop all sync operations
2. Restore from last known good backup
3. Validate data integrity
4. Gradually re-enable sync

### Client Data Reset
For problematic clients:
1. Identify client ID from logs
2. Mark client data for re-sync in database
3. Instruct client to perform full data refresh

## Monitoring and Alerting

### Key Metrics to Monitor
- `sync_operations_total` - Total sync operations
- `sync_conflicts_total` - Conflict count by type
- `sync_duration_seconds` - Sync operation duration
- `api_requests_total{status_code="5xx"}` - Server errors
- `db_connections_active` - Database connections

### Recommended Alerts
1. Sync operations failing > 5% of the time
2. Conflict rate > 1 per minute
3. Sync duration > 30 seconds average
4. Pending changes > 1000
5. Database connection pool exhausted

## Performance Tuning

### Sync Batch Optimization
- Monitor `sync_duration_seconds` histogram
- Adjust batch sizes based on performance
- Consider time-based batching for high-frequency updates

### Database Optimization
- Ensure proper indexing on `changes` table
- Monitor query performance with `db_query_duration_seconds`
- Consider read replicas for sync pull operations

### Network Optimization
- Implement compression for large payloads
- Consider CDN for static assets
- Monitor network latency metrics

## Prevention

### Regular Maintenance
- Weekly health dashboard review
- Monthly performance benchmarking
- Quarterly disaster recovery testing

### Capacity Planning
- Monitor growth trends
- Plan for peak usage periods
- Scale infrastructure proactively

## Contact Information

- **DevOps Team:** devops@company.com
- **Database Admin:** dba@company.com
- **Application Support:** support@company.com

## Version History
- v1.0 - Initial runbook (2025-12-30)