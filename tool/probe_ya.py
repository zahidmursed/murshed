import re
t = open('lib/utils/name_transliterator.dart', encoding='utf-8').read()
YA_PRE = chr(0x09DF)
YA_DECOMP = chr(0x09AF) + chr(0x09BC)
print('precomposed 09DF count in file:', t.count(YA_PRE))
print('decomposed YA+nukta count in file:', t.count(YA_DECOMP))
# dict keys containing either form
keys = re.findall(r"'([^']*)': \('", t)
ya_keys = [k for k in keys if YA_PRE in k or YA_DECOMP in k]
print('dict keys with YA:', len(ya_keys))
for k in ya_keys[:20]:
    cps = ' '.join('%04X' % ord(c) for c in k)
    print('  ', k, '<', cps, '>')
print('--- screenshot tokens present in dict? ---')
for tok in ['রাইয়ান', 'রেদোয়ান', 'জুনায়েদ', 'জোনায়ের', 'ফয়সাল', 'সুরুজ',
            'তাওসীফ', 'রায়হান', 'মিয়া', 'জুবায়ের', 'মুন্সী']:
    norm_pre = tok.replace(YA_DECOMP, YA_PRE)
    hit = ("'%s': ('" % tok) in t or ("'%s': ('" % norm_pre) in t
    cps = ' '.join('%04X' % ord(c) for c in tok)
    print('  ', tok, '<', cps, '>', 'dict-hit' if hit else 'MISSING')
