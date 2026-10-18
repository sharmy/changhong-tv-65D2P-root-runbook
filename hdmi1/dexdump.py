#!/usr/bin/env python3
# 极简 DEX 反汇编器（纯标准库）：只为看清方法里用到的字符串常量与调用
import sys, struct

class Dex:
    def __init__(self, data):
        self.d = data
        assert data[:4] == b'dex\n', 'not dex'
        h = data
        (self.map_off, self.str_size, self.str_off, self.type_size, self.type_off,
         self.proto_size, self.proto_off, self.field_size, self.field_off,
         self.method_size, self.method_off, self.class_size, self.class_off) = struct.unpack_from('<13I', h, 0x34)
        self.strings = [self._str_at(i) for i in range(self.str_size)]
        self.types = [self.strings[struct.unpack_from('<I', data, self.type_off + 4*i)[0]] for i in range(self.type_size)]
        self.methods = []
        for i in range(self.method_size):
            c, p, n = struct.unpack_from('<HHI', data, self.method_off + 8*i)
            self.methods.append((self.types[c], self.strings[n], p))
        self.fields = []
        for i in range(self.field_size):
            c, t, n = struct.unpack_from('<HHI', data, self.field_off + 8*i)
            self.fields.append((self.types[c], self.strings[n], self.types[t]))

    def _uleb(self, off):
        r = 0; s = 0
        while True:
            b = self.d[off]; off += 1
            r |= (b & 0x7f) << s
            if not (b & 0x80): break
            s += 7
        return r, off

    def _str_at(self, i):
        off = struct.unpack_from('<I', self.d, self.str_off + 4*i)[0]
        n, off = self._uleb(off)
        return self.d[off:off+n].decode('utf-8', 'replace')

    def classes(self):
        for i in range(self.class_size):
            idx, acc, sup, ifo, sfo, ano, cdo, svo = struct.unpack_from('<8I', self.d, self.class_off + 32*i)
            yield i, self.types[idx], cdo

    def class_methods(self, cdo):
        if cdo == 0: return []
        off = cdo
        sf, off = self._uleb(off); inf, off = self._uleb(off)
        dm, off = self._uleb(off); vm, off = self._uleb(off)
        out = []
        prev = 0
        for _ in range(sf): 
            _, off = self._uleb(off); _, off = self._uleb(off)
        prev = 0
        for _ in range(inf):
            _, off = self._uleb(off); _, off = self._uleb(off)
        prev = 0
        for _ in range(dm):
            d, off = self._uleb(off); a, off = self._uleb(off); c, off = self._uleb(off)
            prev += d; out.append((self.methods[prev], a, c, 'direct'))
        prev = 0
        for _ in range(vm):
            d, off = self._uleb(off); a, off = self._uleb(off); c, off = self._uleb(off)
            prev += d; out.append((self.methods[prev], a, c, 'virtual'))
        return out

    def code(self, code_off):
        (regs, ins, outs, tries, dbg, insns_size) = struct.unpack_from('<4HII', self.d, code_off)
        insns = struct.unpack_from('<%dH' % insns_size, self.d, code_off + 16)
        return regs, insns

NAMES = {
 0x01:'move',0x02:'move/from16',0x03:'move/16',0x04:'move-wide',0x05:'move-wide/from16',
 0x06:'move-wide/16',0x07:'move-object',0x08:'move-object/from16',0x09:'move-object/16',
 0x0a:'move-result',0x0b:'move-result-wide',0x0c:'move-result-object',0x0d:'move-exception',
 0x0e:'return-void',0x0f:'return',0x10:'return-wide',0x11:'return-object',
 0x12:'const/4',0x13:'const/16',0x14:'const',0x15:'const/high16',0x16:'const-wide/16',
 0x17:'const-wide/32',0x18:'const-wide',0x19:'const-wide/high16',
 0x1a:'const-string',0x1b:'const-string/jumbo',0x1c:'const-class',
 0x1d:'monitor-enter',0x1e:'monitor-exit',0x1f:'check-cast',0x20:'instance-of',
 0x21:'array-length',0x22:'new-instance',0x23:'new-array',0x24:'filled-new-array',
 0x25:'filled-new-array/range',0x26:'fill-array-data',0x27:'throw',
 0x28:'goto',0x29:'goto/16',0x2a:'goto/32',0x2b:'packed-switch',0x2c:'sparse-switch',
 0x0e:'return-void',
}
for i,n in enumerate(['cmpl-float','cmpg-float','cmpl-double','cmpg-double','cmp-long']):
    NAMES[0x2d+i] = n
