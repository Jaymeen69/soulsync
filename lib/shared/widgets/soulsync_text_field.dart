import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';

class SoulSyncTextField extends StatefulWidget {
  const SoulSyncTextField({
    super.key,
    required this.label,
    this.hint,
    this.controller,
    this.validator,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.prefixIcon,
    this.suffix,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofillHints,
    this.focusNode,
  });

  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;

  @override
  State<SoulSyncTextField> createState() => _SoulSyncTextFieldState();
}

class _SoulSyncTextFieldState extends State<SoulSyncTextField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText;
  }

  @override
  void didUpdateWidget(SoulSyncTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscureText != widget.obscureText) {
      setState(() {
        _obscure = widget.obscureText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      obscureText: _obscure,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      enabled: widget.enabled,
      autofillHints: widget.autofillHints,
      focusNode: widget.focusNode,
      style: TextStyle(
        color: context.ssTextPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(
          color: context.ssIsDark
              ? AppColors.darkTextSecondary
              : const Color(0xFF4A3E6B),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: TextStyle(
          color: context.ssPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        hintText: widget.hint,
        hintStyle: TextStyle(
          color: context.ssTextHint,
          fontSize: 14,
        ),
        filled: true,
        fillColor: context.ssInputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.ssBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.ssBorder, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.ssPrimary, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, color: context.ssPrimary, size: 22)
            : null,
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _obscure ? context.ssTextHint : context.ssPrimary,
                  size: 22,
                ),
                tooltip: _obscure ? 'Show password' : 'Hide password',
                splashRadius: 22,
                onPressed: () {
                  setState(() {
                    _obscure = !_obscure;
                  });
                },
              )
            : widget.suffix,
      ),
    );
  }
}
