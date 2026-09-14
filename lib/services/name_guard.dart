/// 远端命令参数白名单，避免把用户输入拼进 shell。
class NameGuard {
  static final RegExp unit = RegExp(r'^[A-Za-z0-9:_.@\\-]{1,128}$');
  static final RegExp dockerName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
  static final RegExp imageRef = RegExp(
    r'^[A-Za-z0-9._\-/:%]{1,256}$',
  );

  static void unitName(String value) {
    if (!unit.hasMatch(value) || value.contains('..')) {
      throw FormatException('非法的 systemd 单元名');
    }
  }

  static void container(String value) {
    if (!dockerName.hasMatch(value)) {
      throw FormatException('非法的容器名或 ID');
    }
  }

  static void image(String value) {
    if (!imageRef.hasMatch(value) ||
        value.contains('..') ||
        value.contains('//')) {
      throw FormatException('非法的镜像引用');
    }
  }
}
