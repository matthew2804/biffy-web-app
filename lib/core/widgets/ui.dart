import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../data/models/catalog.dart';
import '../../data/models/order.dart';

/// Tarjeta blanca con radio 20 y sombra suave.
class BiffyCard extends StatelessWidget {
  const BiffyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.radius = 20,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: r,
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = color == null
        ? null
        : FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          );
    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
          : FilledButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final style = foreground == null
        ? null
        : OutlinedButton.styleFrom(foregroundColor: foreground);
    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? OutlinedButton(
              style: style,
              onPressed: onPressed,
              child: Text(label),
            )
          : OutlinedButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.emoji,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final String emoji;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: t.bodySmall, textAlign: TextAlign.center),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Píldora seleccionable (filtros, categorías, opciones).
class SelectPill extends StatelessWidget {
  const SelectPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primary : p.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? AppColors.primary : p.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40, maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null) ...[Text(emoji!), const SizedBox(width: 6)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: selected ? AppColors.text : p.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge = 0,
    this.color,
    this.iconColor,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final int badge;
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: tooltip,
        button: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: color ?? p.surface,
              shape: const CircleBorder(),
              elevation: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(icon, size: 22, color: iconColor ?? p.text),
                ),
              ),
            ),
            if (badge > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.textColor});

  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? context.palette.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? context.palette.text,
        ),
      ),
    );
  }
}

class DemoBadge extends StatelessWidget {
  const DemoBadge([this.text = 'Demostración · sin cobros reales', Key? key])
    : super(key: key);
  final String text;

  @override
  Widget build(BuildContext context) => Tag(
    '🧪 $text',
    color: AppColors.secondary.withValues(alpha: 0.25),
    textColor: AppColors.text,
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.kitchen = false});

  final OrderStatus status;
  final bool kitchen;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      OrderStatus.delivered => (AppColors.success, Colors.white),
      OrderStatus.cancelled => (AppColors.error, Colors.white),
      OrderStatus.pending => (AppColors.primary, AppColors.text),
      OrderStatus.ready => (AppColors.secondary, AppColors.text),
      _ => (context.palette.surfaceSoft, context.palette.text),
    };
    return Tag(
      kitchen ? status.kitchenLabel : status.buyerLabel,
      color: bg,
      textColor: fg,
    );
  }
}

class BeeLogo extends StatelessWidget {
  const BeeLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/biffy-logo.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    semanticLabel: 'Logo de Biffy',
  );
}

/// Foto local (`assets/...`) o remota (URL de Supabase Storage en
/// `image_url`); si no carga se muestra [fallback].
Widget catalogImage(
  String src, {
  double? width,
  double? height,
  required Widget fallback,
}) {
  Widget onError(BuildContext _, Object _, StackTrace? _) => fallback;
  return src.startsWith('http')
      ? Image.network(
          src,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: onError,
        )
      : Image.asset(
          src,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: onError,
        );
}

/// Foto del plato o emoji grande sobre superficie lavanda.
class FoodImage extends StatelessWidget {
  const FoodImage({
    super.key,
    required this.emoji,
    this.asset,
    this.size = 72,
    this.radius = 16,
    this.width,
  });

  factory FoodImage.dish(
    Dish d, {
    double size = 72,
    double radius = 16,
    double? width,
  }) => FoodImage(
    emoji: d.emoji,
    asset: d.imageAsset,
    size: size,
    radius: radius,
    width: width,
  );

  final String emoji;
  final String? asset;
  final double size;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width ?? size,
        height: size,
        color: context.palette.surfaceSoft,
        alignment: Alignment.center,
        child: asset != null
            ? catalogImage(
                asset!,
                width: width ?? size,
                height: size,
                fallback: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
              )
            : Text(emoji, style: TextStyle(fontSize: size * 0.5)),
      ),
    );
  }
}

/// Foto de perfil redonda; si la persona no tiene foto, muestra la inicial de su nombre.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.asset,
    this.radius = 22,
  });

  final String name;
  final String? asset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(
        fontSize: radius * 0.8,
        fontWeight: FontWeight.w800,
        color: AppColors.text,
      ),
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary,
      child: asset == null
          ? initial
          : ClipOval(
              child: catalogImage(
                asset!,
                width: radius * 2,
                height: radius * 2,
                fallback: initial,
              ),
            ),
    );
  }
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 20,
    this.compact = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = compact ? 36.0 : 44.0;
    Widget btn(IconData icon, String label, VoidCallback? onTap) => Semantics(
      label: label,
      button: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: s,
          height: s,
          child: Icon(icon, size: 18, color: onTap == null ? p.muted : p.text),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
            min == 0 && value == 1 ? Icons.delete_outline : Icons.remove,
            min == 0 && value == 1 ? 'Quitar producto' : 'Disminuir cantidad',
            value <= min ? null : () => onChanged(value - 1),
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          btn(
            Icons.add,
            'Aumentar cantidad',
            value >= max ? null : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.bold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: bold ? 16 : 14,
      color: valueColor,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: style.copyWith(color: bold ? null : context.palette.muted),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class BigNumber extends StatelessWidget {
  const BigNumber(this.label, this.value, {super.key, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return BiffyCard(
      color: highlight ? AppColors.primary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight ? AppColors.text : context.palette.muted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppTypography.heading,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: highlight ? AppColors.text : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Confirmar',
  String cancel = 'Cancelar',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(100, 44),
                )
              : FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : null,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// Contenido con ancho máximo móvil (360–448 px) centrado en pantallas anchas.
class MobileFrame extends StatelessWidget {
  const MobileFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    // heightFactor 1: no se expande verticalmente (seguro en bottomNavigationBar).
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: child,
    ),
  );
}
