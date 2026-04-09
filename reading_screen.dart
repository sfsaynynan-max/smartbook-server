import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/book.dart';
import '../theme/app_theme.dart';
import '../services/gutenberg_service.dart';
import '../services/translation_service.dart';

class ReadingScreen extends StatefulWidget {
  final Book book;
  final String primaryLanguage;
  final String? secondaryLanguage;

  const ReadingScreen({
    super.key,
    required this.book,
    required this.primaryLanguage,
    this.secondaryLanguage,
  });

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with TickerProviderStateMixin {
  List<String> _primaryParagraphs = [];
  List<String> _secondaryParagraphs = [];
  bool _loadingText = true;
  bool _translating = false;
  double _translationProgress = 0.0;
  bool _showToolbar = true;
  double _fontSize = 17.0;
  int? _longPressedIndex;

  late AnimationController _toolbarController;
  late Animation<double> _toolbarAnimation;

  bool get _isOriginalPrimary =>
      widget.primaryLanguage == 'الأصلية' ||
      widget.primaryLanguage == 'English';
  bool get _hasSecondary => widget.secondaryLanguage != null;

  @override
  void initState() {
    super.initState();
    _toolbarController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _toolbarAnimation = CurvedAnimation(
        parent: _toolbarController, curve: Curves.easeOutCubic);
    _toolbarController.forward();
    _loadContent();
  }

  @override
  void dispose() {
    _toolbarController.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final paragraphs =
          await GutenbergService.fetchBookParagraphs(widget.book.id);

      if (!mounted) return;

      if (paragraphs.isEmpty) {
        setState(() => _loadingText = false);
        return;
      }

      setState(() {
        _primaryParagraphs = paragraphs;
        _loadingText = false;
      });

      // ترجمة في الخلفية
      if (!_isOriginalPrimary) {
        if (!mounted) return;
        setState(() {
          _translating = true;
          _translationProgress = 0.0;
        });

        final cached = await TranslationService.loadBookTranslation(
          bookId: widget.book.id,
          language: widget.primaryLanguage,
        );

        if (!mounted) return;

        if (cached != null && cached.isNotEmpty) {
          setState(() {
            _primaryParagraphs = cached;
            _translating = false;
          });
        } else {
          final results = await TranslationService.translateParagraphs(
            paragraphs: paragraphs,
            targetLanguage: widget.primaryLanguage,
            sourceLanguage: 'English',
            bookId: widget.book.id,
            onProgress: (p) {
              if (mounted) setState(() => _translationProgress = p);
            },
          );
          if (!mounted) return;
          setState(() {
            _primaryParagraphs = results;
            _translating = false;
          });
        }
      }

      // اللغة الثانوية
      if (_hasSecondary) {
        final secLang = widget.secondaryLanguage!;
        if (secLang == 'الأصلية' || secLang == 'English') {
          if (mounted) setState(() => _secondaryParagraphs = paragraphs);
        } else {
          final cached2 = await TranslationService.loadBookTranslation(
            bookId: widget.book.id,
            language: secLang,
          );
          if (!mounted) return;
          if (cached2 != null && cached2.isNotEmpty) {
            setState(() => _secondaryParagraphs = cached2);
          } else {
            final results2 =
                await TranslationService.translateParagraphs(
              paragraphs: paragraphs,
              targetLanguage: secLang,
              sourceLanguage: 'English',
              bookId: widget.book.id,
              onProgress: (_) {},
            );
            if (!mounted) return;
            setState(() => _secondaryParagraphs = results2);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loadingText = false);
    }
  }

  bool _isRTL(String language) =>
      ['العربية', 'الفارسية', 'العبرية'].contains(language);

  void _toggleToolbar() {
    setState(() => _showToolbar = !_showToolbar);
    if (_showToolbar) {
      _toolbarController.forward();
    } else {
      _toolbarController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      body: Stack(
        children: [
          // المحتوى
          _loadingText
              ? _buildLoadingState()
              : _primaryParagraphs.isEmpty
                  ? _buildEmptyState()
                  : GestureDetector(
                      onTap: _toggleToolbar,
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          22,
                          MediaQuery.of(context).padding.top + 80,
                          22,
                          120,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_translating)
                              _buildTranslatingBanner(),
                            ..._primaryParagraphs
                                .asMap()
                                .entries
                                .map((e) => _buildParagraph(e.key))
                                .toList(),
                          ],
                        ),
                      ),
                    ),

          // شريط أعلى
          AnimatedBuilder(
            animation: _toolbarAnimation,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, -80 * (1 - _toolbarAnimation.value)),
              child: Opacity(
                  opacity: _toolbarAnimation.value, child: child),
            ),
            child: _buildTopBar(),
          ),

