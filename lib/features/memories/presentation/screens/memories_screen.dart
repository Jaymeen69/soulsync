import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/soulsync_button.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _memories = [];
  List<Map<String, dynamic>> _letters = [];
  bool _isLoading = false;
  String _selectedTagFilter = 'All';
  String _memorySearchQuery = '';
  final Set<String> _favoriteMemoryIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    setState(() => _isLoading = true);

    try {
      final coupleId = user.coupleId ?? "c1";

      // 1. Fetch memories
      final memRes = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/memories?couple_id=$coupleId'),
      ).timeout(const Duration(seconds: 4));

      if (memRes.statusCode == 200) {
        final data = jsonDecode(memRes.body) as Map<String, dynamic>;
        _memories = (data['memories'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      }

      // 2. Fetch letters
      final letRes = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/letters?couple_id=$coupleId&viewer_id=${user.id}'),
      ).timeout(const Duration(seconds: 4));

      if (letRes.statusCode == 200) {
        final data = jsonDecode(letRes.body) as Map<String, dynamic>;
        _letters = (data['letters'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      }
    } catch (_) {
      // Graceful fallback to seeded items if offline
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddMemoryDialog() {
    final titleCtrl = TextEditingController();
    final captionCtrl = TextEditingController();
    String selectedTag = 'Date';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: const Text('Add Memory 📸', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  style: TextStyle(color: ctx.ssTextPrimary),
                  decoration: InputDecoration(
                    labelText: 'Memory Title',
                    hintText: 'e.g. Sunset Picnic at the Park 🌅',
                    filled: true,
                    fillColor: ctx.ssSurfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: captionCtrl,
                  maxLines: 3,
                  style: TextStyle(color: ctx.ssTextPrimary),
                  decoration: InputDecoration(
                    labelText: 'Story / Caption',
                    hintText: 'What made this moment unforgettable?',
                    filled: true,
                    fillColor: ctx.ssSurfaceVariant,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Category Tag:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['Date', 'Trip', 'Milestone', 'Cozy Day'].map((tag) {
                    final isSel = selectedTag == tag;
                    return ChoiceChip(
                      label: Text(tag),
                      selected: isSel,
                      selectedColor: AppColors.primary,
                      backgroundColor: ctx.ssSurfaceVariant,
                      labelStyle: TextStyle(color: isSel ? Colors.white : ctx.ssTextPrimary, fontSize: 12),
                      onSelected: (_) => setDlgState(() => selectedTag = tag),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(ctx);
                final user = ref.read(currentUserProvider);
                try {
                  await http.post(
                    Uri.parse('${AuthNotifier.apiBaseUrl}/api/memories'),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'couple_id': user?.coupleId ?? 'c1',
                      'user_id': user?.id ?? 'u1',
                      'title': title,
                      'caption': captionCtrl.text.trim(),
                      'tag': selectedTag,
                      'date': 'Today',
                    }),
                  );
                  _fetchData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✨ Memory saved to your couple vault!')),
                    );
                  }
                } catch (_) {}
              },
              child: const Text('Save Memory'),
            ),
          ],
        ),
      ),
    );
  }

  void _showWriteLetterDialog() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Write Love Letter 💌', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                style: TextStyle(color: ctx.ssTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Prompt / Occasion',
                  hintText: 'e.g. Open when you need reassurance 🥺',
                  filled: true,
                  fillColor: ctx.ssSurfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 5,
                style: TextStyle(color: ctx.ssTextPrimary),
                decoration: InputDecoration(
                  labelText: 'Letter Message (Sealed for Partner)',
                  hintText: 'Pour your heart out. Only your partner will ever see this.',
                  filled: true,
                  fillColor: ctx.ssSurfaceVariant,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final title = titleCtrl.text.trim();
              final content = contentCtrl.text.trim();
              if (title.isEmpty || content.isEmpty) return;
              Navigator.pop(ctx);
              final user = ref.read(currentUserProvider);
              try {
                await http.post(
                  Uri.parse('${AuthNotifier.apiBaseUrl}/api/letters'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'couple_id': user?.coupleId ?? 'c1',
                    'sender_id': user?.id ?? 'u1',
                    'sender_name': user?.displayName ?? 'You',
                    'title': title,
                    'content': content,
                    'unlock_condition': 'Open Anytime',
                  }),
                );
                _fetchData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('💌 Love letter sealed and delivered!')),
                  );
                }
              } catch (_) {}
            },
            child: const Text('Seal & Deliver'),
          ),
        ],
      ),
    );
  }

  void _showMemoryDetail(Map<String, dynamic> memory) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  color: AppColors.primary.withOpacity(0.12),
                  child: Image.network(
                    memory['image_url'] ?? 'https://images.unsplash.com/photo-1518199266791-5375a83190b7',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.favorite_rounded, size: 64, color: AppColors.accent),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            memory['tag'] ?? 'Memory',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        Text(
                          memory['date'] ?? 'Recently',
                          style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(memory['title'] ?? 'Our Memory', style: AppTypography.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      memory['caption'] ?? 'A special moment saved in your shared couple vault.',
                      style: AppTypography.bodyMedium.copyWith(color: ctx.ssTextSecondary),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLetterDetail(Map<String, dynamic> letter) {
    final isLocked = letter['is_locked'] == true;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(isLocked ? Icons.lock_clock_rounded : Icons.favorite_rounded, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(letter['title'] ?? 'Love Letter', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From: ${letter['sender_name'] ?? "Partner"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ctx.ssSurfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ctx.ssAccent.withValues(alpha: 0.25)),
                ),
                child: Text(
                  letter['content'] ?? 'No message body.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    fontStyle: isLocked ? FontStyle.italic : FontStyle.normal,
                    color: isLocked ? ctx.ssTextSecondary : ctx.ssTextPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ssBg,
      appBar: AppBar(
        title: const Text('Memories 📸'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.ssPrimary,
          unselectedLabelColor: context.ssTextSecondary,
          indicatorColor: context.ssPrimary,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Memory Vault 🖼️'),
            Tab(text: 'Love Letters 💌'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Memory Vault (Section 7 & 10 Fix)
                RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView(
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
                            onPressed: _showAddMemoryDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Storage indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.ssInputFill,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.ssBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.cloud_done_rounded, color: context.ssPrimary, size: 16),
                            const SizedBox(width: 8),
                            Text('Storage: 28.4 MB / 5.0 GB Cloud Vault 🔒', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.ssTextSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Search bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: context.ssSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.ssBorder, width: 1.2),
                        ),
                        child: TextField(
                          style: TextStyle(color: context.ssTextPrimary),
                          decoration: InputDecoration(
                            hintText: 'Search memories by title or keyword...',
                            hintStyle: TextStyle(fontSize: 13, color: context.ssTextHint),
                            prefixIcon: Icon(Icons.search, size: 20, color: context.ssTextSecondary),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onChanged: (v) => setState(() => _memorySearchQuery = v.trim().toLowerCase()),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Category filter chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['All', 'Date', 'Travel', 'Milestone', 'Trip'].map((tag) {
                            final isSel = _selectedTagFilter == tag;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(tag, style: TextStyle(fontSize: 12, color: isSel ? Colors.white : context.ssTextPrimary)),
                                selected: isSel,
                                selectedColor: AppColors.primary,
                                backgroundColor: context.ssSurfaceVariant,
                                onSelected: (_) => setState(() => _selectedTagFilter = tag),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_memories.isEmpty)
                        _buildDefaultMemoryCards()
                      else
                        ..._memories.map((m) => _MemoryItemCard(item: m, onTap: () => _showMemoryDetail(m))),
                    ],
                  ),
                ),

                // Tab 2: Love Letters (Section 11 Fix)
                RefreshIndicator(
                  onRefresh: _fetchData,
                  child: ListView(
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
                            onPressed: _showWriteLetterDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_letters.isEmpty)
                        _buildDefaultLetterCards()
                      else
                        ..._letters.map((l) => _LetterItemCard(letter: l, onTap: () => _showLetterDetail(l))),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDefaultMemoryCards() {
    final list = [
      {'title': 'Our Paris Getaway ☕', 'date': 'Oct 24, 2024', 'caption': 'The best croissants and walking along the Seine together.', 'tag': 'Trip'},
      {'title': 'Sunset at the Beach 🌅', 'date': 'Aug 15, 2024', 'caption': 'We watched the sun go down and talked for 4 hours straight.', 'tag': 'Date'},
      {'title': 'First Video Call Milestone 📱', 'date': 'May 02, 2024', 'caption': 'Remember when we stayed on call until 4am by accident?', 'tag': 'Milestone'},
    ];
    return Column(
      children: list.map((m) => _MemoryItemCard(item: m, onTap: () => _showMemoryDetail(m))).toList(),
    );
  }

  Widget _buildDefaultLetterCards() {
    final list = [
      {'title': 'Open when you feel lonely 🥺', 'sender_name': 'Partner', 'content': 'Remember that distance is only physical. Every second brings us closer... You are my whole universe!', 'is_locked': false},
      {'title': 'Open on our Anniversary 🎂', 'sender_name': 'Partner', 'content': '🔒 Locked until our special anniversary milestone!', 'is_locked': true},
      {'title': 'Open after a hard workday 💼', 'sender_name': 'You', 'content': 'Take a deep breath. You did your absolute best today, I am endlessly proud of you.', 'is_locked': false},
    ];
    return Column(
      children: list.map((l) => _LetterItemCard(letter: l, onTap: () => _showLetterDetail(l))).toList(),
    );
  }
}

class _MemoryItemCard extends StatelessWidget {
  const _MemoryItemCard({required this.item, required this.onTap});
  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.ssSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.ssBorder),
          boxShadow: [
            BoxShadow(color: AppColors.primary.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: context.ssPrimary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.photo_library_rounded, color: context.ssPrimary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['title'] ?? 'Memory', style: AppTypography.titleLarge),
                  const SizedBox(height: 2),
                  Text(item['caption'] ?? '', style: AppTypography.bodySmall.copyWith(color: context.ssTextSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text(item['date'] ?? '', style: TextStyle(fontSize: 11, color: context.ssTextHint)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.ssTextHint),
          ],
        ),
      ),
    );
  }
}

class _LetterItemCard extends StatelessWidget {
  const _LetterItemCard({required this.letter, required this.onTap});
  final Map<String, dynamic> letter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isLocked = letter['is_locked'] == true;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.ssSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.ssAccent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLocked ? context.ssSurfaceVariant : context.ssAccent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLocked ? Icons.lock_clock_rounded : Icons.mark_email_read_rounded,
                color: isLocked ? context.ssTextHint : context.ssAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(letter['title'] ?? 'Love Letter', style: AppTypography.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    isLocked ? 'Sealed & Locked' : (letter['content'] ?? ''),
                    style: AppTypography.bodySmall.copyWith(
                      color: isLocked ? AppColors.warning : context.ssTextSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.ssTextHint),
          ],
        ),
      ),
    );
  }
}
