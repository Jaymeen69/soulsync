import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/route_names.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Map<String, dynamic>> _memories = [];
  bool _isLoadingMemories = false;
  Map<String, dynamic>? _coupleStatus;

  @override
  void initState() {
    super.initState();
    _fetchHomeData();
  }

  Future<void> _fetchHomeData() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _isLoadingMemories = true);
    try {
      // 1. Fetch couple status
      final coupleRes = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/couple/status?user_id=${user.id}&email=${user.email}'),
      ).timeout(const Duration(seconds: 4));

      if (coupleRes.statusCode == 200) {
        final data = jsonDecode(coupleRes.body) as Map<String, dynamic>;
        if (mounted) setState(() => _coupleStatus = data);
      }

      // 2. Fetch memories
      final memRes = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/memories?couple_id=${user.coupleId ?? ""}'),
      ).timeout(const Duration(seconds: 4));

      if (memRes.statusCode == 200) {
        final data = jsonDecode(memRes.body) as Map<String, dynamic>;
        final list = (data['memories'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
        if (mounted) setState(() => _memories = list);
      }
    } catch (_) {
      // Graceful local defaults
    } finally {
      if (mounted) setState(() => _isLoadingMemories = false);
    }
  }

  void _showConnectPartnerDialog(BuildContext context, SoulSyncUser user) {
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Quick Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your partner\'s 8-character invitation code to link your accounts:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'e.g. SOUL-1234',
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
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
              final code = codeCtrl.text.trim();
              if (code.isEmpty) return;
              Navigator.pop(ctx);
              try {
                final res = await ref.read(authRepositoryProvider).connectPartner(code);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('✨ ${res["message"] ?? "Connection request sent!"}')),
                  );
                  _fetchHomeData();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('⚠️ ${e.toString().replaceFirst("Exception: ", "")}')),
                  );
                }
              }
            },
            child: const Text('Connect'),
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
              // Memory Image or Banner
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: AppColors.primary.withOpacity(0.1),
                  child: Image.network(
                    memory['image_url'] ?? 'https://images.unsplash.com/photo-1518199266791-5375a83190b7',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.favorite_rounded, size: 60, color: AppColors.accent),
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
                            memory['tag'] ?? 'Moment',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                        Text(
                          memory['date'] ?? 'Recent',
                          style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      memory['title'] ?? 'Our Memory',
                      style: AppTypography.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      memory['caption'] ?? 'A special moment saved in your shared couple vault.',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final userName = user?.displayName ?? 'You';
    final partnerName = user?.partnerName ?? 'Partner';
    final userInviteCode = user?.inviteCode ?? 'SOUL-8492';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchHomeData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Bar: Partner Presence & Time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Good evening, $userName 💞', style: AppTypography.headlineMedium),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$partnerName is active now',
                              style: AppTypography.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.primaryLight.withOpacity(0.2),
                      child: const Icon(Icons.notifications_none_rounded, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Hero Relationship Duration Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _AvatarBubble(name: userName, initial: userName.isNotEmpty ? userName[0].toUpperCase() : 'Y'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                          _AvatarBubble(name: partnerName, initial: partnerName.isNotEmpty ? partnerName[0].toUpperCase() : 'P'),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '342 Days Together',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Anniversary: December 12, 2023',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Quick Connection Card (Section 5 Fix)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withOpacity(0.12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.qr_code_2_rounded, color: AppColors.primary, size: 22),
                              const SizedBox(width: 8),
                              Text('Quick Connection', style: AppTypography.titleLarge),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              if (user != null) _showConnectPartnerDialog(context, user);
                            },
                            child: const Text('Enter Code +'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Share your code with your partner to pair devices:',
                        style: AppTypography.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              userInviteCode,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: AppColors.primary,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: userInviteCode));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Copied code $userInviteCode to clipboard!')),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Copy Code',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Quick Action Shortcuts
                Text('Instant Signals', style: AppTypography.headlineSmall),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        title: 'Love Pulse',
                        subtitle: 'Tap to buzz partner',
                        icon: Icons.favorite_rounded,
                        color: AppColors.pulseLove,
                        onTap: () => context.go(RouteNames.connect),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickActionCard(
                        title: 'Mood Sync',
                        subtitle: 'Share how you feel',
                        icon: Icons.sentiment_very_satisfied_rounded,
                        color: AppColors.pulseKiss,
                        onTap: () => context.go(RouteNames.connect),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Recent Memories Section (Section 7 Fix: Clickable & Fully Functional)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Memories', style: AppTypography.headlineSmall),
                    TextButton(
                      onPressed: () => context.go(RouteNames.memories),
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoadingMemories)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                else if (_memories.isEmpty)
                  _buildDefaultMemories()
                else
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _memories.length,
                      itemBuilder: (context, index) {
                        final m = _memories[index];
                        return _MemoryThumbnail(
                          title: m['title'] ?? 'Our Memory',
                          date: m['date'] ?? 'Recently',
                          color: index % 2 == 0 ? const Color(0xFF6C3EBC) : const Color(0xFFE8498A),
                          onTap: () => _showMemoryDetail(m),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultMemories() {
    final defaults = [
      {'title': 'Our Paris Trip ☕', 'date': '2 weeks ago', 'caption': 'The best croissants and walking along the Seine.', 'tag': 'Trip'},
      {'title': 'Sunset Beach Walk 🌅', 'date': 'Last month', 'caption': 'Watched the sun dip below the horizon holding hands.', 'tag': 'Date'},
      {'title': 'First Date Coffee 🥐', 'date': 'Dec 12, 2023', 'caption': 'Where our wonderful adventure first began.', 'tag': 'Milestone'},
    ];
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: defaults.length,
        itemBuilder: (context, index) {
          final m = defaults[index];
          return _MemoryThumbnail(
            title: m['title']!,
            date: m['date']!,
            color: index % 2 == 0 ? const Color(0xFF6C3EBC) : const Color(0xFFE8498A),
            onTap: () => _showMemoryDetail(m),
          );
        },
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({required this.name, required this.initial});
  final String name;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white,
          child: Text(
            initial,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
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
          border: Border.all(color: color.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(title, style: AppTypography.titleLarge),
            const SizedBox(height: 2),
            Text(subtitle, style: AppTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MemoryThumbnail extends StatelessWidget {
  const _MemoryThumbnail({
    required this.title,
    required this.date,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String date;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.photo_library_rounded, color: color, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  date,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
