import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../domain/models/chat_message.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isSearching = false;
  String _searchQuery = '';
  ChatMessage? _replyingTo;
  bool _partnerTyping = false;
  Timer? _pollingTimer;

  static const List<String> _quickEmojis = ['❤️', '🥰', '😘', '🔥', '✨', '🌹', '🫂', '🥺'];

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchMessages(isBackground: true);
    });
  }

  Future<void> _fetchMessages({bool isBackground = false}) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final coupleId = user.coupleId ?? 'c_u5_u4';

    if (!isBackground) setState(() => _isLoading = true);
    try {
      final queryParam = _searchQuery.isNotEmpty ? '&query=${Uri.encodeComponent(_searchQuery)}' : '';
      final res = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/chat/messages?couple_id=$coupleId$queryParam'),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawList = data['messages'] as List<dynamic>? ?? [];
        final parsed = rawList.map((m) => ChatMessage.fromJson(m as Map<String, dynamic>)).toList();
        if (mounted) {
          setState(() {
            _messages = parsed;
          });
          if (!isBackground) {
            _scrollToBottom();
          }
        }
      }

      // Check partner status
      final statusRes = await http.get(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/chat/status?couple_id=$coupleId&user_id=${user.id}'),
      ).timeout(const Duration(seconds: 3));
      if (statusRes.statusCode == 200) {
        final stData = jsonDecode(statusRes.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _partnerTyping = stData['partner_typing'] == true;
          });
        }
      }
    } catch (_) {
    } finally {
      if (!isBackground && mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({String? mediaType, String? mediaUrl, String? voiceDuration}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && mediaUrl == null && voiceDuration == null) return;

    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final coupleId = user.coupleId ?? 'c_u5_u4';

    setState(() => _isSending = true);
    _msgCtrl.clear();
    HapticFeedback.lightImpact();

    try {
      final body = {
        'couple_id': coupleId,
        'sender_id': user.id,
        'sender_name': user.displayName,
        'content': text.isNotEmpty ? text : (mediaType == 'voice' ? 'Voice Whisper 🎙️' : 'Photo 📸'),
        'media_type': mediaType ?? 'text',
        'media_url': mediaUrl,
        'voice_duration': voiceDuration,
        'reply_to_id': _replyingTo?.id,
        'reply_preview': _replyingTo != null ? '${_replyingTo!.senderName}: ${_replyingTo!.content}' : null,
      };

      final res = await http.post(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/chat/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 201) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final newMsg = ChatMessage.fromJson(data['message'] as Map<String, dynamic>);
        if (mounted) {
          setState(() {
            _messages.add(newMsg);
            _replyingTo = null;
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleReaction(ChatMessage msg, String emoji) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    HapticFeedback.selectionClick();

    try {
      final res = await http.post(
        Uri.parse('${AuthNotifier.apiBaseUrl}/api/chat/reactions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message_id': msg.id,
          'user_id': user.id,
          'emoji': emoji,
        }),
      );
      if (res.statusCode == 200) {
        _fetchMessages(isBackground: true);
      }
    } catch (_) {}
  }

  void _showMediaAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Share with Partner 💖', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _AttachmentAction(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  color: AppColors.accent,
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendMessage(
                      mediaType: 'image',
                      mediaUrl: 'https://images.unsplash.com/photo-1518199266791-5375a83190b7?w=600',
                    );
                  },
                ),
                _AttachmentAction(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendMessage(
                      mediaType: 'image',
                      mediaUrl: 'https://images.unsplash.com/photo-1516589178581-6cd7833ae3b2?w=600',
                    );
                  },
                ),
                _AttachmentAction(
                  icon: Icons.mic_rounded,
                  label: 'Voice Note',
                  color: const Color(0xFFE94057),
                  onTap: () {
                    Navigator.pop(ctx);
                    _sendMessage(
                      mediaType: 'voice',
                      voiceDuration: '0:18',
                    );
                  },
                ),
                _AttachmentAction(
                  icon: Icons.card_giftcard_rounded,
                  label: 'Send Gift',
                  color: const Color(0xFFFF9800),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showSendGiftDialog();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showSendGiftDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Text('Send Virtual Gift 🎁', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pick a romantic gift to send in chat:', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _GiftChip(emoji: '🌹', name: 'Rose', onTap: () => _submitGift(ctx, '🌹', 'Digital Red Rose')),
                _GiftChip(emoji: '🧸', name: 'Teddy', onTap: () => _submitGift(ctx, '🧸', 'Cuddle Teddy')),
                _GiftChip(emoji: '💛', name: 'Locket', onTap: () => _submitGift(ctx, '💛', 'Heart Locket')),
                _GiftChip(emoji: '🎁', name: 'Surprise', onTap: () => _submitGift(ctx, '🎁', 'Starlight Box')),
                _GiftChip(emoji: '💍', name: 'Diamond', onTap: () => _submitGift(ctx, '💍', 'Eternal Ring')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submitGift(BuildContext ctx, String emoji, String giftName) async {
    Navigator.pop(ctx);
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final coupleId = user.coupleId ?? 'c_u5_u4';

    await http.post(
      Uri.parse('${AuthNotifier.apiBaseUrl}/api/gifts/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'couple_id': coupleId,
        'sender_id': user.id,
        'sender_name': user.displayName,
        'gift_name': giftName,
        'emoji': emoji,
        'message': 'Sent you a $giftName with all my love $emoji',
      }),
    );

    _sendMessage(
      mediaType: 'text',
      mediaUrl: null,
    );
    _fetchMessages(isBackground: true);
  }

  void _showReactionsPicker(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: _quickEmojis.map((emoji) {
            return InkWell(
              onTap: () {
                Navigator.pop(ctx);
                _toggleReaction(msg, emoji);
              },
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final partnerName = user?.partnerName ?? 'Soulmate';

    return Scaffold(
      backgroundColor: const Color(0xFFFBF8FD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search chat messages...',
                  border: InputBorder.none,
                  hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchCtrl.clear();
                      });
                      _fetchMessages();
                    },
                  ),
                ),
                onSubmitted: (v) {
                  setState(() => _searchQuery = v.trim());
                  _fetchMessages();
                },
              )
            : Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primary.withOpacity(0.15),
                        child: Text(
                          partnerName.isNotEmpty ? partnerName[0].toUpperCase() : 'P',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C853),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(partnerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text(
                          _partnerTyping ? 'typing... ✨' : 'Online & in love 🔒',
                          style: TextStyle(
                            fontSize: 11,
                            color: _partnerTyping ? AppColors.accent : const Color(0xFF00C853),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search_rounded, color: AppColors.textPrimary),
              onPressed: () => setState(() => _isSearching = true),
            ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textPrimary),
            onPressed: () => _showChatOptions(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('💌', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('Your Private Couple Space', style: AppTypography.titleMedium),
                            const SizedBox(height: 6),
                            const Text(
                              'Every message, photo, and voice whisper is completely private between you two.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, idx) {
                          final msg = _messages[idx];
                          final isMe = msg.senderId == (user?.id ?? 'u5');
                          return _MessageBubble(
                            message: msg,
                            isMe: isMe,
                            onLongPress: () => _showReactionsPicker(msg),
                            onReply: () => setState(() => _replyingTo = msg),
                          );
                        },
                      ),
          ),

          // Replying indicator banner
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.primary.withOpacity(0.08),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyingTo!.senderName}: ${_replyingTo!.content}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                    onPressed: () => setState(() => _replyingTo = null),
                  ),
                ],
              ),
            ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.primary.withOpacity(0.08))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary, size: 26),
                    onPressed: _showMediaAttachmentSheet,
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAF7FF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFDACDF2), width: 1.2),
                      ),
                      child: TextField(
                        controller: _msgCtrl,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Whisper something sweet...',
                          hintStyle: TextStyle(color: Color(0xFF7E7399), fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE94057), Color(0xFF8A2387)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      onPressed: _isSending ? null : () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChatOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.volume_off_outlined, color: AppColors.textPrimary),
            title: const Text('Mute Chat Notifications'),
            onTap: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notifications muted for this couple space.')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.report_outlined, color: AppColors.error),
            title: const Text('Report Inappropriate Content', style: TextStyle(color: AppColors.error)),
            onTap: () {
              Navigator.pop(ctx);
              _showReportDialog(context);
            },
          ),
        ],
      ),
    );
  }

  void _showReportDialog(BuildContext context) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Report Content 🛡️', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please specify the reason for your report. Reports are reviewed strictly according to our relationship safety and privacy policies.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Inappropriate language or spam',
                filled: true,
                fillColor: const Color(0xFFFAF7FF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDACDF2))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);
              final user = ref.read(currentUserProvider);
              await http.post(
                Uri.parse('${AuthNotifier.apiBaseUrl}/api/safety/report'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'reporter_id': user?.id,
                  'reason': reason,
                  'details': 'Submitted from Couple Chat menu',
                }),
              );
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🛡️ Report submitted securely for admin safety review.')));
            },
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback onLongPress;
  final VoidCallback onReply;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.onLongPress,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      onDoubleTap: onReply,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Reply quote if present
            if (message.replyPreview != null)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '↩️ ${message.replyPreview!}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                ),
              ),

            // Message Bubble
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [Color(0xFFE94057), Color(0xFF8A2387)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                border: isMe ? null : Border.all(color: const Color(0xFFDACDF2), width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.mediaType == 'image' && message.mediaUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        message.mediaUrl!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      ),
                    )
                  else if (message.mediaType == 'voice')
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_filled_rounded, color: isMe ? Colors.white : AppColors.primary, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          'Voice Whisper (${message.voiceDuration ?? "0:15"})',
                          style: TextStyle(
                            color: isMe ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : AppColors.textPrimary,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: isMe ? Colors.white.withOpacity(0.7) : AppColors.textHint,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                          size: 13,
                          color: message.isRead ? const Color(0xFFFFD54F) : Colors.white70,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Emoji Reactions Display
            if (message.reactions.isNotEmpty)
              Transform.translate(
                offset: const Offset(0, -6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDACDF2), width: 1),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: message.reactions.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text('${e.key} ${e.value.length > 1 ? e.value.length : ""}', style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _GiftChip extends StatelessWidget {
  final String emoji;
  final String name;
  final VoidCallback onTap;

  const _GiftChip({required this.emoji, required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDACDF2)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
