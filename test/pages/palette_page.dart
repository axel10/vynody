import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:palette_generator_master/palette_generator_master.dart';
import 'package:palette_generator/palette_generator.dart' as standard;

void main() {
  runApp(const PaletteTestApp());
}

class PaletteTestApp extends StatelessWidget {
  const PaletteTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Palette Generator Visualizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39C5BB),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Inter', // Fallback to system font if Inter is not there
      ),
      home: const PalettePage(),
    );
  }
}

class PalettePage extends StatefulWidget {
  const PalettePage({super.key});

  @override
  State<PalettePage> createState() => _PalettePageState();
}

class _PalettePageState extends State<PalettePage> with SingleTickerProviderStateMixin {
  PaletteGeneratorMaster? _paletteMaster;
  standard.PaletteGenerator? _paletteStandard;
  late TabController _tabController;
  Uint8List? _imageBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPalette();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPalette() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Read the test image file
      // Relative to project root
      final file = File('test/utils/test.jpg');
      if (!file.existsSync()) {
        setState(() {
          _error = 'Error: test/utils/test.jpg not found.\nMake sure you are running from project root.';
          _isLoading = false;
        });
        return;
      }
      final bytes = await file.readAsBytes();
      
      // 2. Decode the image using the 'image' package
      final image = img.decodeImage(bytes);
      if (image == null) {
        setState(() {
          _error = 'Error: Failed to decode image.';
          _isLoading = false;
        });
        return;
      }

      // 3. Resize the image for faster processing
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
      final paletteMaster = await PaletteGeneratorMaster.fromByteData(
        EncodedImageMaster(
          ByteData.sublistView(rgbaBytes),
          width: resized.width,
          height: resized.height,
        ),
        maximumColorCount: 20,
      );

      // 5. Use standard palette_generator
      final paletteStandard = await standard.PaletteGenerator.fromImageProvider(
        MemoryImage(bytes),
        maximumColorCount: 20,
      );

      setState(() {
        _imageBytes = bytes;
        _paletteMaster = paletteMaster;
        _paletteStandard = paletteStandard;
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
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Palette Comparison'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loadPalette,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Master'),
            Tab(text: 'Standard'),
          ],
          indicatorColor: const Color(0xFF39C5BB),
          labelColor: const Color(0xFF39C5BB),
          unselectedLabelColor: Colors.white54,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildContent(_paletteMaster, isMaster: true),
                    _buildContent(_paletteStandard, isMaster: false),
                  ],
                ),
    );
  }

  Widget _buildContent(dynamic palette, {required bool isMaster}) {
    if (palette == null) return const SizedBox.shrink();

    final List<Map<String, dynamic>> profiles = [
      {'label': 'Dominant', 'color': palette.dominantColor?.color},
      {'label': 'Vibrant', 'color': palette.vibrantColor?.color},
      {'label': 'Light Vibrant', 'color': palette.lightVibrantColor?.color},
      {'label': 'Dark Vibrant', 'color': palette.darkVibrantColor?.color},
      {'label': 'Muted', 'color': palette.mutedColor?.color},
      {'label': 'Light Muted', 'color': palette.lightMutedColor?.color},
      {'label': 'Dark Muted', 'color': palette.darkMutedColor?.color},
    ];

    final List paletteColors = palette.paletteColors;
    final dominantPopulation = palette.dominantColor?.population ?? 1;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImagePreview(),
          const SizedBox(height: 32),
          _buildSectionTitle('Standard Profiles (${isMaster ? "Master" : "Standard"})'),
          const SizedBox(height: 16),
          _buildProfilesGrid(profiles),
          const SizedBox(height: 32),
          _buildSectionTitle('All Extracted Colors (${paletteColors.length})'),
          const SizedBox(height: 16),
          _buildAllColorsList(paletteColors, dominantPopulation),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildImagePreview() {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _imageBytes != null
            ? Image.memory(
                _imageBytes!,
                height: 250,
                width: double.infinity,
                fit: BoxFit.cover,
              )
            : const SizedBox(height: 250, child: Center(child: Text('No Image'))),
      ),
    );
  }

  Widget _buildProfilesGrid(List<Map<String, dynamic>> profiles) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final color = profile['color'] as Color?;
        return _buildColorCard(profile['label'] as String, color);
      },
    );
  }

  Widget _buildColorCard(String label, Color? color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color ?? Colors.grey[800],
              borderRadius: BorderRadius.circular(8),
              boxShadow: color != null
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                Text(
                  color != null ? '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}' : 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllColorsList(List paletteColors, int dominantPopulation) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: paletteColors.length,
      itemBuilder: (context, index) {
        final paletteColor = paletteColors[index];
        final color = paletteColor.color;
        final population = paletteColor.population;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${color.value.toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'Population: $population',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              // Population bar
              Container(
                width: 100,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: Container(
                  width: (100 * (population / dominantPopulation).clamp(0, 1)).toDouble(),
                  height: 4,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
