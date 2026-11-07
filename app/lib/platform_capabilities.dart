import 'package:flutter/foundation.dart';

/// What this device can do on its own, as opposed to what a remote host
/// offers over the network.
///
/// iOS is a remote client only: no on-device engine, no bundled rootfs, no
/// phone control (docs/roadmap.md「iOS：只做远程客户端」). Everything else keeps
/// what it had — Android runs DSH from its bundled rootfs — so this file
/// names iOS alone instead of allow-listing Android, which would also strip the
/// runtime from desktop hosts and from `flutter test` (that runs as the host
/// platform).
abstract final class PlatformCapabilities {
  static bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Whether DSH runs on this device: install, start, stop, logs, footprint.
  /// Gate every local-runtime entry point (安装, 运行环境, 引擎, 后台保活) on it.
  static bool get localRuntime => !_isIOS;

  /// Whether the native 手机操控 bridge (`dsh/phone`) exists here.
  static bool get phoneControl => localRuntime;
}
