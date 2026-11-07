// iOS ships as a remote client only: no on-device engine, no phone control
// (docs/roadmap.md「iOS：只做远程客户端」). This checks the split holds where people
// actually see it — 设置 rows, 全部功能 and settings links — while Android keeps
// all of it.

import 'package:dsh_app/platform_capabilities.dart';
import 'package:dsh_app/ui/features/feature_catalog.dart';
import 'package:dsh_app/ui/settings/index/settings_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything this device can reach by its setting ids, as the index hands
/// them out (search, 设置 and the guide all read this).
Set<String> _spotIds() => {for (final spot in SettingsIndex.spots) spot.id};

/// The ids in 全部功能, the phone-control tile included when it exists.
List<String> _featureIds() => [for (final section in featureSections) ...section.items.map((i) => i.id)];

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Android runs the engine and phone control itself', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PlatformCapabilities.localRuntime, isTrue);
    expect(PlatformCapabilities.phoneControl, isTrue);
  });

  test('iOS runs neither', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PlatformCapabilities.localRuntime, isFalse);
    expect(PlatformCapabilities.phoneControl, isFalse);
  });

  test('the engine, 后台保活 and 系统权限 leave 设置 on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final everywhere = _spotIds();
    for (final id in ['page:engine', 'page:background', 'page:systemAccess']) {
      expect(everywhere, contains(id), reason: 'listed on Android');
    }

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final remote = _spotIds();
    for (final id in ['page:engine', 'page:background', 'page:systemAccess']) {
      expect(remote, isNot(contains(id)), reason: id);
    }
  });

  test('手机操控 and its two sub-pages leave 设置 on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final everywhere = _spotIds();
    for (final id in ['page:phone', 'page:phoneAppRules', 'page:phoneDnd', 'page:phoneUnlocks']) {
      expect(everywhere, contains(id), reason: 'listed on Android');
    }

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final remote = _spotIds();
    for (final id in ['page:phone', 'page:phoneAppRules', 'page:phoneDnd', 'page:phoneUnlocks']) {
      expect(remote, isNot(contains(id)), reason: id);
    }
  });

  test('rows that need this phone or its phone control leave 设置 on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final conditional = [
      for (final spot in SettingsIndex.spots)
        if (spot.condition == SpotCondition.localHost || spot.condition == SpotCondition.phoneControlOn) spot.id,
    ];
    expect(conditional, isEmpty, reason: 'no row waits on a host this device cannot be');
  });

  test('远程主机 and the rest of 设置 stay on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final remote = _spotIds();
    expect(remote, contains('page:remote'));
    expect(remote, contains('page:models'));
    expect(remote, contains('page:appearance'));
    expect(remote, isNotEmpty);
  });

  test('手机操控 leaves 全部功能 on iOS, the rest stays', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final everywhere = _featureIds();
    expect(everywhere, contains('phone'));

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final remote = _featureIds();
    expect(remote, isNot(contains('phone')));
    expect(remote, contains('remote'));
    expect(remote, contains('models'));
  });

  test('a link to a page this device lacks opens nothing on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(settingsPageForLink('phone'), isNotNull);
    expect(settingsPageForLink('engine'), isNotNull);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(settingsPageForLink('phone'), isNull);
    expect(settingsPageForLink('engine'), isNull);
    expect(settingsPageForLink('remote'), isNotNull, reason: '远程主机 is how a remote client gets anywhere');
  });
}
