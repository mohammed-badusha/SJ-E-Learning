// Supplied logo launcher export tool, run with: flutter test tools/render_brand.dart
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/shared/widgets.dart';

void main() {
  testWidgets('Export SJ launcher artwork', (tester) async {
    final outputs = <String, int>{
      'assets/brand/sj-mark.png': 1024,
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      'web/favicon.png': 32,
      'web/icons/Icon-192.png': 192,
      'web/icons/Icon-512.png': 512,
      'web/icons/Icon-maskable-192.png': 192,
      'web/icons/Icon-maskable-512.png': 512,
    };
    const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final manifest = jsonDecode(
      (await tester.runAsync(
        () => File('$iosDir/Contents.json').readAsString(),
      ))!,
    );
    for (final entry in manifest['images'] as List) {
      if (entry['filename'] == null) continue;
      final size = double.parse((entry['size'] as String).split('x').first);
      final scale = double.parse(
        (entry['scale'] as String).replaceAll('x', ''),
      );
      outputs['$iosDir/${entry['filename']}'] = (size * scale).round();
    }
    for (final item in outputs.entries) {
      tester.view.physicalSize = Size.square(item.value.toDouble());
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Colors.white,
              child: SJMark(size: item.value.toDouble()),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/brand/sj-logo-source.png'),
          key.currentContext!,
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(item.key).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
