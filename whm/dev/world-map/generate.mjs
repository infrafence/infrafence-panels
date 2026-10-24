// Generates plugin/map/world.json and plugin/map/countries.json, the static data of the Overview's
// attack map. Run once, by hand, when the geometry or the country list changes; the output is
// committed and nothing of this runs on a server.
//
//   node dev/world-map/generate.mjs NODE_MODULES COUNTRY_POINTS OUTDIR
//
// NODE_MODULES   a node_modules directory with world-atlas@2.0.2, d3-geo@3.1.1 and
//                topojson-client@3.1.0 (the versions the InfraFence dashboard draws its map with)
// COUNTRY_POINTS a file with lines `XX: ["NNN", lat, lon],` (ISO alpha-2, the ISO numeric id of
//                the country's shape in world-atlas or "", and where its dot goes)
// OUTDIR         plugin/map
//
// world.json: the projection (Equal Earth, 960 wide, Antarctica left out, as on the dashboard),
// every country as an SVG path with its alpha-2 code ("" when it has none), and each code's dot
// position in the same coordinates. countries.json: the country names in the plugin's six
// languages, from the ICU/CLDR data of the Node.js that runs this script.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [nm, pointsFile, out] = process.argv.slice(2);
if (!nm || !pointsFile || !out) {
  console.error("usage: generate.mjs NODE_MODULES COUNTRY_POINTS OUTDIR");
  process.exit(2);
}

const mod = (p) => import(pathToFileURL(join(nm, p)).href);
const { geoEqualEarth, geoPath } = await mod("d3-geo/src/index.js");
const { feature } = await mod("topojson-client/src/index.js");
const topo = JSON.parse(readFileSync(join(nm, "world-atlas/countries-110m.json"), "utf8"));

const WIDTH = 960;
const ANTARCTICA = "010";

const points = {};
for (const m of readFileSync(pointsFile, "utf8").matchAll(
  /^\s*([A-Z]{2}): \["(\d*)", (-?[\d.]+), (-?[\d.]+)\],/gm,
)) {
  points[m[1]] = { id: m[2], lat: Number(m[3]), lon: Number(m[4]) };
}
const codeById = new Map(
  Object.entries(points)
    .filter(([, p]) => p.id)
    .map(([code, p]) => [p.id, code]),
);

const all = feature(topo, topo.objects.countries);
const land = {
  type: "FeatureCollection",
  features: all.features.filter((f) => String(f.id) !== ANTARCTICA),
};
const projection = geoEqualEarth().fitWidth(WIDTH, land);
const path = geoPath(projection).digits(0);
const [[, top], [, bottom]] = path.bounds(land);
projection.translate([projection.translate()[0], projection.translate()[1] - top + 2]);
const height = Math.ceil(bottom - top) + 4;

const shapes = land.features
  .map((f) => [codeById.get(String(f.id ?? "")) ?? "", path(f) ?? ""])
  .filter(([, d]) => d);

const round = (n) => Math.round(n * 10) / 10;
const dots = {};
for (const [code, p] of Object.entries(points)) {
  if (code === "AQ") continue;
  const xy = projection([p.lon, p.lat]);
  if (xy) dots[code] = [round(xy[0]), round(xy[1])];
}

writeFileSync(
  join(out, "world.json"),
  JSON.stringify({
    source:
      "Natural Earth 1:110m Admin 0 countries (public domain), via world-atlas 2.0.2 (ISC); Equal Earth projection",
    width: WIDTH,
    height,
    shapes,
    dots,
  }) + "\n",
);

const LANGS = { en: "en", it: "it", es: "es", fr: "fr", de: "de", pt: "pt-BR" };
const names = {};
for (const [lang, tag] of Object.entries(LANGS)) {
  const dn = new Intl.DisplayNames([tag], { type: "region" });
  names[lang] = {};
  for (const code of Object.keys(points).sort()) {
    const n = dn.of(code);
    if (n && n !== code) names[lang][code] = n;
  }
}
writeFileSync(join(out, "countries.json"), JSON.stringify(names, null, 0) + "\n");

console.log(
  `${shapes.length} shapes, ${Object.keys(dots).length} dots, ${WIDTH}x${height}; names for ${Object.keys(points).length} codes`,
);
