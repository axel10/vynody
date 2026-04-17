import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:palette_generator_master/palette_generator_master.dart';

void main() {
  test('Print PaletteGeneratorMaster results for test.jpg', () async {
    // 1. Read the test image file
    final file = File('test/utils/test.jpg');
    if (!file.existsSync()) {
      print('Error: test/utils/test.jpg not found.');
      return;
    }
    final bytes = await file.readAsBytes();
    
    // 2. Decode the image using the 'image' package
    final image = img.decodeImage(bytes);
    if (image == null) {
      print('Error: Failed to decode image.');
      return;
    }

    // 3. Resize the image for faster processing (following the logic in theme_color_helper.dart)
    final resized = image.width >= image.height
        ? img.copyResize(
            image,
            width: 200,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: 200,
            interpolation: img.Interpolation.average,
          );

    // 4. Get RGBA bytes and create EncodedImageMaster
    final rgbaBytes = resized.getBytes(order: img.ChannelOrder.rgba);
    final palette = await PaletteGeneratorMaster.fromByteData(
      EncodedImageMaster(
        ByteData.sublistView(rgbaBytes),
        width: resized.width,
        height: resized.height,
      ),
      maximumColorCount: 20,
    );

    // 5. Helper function to format color to Hex
    String toHex(Color? color) {
      if (color == null) return 'null';

      return color.toString();
      // if (color == null) return 'null';
      // return '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }

    // 6. Print the results
    print('--- Palette Results for test.jpg ---');
    print('Dominant:       ${toHex(palette.dominantColor?.color)}');
    print('Vibrant:        ${toHex(palette.vibrantColor?.color)}');
    print('Light Vibrant:  ${toHex(palette.lightVibrantColor?.color)}');
    print('Dark Vibrant:   ${toHex(palette.darkVibrantColor?.color)}');
    print('Muted:          ${toHex(palette.mutedColor?.color)}');
    print('Light Muted:    ${toHex(palette.lightMutedColor?.color)}');
    print('Dark Muted:     ${toHex(palette.darkMutedColor?.color)}');
    print('------------------------------------');
    
    print('\nAll Colors found (${palette.paletteColors.length}):');
    for (var i = 0; i < palette.paletteColors.length; i++) {
      final pColor = palette.paletteColors[i];
      print('[$i] Hex: ${toHex(pColor.color)} | Population: ${pColor.population}');
    }
  });
}
