import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';

class AppBottomNav extends StatelessWidget {
  final String currentRoute;

  const AppBottomNav({super.key, this.currentRoute = ''});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final role = authProvider.role;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: currentRoute == '/home'
                ? null
                : () {
                    try {
                      Navigator.of(context).pushReplacementNamed('/home');
                    } catch (e) {
                      debugPrint('Navigation to /home failed: $e');
                    }
                  },
          ),

          // Inventory (admin/superadmin only)
          if (role == 'superadmin' || role == 'admin')
            IconButton(
              icon: const Icon(Icons.inventory),
              onPressed: currentRoute == '/inventory'
                  ? null
                  : () {
                      try {
                        Navigator.of(context)
                            .pushReplacementNamed('/inventory');
                      } catch (e) {
                        debugPrint('Navigation to /inventory failed: $e');
                      }
                    },
            ),

          // POS (available to all)
          IconButton(
            icon: const Icon(Icons.point_of_sale),
            onPressed: currentRoute == '/pos'
                ? null
                : () {
                    try {
                      Navigator.of(context).pushReplacementNamed('/pos');
                    } catch (e) {
                      debugPrint('Navigation to /pos failed: $e');
                    }
                  },
          ),

          // Analytics (admin/superadmin only)
          if (role == 'superadmin' || role == 'admin')
            IconButton(
              icon: const Icon(Icons.analytics),
              onPressed: currentRoute == '/analytics'
                  ? null
                  : () {
                      try {
                        Navigator.of(context)
                            .pushReplacementNamed('/analytics');
                      } catch (e) {
                        debugPrint('Navigation to /analytics failed: $e');
                      }
                    },
            ),

          // Audit Logs (admin/superadmin only)
          if (role == 'superadmin' || role == 'admin')
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: currentRoute == '/audit_logs'
                  ? null
                  : () {
                      try {
                        Navigator.of(context)
                            .pushReplacementNamed('/audit_logs');
                      } catch (e) {
                        debugPrint('Navigation to /audit_logs failed: $e');
                      }
                    },
            ),
          // Settings (available to all roles)
          // IconButton(
          //   icon: const Icon(Icons.settings),
          //   onPressed: currentRoute == '/settings'
          //       ? null
          //       : () => Navigator.of(context).pushReplacementNamed('/settings'),
          // ),
        ],
      ),
    );
  }
}
