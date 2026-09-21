/* =============================================================================
 * widgets.dart — 화면들이 같이 쓰는 조각들
 *
 * 지금 앱의 CSS 클래스(.card · .note · .pill · .avatar)와 같은 자리를
 * 맡습니다. 화면마다 따로 만들면 여백과 모서리가 조금씩 달라지고,
 * 그 차이가 "다른 앱" 처럼 보이게 합니다.
 * ========================================================================== */
import 'package:flutter/material.dart';

import '../theme.dart';
import 'fmt.dart';

MbColors mb(BuildContext c) => Theme.of(c).extension<MbColors>()!;

class MbCard extends StatelessWidget {
  const MbCard({super.key, required this.child, this.padding, this.onTap});
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final inner = Padding(padding: padding ?? const EdgeInsets.all(16), child: child);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? inner : InkWell(onTap: onTap, child: inner),
    );
  }
}

/// 제목 한 줄. 카드 안에서 쓰는 작은 머리글입니다.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

enum Tone { none, ok, warn, bad }

/// 설명 상자. **근거** 를 접어 둘 수 있습니다 — 숫자를 주장할 때는
/// 왜 그런지를 같이 들고 있어야 합니다.
class Note extends StatefulWidget {
  const Note({super.key, this.title, required this.text, this.tone = Tone.none, this.evidence});
  final String? title;
  final String text;
  final Tone tone;
  final String? evidence;

  @override
  State<Note> createState() => _NoteState();
}

class _NoteState extends State<Note> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    final (fg, bg) = switch (widget.tone) {
      Tone.ok => (c.ok, c.okBg),
      Tone.warn => (c.warn, c.warnBg),
      Tone.bad => (c.bad, c.badBg),
      Tone.none => (Theme.of(context).colorScheme.onSurface, Theme.of(context).colorScheme.surface),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.tone == Tone.none ? Theme.of(context).dividerColor : fg.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          if (widget.title != null)
            TextSpan(text: '${widget.title} ', style: TextStyle(fontWeight: FontWeight.w700, color: fg)),
          TextSpan(text: widget.text, style: TextStyle(color: fg)),
        ]), style: const TextStyle(fontSize: 13, height: 1.5)),
        if (widget.evidence != null) ...[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_open ? '근거 ▾' : '근거 ▸',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700, color: fg.withValues(alpha: 0.8),
                      decoration: TextDecoration.underline)),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.evidence!,
                  style: TextStyle(fontSize: 12, height: 1.6, color: fg.withValues(alpha: 0.9))),
            ),
        ],
      ]),
    );
  }
}

/// 숫자 한 칸. 값이 없으면 `—` 입니다 — 0 이 아닙니다.
class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, this.unit, this.delta, this.color});
  final String label;
  final String value;
  final String? unit;
  final String? delta;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
      const SizedBox(height: 2),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
        children: [
          Text(value, style: t.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          if (unit != null)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(unit!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
            ),
        ]),
      if (delta != null)
        Text(delta!, style: t.textTheme.labelSmall?.copyWith(color: t.hintColor)),
    ]);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = Tone.none, this.onTap, this.selected = false});
  final String text;
  final Tone tone;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = mb(context);
    final t = Theme.of(context);
    final fg = switch (tone) {
      Tone.ok => c.ok,
      Tone.warn => c.warn,
      Tone.bad => c.bad,
      Tone.none => selected ? t.colorScheme.onPrimary : t.colorScheme.onSurface,
    };
    final bg = switch (tone) {
      Tone.ok => c.okBg,
      Tone.warn => c.warnBg,
      Tone.bad => c.badBg,
      Tone.none => selected ? t.colorScheme.primary : c.accentSub,
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
    return onTap == null
        ? chip
        : InkWell(borderRadius: BorderRadius.circular(999), onTap: onTap, child: chip);
  }
}

/// 사람 동그라미. 사진이 있으면 사진, 없으면 이름 첫 글자에 **이름에서 뽑은
/// 색**을 입힙니다 — 같은 사람은 언제나 같은 색이라 목록에서 눈이 찾습니다.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.displayName, this.avatarUrl, this.id, this.size = 40});
  final String? displayName;
  final String? avatarUrl;
  final String? id;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(avatarUrl!, width: size, height: size, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _letter(context)),
      );
    }
    return _letter(context);
  }

  Widget _letter(BuildContext context) {
    final hue = tintOf(id ?? displayName ?? '').toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.28 : 0.88).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.65, dark ? 0.82 : 0.32).toColor();
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(firstChar(displayName),
          style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// 아무것도 없을 때. **무엇을 하면 되는지**까지 말합니다 —
/// "비어 있습니다" 만 쓰면 사용자는 고장인지 빈 건지 모릅니다.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.detail, this.action});
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(children: [
        Text(title, textAlign: TextAlign.center, style: t.textTheme.titleSmall),
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(detail!, textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, height: 1.5)),
        ],
        if (action != null) ...[const SizedBox(height: 14), action!],
      ]),
    );
  }
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
}

/* --- 굵게 --------------------------------------------------------------------
 *
 * 문구 안에서 한 대목을 굵게 하고 싶을 때가 자주 있습니다 — "**이 기기에만**
 * 저장됩니다" 같은 자리는 그 대목이 문장의 전부니까요.
 *
 * 그런데 Flutter 의 Text 는 마크다운을 모릅니다. `**` 를 그대로 찍습니다.
 * 실제로 온보딩 고지에 "측정 기록은 **이 기기에만** 저장됩니다" 가
 * 별표째로 나갔습니다 — 제일 중요한 문장이 제일 어설퍼 보이는 자리였습니다.
 * -------------------------------------------------------------------------- */

final RegExp _bold = RegExp(r'\*\*(.+?)\*\*', dotAll: true);

/// `**굵게**` 표시를 실제로 굵게 그립니다.
TextSpan boldSpan(String text, {TextStyle? style}) {
  final parts = <TextSpan>[];
  var at = 0;
  for (final m in _bold.allMatches(text)) {
    if (m.start > at) parts.add(TextSpan(text: text.substring(at, m.start)));
    parts.add(TextSpan(
        text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
    at = m.end;
  }
  if (at < text.length) parts.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: parts);
}

/// `**굵게**` 를 알아보는 Text.
class RichishText extends StatelessWidget {
  const RichishText(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text.rich(
        boldSpan(text, style: style ?? DefaultTextStyle.of(context).style),
        textAlign: textAlign,
      );
}
