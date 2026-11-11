import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../shared/player_avatar.dart';
import '../../../shared/widgets.dart';

/// Only these newly encoded pixels leave the device, never the original photo or its metadata.
Future<Uint8List> portraitThumbnail(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodecWithSize(
    await ui.ImmutableBuffer.fromUint8List(bytes),
    getTargetSize: (w, h) {
      if (w * h > 64000000 || w / h > 12 || h / w > 12) {
        throw const FormatException('Unsupported dimensions');
      }
      final scale = math.min(1.0, 192 / math.min(w, h));
      return ui.TargetImageSize(
        width: math.max(1, (w * scale).round()),
        height: math.max(1, (h * scale).round()),
      );
    },
  );
  try {
    final frame = (await codec.getNextFrame()).image;
    try {
      final side = math.min(frame.width, frame.height).toDouble();
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        frame,
        ui.Rect.fromLTWH(
          (frame.width - side) / 2,
          (frame.height - side) / 2,
          side,
          side,
        ),
        const ui.Rect.fromLTWH(0, 0, 192, 192),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(192, 192);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      frame.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class PortraitChoice {
  const PortraitChoice(this.reference, [this.photo]);
  final String reference;
  final Uint8List? photo;
}

class PortraitPicker extends StatefulWidget {
  const PortraitPicker({
    super.key,
    required this.name,
    required this.original,
    required this.choice,
    required this.onChanged,
  });
  final String name;
  final String? original;
  final PortraitChoice? choice;
  final ValueChanged<PortraitChoice> onChanged;
  @override
  State<PortraitPicker> createState() => _PortraitPickerState();
}

class _PortraitPickerState extends State<PortraitPicker> {
  bool picking = false;
  Future<void> pick() async {
    setState(() => picking = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withReadStream: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 16 * 1024 * 1024) {
        showMessage(context, 'Choose a photo smaller than 16 MB.');
        return;
      }
      final buffer = BytesBuilder(copy: false);
      if (file.readStream != null) {
        await for (final chunk in file.readStream!) {
          if (buffer.length + chunk.length > 16 * 1024 * 1024) {
            throw const FormatException();
          }
          buffer.add(chunk);
        }
      } else {
        buffer.add(file.bytes ?? await file.xFile.readAsBytes());
      }
      final photo = await portraitThumbnail(buffer.takeBytes());
      if (mounted) widget.onChanged(PortraitChoice('gallery', photo));
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'That image couldn’t be opened. Try a JPG, PNG or WebP photo.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.choice?.reference ?? widget.original;
    return ArenaCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlayerAvatar(
                name: widget.name,
                reference: current,
                draft: widget.choice?.photo,
                size: 64,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Player picture', style: context.type.titleMedium),
                    Text(
                      'Optional · visible to other learners',
                      style: context.type.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in portraits.entries)
                Semantics(
                  button: true,
                  selected: current == 'preset:${e.key}',
                  label: e.value,
                  excludeSemantics: true,
                  child: Tooltip(
                    message: e.value,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(32),
                      onTap: () =>
                          widget.onChanged(PortraitChoice('preset:${e.key}')),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: 2,
                            color: current == 'preset:${e.key}'
                                ? Theme.of(context).colorScheme.primary
                                : context.tokens.line,
                          ),
                        ),
                        child: PlayerAvatar(
                          name: e.value,
                          reference: 'preset:${e.key}',
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: picking ? null : pick,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(picking ? 'Opening photo…' : 'Choose from gallery'),
              ),
              if (current != null && current != 'initials')
                TextButton(
                  onPressed: () =>
                      widget.onChanged(const PortraitChoice('initials')),
                  child: const Text('Use initials'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
