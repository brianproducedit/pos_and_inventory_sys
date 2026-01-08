import 'package:flutter/material.dart';

class PrimaryTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final String? errorText;
  final bool obscureText;
  final Widget? suffixIcon;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;

  const PrimaryTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.errorText,
    this.obscureText = false,
    this.suffixIcon,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.semanticLabel,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscureText,
      enabled: enabled,
      autofocus: autofocus,
      focusNode: focusNode,
      style: const TextStyle(
          color: Colors.black), // Explicitly set text color to black
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.12 * 255)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 2.0),
        ),
        suffixIcon: suffixIcon,
      ),
      // Accessibility
      maxLines: maxLines,
      keyboardType: keyboardType ?? TextInputType.text,
      textInputAction: textInputAction ?? TextInputAction.next,
    );
  }
}