for i,n in enumerate(['if-eq','if-ne','if-lt','if-ge','if-gt','if-le']):
    NAMES[0x32+i] = n
for i,n in enumerate(['if-eqz','if-nez','if-ltz','if-gez','if-gtz','if-lez']):
    NAMES[0x38+i] = n
for i,n in enumerate(['aget','aget-wide','aget-object','aget-boolean','aget-byte','aget-char','aget-short',
                      'aput','aput-wide','aput-object','aput-boolean','aput-byte','aput-char','aput-short']):
    NAMES[0x44+i] = n
for i,n in enumerate(['iget','iget-wide','iget-object','iget-boolean','iget-byte','iget-char','iget-short',
                      'iput','iput-wide','iput-object','iput-boolean','iput-byte','iput-char','iput-short']):
    NAMES[0x52+i] = n
for i,n in enumerate(['sget','sget-wide','sget-object','sget-boolean','sget-byte','sget-char','sget-short',
                      'sput','sput-wide','sput-object','sput-boolean','sput-byte','sput-char','sput-short']):
    NAMES[0x60+i] = n
for i,n in enumerate(['invoke-virtual','invoke-super','invoke-direct','invoke-static','invoke-interface']):
    NAMES[0x6e+i] = n
for i,n in enumerate(['invoke-virtual/range','invoke-super/range','invoke-direct/range','invoke-static/range','invoke-interface/range']):
    NAMES[0x74+i] = n
for i,n in enumerate(['neg-int','not-int','neg-long','not-long','neg-float','neg-double',
                      'int-to-long','int-to-float','int-to-double','long-to-int','long-to-float','long-to-double',
                      'float-to-int','float-to-long','float-to-double','double-to-int','double-to-long','double-to-float',
                      'int-to-byte','int-to-char','int-to-short']):
    NAMES[0x7b+i] = n
for i,n in enumerate(['add-int','sub-int','mul-int','div-int','rem-int','and-int','or-int','xor-int','shl-int','shr-int','ushr-int']):
    NAMES[0x90+i] = n
for i,n in enumerate(['add-long','sub-long','mul-long','div-long','rem-long','and-long','or-long','xor-long','shl-long','shr-long','ushr-long',
                      'add-float','sub-float','mul-float','div-float','rem-float','add-double','sub-double','mul-double','div-double','rem-double']):
    NAMES[0x9b+i] = n

