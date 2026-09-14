import 'package:dakhila_camera/models/document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseBulkDocName parses valid names (case-insensitive)', () {
    expect(parseBulkDocName('281_BIRTH.pdf'), ('281', DocType.BIRTH));
    expect(parseBulkDocName('282_form.JPG'), ('282', DocType.FORM));
    expect(parseBulkDocName('1001_photo.jpeg'), ('1001', DocType.PHOTO));
    expect(parseBulkDocName(' 500_PHOTO.png '), ('500', DocType.PHOTO));
  });

  test('invalid names return null', () {
    expect(parseBulkDocName('281.jpg'), isNull); // টাইপ নেই
    expect(parseBulkDocName('281_CERT.pdf'), isNull); // অজানা টাইপ
    expect(parseBulkDocName('abc_BIRTH.pdf'), isNull); // দাখিলা সংখ্যা নয়
    expect(parseBulkDocName('281_BIRTH'), isNull); // ext নেই
  });
}
