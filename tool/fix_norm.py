BLK_END_MARKER = "  /// সংক্ষেপ/রূপভেদ"
p = 'lib/utils/name_transliterator.dart'
lines = open(p, encoding='utf-8').read().split('\n')
s = next(i for i, l in enumerate(lines) if l == 'class NameTransliterator {')
start = s + 2
assert '09DF' in lines[start], repr(lines[start])
e = next(i for i in range(start, len(lines)) if lines[i] == BLK_END_MARKER)
before = [l for l in lines[start:e] if 'containsBengali' in l]
assert len(before) == 2, repr(before)
del lines[start:e]
lines[start:start] = BLK
open(p, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
print('OK new total:', len(lines))
