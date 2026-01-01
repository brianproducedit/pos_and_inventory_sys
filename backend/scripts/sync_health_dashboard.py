#!/usr/bin/env python3
"""
Sync Health Dashboard
Provides monitoring and health checks for the sync system.
Run this script to get real-time sync metrics and health status.
"""

import requests
import json
import time
from datetime import datetime, timedelta
from typing import Dict, Any, List
import sys
import os

# Add src to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), 'src'))

try:
    from src.database import SessionLocal
    from src.models import Product, Store, User, Change, AuditLog
    from src.metrics import update_business_metrics
except ImportError:
    print("Warning: Could not import database models. Some features will be limited.")
    SessionLocal = None

class SyncHealthDashboard:
    """Dashboard for monitoring sync system health"""

    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()

    def get_metrics(self) -> Dict[str, Any]:
        """Fetch Prometheus metrics from the server"""
        try:
            response = self.session.get(f"{self.base_url}/metrics")
            response.raise_for_status()
            return self._parse_prometheus_metrics(response.text)
        except Exception as e:
            return {"error": f"Failed to fetch metrics: {e}"}

    def get_feature_flags(self) -> Dict[str, Any]:
        """Get current feature flags"""
        try:
            response = self.session.get(f"{self.base_url}/feature-flags")
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": f"Failed to fetch feature flags: {e}"}

    def get_system_status(self) -> Dict[str, Any]:
        """Get system status"""
        try:
            response = self.session.get(f"{self.base_url}/status")
            response.raise_for_status()
            return response.json()
        except Exception as e:
            return {"error": f"Failed to fetch system status: {e}"}

    def get_database_health(self) -> Dict[str, Any]:
        """Get database health metrics (requires direct DB access)"""
        if not SessionLocal:
            return {"error": "Database access not available"}

        try:
            db = SessionLocal()
            health = {}

            # Count records
            health['products_total'] = db.query(Product).count()
            health['stores_total'] = db.query(Store).count()
            health['users_total'] = db.query(User).count()
            health['changes_total'] = db.query(Change).count()
            health['audit_logs_total'] = db.query(AuditLog).count()

            # Recent activity
            one_hour_ago = datetime.utcnow() - timedelta(hours=1)
            health['changes_last_hour'] = db.query(Change).filter(Change.created_at > one_hour_ago).count()
            health['audit_logs_last_hour'] = db.query(AuditLog).filter(AuditLog.created_at > one_hour_ago).count()

            # Sync queue health
            pending_changes = db.query(Change).filter(Change.processed_at.is_(None)).count()
            health['pending_changes'] = pending_changes

            # Update business metrics
            update_business_metrics(
                products=health['products_total'],
                stores=health['stores_total']
            )

            db.close()
            return health
        except Exception as e:
            return {"error": f"Database health check failed: {e}"}

    def _parse_prometheus_metrics(self, metrics_text: str) -> Dict[str, Any]:
        """Parse Prometheus metrics text into a dictionary"""
        parsed = {}
        lines = metrics_text.strip().split('\n')

        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            if '{' in line and '}' in line:
                # Handle metrics with labels
                metric_name = line.split('{')[0]
                # For simplicity, just count occurrences
                if metric_name not in parsed:
                    parsed[metric_name] = 0
                parsed[metric_name] += 1
            else:
                parts = line.split()
                if len(parts) >= 2:
                    metric_name = parts[0]
                    try:
                        value = float(parts[1])
                        parsed[metric_name] = value
                    except ValueError:
                        parsed[metric_name] = parts[1]

        return parsed

    def display_dashboard(self):
        """Display the complete health dashboard"""
        print("🔍 POS & Inventory Sync Health Dashboard")
        print("=" * 50)
        print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()

        # System Status
        print("📊 System Status:")
        status = self.get_system_status()
        if "error" not in status:
            print(f"  Status: {status.get('status', 'unknown')}")
            print(f"  Version: {status.get('version', 'unknown')}")
            features = status.get('features', {})
            print(f"  Enabled Features: {len(features)}")
            for feature, enabled in features.items():
                print(f"    - {feature}: {'✅' if enabled else '❌'}")
        else:
            print(f"  ❌ {status['error']}")
        print()

        # Feature Flags
        print("🚩 Feature Flags:")
        flags = self.get_feature_flags()
        if "error" not in flags:
            all_flags = flags.get('flags', {})
            enabled_flags = flags.get('enabled_flags', {})
            print(f"  Total Flags: {len(all_flags)}")
            print(f"  Enabled: {len(enabled_flags)}")
            print(f"  Disabled: {len(all_flags) - len(enabled_flags)}")

            # Show critical sync flags
            critical_flags = ['SYNC_ENABLED', 'OFFLINE_MODE_ENABLED', 'CONFLICT_RESOLUTION_ENABLED']
            print("  Critical Sync Flags:")
            for flag in critical_flags:
                value = all_flags.get(flag, False)
                status_icon = "✅" if value else "❌"
                print(f"    - {flag}: {status_icon}")
        else:
            print(f"  ❌ {flags['error']}")
        print()

        # Database Health
        print("💾 Database Health:")
        db_health = self.get_database_health()
        if "error" not in db_health:
            print(f"  Products: {db_health.get('products_total', 0)}")
            print(f"  Stores: {db_health.get('stores_total', 0)}")
            print(f"  Users: {db_health.get('users_total', 0)}")
            print(f"  Total Changes: {db_health.get('changes_total', 0)}")
            print(f"  Pending Changes: {db_health.get('pending_changes', 0)}")
            print(f"  Changes (last hour): {db_health.get('changes_last_hour', 0)}")
            print(f"  Audit Logs (last hour): {db_health.get('audit_logs_last_hour', 0)}")
        else:
            print(f"  ❌ {db_health['error']}")
        print()

        # Metrics
        print("📈 Sync Metrics:")
        metrics = self.get_metrics()
        if "error" not in metrics:
            # Sync operations
            sync_ops = metrics.get('sync_operations_total', 0)
            print(f"  Total Sync Operations: {sync_ops}")

            # Sync duration (if available)
            sync_duration = metrics.get('sync_duration_seconds_sum', 0)
            sync_count = metrics.get('sync_duration_seconds_count', 1)
            if sync_count > 0:
                avg_duration = sync_duration / sync_count
                print(".2f")(f"  Average Sync Duration: {avg_duration:.2f} seconds")
            else:
                print("  Average Sync Duration: N/A")
            # Conflicts
            conflicts = metrics.get('sync_conflicts_total', 0)
            print(f"  Sync Conflicts: {conflicts}")

            # API metrics
            api_requests = metrics.get('api_requests_total', 0)
            print(f"  API Requests: {api_requests}")

            # Error metrics
            errors = metrics.get('errors_total', 0)
            print(f"  Total Errors: {errors}")
        else:
            print(f"  ❌ {metrics['error']}")
        print()

        # Health Assessment
        print("🏥 Health Assessment:")
        issues = []

        # Check critical systems
        if "error" in status:
            issues.append("System status check failed")
        if "error" in flags:
            issues.append("Feature flags check failed")
        if "error" in db_health:
            issues.append("Database health check failed")
        if "error" in metrics:
            issues.append("Metrics collection failed")

        # Check sync health
        if db_health.get('pending_changes', 0) > 100:
            issues.append("High number of pending changes")
        if metrics.get('sync_conflicts_total', 0) > 10:
            issues.append("High conflict rate detected")

        if not issues:
            print("  ✅ All systems healthy")
        else:
            print("  ⚠️  Issues detected:")
            for issue in issues:
                print(f"    - {issue}")

        print()
        print("=" * 50)


def main():
    """Main dashboard function"""
    import argparse

    parser = argparse.ArgumentParser(description="POS & Inventory Sync Health Dashboard")
    parser.add_argument('--url', default='http://localhost:8000',
                       help='Base URL of the API server (default: http://localhost:8000)')
    parser.add_argument('--watch', action='store_true',
                       help='Continuously monitor (refresh every 30 seconds)')
    parser.add_argument('--interval', type=int, default=30,
                       help='Refresh interval in seconds (default: 30)')

    args = parser.parse_args()

    dashboard = SyncHealthDashboard(args.url)

    if args.watch:
        try:
            while True:
                os.system('cls' if os.name == 'nt' else 'clear')
                dashboard.display_dashboard()
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\nMonitoring stopped.")
    else:
        dashboard.display_dashboard()


if __name__ == "__main__":
    main()