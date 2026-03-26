import 'dart:math';
import 'package:flutter/material.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';

class CustomRefresher extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const CustomRefresher({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return CustomRefreshIndicator(
      offsetToArmed: 90,
      trigger: IndicatorTrigger.leadingEdge,
      onRefresh: onRefresh,
      builder: (context, child, controller) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            /// 🔥 Elastic pull effect (feels natural)
            final pull = controller.value;
            final double translateY =
                (sin(pull * pi / 2) * 90) - 30;

            /// 🔥 Smooth scaling
            final double scale = (pull * 1.3).clamp(0.0, 1.0);

            /// 🔥 Dynamic opacity
            final double opacity = controller.isLoading ? 1 : scale;

            /// 🔥 Status text
            String text = "Pull to sync";
            if (controller.isLoading) {
              text = "Syncing database...";
            } else if (controller.isArmed) {
              text = "Release to sync";
            }

            return Stack(
              children: [
                child,

                /// 🔥 Indicator
                Positioned(
                  top: translateY,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Transform.scale(
                        scale: controller.isLoading ? 1 : scale,
                        child: Opacity(
                          opacity: opacity,
                          child: Container(
                            constraints: const BoxConstraints(
                              maxWidth: 260,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF1A1D20),
                                  Color(0xFF23272A),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                /// Glow
                                BoxShadow(
                                  color: const Color(0xFFFFD166)
                                      .withOpacity(0.25),
                                  blurRadius: 20,
                                  spreadRadius: 1,
                                ),

                                /// Depth
                                const BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 10,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                /// 🔄 ICON / LOADER
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, anim) =>
                                      ScaleTransition(scale: anim, child: child),
                                  child: controller.isLoading
                                      ? const SizedBox(
                                          key: ValueKey("loader"),
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Color(0xFFFFD166),
                                          ),
                                        )
                                      : Transform.rotate(
                                          key: const ValueKey("icon"),
                                          angle: pull * 2 * pi,
                                          child: Icon(
                                            controller.isArmed
                                                ? Icons.cloud_upload_rounded
                                                : Icons.sync_rounded,
                                            color: controller.isArmed
                                                ? const Color(0xFFFFD166)
                                                : Colors.white70,
                                            size: 20,
                                          ),
                                        ),
                                ),

                                const SizedBox(width: 10),

                                /// 📝 TEXT
                                Flexible(
                                  child: Text(
                                    text,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: controller.isArmed ||
                                              controller.isLoading
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
      child: child,
    );
  }
}