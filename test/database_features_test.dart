import 'package:flutter_test/flutter_test.dart';
import 'package:bridgebox/models/models.dart';

void main() {
  group('Database detection in ServiceUnit', () {
    test('PostgreSQL service correctly identified', () {
      const s = ServiceUnit(
        name: 'postgresql.service',
        load: 'loaded',
        active: 'active',
        sub: 'running',
        description: 'PostgreSQL RDBMS',
        category: '数据库',
      );
      expect(s.isDatabase, isTrue);
      expect(s.databaseType, equals('postgres'));
    });

    test('MySQL service correctly identified', () {
      const s = ServiceUnit(
        name: 'mysql.service',
        load: 'loaded',
        active: 'active',
        sub: 'running',
        description: 'MySQL Community Server',
        category: '数据库',
      );
      expect(s.isDatabase, isTrue);
      expect(s.databaseType, equals('mysql'));
    });

    test('Non-database service not identified as database', () {
      const s = ServiceUnit(
        name: 'nginx.service',
        load: 'loaded',
        active: 'active',
        sub: 'running',
        description: 'A high performance web server',
        category: 'Web / 代理',
      );
      expect(s.isDatabase, isFalse);
    });
  });

  group('Database detection in DockerContainer', () {
    test('Postgres container identified by image and port', () {
      const c = DockerContainer(
        id: 'abc1234567890',
        names: '/postgres-master',
        image: 'postgres:16-alpine',
        status: 'Up 3 hours',
        state: 'running',
        ports: '0.0.0.0:5432->5432/tcp',
      );
      expect(c.isDatabase, isTrue);
      expect(c.databaseType, equals('postgres'));
    });

    test('MySQL container identified by image', () {
      const c = DockerContainer(
        id: 'def1234567890',
        names: '/prod-mysql',
        image: 'mysql:8.0',
        status: 'Up 1 day',
        state: 'running',
        ports: '3306/tcp',
      );
      expect(c.isDatabase, isTrue);
      expect(c.databaseType, equals('mysql'));
    });

    test('Web container not identified as database', () {
      const c = DockerContainer(
        id: 'ghi1234567890',
        names: '/web-ui',
        image: 'nginx:alpine',
        status: 'Up 2 hours',
        state: 'running',
        ports: '0.0.0.0:80->80/tcp',
      );
      expect(c.isDatabase, isFalse);
      expect(c.databaseType, isNull);
    });
  });

  group('DatabaseQueryResult', () {
    test('Tabular data result', () {
      const res = DatabaseQueryResult(
        columns: ['id', 'username', 'email'],
        rows: [
          ['1', 'admin', 'admin@example.com'],
          ['2', 'user', 'user@example.com'],
        ],
        rowCount: 2,
        executionDurationMs: 15,
      );
      expect(res.isTabular, isTrue);
      expect(res.hasError, isFalse);
      expect(res.rowCount, equals(2));
      expect(res.columns.length, equals(3));
    });

    test('Error result', () {
      final res = DatabaseQueryResult.error('relation "non_existent" does not exist');
      expect(res.hasError, isTrue);
      expect(res.isTabular, isFalse);
    });
  });
}
