import 'package:flutter/material.dart';

class ManagementListItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const ManagementListItem(
      {super.key, required this.title, this.subtitle, this.actions});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: actions ?? [],
        ),
      ),
    );
  }
}
