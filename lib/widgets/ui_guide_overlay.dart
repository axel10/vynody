import 'dart:ui';
import 'package:flutter/material.dart';

/// Interactive UI walkthrough guide overlay that introduces the main interface
/// after a new user finishes or skips the root folder selection.
class UiGuideOverlay extends StatefulWidget {
  const UiGuideOverlay({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<UiGuideOverlay> createState() => _UiGuideOverlayState();
}

class _GuideStepInfo {
  final IconData icon;
  final String title;
  final String description;
  final Alignment cardAlignment;
  final Alignment indicatorAlignment;

  const _GuideStepInfo({
    required this.icon,
    required this.title,
    required this.description,
    required this.cardAlignment,
    required this.indicatorAlignment,
  });
}

class _UiGuideOverlayState extends State<UiGuideOverlay>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;

  static const List<_GuideStepInfo> _steps = [
    _GuideStepInfo(
      icon: Icons.navigation_rounded,
      title: '路径导航与目录管理',
      description:
          '点击顶部可快速返回上级或主页，随时查看当前所在文件夹路径；支持按名称、修改时间等切换目录排序方式。',
      cardAlignment: Alignment(0.0, -0.45),
      indicatorAlignment: Alignment.topCenter,
    ),
    _GuideStepInfo(
      icon: Icons.folder_copy_rounded,
      title: '目录浏览与快捷操作',
      description:
          '点击任意目录卡片即可进入浏览音乐。长按或右键目录与歌曲，可唤起丰富快捷菜单（播放、加入歌单等）。',
      cardAlignment: Alignment.center,
      indicatorAlignment: Alignment.center,
    ),
    _GuideStepInfo(
      icon: Icons.play_circle_filled_rounded,
      title: '播放控制与沉浸歌词',
      description:
          '底部常驻迷你播放控制条，随时控制播放与切换歌曲。点击即可展开沉浸式封面黑胶与动态滚动歌词面板。',
      cardAlignment: Alignment(0.0, 0.45),
      indicatorAlignment: Alignment.bottomCenter,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      _animController.forward(from: 0.0);
      setState(() {
        _currentStep++;
      });
    } else {
      _finish();
    }
  }

  void _finish() {
    _animController.reverse().then((_) {
      widget.onComplete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final step = _steps[_currentStep];
    final isLastStep = _currentStep == _steps.length - 1;

    return Stack(
      children: [
        // Semi-transparent backdrop with subtle blur
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _nextStep,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(
                color: Colors.black.withValues(alpha: 0.65),
              ),
            ),
          ),
        ),

        // Indicator pulse badge near target
        if (step.indicatorAlignment == Alignment.topCenter)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 0,
            right: 0,
            child: Center(
              child: _buildSpotlightBadge(Icons.arrow_upward_rounded),
            ),
          )
        else if (step.indicatorAlignment == Alignment.bottomCenter)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 65,
            left: 0,
            right: 0,
            child: Center(
              child: _buildSpotlightBadge(Icons.arrow_downward_rounded),
            ),
          ),

        // Floating guide card
        SafeArea(
          child: Align(
            alignment: step.cardAlignment,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                      : Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: const Color(0xFF39C5BB).withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step count badge & Skip button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF39C5BB).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '功能指引 ${_currentStep + 1} / ${_steps.length}',
                            style: const TextStyle(
                              color: Color(0xFF39C5BB),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _finish,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: theme.colorScheme.onSurfaceVariant,
                          ),
                          child: const Text('跳过'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Title
                    Row(
                      children: [
                        Icon(
                          step.icon,
                          color: const Color(0xFF39C5BB),
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Description
                    Text(
                      step.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                        height: 1.5,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Next / Finish button
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _nextStep,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF39C5BB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          isLastStep ? '开始体验' : '下一步',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpotlightBadge(IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF39C5BB),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF39C5BB).withValues(alpha: 0.5),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          const Text(
            '关注此区域',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
