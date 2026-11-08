import 'package:flutter/services.dart';

Future<void> loadAppFonts() async {
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  for (final font in ['Inter', 'PlusJakartaSans']) {
    await (FontLoader(
      font,
    )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
  }
  final poppins = FontLoader('Poppins');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
  }
  await poppins.load();
}
