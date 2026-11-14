import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyableRoomCode extends StatelessWidget {
  final String roomId;
  final String prefix;
  final TextStyle? style;
  final double iconSize;

  const CopyableRoomCode({
    super.key,
    required this.roomId,
    this.prefix = '',
    this.style,
    this.iconSize = 16,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: roomId));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Skopiowano kod pokoju')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Kopiuj kod pokoju',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _copy(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$prefix$roomId', style: style),
              const SizedBox(width: 6),
              Icon(Icons.copy, size: iconSize),
            ],
          ),
        ),
      ),
    );
  }
}
