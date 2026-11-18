/// Form validation helpers with strict password complexity policy.
abstract final class Validators {
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  /// Strict password complexity policy:
  /// - Minimum 8 characters
  /// - At least one uppercase letter (A–Z)
  /// - At least one lowercase letter (a–z)
  /// - At least one number (0–9)
  /// - At least one special character (e.g. @, #, $, !, %, *, ?, &, etc.)
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!value.contains(RegExp(r'[A-Z]'))) return 'Must include at least one uppercase letter (A-Z)';
    if (!value.contains(RegExp(r'[a-z]'))) return 'Must include at least one lowercase letter (a-z)';
    if (!value.contains(RegExp(r'[0-9]'))) return 'Must include at least one number (0-9)';
    if (!value.contains(RegExp(r'[@$!%*?&#^()_\-+=\[\]{}|~`]'))) {
      return 'Must include at least one special character (@, #, \$, !, etc.)';
    }
    return null;
  }

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static String? displayName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Name is required';
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    if (value.trim().length > 50) return 'Name must be 50 characters or less';
    return null;
  }

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? inviteCode(String? value) {
    if (value == null || value.trim().isEmpty) return 'Invite code is required';
    if (value.trim().length < 6) return 'Invalid invite code format';
    return null;
  }
}
