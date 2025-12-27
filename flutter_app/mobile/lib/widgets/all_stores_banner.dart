import 'package:flutter/material.dart';

class AllStoresBanner extends StatelessWidget {
  const AllStoresBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.primary;
    final fg = Theme.of(context).colorScheme.onPrimary;

    return Semantics(
      label: 'All Stores Banner',
      child: LayoutBuilder(builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        final height = isNarrow ? 40.0 : 48.0;
        return Container(
          key: const Key('allStoresBanner'),
          width: double.infinity,
          height: height,
          color: bg.withOpacity(0.95),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.language, color: fg, size: isNarrow ? 16 : 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Viewing: All Stores — aggregated data',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w600,
                      fontSize: isNarrow ? 13 : 14),
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 8),
                Text(
                  'Aggregated',
                  style: TextStyle(color: fg.withOpacity(0.9), fontSize: 12),
                ),
              ]
            ],
          ),
        );
      }),
    );
  }
}
