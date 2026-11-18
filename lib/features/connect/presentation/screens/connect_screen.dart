import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/soulsync_button.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  int _selectedPulseIndex = 0;
  int _selectedMoodIndex = 1;
  bool _isSendingPulse = false;
  String? _pulseFeedback;

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

  void _sendPulse() async {
    final pulse = _pulseTypes[_selectedPulseIndex];
    HapticFeedback.heavyImpact();
    setState(() {
      _isSendingPulse = true;
      _pulseFeedback = 'Sent ${pulse.name} ${pulse.emoji} to Partner!';
      _pulseHistory.insert(0, 'You sent "${pulse.name} ${pulse.emoji}" • Just now');
    });

    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        _isSendingPulse = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✨ ${pulse.name} pulse delivered to your partner!'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPulse = _pulseTypes[_selectedPulseIndex];

    return Scaffold(
      backgroundColor: AppColors.background,
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
                color: AppColors.surface,
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
                    'Lightweight signal to say "I\'m thinking of you"',
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
                          colors: [currentPulse.color, currentPulse.color.withOpacity(0.7)],
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
                              color: isSel ? p.color : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Text(p.emoji, style: const TextStyle(fontSize: 16)),
                                const SizedBox(width: 6),
                                Text(
                                  p.name,
                                  style: TextStyle(
                                    color: isSel ? Colors.white : AppColors.textPrimary,
                                    fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
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
                    label: 'Send ${currentPulse.name} ${currentPulse.emoji}',
                    onPressed: _sendPulse,
                    isLoading: _isSendingPulse,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Emotional Sync / Mood Section
            Text('Emotional Sync (Mood)', style: AppTypography.headlineSmall),
            const SizedBox(height: 4),
            Text('Voluntarily share how you feel right now', style: AppTypography.bodySmall),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Updated mood to "${m.label} ${m.emoji}" for partner!')),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSel ? m.color.withOpacity(0.18) : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSel ? m.color : AppColors.primary.withOpacity(0.08),
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
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                            color: isSel ? m.color : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),

            // Pulse History Section
            Text('Recent Activity', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.1)),
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
            const SizedBox(height: 20),
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
