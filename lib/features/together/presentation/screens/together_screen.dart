import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/soulsync_button.dart';

class TogetherScreen extends StatefulWidget {
  const TogetherScreen({super.key});

  @override
  State<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends State<TogetherScreen> {
  final TextEditingController _answerCtrl = TextEditingController();
  bool _hasAnswered = false;
  String _userAnswer = '';

  // Focus Timer
  Timer? _timer;
  int _secondsLeft = 25 * 60; // 25 min pomodoro
  bool _isTimerRunning = false;
  String _currentActivity = 'Study Together 📚';

  void _toggleTimer() {
    if (_isTimerRunning) {
      _timer?.cancel();
      setState(() => _isTimerRunning = false);
    } else {
      setState(() => _isTimerRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_secondsLeft > 0) {
          setState(() => _secondsLeft--);
        } else {
          _timer?.cancel();
          setState(() => _isTimerRunning = false);
        }
      });
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Together 🎮'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Daily Couple Question Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C3EBC), Color(0xFF9C6FE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'DAILY QUESTION',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.stars_rounded, color: Colors.amber, size: 20),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'What is your favorite memory of us traveling together?',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_hasAnswered) ...[
                    TextField(
                      controller: _answerCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.15),
                        hintText: 'Type your answer here...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SoulSyncButton(
                      label: 'Submit & Unlock Partner Answer 🔓',
                      variant: SoulSyncButtonVariant.secondary,
                      onPressed: () {
                        if (_answerCtrl.text.trim().isNotEmpty) {
                          setState(() {
                            _hasAnswered = true;
                            _userAnswer = _answerCtrl.text;
                          });
                        }
                      },
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your Answer:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(_userAnswer, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          const Divider(color: Colors.white24, height: 20),
                          const Text('Partner\'s Answer:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const Text(
                            '"Walking in the rain in Paris looking for that tiny bakery!"',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Together Mode Live Session Timer
            Text('Together Mode (Synchronized)', style: AppTypography.headlineSmall),
            const SizedBox(height: 4),
            Text('Spend intentional focus time together', style: AppTypography.bodySmall),
            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.primary.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_currentActivity, style: AppTypography.titleLarge),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isTimerRunning ? AppColors.success.withOpacity(0.15) : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _isTimerRunning ? 'Partner Connected 🟢' : 'Idle',
                          style: TextStyle(
                            color: _isTimerRunning ? AppColors.success : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _formatTime(_secondsLeft),
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 48,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: SoulSyncButton(
                          label: _isTimerRunning ? 'Pause Session' : 'Start Together ⏱️',
                          variant: _isTimerRunning ? SoulSyncButtonVariant.outlined : SoulSyncButtonVariant.primary,
                          onPressed: _toggleTimer,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Couple Games Carousel
            Text('Couple Games & Quizzes', style: AppTypography.headlineSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _GameCard(
                    title: 'Would You Rather',
                    tag: 'Fun & Silly',
                    emoji: '🎭',
                    color: AppColors.accent,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starting "Would You Rather" game session...')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GameCard(
                    title: 'How Well Do You Know Me?',
                    tag: '10 Questions',
                    emoji: '🎯',
                    color: AppColors.primary,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Starting "How Well Do You Know Me" quiz...')),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.title,
    required this.tag,
    required this.emoji,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String tag;
  final String emoji;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 32)),
            const SizedBox(height: 12),
            Text(title, style: AppTypography.titleLarge, maxLines: 2),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