def dis(dex, code_off, filt=None):
    if code_off == 0: return []
    regs, insns = dex.code(code_off)
    out = []
    pc = 0
    n = len(insns)
    skip = set()
    while pc < n:
        if pc in skip:
            pc += 1; continue
        start = pc
        w = insns[pc]; op = w & 0xff
        nm = NAMES.get(op, 'op%02x' % op)
        a = (w >> 8) & 0xff
        txt = ''
        if op in (0x1a, 0x1f, 0x22, 0x1c):
            b = insns[pc+1]; txt = 'v%d, %s' % (a, dex.strings[b] if op in (0x1a,) else dex.types[b]); pc += 2
        elif op == 0x1b:
            txt = 'v%d, "%s"' % (a, dex.strings[insns[pc+1] | (insns[pc+2] << 16)]); pc += 3
        elif 0x60 <= op <= 0x6d:
            f = dex.fields[insns[pc+1]]; txt = 'v%d, %s.%s:%s' % (a, f[0], f[1], f[2]); pc += 2
        elif 0x52 <= op <= 0x5f:
            b = w >> 12; f = dex.fields[insns[pc+1]]
            txt = 'v%d, v%d, %s.%s:%s' % (b & 0xf, a, f[0], f[1], f[2]) if op < 0x59 else 'v%d, v%d, %s.%s:%s' % (a, b & 0xf, f[0], f[1], f[2])
            pc += 2
        elif op == 0x20 or op == 0x23:
            b = w >> 12; txt = 'v%d, v%d, %s' % (b & 0xf, a, dex.types[insns[pc+1]]); pc += 2
        elif 0x6e <= op <= 0x72:
            cnt = (a >> 4) & 0xf; args = a & 0xf; idx = insns[pc+1]
            m = dex.methods[idx]
            if args == 0: al = ''
            elif args == 1: al = 'v%d' % (insns[pc+2] & 0xf)
            elif args == 2: al = 'v%d, v%d' % (insns[pc+2] & 0xf, insns[pc+2] >> 4)
            elif args == 3: al = 'v%d, v%d, v%d' % (insns[pc+2] & 0xf, (insns[pc+2] >> 4) & 0xf, insns[pc+2] >> 8)
            elif args == 4: al = 'v%d, v%d, v%d, v%d' % (insns[pc+2] & 0xf, (insns[pc+2] >> 4) & 0xf, (insns[pc+2] >> 8) & 0xf, insns[pc+2] >> 12)
            else:
                al = 'v%d..' % (insns[pc+2] & 0xf)
            txt = '{%s}, %s.%s' % (al, m[0], m[1]); pc += 3
        elif 0x74 <= op <= 0x78:
            m = dex.methods[insns[pc+1]]
            txt = '{v%d..v%d}, %s.%s' % (insns[pc+2], insns[pc+2] + (a & 0xff) - 1, m[0], m[1]); pc += 3
        elif 0x32 <= op <= 0x37:
            txt = 'v%d, v%d, %+d' % (w >> 12, a, struct.unpack('<h', struct.pack('<H', insns[pc+1]))[0]); pc += 2
        elif 0x38 <= op <= 0x3d:
            txt = 'v%d, %+d' % (a, struct.unpack('<h', struct.pack('<H', insns[pc+1]))[0]); pc += 2
        elif op in (0x28,):
            txt = '%+d' % struct.unpack('<b', struct.pack('<B', (w >> 8) & 0xff))[0]; pc += 1
        elif op in (0x29,):
            txt = '%+d' % struct.unpack('<h', struct.pack('<H', insns[pc+1]))[0]; pc += 2
        elif op in (0x12,):
            txt = 'v%d, %d' % (a & 0xf, ((w >> 12) & 0xf) - 8 if False else struct.unpack('<b', struct.pack('<B', (w >> 12) & 0xf))[0] if ((w>>12)&0x8) else ((w>>12)&0xf)); pc += 1
        elif op in (0x13, 0x15, 0x16, 0x19):
            txt = 'v%d, %d' % (a, struct.unpack('<h', struct.pack('<H', insns[pc+1]))[0]); pc += 2
        elif op in (0x14, 0x17):
            txt = 'v%d, %d' % (a, insns[pc+1] | (insns[pc+2] << 16)); pc += 3
        elif op == 0x18:
            v = insns[pc+1] | (insns[pc+2] << 16) | (insns[pc+3] << 32) | (insns[pc+4] << 48)
            txt = 'v%d, %d' % (a, v); pc += 5
        elif op in (0x0a,0x0b,0x0c,0x0d,0x0f,0x10,0x11,0x1d,0x1e,0x27):
            txt = 'v%d' % a; pc += 1
        elif op == 0x0e:
            txt = ''; pc += 1
        elif op in range(0x01, 0x0a) or op in (0x21,):
            txt = 'v%d, v%d' % (a, (w >> 12) & 0xff) if op not in (0x02,0x05,0x08) else 'v%d, v%d' % (a, insns[pc+1])
            if op in (0x02,0x05,0x08,0x03,0x06,0x09): pc += 2
            else: pc += 1
        elif 0x44 <= op <= 0x51 or 0x2d <= op <= 0x31:
            txt = 'v%d, v%d, v%d' % (a, (w >> 12) & 0xf, insns[pc+1] & 0xf) if op < 0x4b else 'v%d, v%d, v%d' % ((w >> 12) & 0xf, a, insns[pc+1] & 0xf)
            pc += 2
        elif 0xd0 <= op <= 0xd7:
            txt = 'v%d, v%d, %d' % (w >> 12, a, struct.unpack('<h', struct.pack('<H', insns[pc+1]))[0]); pc += 2
        elif 0xd8 <= op <= 0xe2:
            txt = 'v%d, v%d, %d' % (w >> 12, a, struct.unpack('<b', struct.pack('<B', (a & 0xff))) [0] if False else struct.unpack('<b', struct.pack('<B', insns[pc+1] & 0xff))[0]); pc += 2
        elif 0x90 <= op <= 0xae or 0x7b <= op <= 0x8f:
            txt = 'v%d, v%d, v%d' % (a, (w >> 12) & 0xf, insns[pc+1] & 0xf); pc += 2
        elif 0xb0 <= op <= 0xcf:
            txt = 'v%d, v%d' % (a, (w >> 12) & 0xf); pc += 1
        elif 0x24 <= op <= 0x25:
            pc += 3; txt = '(array)'
        elif op in (0x26, 0x2b, 0x2c):
            off = struct.unpack('<i', struct.pack('<I', insns[pc+1] | (insns[pc+2] << 16)))[0]
            txt = 'v%d, payload@%04x' % (a, start + off)
            pl = start + off
            if op == 0x2c:
                ident = insns[pl]; size = insns[pl+1]
                keys = [insns[pl+2+k] | (insns[pl+3+k] << 16) for k in range(0, size*2, 2)]
                base = pl + 2 + size*2
                tgts = [struct.unpack('<i', struct.pack('<I', insns[base+k] | (insns[base+1+k] << 16)))[0] for k in range(0, size*2, 2)]
                for k, t in zip(keys, tgts):
                    out.append('       [case %d -> %04x]' % (struct.unpack('<i', struct.pack('<I', k))[0] if False else k, start + t))
                skip.update(range(pl, base + size*2))
            elif op == 0x2b:
                ident = insns[pl]; size = insns[pl+1]
                first = insns[pl+2] | (insns[pl+3] << 16)
                base = pl + 4
                for k in range(size):
                    t = struct.unpack('<i', struct.pack('<I', insns[base+2*k] | (insns[base+1+2*k] << 16)))[0]
                    out.append('       [case %d -> %04x]' % (first + k, start + t))
                skip.update(range(pl, base + size*2))
            pc += 3
        else:
            txt = '?'; pc += 1
        out.append('%04x  %-24s %s' % (start, nm, txt))
    return out

if __name__ == '__main__':
    path = sys.argv[1]
    filt = sys.argv[2] if len(sys.argv) > 2 else None
    dex = Dex(open(path, 'rb').read())
    for i, cname, cdo in dex.classes():
        for (m, acc, co, kind) in dex.class_methods(cdo):
            full = '%s.%s' % (m[0], m[1])
            if filt and filt not in full and filt not in cname: continue
            print('### %s  [%s]' % (full, kind))
            try:
                for l in dis(dex, co):
                    print('    ' + l)
            except Exception as e:
                print('    <decode error: %s>' % e)
