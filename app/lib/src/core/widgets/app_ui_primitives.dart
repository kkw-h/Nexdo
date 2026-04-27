import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.borderRadius = 20,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.outline.withValues(alpha: 0.7)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) {
      return card;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      ),
    );
  }
}

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.horizontalPadding = 12,
    this.verticalPadding = 10,
    this.textStyle,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double horizontalPadding;
  final double verticalPadding;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: selected
          ? palette.primaryContainer.withValues(alpha: 0.55)
          : palette.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.primary : palette.outline,
            ),
          ),
          child: Text(
            label,
            style:
                textStyle ??
                Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? palette.primary
                      : palette.onSurface.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class AppDisclosureRow extends StatelessWidget {
  const AppDisclosureRow({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final content = Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: palette.textMuted),
        ],
      ],
    );
    if (onTap == null) {
      return content;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      ),
    );
  }
}

class AppPrimaryBottomButton extends StatelessWidget {
  const AppPrimaryBottomButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: palette.primary,
        foregroundColor: palette.onPrimary,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: palette.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.label,
    this.required = false,
  });

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: palette.onSurface,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        Text(label, style: style),
        if (required) Text(' *', style: style?.copyWith(color: palette.error)),
      ],
    );
  }
}

class AppSectionHeaderRow extends StatelessWidget {
  const AppSectionHeaderRow({
    super.key,
    required this.title,
    required this.trailing,
    this.icon,
  });

  final String title;
  final String trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            color: palette.onSurface.withValues(alpha: 0.78),
            size: 20,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: palette.onSurface,
            ),
          ),
        ),
        Text(
          trailing,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: palette.textMuted),
      ],
    );
  }
}

class AppSelectionRow extends StatelessWidget {
  const AppSelectionRow({
    super.key,
    required this.icon,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: palette.onSurface.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppTagPill extends StatelessWidget {
  const AppTagPill({
    super.key,
    required this.label,
    required this.textColor,
    required this.backgroundColor,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AppInlineChip extends StatelessWidget {
  const AppInlineChip({
    super.key,
    required this.label,
    required this.textColor,
    required this.backgroundColor,
    this.horizontalPadding = 10,
    this.verticalPadding = 3,
    this.borderRadius = 8,
  });

  final String label;
  final Color textColor;
  final Color backgroundColor;
  final double horizontalPadding;
  final double verticalPadding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AppInfoRow extends StatelessWidget {
  const AppInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.onSurface.withValues(alpha: 0.78),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class AppSortTriggerButton extends StatelessWidget {
  const AppSortTriggerButton({
    super.key,
    required this.label,
    required this.onTap,
    this.leadingIcon = Icons.swap_vert_rounded,
  });

  final String label;
  final VoidCallback onTap;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(leadingIcon, size: 18, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPopupMenuRow extends StatelessWidget {
  const AppPopupMenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.textStyle,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final TextStyle? textStyle;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor ?? palette.textMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: textStyle)),
        ],
      ),
    );
  }
}

class AppStateEmptyCard extends StatelessWidget {
  const AppStateEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.outlineSoft, palette.outline],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: palette.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class AppStateErrorCard extends StatelessWidget {
  const AppStateErrorCard({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
    this.icon = Icons.cloud_off_rounded,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: palette.errorContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 28, color: palette.error),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: () => onPressed(),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class AppCenteredLoadingState extends StatelessWidget {
  const AppCenteredLoadingState({super.key, this.strokeWidth = 3});

  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(strokeWidth: strokeWidth));
  }
}

class AppSkeletonBar extends StatelessWidget {
  const AppSkeletonBar({
    super.key,
    required this.widthFactor,
    this.height = 14,
    this.borderRadius,
  });

  final double widthFactor;
  final double height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: AppBreathingPlaceholder(
        borderRadius: borderRadius ?? BorderRadius.circular(999),
        child: SizedBox(height: height),
      ),
    );
  }
}

class AppBreathingPlaceholder extends StatefulWidget {
  const AppBreathingPlaceholder({
    super.key,
    required this.child,
    required this.borderRadius,
  });

  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<AppBreathingPlaceholder> createState() =>
      _AppBreathingPlaceholderState();
}

class _AppBreathingPlaceholderState extends State<AppBreathingPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = _controller.value;
        final begin = Alignment(-1.8 + (2.6 * progress), 0);
        final end = Alignment(-0.8 + (2.6 * progress), 0);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [
                palette.outlineSoft.withValues(alpha: 0.95),
                palette.surface.withValues(alpha: 0.92),
                palette.outlineSoft.withValues(alpha: 0.95),
              ],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class AppSheetContainer extends StatelessWidget {
  const AppSheetContainer({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeScope.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      child: Material(
        color: palette.surface,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: padding ?? const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: child,
        ),
      ),
    );
  }
}
