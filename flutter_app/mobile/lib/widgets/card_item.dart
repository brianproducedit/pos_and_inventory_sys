import 'package:flutter/material.dart';

class CardItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData? leadingIcon;
  const CardItem(
      {super.key,
      required this.title,
      required this.subtitle,
      this.leadingIcon});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: leadingIcon != null ? Icon(leadingIcon) : null,
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
