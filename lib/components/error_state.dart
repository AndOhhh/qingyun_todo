import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

/// 统一错误态（docs/07 §A.1：`AsyncValue.when` 的 error 分支复用本组件）
class ErrorState extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  final String title;

  const ErrorState({
    super.key,
    this.error,
    this.onRetry,
    this.title = '加载失败',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 52,
              color: Color(0xFFFF9500),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              // 详细异常只在 debug 包展示；release 给用户看通用文案（N25）
              kDebugMode ? (error?.toString() ?? '未知错误') : '请稍后重试。',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Color(0xFF8E8E93),
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 18),
              CupertinoButton.filled(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                borderRadius: BorderRadius.circular(18),
                onPressed: onRetry,
                child: const Text('重试', style: TextStyle(fontSize: 14)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
