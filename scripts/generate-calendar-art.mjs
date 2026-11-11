import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const output = fileURLToPath(new URL('../harmonyos/resources/base/media/', import.meta.url));
mkdirSync(output, { recursive: true });
const stars = Array.from({ length: 54 }, (_, index) => `<circle cx="${(index * 137 + 43) % 720}" cy="${(index * 71 + 29) % 240}" r="${index % 9 === 0 ? 1.4 : .6}" fill="#c5d5ed" opacity="${.18 + index % 5 * .13}"/>`).join('');
const craters = Array.from({ length: 22 }, (_, index) => {
  const angle = index * 2.399;
  const distance = 13 + (index * 17) % 53;
  return `<circle cx="${560 + Math.cos(angle) * distance}" cy="${120 + Math.sin(angle) * distance}" r="${3 + index % 5 * 2}" fill="#73869f" opacity=".26" stroke="#e3e6e9" stroke-opacity=".12"/>`;
}).join('');
function scene(name, color, art) {
  for (const detail of [false, true]) {
    const width = detail ? 396 : 720;
    const artwork = detail ? `<g transform="translate(254 83) scale(0.78) translate(-560 -120)">${art}</g>` : art;
    writeFileSync(`${output}calendar_${name}${detail ? '_detail' : ''}.svg`, `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="240" viewBox="0 0 ${width} 240"><defs><linearGradient id="sky" x2="1" y2="1"><stop stop-color="#101827"/><stop offset="1" stop-color="${color}"/></linearGradient><radialGradient id="moon" cx=".35" cy=".3"><stop stop-color="#e2e7e9"/><stop offset=".65" stop-color="#abb9cc"/><stop offset="1" stop-color="#6b7c96"/></radialGradient><linearGradient id="trail"><stop stop-color="#b5dfff" stop-opacity="0"/><stop offset="1" stop-color="#eaf5ff"/></linearGradient></defs><rect width="${width}" height="240" fill="url(#sky)"/>${stars}${artwork}<path d="M0 226 Q200 210 380 229 T720 219 V240 H0Z" fill="#080f1d" opacity=".5"/></svg>\n`);
  }
}
for (let phase = 0; phase < 4; phase++) {
  const shade = phase === 0 ? '<circle cx="560" cy="120" r="71" fill="#111c2c"/>' :
    phase === 1 ? '<path d="M560 48 A72 72 0 0 0 560 192Z" fill="#111c2c"/>' :
    phase === 3 ? '<path d="M560 48 A72 72 0 0 1 560 192Z" fill="#111c2c"/>' : '';
  scene(`moon_${phase}`, '#28314a', `<circle cx="560" cy="120" r="86" fill="#b6c8e0" opacity=".025"/><circle cx="560" cy="120" r="72" fill="url(#moon)"/>${craters}${shade}`);
}
scene('meteor', '#152d3a', Array.from({ length: 9 }, (_, index) => `<path d="M${260 + index * 53} ${30 + index % 3 * 65} l75 38" stroke="url(#trail)" stroke-width="${index % 3 === 0 ? 1.7 : .7}"/>`).join(''));
scene('solar', '#33303d', '<circle cx="560" cy="120" r="84" fill="#eacba6" opacity=".035"/><circle cx="560" cy="120" r="62" fill="#bdb39e" opacity=".85"/><ellipse cx="560" cy="120" rx="92" ry="24" fill="none" stroke="#b5c4d9" stroke-opacity=".22" transform="rotate(-25 560 120)"/>');
scene('planet', '#2a263c', '<circle cx="550" cy="116" r="55" fill="#c4ac8d"/><path d="M501 95 Q550 113 600 95 M498 114 Q550 132 604 114 M502 137 Q550 153 598 137" stroke="#8d817c" stroke-width="9" fill="none" opacity=".65"/><circle cx="644" cy="60" r="3" fill="#e4e4ea"/>');
scene('mercury', '#252c39', '<defs><clipPath id="mercury-disc"><circle cx="560" cy="120" r="55"/></clipPath></defs><circle cx="560" cy="120" r="55" fill="#a7a3a0"/><g clip-path="url(#mercury-disc)">' + craters + '<path d="M570 66 A55 55 0 0 1 570 174 Q610 120 570 66" fill="#141c2b" opacity=".6"/></g>');
scene('venus', '#39323b', '<circle cx="560" cy="120" r="61" fill="#cebea4"/><path d="M566 59 A61 61 0 0 1 566 181 Q616 120 566 59" fill="#202333" opacity=".88"/>');
scene('mars', '#3b2635', '<circle cx="560" cy="120" r="58" fill="#bd7c65"/><path d="M515 108 Q547 88 578 116 T607 143 Q572 168 550 144 T515 108" fill="#785858" opacity=".55"/><ellipse cx="553" cy="65" rx="16" ry="4" fill="#d9cdca"/>');
scene('saturn', '#313041', '<ellipse cx="560" cy="120" rx="100" ry="27" fill="none" stroke="#aaa69e" stroke-width="12" opacity=".7" transform="rotate(-25 560 120)"/><circle cx="560" cy="120" r="49" fill="#b9b19c"/><path d="M515 113 Q560 129 605 113" fill="none" stroke="#9f968c" stroke-width="9"/>');
scene('uranus', '#16303c', '<circle cx="560" cy="120" r="55" fill="#94bfca"/><ellipse cx="560" cy="120" rx="71" ry="13" fill="none" stroke="#b6cdd3" stroke-opacity=".25" transform="rotate(65 560 120)"/>');
scene('neptune', '#1f2949', '<circle cx="560" cy="120" r="55" fill="#657fae"/><path d="M510 110 Q560 128 610 110" fill="none" stroke="#4e6593" stroke-width="9"/>');
