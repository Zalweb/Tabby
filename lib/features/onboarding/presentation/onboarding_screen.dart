import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/tabby_colors.dart';
import '../../../core/config/app_state.dart';
import '../../../shared/widgets/tabby_button.dart';
import '../../../shared/widgets/tabby_mascot_widget.dart';
import '../../tabs/domain/models.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  final List<_OnboardingData> _slides = [
    _OnboardingData(
      emotion: MascotEmotion.idleNeutral,
      title: 'Keep tabs on every shared expense',
      body: 'Log shared meals, rides, borrowed cash, and more in under 5 seconds.',
    ),
    _OnboardingData(
      emotion: MascotEmotion.userIsOwed,
      title: 'Always know who owes who',
      body: 'One running tab per friend. Net balances calculated automatically — no spreadsheets needed.',
    ),
    _OnboardingData(
      emotion: MascotEmotion.celebrating,
      title: 'Settle up without the awkwardness',
      body: 'Send friendly reminders and record settlements via GCash, Maya, Cash, or Bank Transfer.',
    ),
  ];

  void _finishOnboarding() {
    AppState.hasSeenOnboarding.value = true;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TabbyColors.bgCanvas,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _currentIndex == _slides.length - 1 ? null : _finishOnboarding,
                child: Text(
                  _currentIndex == _slides.length - 1 ? '' : 'Skip',
                  style: const TextStyle(color: TabbyColors.textSecondary, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: TabbyColors.brandMintAccent,
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: TabbyMascotWidget(
                            emotion: slide.emotion,
                            size: 140,
                            showBubble: false,
                          ),
                        ),
                        const SizedBox(height: 48),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: TabbyColors.brandDarkTeal,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: TabbyColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentIndex == index ? 20 : 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index ? TabbyColors.brandEmerald : TabbyColors.textSecondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TabbyButton(
                    label: _currentIndex == _slides.length - 1 ? 'Get Started' : 'Next',
                    onPressed: () {
                      if (_currentIndex == _slides.length - 1) {
                        _finishOnboarding();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingData {
  final MascotEmotion emotion;
  final String title;
  final String body;

  _OnboardingData({
    required this.emotion,
    required this.title,
    required this.body,
  });
}
