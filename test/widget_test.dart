import 'package:flutter_test/flutter_test.dart';
import 'package:dakhila_camera/models/student.dart';

void main() {
  test('Student model fromJson and toMap test', () {
    final json = {
      'DAKHILA': 281,
      'STU_NAME': 'আহমেদ হাসান',
      'CLASS_NAME': 'দাখিল ১০ম',
      'FORIK_NO': 1,
      'FATHER_NAME': 'করিম মিয়া',
      'DAKHILA_YEAR': 2025,
    };

    final student = Student.fromJson(json);

    expect(student.dakhila, '281');
    expect(student.stuName, 'আহমেদ হাসান');
    expect(student.className, 'দাখিল ১০ম');
    expect(student.forikNo, '1');
    expect(student.fatherName, 'করিম মিয়া');
    expect(student.isCaptured, 0);

    final map = student.toMap();
    expect(map['dakhila'], '281');
    expect(map['stu_name'], 'আহমেদ হাসান');
    expect(map['is_captured'], 0);
  });

  test('fromJson handles missing and null fields gracefully', () {
    final student = Student.fromJson({
      'DAKHILA': null,
      'STU_NAME': null,
    });

    expect(student.dakhila, '');
    expect(student.stuName, '');
    expect(student.className, '');
    expect(student.forikNo, '');
    expect(student.fatherName, '');
    expect(student.dakhilaYear, '2025'); // default year
    expect(student.isCaptured, 0);
    expect(student.imagePath, isNull);
  });

  test('toMap stores captured state and image path', () {
    final student = Student.fromJson({
      'DAKHILA': '999',
      'STU_NAME': 'টেস্ট শিক্ষার্থী',
    })
      ..imagePath = '/tmp/999.jpg'
      ..isCaptured = 1;

    final map = student.toMap();
    expect(map['image_path'], '/tmp/999.jpg');
    expect(map['is_captured'], 1);
  });

  test('parseJsonToMaps converts a raw JSON list into DB maps', () {
    const raw = '''
    [
      {"DAKHILA": 1, "STU_NAME": "ক", "DAKHILA_YEAR": "2025"},
      {"DAKHILA": 2, "STU_NAME": "খ", "DAKHILA_YEAR": "2025"}
    ]
    ''';

    final maps = Student.parseJsonToMaps(raw);

    expect(maps.length, 2);
    expect(maps[0]['dakhila'], '1');
    expect(maps[1]['stu_name'], 'খ');
  });
}
