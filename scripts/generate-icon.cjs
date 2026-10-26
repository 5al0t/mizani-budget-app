// Original geometric app icon; opaque PNG, generated without external dependencies.
const fs = require('node:fs'), path = require('node:path'), zlib = require('node:zlib');
const size = 1024, stride = size * 3 + 1, raw = Buffer.alloc(stride * size);
function roundRect(x, y, l, t, w, h, r) {
  const dx = Math.max(l + r - x, 0, x - (l + w - r)), dy = Math.max(t + r - y, 0, y - (t + h - r));
  return x >= l && x <= l + w && y >= t && y <= t + h && dx * dx + dy * dy <= r * r;
}
for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
  const k = (x + y) / (size * 2), color = [8 + 3 * k, 44 + 68 * k, 43 + 53 * k];
  if ((x - 746) ** 2 + (y - 253) ** 2 < 91 ** 2) color.splice(0, 3, 232, 194, 134);
  if (roundRect(x, y, 208, 210, 142, 552, 35) || roundRect(x, y, 441, 368, 142, 394, 35) || roundRect(x, y, 674, 526, 142, 236, 35)) color.splice(0, 3, 238, 247, 243);
  const i = y * stride + 1 + x * 3; raw[i] = color[0]; raw[i + 1] = color[1]; raw[i + 2] = color[2];
}
const crc = b => { let c = 0xffffffff; for (const v of b) { c ^= v; for (let j = 0; j < 8; j++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); } return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const t = Buffer.from(type), n = Buffer.alloc(4), check = Buffer.alloc(4); n.writeUInt32BE(data.length); check.writeUInt32BE(crc(Buffer.concat([t, data]))); return Buffer.concat([n, t, data, check]); };
const head = Buffer.alloc(13); head.writeUInt32BE(size); head.writeUInt32BE(size, 4); head[8] = 8; head[9] = 2;
const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', head), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
const folder = path.resolve(__dirname, '../Mizani/Resources/Assets.xcassets/AppIcon.appiconset'); fs.mkdirSync(folder, { recursive: true });
fs.writeFileSync(path.join(folder, 'AppIcon.png'), png);
fs.writeFileSync(path.join(folder, 'Contents.json'), JSON.stringify({ images: [{ filename: 'AppIcon.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }], info: { author: 'xcode', version: 1 } }, null, 2));
fs.writeFileSync(path.join(folder, '../Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2));
console.log('Generated 1024px RGB app icon.');
