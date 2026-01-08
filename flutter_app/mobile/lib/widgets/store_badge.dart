import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/db/app_database.dart';

class StoreBadge extends StatelessWidget {
  final Map<String, dynamic>? store;
  final bool showLocation;
  final bool compact;
  final VoidCallback? onTap;

  const StoreBadge({
    super.key,
    required this.store,
    this.showLocation = true,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Treat null or id==0 as the 'All Stores' global view
    if (store == null || store?['id'] == 0) {
      return _buildAllStoresBadge(context);
    }

    final s = store!;
    final name = (s['name'] ?? 'Unnamed Store').toString();
    final location = s['location']?.toString();
    final isActive = s['is_active'] == true;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1 * 255)
              : Theme.of(context)
                  .colorScheme
                  .error
                  .withValues(alpha: 0.1 * 255),
          border: Border.all(
            color: isActive
                ? Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3 * 255)
                : Theme.of(context)
                    .colorScheme
                    .error
                    .withValues(alpha: 0.3 * 255),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Store Icon
            Container(
              width: compact ? 20 : 24,
              height: compact ? 20 : 24,
              decoration: BoxDecoration(
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.store,
                color: Theme.of(context).colorScheme.onPrimary,
                size: compact ? 12 : 14,
              ),
            ),

            const SizedBox(width: 6),

            // Store Info
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Store Name
                  Text(
                    name,
                    style: (compact
                            ? Theme.of(context).textTheme.bodySmall
                            : Theme.of(context).textTheme.bodyMedium)
                        ?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7 * 255),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),

                  // Store Location
                  if (showLocation &&
                      store!['location'] != null &&
                      !compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      location!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6 * 255),
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],

                  // Status Indicator
                  if (!isActive) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Inactive',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: compact ? 8 : 10,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Tap indicator
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_right,
                size: compact ? 14 : 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5 * 255),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildEmptyBadge(BuildContext context) {
    // Kept for backward compatibility: show a subtle empty badge
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5 * 255),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outline
              .withValues(alpha: 0.3 * 255),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.store_outlined,
            size: compact ? 16 : 20,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.5 * 255),
          ),
          const SizedBox(width: 6),
          Text(
            'No Store Selected',
            style: (compact
                    ? Theme.of(context).textTheme.bodySmall
                    : Theme.of(context).textTheme.bodyMedium)
                ?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5 * 255),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllStoresBadge(BuildContext context) {
    // Check role to show limited access hint for non-admins
    final role = Provider.of<AuthProvider>(context, listen: false).role;
    final isAdminOrSuper =
        role == UserRole.superadmin || role == UserRole.admin;

    final label = isAdminOrSuper
        ? 'Viewing: All Stores'
        : 'Viewing: All Stores (limited access)';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surface
              .withValues(alpha: 0.95 * 255),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.25 * 255),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 20 : 24,
              height: compact ? 20 : 24,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.language,
                color: Theme.of(context).colorScheme.onPrimary,
                size: compact ? 12 : 14,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: (compact
                        ? Theme.of(context).textTheme.bodySmall
                        : Theme.of(context).textTheme.bodyMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_right,
                size: compact ? 14 : 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5 * 255),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Compact version for app bars and headers
class StoreIndicator extends StatelessWidget {
  final Map<String, dynamic>? store;

  const StoreIndicator({
    super.key,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    // Treat null or id==0 as 'All Stores'
    if (store == null || store?['id'] == 0) {
      // Check role - only show All Stores for admin/superadmin
      final role = Provider.of<AuthProvider>(context, listen: false).role;
      final isAdminOrSuper =
          role == UserRole.superadmin || role == UserRole.admin;

      if (!isAdminOrSuper) {
        // For non-admin roles, show a message that they don't have global access
        return Semantics(
          label: 'Store-specific view only',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surface
                  .withValues(alpha: 0.95 * 255),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3 * 255),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outline,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    Icons.store,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Store View',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Show explicit indicator for 'All Stores' (global view)
      const label = 'Viewing: All Stores';

      return Semantics(
        label: 'Viewing All Stores',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surface
                .withValues(alpha: 0.95 * 255),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.3 * 255),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.language,
                  color: Theme.of(context).colorScheme.onPrimary,
                  size: 12,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final s = store!;
    final name = (s['name'] ?? 'Unnamed Store').toString();
    final isActive = s['is_active'] == true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color:
            Theme.of(context).colorScheme.surface.withValues(alpha: 0.9 * 255),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.3 * 255)
              : Theme.of(context)
                  .colorScheme
                  .error
                  .withValues(alpha: 0.3 * 255),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.store,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 12,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
