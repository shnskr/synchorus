import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../providers/app_providers.dart';

/// 설정 화면. 현재는 프로 구매/복원 + 사용 가이드 다시 보기. 향후 확장용 그릇.
/// 가이드는 GlobalKey가 PlayerScreen에 있으므로 여기선 직접 실행하지 않고
/// Navigator.pop('showGuide')로 신호만 보내 PlayerScreen이 _showGuide() 실행.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _buy() async {
    setState(() => _busy = true);
    final purchase = ref.read(purchaseServiceProvider);
    final started = await purchase.buy();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!started) {
      _snack('상품 정보를 불러올 수 없어요. 잠시 후 다시 시도해 주세요.');
    }
    // 성공 시 결과는 purchaseStream → proProvider로 들어와 watch가 갱신.
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    await ref.read(purchaseServiceProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    // 복원 결과도 proProvider로 반영. 없으면 변화 없음.
    if (!ref.read(proProvider)) {
      _snack('복원할 구매 내역이 없어요.');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(proProvider);
    final price = ref.read(purchaseServiceProvider).priceLabel;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 프로 섹션 ──────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Symbols.workspace_premium_rounded,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Synchorus 프로',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (isPro) ...[
                      Row(
                        children: [
                          Icon(
                            Symbols.check_circle_rounded,
                            color: scheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          const Text('프로 사용 중'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '광고가 사라지고 기기 제한 없이 동기화할 수 있어요.',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ] else ...[
                      Text(
                        '한 번만 결제하면 광고가 사라지고, 2대 제한 없이 '
                        '여러 기기를 동기화할 수 있어요. (호스트가 결제하면 그 방의 '
                        '모든 기기에 적용)',
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _buy,
                          child: Text(
                            price != null ? '프로로 업그레이드 ($price)' : '프로로 업그레이드',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _restore,
                          child: const Text('구매 복원'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ── 사용 가이드 ────────────────────────────────────────────
            Card(
              child: ListTile(
                leading: const Icon(Symbols.help_rounded),
                title: const Text('사용법 가이드 다시 보기'),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => Navigator.pop(context, 'showGuide'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
