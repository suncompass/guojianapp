import 'package:flutter/material.dart';

/// 兜底的组件错误展示。
///
/// 框架默认在发布版把构建失败的组件换成 [RenderErrorBox]：纯灰色、不带任何文字，
/// 而且在无限高约束下（例如列表子项）会撑到 100000 逻辑像素高，把整页变成一大块灰。
/// 这里改成有界、可读的卡片，始终带出异常信息，便于用户直接反馈问题。
class AppErrorTile extends StatelessWidget {
  const AppErrorTile({
    super.key,
    required this.message,
    this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  static const maxHeight = 320.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          border: Border.all(color: colors.error.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.report_gmailerrorred_outlined,
                    size: compact ? 18 : 20,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '这部分内容暂时无法显示',
                      style: (compact ? text.bodySmall : text.bodyMedium)
                          ?.copyWith(
                            color: colors.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    message.trim().isEmpty ? '未知错误' : message.trim(),
                    textDirection: TextDirection.ltr,
                    style: (compact ? text.bodySmall : text.bodyMedium)
                        ?.copyWith(color: colors.onErrorContainer),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把框架的兜底错误组件换成有界卡片，避免发布版出现整屏灰块。
void installErrorWidget() {
  ErrorWidget.builder = (FlutterErrorDetails details) =>
      AppErrorTile(message: describeErrorForDisplay(details), compact: true);
}

String describeErrorForDisplay(FlutterErrorDetails details) {
  final exception = details.exception;
  if (exception is FlutterError) {
    return exception.message;
  }
  try {
    final text = '$exception';
    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  } on Object {
    return '未知错误';
  }
}
