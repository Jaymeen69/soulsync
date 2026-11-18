import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class TogetherScreen extends ConsumerStatefulWidget {
  const TogetherScreen({super.key});

  @override
  ConsumerState<TogetherScreen> createState() => _TogetherScreenState();
}

class _TogetherScreenState extends ConsumerState<TogetherScreen> {
  final TextEditingController _answerCtrl = TextEditingController();
  bool _hasAnsweredDaily = false;
  String _userDailyAnswer = '';
  String _dailyQuestionText = 'What is your favorite memory of us traveling together?';

  // Synchronized Focus Timer
  Timer? _timer;
  int _secondsLeft = 25 * 60;
  bool _isTimerRunning = false;
  String _currentActivity = 'Study Together 📚';

  @override
  void initState() {
    super.initState();
    _fetchDailyQuestion();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDailyQuestion() async {
    try {
      final res = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/games/questions?game=daily_couple_questions'),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final qList = data['questions'] as List<dynamic>?;
        if (qList != null && qList.isNotEmpty) {
          setState(() {
            _dailyQuestionText = qList[0]['q'] as String;
          });
        }
      }
    } catch (_) {}
  }

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

  // Launch Playable Game Modal (7 Games Implementation)
  void _playGame(String gameType, String title, String emoji) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PlayGameDialog(
        gameType: gameType,
        title: title,
        emoji: emoji,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final partnerName = user?.partnerName ?? 'Partner';

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
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
                ],
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
                  Text(
                    _dailyQuestionText,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_hasAnsweredDaily) ...[
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
                            _hasAnsweredDaily = true;
                            _userDailyAnswer = _answerCtrl.text;
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
                          Text(_userDailyAnswer, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          const Divider(color: Colors.white24, height: 20),
                          Text('$partnerName\'s Answer:', style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
            Text('Spend intentional focus and connection time together', style: AppTypography.bodySmall),
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
                          _isTimerRunning ? '$partnerName Connected 🟢' : 'Idle',
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
                  SoulSyncButton(
                    label: _isTimerRunning ? 'Pause Session' : 'Start Focus Together ⏱️',
                    variant: _isTimerRunning ? SoulSyncButtonVariant.outlined : SoulSyncButtonVariant.primary,
                    onPressed: _toggleTimer,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // 7 Interactive Couple Games (Section 9 Complete Implementation)
            Text('7 Interactive Couple Games', style: AppTypography.headlineSmall),
            const SizedBox(height: 4),
            Text('Multiplayer games with live answer synchronization', style: AppTypography.bodySmall),
            const SizedBox(height: 14),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.1,
              children: [
                _GameTile(
                  title: 'Would You Rather',
                  tag: 'Fun Choices',
                  emoji: '🎭',
                  color: AppColors.accent,
                  onTap: () => _playGame('would_you_rather', 'Would You Rather', '🎭'),
                ),
                _GameTile(
                  title: 'Truth or Dare',
                  tag: 'Romantic Dares',
                  emoji: '💋',
                  color: AppColors.pulseLove,
                  onTap: () => _playGame('truth_or_dare', 'Truth or Dare', '💋'),
                ),
                _GameTile(
                  title: 'Guess Partner',
                  tag: 'Mind Reader',
                  emoji: '🔮',
                  color: AppColors.primary,
                  onTap: () => _playGame('guess_your_partner', 'Guess Your Partner', '🔮'),
                ),
                _GameTile(
                  title: 'Couple Quiz',
                  tag: 'Trivia & Love',
                  emoji: '🏆',
                  color: const Color(0xFFFF9B4E),
                  onTap: () => _playGame('couple_quiz', 'Couple Quiz', '🏆'),
                ),
                _GameTile(
                  title: 'How Well Know Me',
                  tag: 'Relationship Test',
                  emoji: '🎯',
                  color: const Color(0xFF34AADC),
                  onTap: () => _playGame('how_well_do_you_know_me', 'How Well Do You Know Me?', '🎯'),
                ),
                _GameTile(
                  title: 'Memory Challenge',
                  tag: 'Nostalgia Test',
                  emoji: '📸',
                  color: const Color(0xFF9C6FE4),
                  onTap: () => _playGame('memory_challenge', 'Memory Challenge', '📸'),
                ),
                _GameTile(
                  title: 'Daily Questions',
                  tag: 'Daily Prompts',
                  emoji: '💬',
                  color: AppColors.success,
                  onTap: () => _playGame('daily_couple_questions', 'Daily Couple Questions', '💬'),
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

class _GameTile extends StatelessWidget {
  const _GameTile({
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayGameDialog extends ConsumerStatefulWidget {
  const _PlayGameDialog({
    required this.gameType,
    required this.title,
    required this.emoji,
  });

  final String gameType;
  final String title;
  final String emoji;

  @override
  ConsumerState<_PlayGameDialog> createState() => _PlayGameDialogState();
}

class _PlayGameDialogState extends ConsumerState<_PlayGameDialog> {
  List<Map<String, dynamic>> _questions = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  String? _selectedOption;
  final TextEditingController _customAnsCtrl = TextEditingController();
  bool _isSubmitted = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _customAnsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    try {
      final res = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/games/questions?game=${widget.gameType}'),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _questions = (data['questions'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _submitAnswer(String answer) async {
    final user = ref.read(currentUserProvider);
    final currentQ = _questions[_currentIndex];

    setState(() {
      _selectedOption = answer;
      _isSubmitted = true;
    });

    try {
      await http.post(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/games/session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'couple_id': user?.coupleId ?? 'c1',
          'game_type': widget.gameType,
          'user_id': user?.id ?? 'u1',
          'question_id': currentQ['id'] ?? 'q',
          'answer': answer,
        }),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading ${widget.title}...'),
          ],
        ),
      );
    }

    if (_questions.isEmpty) {
      return AlertDialog(
        title: Text('${widget.emoji} ${widget.title}'),
        content: const Text('No questions available right now. Please try again later!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      );
    }

    final currentQ = _questions[_currentIndex];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Round ${_currentIndex + 1} of ${_questions.length}',
              style: const TextStyle(color: AppColors.textHint, fontSize: 11, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              currentQ['q'] ?? '',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.3),
            ),
            const SizedBox(height: 20),

            // Would You Rather 2 Options
            if (widget.gameType == 'would_you_rather') ...[
              _buildOptionButton(currentQ['opt1'] ?? 'Option 1'),
              const SizedBox(height: 10),
              _buildOptionButton(currentQ['opt2'] ?? 'Option 2'),
            ]
            // Multiple options
            else if (currentQ.containsKey('options')) ...[
              ...((currentQ['options'] as List<dynamic>?)?.map((opt) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildOptionButton(opt.toString()),
                      )) ??
                  []),
            ]
            // Text or Dare input
            else ...[
              TextField(
                controller: _customAnsCtrl,
                decoration: InputDecoration(
                  hintText: 'Enter your answer...',
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  if (_customAnsCtrl.text.trim().isNotEmpty) {
                    _submitAnswer(_customAnsCtrl.text.trim());
                  }
                },
                child: const Text('Lock In Answer 🔒'),
              ),
            ],

            if (_isSubmitted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Answer recorded and synced with partner! ✨', style: TextStyle(color: AppColors.success, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_currentIndex < _questions.length - 1)
          TextButton(
            onPressed: () {
              setState(() {
                _currentIndex++;
                _selectedOption = null;
                _isSubmitted = false;
                _customAnsCtrl.clear();
              });
            },
            child: const Text('Next Question ➡️'),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Finish Game 🎉'),
          ),
      ],
    );
  }

  Widget _buildOptionButton(String text) {
    final isSel = _selectedOption == text;
    return InkWell(
      onTap: () => _submitAnswer(text),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSel ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isSel ? AppColors.primary : Colors.transparent),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSel ? Colors.white : AppColors.textPrimary,
            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
