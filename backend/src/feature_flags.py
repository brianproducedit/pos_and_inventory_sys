"""
Feature Flags Management
Provides centralized feature flag management for gradual rollouts and A/B testing.
"""
import os
from typing import Dict, Any, Optional
from decouple import config as decouple_config


class FeatureFlags:
    """Centralized feature flag management system"""

    def __init__(self):
        # Default feature flags with their default values
        self._flags: Dict[str, Any] = {
            # Sync-related features
            'SYNC_ENABLED': True,
            'OFFLINE_MODE_ENABLED': True,
            'CONFLICT_RESOLUTION_ENABLED': True,
            'BULK_SYNC_ENABLED': False,  # Gradual rollout

            # Authentication features
            'OFFLINE_AUTH_ENABLED': True,
            'SECURE_CREDENTIAL_STORAGE': True,

            # Store management features
            'MULTI_STORE_ENABLED': True,
            'STORE_SWITCHING_ENABLED': True,
            'ROLE_BASED_ACCESS_ENABLED': True,

            # Analytics features
            'ANALYTICS_ENABLED': True,
            'REAL_TIME_ANALYTICS': False,  # Gradual rollout

            # Admin features
            'ADMIN_DASHBOARD_ENABLED': True,
            'AUDIT_LOGGING_ENABLED': True,

            # Experimental features (default off)
            'EXPERIMENTAL_UI_ENABLED': False,
            'ADVANCED_REPORTING_ENABLED': False,
        }

        # Load from environment variables
        self._load_from_env()

    def _load_from_env(self):
        """Load feature flags from environment variables"""
        for flag_name in self._flags.keys():
            env_value = os.getenv(f'FEATURE_{flag_name}')
            if env_value is not None:
                # Convert string values to appropriate types
                if env_value.lower() in ('true', '1', 'yes', 'on'):
                    self._flags[flag_name] = True
                elif env_value.lower() in ('false', '0', 'no', 'off'):
                    self._flags[flag_name] = False
                else:
                    # Try to convert to int/float, otherwise keep as string
                    try:
                        if '.' in env_value:
                            self._flags[flag_name] = float(env_value)
                        else:
                            self._flags[flag_name] = int(env_value)
                    except ValueError:
                        self._flags[flag_name] = env_value

    def is_enabled(self, flag_name: str) -> bool:
        """Check if a feature flag is enabled"""
        return bool(self._flags.get(flag_name, False))

    def get_value(self, flag_name: str, default: Any = None) -> Any:
        """Get the value of a feature flag"""
        return self._flags.get(flag_name, default)

    def set_flag(self, flag_name: str, value: Any):
        """Set a feature flag value (for testing or runtime configuration)"""
        self._flags[flag_name] = value

    def get_all_flags(self) -> Dict[str, Any]:
        """Get all feature flags and their values"""
        return self._flags.copy()

    def get_enabled_flags(self) -> Dict[str, Any]:
        """Get only enabled feature flags"""
        return {k: v for k, v in self._flags.items() if self.is_enabled(k)}


# Global feature flags instance
feature_flags = FeatureFlags()


def is_feature_enabled(flag_name: str) -> bool:
    """Convenience function to check if a feature is enabled"""
    return feature_flags.is_enabled(flag_name)


def get_feature_value(flag_name: str, default: Any = None) -> Any:
    """Convenience function to get a feature flag value"""
    return feature_flags.get_value(flag_name, default)