          // شريط أسفل
          AnimatedBuilder(
            animation: _toolbarAnimation,
            builder: (_, child) => Transform.translate(
              offset: Offset(0, 100 * (1 - _toolbarAnimation.value)),
              child: Opacity(
                  opacity: _toolbarAnimation.value, child: child),
            ),
            child: Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildBottomBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 70, height: 70,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.menu_book_rounded,
                color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 20),
          const Text('جارٍ تحميل الكتاب...',
              style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('يتم جلب النص من المكتبة',
              style: TextStyle(
                  color: AppColors.textLight, fontSize: 13)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.textLight, size: 48),
          const SizedBox(height: 16),
          const Text('تعذر تحميل الكتاب',
              style: TextStyle(
                  color: AppColors.textDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('تحقق من الاتصال وحاول مجدداً',
              style: TextStyle(
                  color: AppColors.textLight, fontSize: 13)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              setState(() => _loadingText = true);
              _loadContent();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('إعادة المحاولة',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslatingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadowDeep,
              blurRadius: 8,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.translate,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                'جارٍ الترجمة إلى ${widget.primaryLanguage}...',
                style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
              const Spacer(),
              Text(
                '${(_translationProgress * 100).toInt()}%',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _translationProgress,
              backgroundColor: AppColors.primarySoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParagraph(int index) {
    if (index >= _primaryParagraphs.length) return const SizedBox();

    final isLongPressed = _longPressedIndex == index;
    String displayText = _primaryParagraphs[index];
    bool showingSecondary = false;

    if (isLongPressed && _hasSecondary &&
        index < _secondaryParagraphs.length &&
        _secondaryParagraphs[index].isNotEmpty) {
      displayText = _secondaryParagraphs[index];
      showingSecondary = true;
    }

    final isRTL = showingSecondary
        ? _isRTL(widget.secondaryLanguage!)
        : _isRTL(widget.primaryLanguage);

    return GestureDetector(
      onLongPressStart: (_) {
        if (_hasSecondary) {
          setState(() => _longPressedIndex = index);
          HapticFeedback.mediumImpact();
        }
      },
      onLongPressEnd: (_) => setState(() => _longPressedIndex = null),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 28),
        padding: isLongPressed
            ? const EdgeInsets.all(14)
            : EdgeInsets.zero,
        decoration: isLongPressed
            ? BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.accent.withOpacity(0.3),
                    width: 1.5),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLongPressed && _hasSecondary)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app_rounded,
                        color: AppColors.accent, size: 12),
                    const SizedBox(width: 4),
                    Text(widget.secondaryLanguage!,
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            Text(
              displayText,
              textAlign: isRTL ? TextAlign.right : TextAlign.left,
              textDirection:
                  isRTL ? TextDirection.rtl : TextDirection.ltr,
              style: TextStyle(
                fontSize: _fontSize,
                color: AppColors.textDark.withOpacity(0.85),
                height: 2.0,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: EdgeInsets.fromLTRB(
                16, MediaQuery.of(context).padding.top + 8, 16, 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF7).withOpacity(0.9),
              border: Border(
                  bottom: BorderSide(
                      color: AppColors.textLight.withOpacity(0.15),
                      width: 1)),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadowDeep,
                            blurRadius: 8,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textDark, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.book.titleAr,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(widget.primaryLanguage,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (_hasSecondary) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.touch_app_rounded,
                                color: AppColors.textLight, size: 10),
                            const SizedBox(width: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accentSoft,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(widget.secondaryLanguage!,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.accent,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showFontSizeDialog,
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadowDeep,
                            blurRadius: 8,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: const Icon(Icons.text_fields_rounded,
                        color: AppColors.textMid, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(
              20, 12, 20,
              MediaQuery.of(context).padding.bottom + 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF7).withOpacity(0.95),
            border: Border(
                top: BorderSide(
                    color: AppColors.textLight.withOpacity(0.15),
                    width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (_hasSecondary)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app_rounded,
                          color: AppColors.accent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'اضغط ← ${widget.secondaryLanguage}',
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(),
              _bottomAction(Icons.bookmark_outline_rounded,
                  'حفظ', false, () {}),
              _bottomAction(Icons.download_rounded, 'تنزيل',
                  false, _showDownloadDialog),
              _bottomAction(Icons.share_rounded, 'مشاركة',
                  false, () {}),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomAction(IconData icon, String label,
      bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: isActive
                  ? AppColors.primary
                  : AppColors.textLight,
              size: 22),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: isActive
                      ? AppColors.primary
                      : AppColors.textLight)),
        ],
      ),
    );
  }

  void _showFontSizeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModal) => Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textLight.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text('حجم الخط',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark)),
              const SizedBox(height: 16),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setModal(() {});
                      setState(() => _fontSize =
                          (_fontSize - 1).clamp(12, 26));
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.remove_rounded,
                          color: AppColors.accent),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 12, max: 26, divisions: 14,
                      activeColor: AppColors.primary,
                      inactiveColor: AppColors.primarySoft,
                      onChanged: (v) {
                        setModal(() {});
                        setState(() => _fontSize = v);
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setModal(() {});
                      setState(() => _fontSize =
                          (_fontSize + 1).clamp(12, 26));
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add_rounded,
                          color: AppColors.primary),
                    ),
                  ),
                ],
              ),
              Text('${_fontSize.toInt()} pt',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showDownloadDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textLight.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60, height: 60,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.download_rounded,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('تنزيل الصفحة الحالية',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark)),
            const SizedBox(height: 8),
            const Text(
              'سيتم تنزيل الصفحة مع علامة مائية\nلا يمكن تنزيل الكتاب كاملاً',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMid,
                  height: 1.6),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFFFF9A6C)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.download_rounded,
                        color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('تنزيل مع العلامة المائية',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
