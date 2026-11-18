import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/soulsync_button.dart';

class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<_MemoryItem> _memories = [
    const _MemoryItem(
      title: 'Our Paris Getaway ☕',
      date: 'Oct 24, 2024',
      caption: 'The best croissants and walking along the Seine together.',
      tag: 'Trip',
      color: Color(0xFF6C3EBC),
    ),
    const _MemoryItem(
      title: 'Sunset at the Beach 🌅',
      date: 'Aug 15, 2024',
      caption: 'We watched the sun go down and talked for 4 hours straight.',
      tag: 'Date',
      color: Color(0xFFE8498A),
    ),
    const _MemoryItem(
      title: 'First Video Call Milestone 📱',
      date: 'May 02, 2024',
      caption: 'Remember when we stayed on call until 4am by accident?',
      tag: 'Milestone',
      color: Color(0xFF4A1E9E),
    ),
  ];

  final List<_LetterItem> _letters = [
    const _LetterItem(
      title: 'Open when you feel lonely 🥺',
      from: 'From Partner',
      date: 'Nov 10, 2024',
      preview: 'Remember that distance is only physical. Every second brings us closer...',
      isLocked: false,
    ),
    const _LetterItem(
      title: 'Open on our Anniversary 🎂',
      from: 'From Partner',
      date: 'Dec 12, 2024',
      preview: 'Locked until December 12, 2024!',
      isLocked: true,
    ),
    const _LetterItem(
      title: 'Open after a hard workday 💼',
      from: 'From You',
      date: 'Oct 05, 2024',
      preview: 'Take a deep breath. You did your absolute best today, I am so proud of you.',
      isLocked: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Memories 📸'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Memory Vault 🖼️'),
            Tab(text: 'Love Letters 💌'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Memory Vault
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Shared Timeline', style: AppTypography.headlineSmall),
                  SoulSyncButton(
                    label: '+ Add Memory',
                    width: 130,
                    height: 38,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Opening media picker to add photo memory...')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._memories.map((m) => _MemoryCard(item: m)),
            ],
          ),

          // Tab 2: Love Letters
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('"Open When" Letters', style: AppTypography.headlineSmall),
                  SoulSyncButton(
                    label: '+ Write Letter',
                    width: 130,
                    height: 38,
                    variant: SoulSyncButtonVariant.secondary,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Opening letter composer...')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._letters.map((l) => _LetterCard(letter: l)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemoryItem {
  const _MemoryItem({required this.title, required this.date, required this.caption, required this.tag, required this.color});
  final String title;
  final String date;
  final String caption;
  final String tag;
  final Color color;
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.item});
  final _MemoryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: item.color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [item.color.withOpacity(0.7), item.color],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Center(
              child: Icon(Icons.photo_library_rounded, size: 48, color: Colors.white.withOpacity(0.8)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.title, style: AppTypography.titleLarge),
                    Text(item.date, style: AppTypography.caption),
                  ],
                ),
                const SizedBox(height: 6),
                Text(item.caption, style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LetterItem {
  const _LetterItem({required this.title, required this.from, required this.date, required this.preview, required this.isLocked});
  final String title;
  final String from;
  final String date;
  final String preview;
  final bool isLocked;
}

class _LetterCard extends StatelessWidget {
  const _LetterCard({required this.letter});
  final _LetterItem letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: letter.isLocked ? AppColors.textHint.withOpacity(0.3) : AppColors.accent.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: letter.isLocked ? AppColors.surfaceVariant : AppColors.accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              letter.isLocked ? Icons.lock_outline_rounded : Icons.mark_email_read_rounded,
              color: letter.isLocked ? AppColors.textHint : AppColors.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(letter.title, style: AppTypography.titleLarge),
                const SizedBox(height: 2),
                Text('${letter.from} • ${letter.date}', style: AppTypography.caption),
                const SizedBox(height: 8),
                Text(
                  letter.preview,
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: letter.isLocked ? FontStyle.italic : FontStyle.normal,
                    color: letter.isLocked ? AppColors.textHint : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
