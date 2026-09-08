/**
 * Renders one 1200x630 social card per page.
 *
 * There is no image toolchain on this machine beyond `sips`, which cannot
 * draw text. So the cards are drawn in a real browser canvas: this script
 * serves the drawing page and a manifest, the page renders every card and
 * POSTs each PNG back, and this script writes them to build/web/static/og/.
 *
 *   node seo/build.mjs        # writes the manifest inputs
 *   node seo/og.mjs           # then open the printed URL in a browser
 *
 * `npm run seo:og` does the same. The server exits once every card is in.
 */

import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { site } from './site.mjs';
import home from './pages/home.mjs';
import features from './pages/features.mjs';
import tools from './pages/tools.mjs';
import blog1 from './pages/blog.mjs';
import blog2 from './pages/blog2.mjs';
import misc from './pages/misc.mjs';
import glossary from './pages/glossary.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
/* Written to seo/assets/og, not build/, because `flutter clean` wipes build/
   on every deploy and re-rendering needs a browser. build.mjs copies them in. */
const OUT = path.join(ROOT, 'seo', 'assets', 'og');
fs.mkdirSync(OUT, { recursive: true });

const pages = [...home, ...features, ...tools, ...blog1, ...blog2, ...misc, ...glossary];

const ogSlug = (p) => (p === '/' ? 'default' : p.replace(/^\/|\/$/g, '').replace(/\//g, '-'));

/** The site's own section vocabulary, so a card says what kind of page it is. */
const kickerFor = (p) =>
  p === '/' ? 'Inventory management software'
  : p.startsWith('/tools/') ? 'Free calculator'
  : p === '/tools' ? 'Free tools'
  : p.startsWith('/blog/') ? 'Guide'
  : p === '/blog' ? 'Guides'
  : p.startsWith('/features/') ? 'Feature'
  : p === '/features' ? 'Features'
  : p.startsWith('/compare/') ? 'Comparison'
  : p === '/pricing' ? 'Pricing'
  : p === '/glossary' ? 'Reference'
  : 'SmartShelfKart';

/* The <title> is written for a search result and ends in the brand name; the
   card already shows the brand, so strip it rather than saying it twice. */
const cardTitle = (p) =>
  (p.ogTitle || p.title)
    .replace(/\s*[|—–-]\s*SmartShelfKart\s*$/i, '')
    .replace(/\s*\(Free[^)]*\)\s*$/i, '')
    .trim();

const cards = pages
  .filter((p) => !p.noindex)
  .map((p) => ({ slug: ogSlug(p.path), kicker: kickerFor(p.path), title: cardTitle(p) }));

const PAGE = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>rendering…</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Sora:wght@600;800&family=IBM+Plex+Mono:wght@500&display=block">
<style>body{margin:0;background:#0b1413;color:#cfe;font:14px/1.5 system-ui;padding:20px}
canvas{width:420px;height:auto;border-radius:8px;margin:8px 8px 0 0;vertical-align:top}</style>
</head><body><p id="status">starting…</p><div id="out"></div><script>
const W=1200,H=630;
const log=(m)=>{document.getElementById('status').textContent=m;document.title=m;};

function roundRect(c,x,y,w,h,r){c.beginPath();c.moveTo(x+r,y);c.arcTo(x+w,y,x+w,y+h,r);
  c.arcTo(x+w,y+h,x,y+h,r);c.arcTo(x,y+h,x,y,r);c.arcTo(x,y,x+w,y,r);c.closePath();}

function wrap(c,text,maxW){
  const words=text.split(/\\s+/);const lines=[];let line='';
  for(const w of words){const t=line?line+' '+w:w;
    if(c.measureText(t).width>maxW&&line){lines.push(line);line=w;}else{line=t;}}
  if(line)lines.push(line);return lines;
}

async function draw(card,logo){
  const cv=document.createElement('canvas');cv.width=W;cv.height=H;
  const c=cv.getContext('2d');

  // ground: the brand gradient, deepest at the top-left where the logo sits
  const g=c.createLinearGradient(0,0,W,H);
  g.addColorStop(0,'#053f39');g.addColorStop(.52,'#0b7b70');g.addColorStop(1,'#0e93aa');
  c.fillStyle=g;c.fillRect(0,0,W,H);

  // the swoosh from the app icon, as a wide soft arc across the lower right
  c.save();c.globalAlpha=.16;c.strokeStyle='#7ff0ff';c.lineWidth=54;c.lineCap='round';
  c.beginPath();c.moveTo(-60,600);c.bezierCurveTo(340,760,900,470,1290,238);c.stroke();
  c.globalAlpha=.10;c.lineWidth=22;
  c.beginPath();c.moveTo(-60,672);c.bezierCurveTo(360,830,940,540,1290,310);c.stroke();
  c.restore();

  // top-left: logo + wordmark
  c.save();roundRect(c,72,64,84,84,20);c.clip();c.drawImage(logo,72,64,84,84);c.restore();
  c.fillStyle='#ffffff';c.font='700 33px Sora, sans-serif';c.textBaseline='alphabetic';
  c.fillText('SmartShelfKart',176,118);

  // kicker
  c.fillStyle='rgba(190,245,255,.92)';c.font='500 20px "IBM Plex Mono", monospace';
  c.fillText(card.kicker.toUpperCase(),74,222);
  c.fillStyle='rgba(150,235,255,.55)';c.fillRect(74,238,64,3);

  // title — size steps down until it fits three lines
  const maxW=1052;let size=76,lines=[];
  for(;size>=40;size-=4){
    c.font='800 '+size+'px Sora, sans-serif';
    lines=wrap(c,card.title,maxW);
    if(lines.length<=3)break;
  }
  c.fillStyle='#ffffff';
  const lh=size*1.16;
  let y=300+size*0.82;
  if(lines.length===1)y+=lh*0.5;
  for(const l of lines.slice(0,3)){c.fillText(l,74,y);y+=lh;}

  // footer rule + domain
  c.fillStyle='rgba(255,255,255,.22)';c.fillRect(74,H-96,1052,1);
  c.fillStyle='rgba(215,250,255,.9)';c.font='500 22px "IBM Plex Mono", monospace';
  c.fillText('smartshelfkart.com',74,H-52);
  c.fillStyle='rgba(215,250,255,.62)';c.font='600 21px Sora, sans-serif';
  const rt='Free on every plan during launch';
  c.fillText(rt,1126-c.measureText(rt).width,H-52);

  const blob=await new Promise(r=>cv.toBlob(r,'image/jpeg',0.88));
  await fetch('/save?slug='+encodeURIComponent(card.slug),{method:'POST',body:blob});
  cv.style.width='260px';document.getElementById('out').appendChild(cv);
}

(async()=>{
  try{
    const cards=await (await fetch('/cards.json')).json();
    const logo=new Image();logo.src='/logo.png';
    await logo.decode();
    await document.fonts.load('800 76px Sora');
    await document.fonts.load('500 22px "IBM Plex Mono"');
    await document.fonts.ready;
    for(let i=0;i<cards.length;i++){log('rendering '+(i+1)+'/'+cards.length);await draw(cards[i],logo);}
    await fetch('/done',{method:'POST'});
    log('DONE '+cards.length);
  }catch(e){log('ERROR '+e.message);}
})();
</script></body></html>`;

let saved = 0;
const server = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://localhost');
  if (u.pathname === '/card') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(PAGE);
  }
  if (u.pathname === '/cards.json') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify(cards));
  }
  if (u.pathname === '/logo.png') {
    res.writeHead(200, { 'Content-Type': 'image/png' }); // the logo source stays PNG (alpha)
    return res.end(fs.readFileSync(path.join(ROOT, 'seo', 'assets', 'logo-256.png')));
  }
  if (u.pathname === '/save' && req.method === 'POST') {
    const slug = u.searchParams.get('slug');
    const chunks = [];
    req.on('data', (d) => chunks.push(d));
    req.on('end', () => {
      const buf = Buffer.concat(chunks);
      fs.writeFileSync(path.join(OUT, slug + '.jpg'), buf);
      saved++;
      console.log(`  ${String(saved).padStart(2)}/${cards.length}  ${slug}.jpg  ${(buf.length / 1024).toFixed(0)} KB`);
      res.writeHead(204).end();
    });
    return;
  }
  if (u.pathname === '/done') {
    res.writeHead(204).end();
    console.log(`\nDone. ${saved} cards written to seo/assets/og/ — run \`npm run seo\` to copy them into the build.`);
    setTimeout(() => { server.close(); process.exit(saved === cards.length ? 0 : 1); }, 120);
    return;
  }
  res.writeHead(404).end();
});

server.listen(0, '127.0.0.1', () => {
  const { port } = server.address();
  console.log(`Rendering ${cards.length} social cards for ${site.origin}`);
  console.log(`Open: http://127.0.0.1:${port}/card\n`);
});

setTimeout(() => {
  console.error(`Timed out with ${saved}/${cards.length} cards.`);
  process.exit(1);
}, 180000).unref?.();
