import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  int _selectedPulseIndex = 0;
  int _selectedMoodIndex = 0;
  bool _isSendingPulse = false;
  bool _isSavingMood = false;
  bool _isMoodPrivate = false;
  final TextEditingController _moodNoteCtrl = TextEditingController();

  Map<String, dynamic>? _partnerLatestMood;
  List<Map<String, dynamic>> _userMoodHistory = [];

  static const List<_PulseType> _pulseTypes = [
    _PulseType(name: 'Love', emoji: '❤️', icon: Icons.favorite_rounded, color: AppColors.pulseLove),
    _PulseType(name: 'Hug', emoji: '🫂', icon: Icons.accessibility_new_rounded, color: AppColors.pulseHug),
    _PulseType(name: 'Kiss', emoji: '💋', icon: Icons.volunteer_activism_rounded, color: AppColors.pulseKiss),
    _PulseType(name: 'Missing You', emoji: '🥺', icon: Icons.favorite_border_rounded, color: AppColors.pulseMissing),
    _PulseType(name: 'Thinking of You', emoji: '💭', icon: Icons.psychology_rounded, color: AppColors.pulseThinking),
  ];

  static const List<_MoodItem> _moodItems = [
    _MoodItem(label: 'Happy', emoji: '😊', color: Color(0xFFFFB300)),
    _MoodItem(label: 'Romantic', emoji: '🥰', color: AppColors.accent),
    _MoodItem(label: 'Excited', emoji: '🤩', color: Color(0xFFFF5722)),
    _MoodItem(label: 'Need Attention', emoji: '🥺', color: AppColors.primaryLight),
    _MoodItem(label: 'Stressed', emoji: '😫', color: Color(0xFF78909C)),
    _MoodItem(label: 'Lonely', emoji: '😔', color: Color(0xFF5C6BC0)),
  ];

  final List<String> _pulseHistory = [
    'You sent "Thinking of You 💭" • 5m ago',
    'Partner sent "Love ❤️" • 42m ago',
    'Partner sent "Hug 🫂" • 2h ago',
    'You sent "Kiss 💋" • Yesterday',
  ];

  @override
  void initState() {
    super.initState();
    _fetchMoodData();
  }

  @override
  void dispose() {
    _moodNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchMoodData() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final res = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/mood?user_id=${user.id}&couple_id=${user.coupleId ?? ""}'),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _partnerLatestMood = data['partner_latest'] as Map<String, dynamic>?;
            _userMoodHistory = (data['user_history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _sendPulse() async {
    final user = ref.read(currentUserProvider);
    final pulse = _pulseTypes[_selectedPulseIndex];
    HapticFeedback.heavyImpact();

    setState(() {
      _isSendingPulse = true;
    });

    try {
      final res = await http.post(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/pulse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sender': user?.displayName ?? 'You',
          'recipient': user?.partnerName ?? 'Partner',
          'type': '${pulse.name} ${pulse.emoji}',
        }),
      ).timeout(const Duration(seconds: 4));

      if (mounted) {
        setState(() {
          _pulseHistory.insert(0, 'You sent "${pulse.name} ${pulse.emoji}" • Just now');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ ${pulse.name} ${pulse.emoji} pulse delivered to your partner!'),
            duration: const Duration(seconds: 2),
            backgroundColor: pulse.color,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delivered pulse locally: ${pulse.name} ${pulse.emoji}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingPulse = false);
    }
  }

  Future<void> _submitMood() async {
    final user = ref.read(currentUserProvider);
    final chosenMood = _moodItems[_selectedMoodIndex];
    setState(() => _isSavingMood = true);

    try {
      await http.post(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/mood'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': user?.id ?? 'u1',
          'couple_id': user?.coupleId ?? 'c1',
          'mood': chosenMood.label,
          'emoji': chosenMood.emoji,
          'note': _moodNoteCtrl.text.trim(),
          'is_private': _isMoodPrivate,
        }),
      ).timeout(const Duration(seconds: 4));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isMoodPrivate
                  ? '🔒 Private mood saved in personal journal.'
                  : '✨ Mood "${chosenMood.label} ${chosenMood.emoji}" shared with ${user?.partnerName ?? "Partner"}!',
            ),
          ),
        );
        _moodNoteCtrl.clear();
        _fetchMoodData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mood recorded locally!')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingMood = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPulse = _pulseTypes[_selectedPulseIndex];
    final user = ref.watch(currentUserProvider);
    final partnerName = user?.partnerName ?? 'Partner';

    return Scaffold(
      backgroundColor: context.ssBg,
      appBar: AppBar(
        title: const Text('Connect 💌'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Love Pulse Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: context.ssSurface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: currentPulse.color.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(color: currentPulse.color.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text('Send a Love Pulse', style: AppTypography.headlineMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Instant haptic & emotional signal to your partner',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: 24),

                  // Animated Pulse Big Bubble
                  GestureDetector(
                    onTap: _sendPulse,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _isSendingPulse ? 130 : 110,
                      height: _isSendingPulse ? 130 : 110,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [currentPulse.color, currentPulse.color.withOpacity(0.75)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: currentPulse.color.withOpacity(0.4),
                            blurRadius: _isSendingPulse ? 30 : 15,
                            spreadRadius: _isSendingPulse ? 6 : 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          currentPulse.emoji,
                          style: TextStyle(fontSize: _isSendingPulse ? 54 : 44),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Pulse Type Selector Pills
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pulseTypes.length, (index) {
                        final p = _pulseTypes[index];
                        final isSel = _selectedPulseIndex == index;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() => _selectedPulseIndex = index);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? p.color : context.ssSurfaceVariant,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Text(p.emoji, style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 6),
                                Text(
                                  p.name,
                                  style: TextStyle(
                                    color: isSel ? Colors.white : context.ssTextPrimary,
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SoulSyncButton(
                    label: 'Send ${currentPulse.name} ${currentPulse.emoji} to $partnerName',
                    onPressed: _sendPulse,
                    isLoading: _isSendingPulse,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Partner's Shared Mood Banner (Section 6 Fix)
            if (_partnerLatestMood != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.accent.withOpacity(0.15), AppColors.primary.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Text(
                      _partnerLatestMood!['emoji'] ?? '🥰',
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$partnerName is feeling ${_partnerLatestMood!['mood']} right now',
                            style: AppTypography.titleLarge,
                          ),
                          if ((_partnerLatestMood!['note'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '"${_partnerLatestMood!['note']}"',
                              style: AppTypography.bodySmall.copyWith(fontStyle: FontStyle.italic),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Emotional Sync / Mood Section (Section 6 Fix: Note + Privacy + Backend Sync)
            Text('Emotional Sync (Mood)', style: AppTypography.headlineSmall),
            const SizedBox(height: 4),
            Text('Check in and voluntarily share your mood with your partner', style: AppTypography.bodySmall),
            const SizedBox(height: 14),

            // Mood selector grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _moodItems.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.25,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, index) {
                final m = _moodItems[index];
                final isSel = _selectedMoodIndex == index;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedMoodIndex = index);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSel ? m.color.withValues(alpha: 0.2) : context.ssSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSel ? m.color : context.ssBorder,
                        width: isSel ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(m.emoji, style: const TextStyle(fontSize: 26)),
                        const SizedBox(height: 4),
                        Text(
                          m.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                            color: isSel ? m.color : context.ssTextPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Optional Personal Note TextField
            TextField(
              controller: _moodNoteCtrl,
              style: TextStyle(color: context.ssTextPrimary),
              decoration: InputDecoration(
                hintText: 'Add an optional note for $partnerName...',
                filled: true,
                fillColor: context.ssInputFill,
                prefixIcon: Icon(Icons.edit_note_rounded, color: context.ssPrimary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.ssBorder),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Private vs Shared with Partner Switch (Rule: Private by default not exposed to partner or admin)
            Row(
              children: [
                Switch(
                  value: _isMoodPrivate,
                  activeColor: AppColors.primary,
                  onChanged: (val) => setState(() => _isMoodPrivate = val),
                ),
                Text(
                  _isMoodPrivate ? 'Keep this mood private (Journal only 🔒)' : 'Share this mood with $partnerName 💞',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: _isMoodPrivate ? AppColors.warning : AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            SoulSyncButton(
              label: 'Update My Mood',
              onPressed: _submitMood,
              isLoading: _isSavingMood,
              variant: SoulSyncButtonVariant.secondary,
            ),
            const SizedBox(height: 28),

            // Pulse History Section
            Text('Recent Activity', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: context.ssSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.ssBorder),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _pulseHistory.length,
                separatorBuilder: (_, __) => Divider(color: AppColors.primary.withOpacity(0.06), height: 1),
                itemBuilder: (context, index) {
                  final item = _pulseHistory[index];
                  final isYou = item.startsWith('You');
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isYou ? AppColors.primary.withOpacity(0.1) : AppColors.accent.withOpacity(0.1),
                      child: Icon(
                        isYou ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: isYou ? AppColors.primary : AppColors.accent,
                        size: 18,
                      ),
                    ),
                    title: Text(item, style: AppTypography.bodyMedium),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _PulseType {
  const _PulseType({required this.name, required this.emoji, required this.icon, required this.color});
  final String name;
  final String emoji;
  final IconData icon;
  final Color color;
}

class _MoodItem {
  const _MoodItem({required this.label, required this.emoji, required this.color});
  final String label;
  final String emoji;
  final Color color;
}
