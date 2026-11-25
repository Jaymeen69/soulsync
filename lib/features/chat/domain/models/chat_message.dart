class ChatMessage {
  final String id;
  final String coupleId;
  final String senderId;
  final String senderName;
  final String content;
  final String mediaType; // 'text', 'image', 'video', 'voice'
  final String? mediaUrl;
  final String? voiceDuration;
  final String? replyToId;
  final String? replyPreview;
  final Map<String, List<String>> reactions;
  final bool isRead;
  final bool delivered;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.coupleId,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.mediaType = 'text',
    this.mediaUrl,
    this.voiceDuration,
    this.replyToId,
    this.replyPreview,
    this.reactions = const {},
    this.isRead = false,
    this.delivered = true,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    Map<String, List<String>> parsedReactions = {};
    if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((k, v) {
        if (v is List) {
          parsedReactions[k.toString()] = v.map((e) => e.toString()).toList();
        }
      });
    }

    return ChatMessage(
      id: json['id']?.toString() ?? '',
      coupleId: json['couple_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? 'Partner',
      content: json['content']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? 'text',
      mediaUrl: json['media_url']?.toString(),
      voiceDuration: json['voice_duration']?.toString(),
      replyToId: json['reply_to_id']?.toString(),
      replyPreview: json['reply_preview']?.toString(),
      reactions: parsedReactions,
      isRead: json['is_read'] == true,
      delivered: json['delivered'] != false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'couple_id': coupleId,
        'sender_id': senderId,
        'sender_name': senderName,
        'content': content,
        'media_type': mediaType,
        'media_url': mediaUrl,
        'voice_duration': voiceDuration,
        'reply_to_id': replyToId,
        'reply_preview': replyPreview,
        'reactions': reactions,
        'is_read': isRead,
        'delivered': delivered,
        'created_at': createdAt.toIso8601String(),
      };
}
