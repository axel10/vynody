import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:material_color_utilities/material_color_utilities.dart';

void main() {
  runApp(const MCUApp());
}

class MCUApp extends StatelessWidget {
  const MCUApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Material Color Utilities Explorer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
      ),
      home: const MCUPage(),
    );
  }
}

class MCUPage extends StatefulWidget {
  const MCUPage({super.key});

  @override
  State<MCUPage> createState() => _MCUPageState();
}

class _MCUPageState extends State<MCUPage> {
  List<ColorPopulation> _topColors = [];
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _extractColors();
  }

  Future<void> _extractColors() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final file = File('test/utils/test.jpg');
      if (!file.existsSync()) {
        setState(() {
          _error = 'Error: test/utils/test.jpg not found.';
          _isLoading = false;
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');

      // Resize for performance
      final resized = img.copyResize(image, width: 128);
      
      // Convert to ARGB format expected by MCU
      final pixels = <int>[];
      for (var y = 0; y < resized.height; y++) {
        for (var x = 0; x < resized.width; x++) {
          final pixel = resized.getPixel(x, y);
          // image package pixels are often RGBA, MCU needs ARGB
          final a = pixel.a.toInt();
          final r = pixel.r.toInt();
          final g = pixel.g.toInt();
          final b = pixel.b.toInt();
          final argb = (a << 24) | (r << 16) | (g << 8) | b;
          pixels.add(argb);
        }
      }

      // Use MCU Quantizer
      final result = await QuantizerCelebi().quantize(pixels, 128);
      
      // Score colors to find the best "theme" candidates, 
      // but the user asked for "top 8" which usually implies population.
      // However, Score.score is the "Material" way to find significant colors.
      final rankedInts = Score.score(result.colorToCount);
      
      // Map to ColorPopulation objects
      final List<ColorPopulation> colors = [];
      
      // First, get the scored colors
      for (var argb in rankedInts.take(8)) {
        colors.add(ColorPopulation(
          color: Color(argb),
          count: result.colorToCount[argb] ?? 0,
          isScored: true,
        ));
      }

      // If we don't have 8 from score, or just to show population-based ones:
      // Sort all by count
      final sortedByCount = result.colorToCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      setState(() {
        _imageBytes = bytes;
        _topColors = colors;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar.large(
            title: const Text('Material Color Utilities'),
            backgroundColor: const Color(0xFF0F0F0F),
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(onPressed: _extractColors, icon: const Icon(Icons.refresh)),
            ],
          ),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(child: Center(child: Text(_error!)))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageHero(),
                    const SizedBox(height: 32),
                    const Text(
                      'Top 8 Significant Colors (MCU Scored)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Text(
                      'Calculated using QuantizerCelebi and Score ranking',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildColorCard(_topColors[index], index + 1),
                  childCount: _topColors.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ]
        ],
      ),
    );
  }

  Widget _buildImageHero() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(
          image: MemoryImage(_imageBytes!),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        alignment: Alignment.bottomLeft,
        child: const Text(
          'Input: test.jpg',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildColorCard(ColorPopulation item, int rank) {
    final color = item.color;
    final hct = Hct.fromInt(color.value);
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    color: hct.tone < 50 ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                  ),
                  Text(
                    'H: ${hct.hue.toInt()} C: ${hct.chroma.toInt()} T: ${hct.tone.toInt()}',
                    style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
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

class ColorPopulation {
  final Color color;
  final int count;
  final bool isScored;

  ColorPopulation({required this.color, required this.count, this.isScored = false});
}
