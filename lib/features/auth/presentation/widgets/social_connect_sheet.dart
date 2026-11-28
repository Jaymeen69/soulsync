import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/api_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/network/api_error_handler.dart';
import '../../../../core/router/route_names.dart';
import '../../../../shared/utils/validators.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../../../../shared/widgets/soulsync_text_field.dart';
import '../providers/auth_provider.dart';

/// Supported social account providers for quick connect & linking.
const List<Map<String, dynamic>> kSocialProviders = [
  {'id': 'google', 'label': 'Google', 'icon': Icons.g_mobiledata_rounded},
  {'id': 'apple', 'label': 'Apple', 'icon': Icons.apple_rounded},
  {'id': 'instagram', 'label': 'Instagram', 'icon': Icons.camera_alt_outlined},
  {'id': 'facebook', 'label': 'Facebook', 'icon': Icons.facebook_rounded},
  {'id': 'other', 'label': 'Other', 'icon': Icons.public_rounded},
];

/// Opens a bottom sheet to sign in or register using Google or another social account.
Future<void> showSocialConnectSheet(
  BuildContext context,
  WidgetRef ref, {
  String initialProvider = 'google',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SocialConnectSheet(
      parentContext: context,
      ref: ref,
      initialProvider: initialProvider,
    ),
  );
}

/// Developer-only dialog to inspect or override backend URL in debug builds.
Future<void> showServerUrlDialog(BuildContext context) async {
  if (!kDebugMode || ApiConfig.isProduction) return;
  final ctrl = TextEditingController(text: AuthNotifier.apiBaseUrl);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: context.ssSurface,
      title: Text(
        'Server Connection (Dev)',
        style: TextStyle(color: context.ssTextPrimary, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter a custom development or staging backend URL.',
            style: TextStyle(color: context.ssTextSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            style: TextStyle(color: context.ssTextPrimary, fontSize: 13.5),
            decoration: InputDecoration(
              labelText: 'Backend API URL',
              hintText: ApiConfig.defaultDevUrl,
              filled: true,
              fillColor: context.ssInputFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await AuthNotifier.setServerUrl('');
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Reset Default'),
        ),
        ElevatedButton(
          onPressed: () async {
            await AuthNotifier.setServerUrl(ctrl.text);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  ctrl.dispose();
}

/// Reusable "Or continue with" social login buttons for Login & Register screens.
class SocialAuthButtons extends ConsumerWidget {
  const SocialAuthButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: context.ssBorder)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR CONTINUE WITH',
                style: AppTypography.labelMedium.copyWith(
                  color: context.ssTextSecondary,
                  fontSize: 11,
                  letterSpacing: 0.9,
                ),
              ),
            ),
            Expanded(child: Divider(color: context.ssBorder)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showSocialConnectSheet(context, ref, initialProvider: 'google'),
                icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                label: const Text('Google', style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.ssTextPrimary,
                  backgroundColor: context.ssSurface.withValues(alpha: 0.85),
                  side: BorderSide(color: context.ssBorder, width: 1.3),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => showSocialConnectSheet(context, ref, initialProvider: 'other'),
                icon: const Icon(Icons.hub_outlined, size: 19),
                label: const Text('Other Social', style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.ssTextPrimary,
                  backgroundColor: context.ssSurface.withValues(alpha: 0.85),
                  side: BorderSide(color: context.ssBorder, width: 1.3),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SocialConnectSheet extends StatefulWidget {
  const _SocialConnectSheet({
    required this.parentContext,
    required this.ref,
    required this.initialProvider,
  });

  final BuildContext parentContext;
  final WidgetRef ref;
  final String initialProvider;

  @override
  State<_SocialConnectSheet> createState() => _SocialConnectSheetState();
}

class _SocialConnectSheetState extends State<_SocialConnectSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _handleCtrl = TextEditingController();
  late String _provider;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _provider = widget.initialProvider;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _handleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.ref.read(authRepositoryProvider).signInWithSocial(
            provider: _provider,
            email: _emailCtrl.text,
            displayName: _nameCtrl.text,
            socialAccount: _handleCtrl.text,
          );
      if (mounted) {
        Navigator.pop(context);
        if (widget.parentContext.mounted) {
          widget.parentContext.go(RouteNames.home);
        }
      }
    } catch (e) {
      setState(() => _error = ApiErrorHandler.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + bottomInset),
      decoration: BoxDecoration(
        color: context.ssSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: context.ssBorder),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.ssBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Connect Social Account',
                style: AppTypography.headlineMedium.copyWith(
                  color: context.ssTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose Google or another social provider to sign in or link your account.',
                style: AppTypography.bodySmall.copyWith(color: context.ssTextSecondary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kSocialProviders.map((p) {
                  final id = p['id'] as String;
                  final selected = _provider == id;
                  return ChoiceChip(
                    avatar: Icon(
                      p['icon'] as IconData,
                      size: 17,
                      color: selected ? Colors.white : context.ssPrimary,
                    ),
                    label: Text(p['label'] as String),
                    selected: selected,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : context.ssTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: context.ssInputFill,
                    onSelected: (_) => setState(() => _provider = id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SoulSyncTextField(
                label: '${_provider[0].toUpperCase()}${_provider.substring(1)} Email',
                hint: 'you@gmail.com',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
                validator: Validators.email,
              ),
              const SizedBox(height: 12),
              SoulSyncTextField(
                label: 'Display Name (Optional)',
                hint: 'Your name in SoulSync',
                controller: _nameCtrl,
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 12),
              SoulSyncTextField(
                label: 'Social Handle / ID (Optional)',
                hint: '@username or account ID',
                controller: _handleCtrl,
                prefixIcon: Icons.alternate_email_rounded,
              ),
              const SizedBox(height: 18),
              SoulSyncButton(
                label: 'Continue with ${_provider[0].toUpperCase()}${_provider.substring(1)}',
                onPressed: _submit,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
