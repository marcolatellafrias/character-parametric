// Hornea cada artboard de character_face.riv a un PNG en Textures/character/.
//
// POR QUE UN NAVEGADOR HEADLESS: el runtime de Rive para JS dibuja sobre un <canvas>, que en Node no
// existe. Las alternativas son canvas nativos (node-canvas) que en Windows piden toolchain de C++, o
// correr el runtime en un Chromium real. Puppeteer baja su propio Chromium y no compila nada, que es
// lo que lo hace instalable sin dolor.
//
// EL NOMBRE DEL ARTBOARD ES EL NOMBRE DEL PNG, y ese es el nombre de la malla en el .glb. La cadena
// Blender -> Rive -> Godot se sostiene sola con esa convencion: no hay tabla que mantener en ningun
// lado. Ver CharacterAppearance._source_texture.
//
// EL TAMANO SALE DEL PROPIO ARTBOARD, no de una lista aca. Si en Rive lo redimensionas, el PNG sale
// con el tamano nuevo sin tocar codigo — que es la misma razon por la que Godot mide los huesos del
// modelo en vez de tener constantes.

const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer');

const ROOT = path.resolve(__dirname, '..', '..');
const RIV = path.join(ROOT, 'Art', 'rive', 'character_face.riv');
const OUT = path.join(ROOT, 'Textures', 'character');

// Los artboards a hornear. Tienen que estar marcados como COMPONENTE en Rive (Shift+N) o no viajan
// dentro del .riv — es silencioso, el archivo simplemente no los trae.
const ARTBOARDS = [
	'forehead_plane_mesh',
	'brows_plane_mesh',
	'eye_plane_mesh',
	'mouth_plane_mesh',
	'chin_plane_mesh',
	'cheekbones_plane_mesh',
	'teartrough_plane_mesh',
	'nose_plane_mesh',
];

// Multiplicador de resolucion sobre el tamano del artboard. 1 = tal cual se autoro.
const SCALE = 1;

async function main() {
	if (!fs.existsSync(RIV)) {
		console.error(`[rive-bake] no existe ${RIV}`);
		process.exit(1);
	}
	fs.mkdirSync(OUT, { recursive: true });

	const riv = fs.readFileSync(RIV).toString('base64');
	const browser = await puppeteer.launch({ headless: 'new' });
	const page = await browser.newPage();

	page.on('console', (m) => console.log('[chromium]', m.text()));

	await page.setContent('<!doctype html><html><body></body></html>');
	await page.addScriptTag({ path: require.resolve('@rive-app/canvas') });

	const results = await page.evaluate(
		async (rivB64, names, scale) => {
			// base64 -> bytes, dentro de la pagina.
			const bin = atob(rivB64);
			const bytes = new Uint8Array(bin.length);
			for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);

			const out = [];
			for (const name of names) {
				try {
					const canvas = document.createElement('canvas');
					document.body.appendChild(canvas);

					const png = await new Promise((resolve, reject) => {
						const r = new rive.Rive({
							buffer: bytes.buffer,
							canvas: canvas,
							artboard: name,
							autoplay: false,
							onLoad: () => {
								// El tamano nativo del artboard. `bounds` es {minX,minY,maxX,maxY}.
								const b = r.bounds;
								const w = Math.max(1, Math.round((b.maxX - b.minX) * scale));
								const h = Math.max(1, Math.round((b.maxY - b.minY) * scale));
								canvas.width = w;
								canvas.height = h;
								r.resizeDrawingSurfaceToCanvas();
								// Un frame: son estaticos por ahora. Cuando animemos, aca se elige el
								// tiempo y se hornea una tira de frames.
								r.drawFrame();
								requestAnimationFrame(() => {
									resolve({ name, w, h, data: canvas.toDataURL('image/png') });
								});
							},
							onLoadError: (e) => reject(new Error(String(e))),
						});
					});
					out.push(png);
				} catch (e) {
					out.push({ name, error: String(e) });
				}
			}
			return out;
		},
		riv,
		ARTBOARDS,
		SCALE
	);

	await browser.close();

	let ok = 0;
	for (const r of results) {
		if (r.error || !r.data) {
			console.error(`[rive-bake] FALLO  ${r.name}: ${r.error || 'sin datos'}`);
			continue;
		}
		const file = path.join(OUT, `${r.name}.png`);
		fs.writeFileSync(file, Buffer.from(r.data.split(',')[1], 'base64'));
		console.log(`[rive-bake] ${r.name}.png  ${r.w}x${r.h}`);
		ok++;
	}
	console.log(`[rive-bake] ${ok}/${ARTBOARDS.length} horneados en Textures/character/`);
	if (ok === 0) process.exit(1);
}

main().catch((e) => {
	console.error('[rive-bake]', e);
	process.exit(1);
});
