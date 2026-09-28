// ============================================================
// A live GROUP chat screen. Everyone who opens this
// screen sees the same message stream, in real time.
// ============================================================

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/chat_service.dart';

const _kBrandYellow = Color(0xFFFFDE59);

String _formatTimestamp(DateTime? timestamp) {
  if (timestamp == null) return 'Sending...';

  final hour24 = timestamp.hour;
  final minute = timestamp.minute.toString().padLeft(2, '0');
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:$minute $period';
}

class GroupChatScreen extends StatefulWidget {
  final String tourId; // which tour's chat this is — now required

  const GroupChatScreen({super.key, required this.tourId});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late final ChatService _chatService = ChatService(tourId: widget.tourId);
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isGuide = false;
  bool _sendAsAnnouncement = false;
  bool _filterAnnouncementsOnly = false;
  bool _announcementBannerExpanded = false;

  @override
  void initState() {
    super.initState();
    _chatService.isCurrentUserGuide().then((isGuide) {
      if (!mounted) return;
      setState(() => _isGuide = isGuide);
    });
  }

  Future<void> _showHelpSheet() async {
    final result = await showModalBottomSheet<({HelpSeverity severity, String text})>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _HelpSheet(),
    );

    if (result == null) return; // sheet dismissed without sending

    try {
      await _chatService.sendHelpRequest(result.text, result.severity);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;

    _textController.clear();

    try {
      if (_sendAsAnnouncement) {
        await _chatService.sendAnnouncement(text);
      } else {
        await _chatService.sendMessage(text);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e')),
      );
      return;
    }

    // Give the list a moment to rebuild with the new message before
    // scrolling to it.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Chat')),
      body: Column(
        children: [
          _AnnouncementBanner(
            stream: _chatService.latestAnnouncementStream(),
            expanded: _announcementBannerExpanded,
            onToggle: () => setState(
              () => _announcementBannerExpanded = !_announcementBannerExpanded,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.messagesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allMessages = snapshot.data!;
                final messages = _filterAnnouncementsOnly
                    ? allMessages.where((m) => m.isAnnouncement).toList()
                    : allMessages;

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      _filterAnnouncementsOnly
                          ? 'No announcements yet.'
                          : 'No messages yet — say hi!',
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == currentUserId;

                    final avatar = _Avatar(
                      photoUrl: message.senderPhotoUrl,
                      name: message.senderName,
                    );

                    final bubble = Container(
                      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                      ),
                      decoration: message.isAnnouncement
                          ? BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade300, width: 1.5),
                            )
                          : message.isHelp
                              ? BoxDecoration(
                                  color: _severityColor(message.severity).shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _severityColor(message.severity).shade300,
                                    width: 1.5,
                                  ),
                                )
                              : BoxDecoration(
                                  color: isMe ? Colors.blue.shade400 : Colors.grey.shade300,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.isAnnouncement)
                            Row(
                              children: [
                                Text(
                                  '${message.senderName} (Guide)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ANNOUNCEMENT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            )
                          else if (message.isHelp)
                            Row(
                              children: [
                                Text(
                                  message.senderName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _severityLabel(message.severity).toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _severityColor(message.severity).shade700,
                                  ),
                                ),
                              ],
                            )
                          else if (!isMe)
                            Text(
                              message.senderName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          Text(
                            message.isHelp && message.text.isEmpty
                                ? _severityDescription(message.severity)
                                : message.text,
                            style: TextStyle(
                              color: (message.isAnnouncement || message.isHelp)
                                  ? Colors.black87
                                  : (isMe ? Colors.white : Colors.black87),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatTimestamp(message.timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: (message.isAnnouncement || message.isHelp)
                                  ? Colors.grey.shade600
                                  : (isMe ? Colors.white70 : Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment:
                            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: isMe
                            ? [Flexible(child: bubble), avatar]
                            : [avatar, Flexible(child: bubble)],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // Filter Announcements is available to everyone.
                  // Send Announcement stays guide only, checked once in
                  // initState against the 'guides' collection.
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GuidePillButton(
                          label: 'Filter Announcements',
                          dotColor: Colors.green,
                          selected: _filterAnnouncementsOnly,
                          onTap: () => setState(
                            () => _filterAnnouncementsOnly = !_filterAnnouncementsOnly,
                          ),
                        ),
                        if (_isGuide) const SizedBox(width: 10),
                        if (_isGuide)
                          _GuidePillButton(
                            label: 'Send Announcement',
                            dotColor: Colors.red,
                            selected: _sendAsAnnouncement,
                            onTap: () => setState(
                              () => _sendAsAnnouncement = !_sendAsAnnouncement,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (!_isGuide)
                        GestureDetector(
                          onTap: _showHelpSheet,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.pan_tool_alt_outlined, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Help',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (!_isGuide) const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: _sendAsAnnouncement
                                ? 'Type an announcement...'
                                : 'Type a message...',
                            filled: true,
                            fillColor: _sendAsAnnouncement
                                ? Colors.blue.shade50
                                : Colors.grey.shade100,
                            suffixIcon: const Icon(Icons.mic_none, color: Colors.black54),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                          textInputAction: TextInputAction.send,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _sendAsAnnouncement ? Colors.blue.shade400 : _kBrandYellow,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _sendAsAnnouncement ? Icons.campaign : Icons.send,
                            color: _sendAsAnnouncement ? Colors.white : Colors.black87,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared metadata for each severity level — one place to change labels,
// colors, or descriptions instead of hunting through the UI code.
MaterialColor _severityColor(HelpSeverity? severity) {
  switch (severity) {
    case HelpSeverity.question:
      return Colors.blue;
    case HelpSeverity.assistance:
      return Colors.orange;
    case HelpSeverity.emergency:
      return Colors.red;
    case null:
      return Colors.grey;
  }
}

String _severityLabel(HelpSeverity? severity) {
  switch (severity) {
    case HelpSeverity.question:
      return 'Question';
    case HelpSeverity.assistance:
      return 'Need Assistance';
    case HelpSeverity.emergency:
      return 'Emergency';
    case null:
      return 'Help';
  }
}

String _severityDescription(HelpSeverity? severity) {
  switch (severity) {
    case HelpSeverity.question:
      return 'Has a question for the guide.';
    case HelpSeverity.assistance:
      return 'Needs assistance.';
    case HelpSeverity.emergency:
      return 'Needs emergency help.';
    case null:
      return '';
  }
}

// ============================================================
// _HelpSheet — the bottom sheet opened by the Help button. Pick a
// severity, optionally add a message, then send. Returns the choice via
// Navigator.pop, rather than sending directly, so GroupChatScreen stays
// in charge of actually calling ChatService (and handling errors).
// ============================================================
class _HelpSheet extends StatefulWidget {
  const _HelpSheet();

  @override
  State<_HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends State<_HelpSheet> {
  final TextEditingController _textController = TextEditingController();
  HelpSeverity? _selected;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        // Keeps the sheet above the onscreen keyboard when the text
        // field is focused.
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you need?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          for (final severity in HelpSeverity.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SeverityOption(
                severity: severity,
                selected: _selected == severity,
                onTap: () => setState(() => _selected = severity),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            decoration: InputDecoration(
              hintText: 'Add a message (optional)',
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              // Disabled until a severity is picked, a message alone
              // without a severity wouldn't render correctly.
              onPressed: _selected == null
                  ? null
                  : () => Navigator.of(context).pop((
                        severity: _selected!,
                        text: _textController.text,
                      )),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selected == null ? Colors.grey.shade300 : _severityColor(_selected),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityOption extends StatelessWidget {
  final HelpSeverity severity;
  final bool selected;
  final VoidCallback onTap;

  const _SeverityOption({
    required this.severity,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(severity);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color.shade400 : Colors.grey.shade300, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _severityLabel(severity),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    _severityDescription(severity),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// _AnnouncementBanner — the pinned banner at the top of the chat showing
// the most recent guide announcement.
// ============================================================
class _AnnouncementBanner extends StatelessWidget {
  final Stream<List<ChatMessage>> stream;
  final bool expanded;
  final VoidCallback onToggle;

  const _AnnouncementBanner({
    required this.stream,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatMessage>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Announcement failed to load: ${snapshot.error}',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          );
        }

        final announcements = snapshot.data;
        if (announcements == null || announcements.isEmpty) {
          // No announcement yet, show nothing rather
          // than an empty looking banner taking up space.
          return const SizedBox.shrink();
        }

        final latest = announcements.first;

        return GestureDetector(
          onTap: onToggle,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.campaign, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Latest Announcement',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  latest.text,
                  textAlign: TextAlign.center,
                  maxLines: expanded ? null : 1,
                  overflow: expanded ? null : TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Icon(
                  expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// _GuidePillButton — the small colored pill buttons above the input bar.
// "Filter Announcements" is available to everyone; "Send Announcement"
// only appears for guides. A filled dot + label, with a slightly
// darker/filled background while active, so it's clear at a glance
// which modes are currently on.
// ============================================================
class _GuidePillButton extends StatelessWidget {
  final String label;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  const _GuidePillButton({
    required this.label,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? dotColor.withOpacity(0.25) : dotColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(30),
          border: selected ? Border.all(color: dotColor, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// _Avatar — shows the sender's real photo if they have one, otherwise
// falls back to a colored circle with their initials. Tourists set up
// via name + phone number (no photo required) will very often hit the
// fallback case, hence a solid color circle + initials rather than a broken
// image icon.
// ============================================================
class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _Avatar({required this.photoUrl, required this.name});

  // Derives a consistent color per person from their name, so the same
  // person's avatar always looks the same across messages
  // instead of a random color every rebuild.
  Color _colorForName(String name) {
    const palette = [
      Color(0xFF8FC7EE),
      Color(0xFFFFB4A2),
      Color(0xFFB5EAD7),
      Color(0xFFFFDAC1),
      Color(0xFFC7CEEA),
    ];
    final index = name.isEmpty ? 0 : name.codeUnitAt(0) % palette.length;
    return palette[index];
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundImage: NetworkImage(photoUrl!),
      );
    }

    return CircleAvatar(
      radius: 16,
      backgroundColor: _colorForName(name),
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}