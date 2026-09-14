import 'package:bridgebox/services/name_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('允许常见 unit / 容器 / 镜像名', () {
    NameGuard.unitName('nginx.service');
    NameGuard.unitName('docker');
    NameGuard.container('anpy-mysql');
    NameGuard.image('nginx:alpine');
    NameGuard.image('ghcr.io/foo/bar:1.2.3');
  });

  test('拒绝危险输入', () {
    expect(() => NameGuard.unitName('nginx; reboot'), throwsFormatException);
    expect(() => NameGuard.container('../etc'), throwsFormatException);
    expect(() => NameGuard.image('nginx && curl evil'), throwsFormatException);
  });
}
