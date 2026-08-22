import 'package:flutter/material.dart';
import 'package:mobile/utils/smooth_page_route.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'package:mobile/widgets/app_bottom_nav.dart';
import 'package:mobile/providers/store_provider.dart';
import 'package:mobile/widgets/store_quick_action.dart';
import 'package:mobile/widgets/store_badge.dart';
import 'package:mobile/theme/tokens.dart';
import 'package:mobile/db/app_database.dart';
import 'store_settings_screen.dart';
import 'user_settings_screen.dart';
import 'system_settings_screen.dart';
import 'user_profile_screen.dart';


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.role ?? UserRole.cashier;
    // Debug: log role so we can verify Settings visibility on device
    debugPrint('SettingsScreen built, role=$role');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.primaryBrand,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: StoreIndicator(
                store: context.watch<StoreProvider>().currentStore),
          ),
        ),
        actions: [
          if (role == UserRole.superadmin || role == UserRole.admin)
            const StoreQuickAction(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // User Profile (available to all users)
          _buildSettingsCard(
            context,
            'User Profile',
            'Update profile information and password',
            Icons.account_circle,
            () => context.pushSmooth(const UserProfileScreen()),
          ),

          const SizedBox(height: 16),

          // User Settings (available to all users)
          _buildSettingsCard(
            context,
            'User Settings',
            'Theme, language, notifications',
            Icons.person,
            () => context.pushSmooth(const UserSettingsScreen()),
          ),

          const SizedBox(height: 16),

          // Data Protection (admin & superadmin)
          if (role == UserRole.admin || role == UserRole.superadmin) ...[
            _buildSettingsCard(
              context,
              'Data Protection',
              'Backup, restore, and data integrity',
              Icons.security,
              () => Navigator.pushNamed(context, '/data_protection'),
            ),
            const SizedBox(height: 16),
          ],

          // Store Settings (admin only)
          if (role == UserRole.admin) ...[
            _buildSettingsCard(
              context,
              'Store Settings',
              'Business info, receipt settings',
              Icons.store,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoreSettingsScreen()),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // System Settings (superadmin only)
          if (role == UserRole.superadmin) ...[
            _buildSettingsCard(
              context,
              'System Settings',
              'Global system configuration',
              Icons.admin_panel_settings,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SystemSettingsScreen()),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Sync demo (admin & superadmin)
          if (role == UserRole.superadmin || role == UserRole.admin) ...[
            _buildSettingsCard(
              context,
              'Sync Errors',
              'View and resolve sync conflicts',
              Icons.error_outline,
              () => Navigator.pushNamed(context, '/admin/sync-errors'),
            ),

          ],
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentRoute: '/settings'),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryBrand),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing:
            const Icon(Icons.chevron_right, color: AppColors.primaryBrand),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
