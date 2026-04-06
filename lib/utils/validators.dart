final _emailRegex = RegExp(
  r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)+$',
);

String? validateEmail(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please enter your email';
  }
  if (!_emailRegex.hasMatch(value.trim())) {
    return 'Please enter a valid email address';
  }
  return null;
}

String? validateRequired(String? value, [String fieldName = 'This field']) {
  if (value == null || value.trim().isEmpty) {
    return '$fieldName is required';
  }
  return null;
}

String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required';
  }
  if (value.length < 6) {
    return 'Password must be at least 6 characters';
  }
  return null;
}

String? validatePhone(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final digits = value.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.length < 7 || digits.length > 15) {
    return 'Please enter a valid phone number';
  }
  return null;
}

String? validateOptionalEmail(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  if (!_emailRegex.hasMatch(value.trim())) {
    return 'Please enter a valid email address';
  }
  return null;
}

String? validatePositiveNumber(String? value, [String fieldName = 'Value']) {
  if (value == null || value.trim().isEmpty) {
    return '$fieldName is required';
  }
  final n = num.tryParse(value.trim());
  if (n == null) {
    return 'Please enter a valid number';
  }
  if (n <= 0) {
    return '$fieldName must be greater than zero';
  }
  return null;
}

String? validateDropdown(String? value, [String fieldName = 'Selection']) {
  if (value == null || value.isEmpty) {
    return 'Please select $fieldName';
  }
  return null;
}
