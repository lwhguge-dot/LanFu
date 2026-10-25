// Stamps the LanFu product version into package.json for release packaging.
// Every job that stages an app tree must run this: each job checks out the
// repo fresh, so the build job's stamp does not carry over — without it the
// installer ships whatever the last manual bump wrote (0.4.30-0.4.33 all
// shipped with the banner stuck on 0.4.29).
import fs from "node:fs";

const version = process.argv[2];
if (!version) {
  console.error("usage: node scripts/stamp-product-version.mjs <version>");
  process.exit(1);
}
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.lanfu = Object.assign({}, pkg.lanfu, { productVersion: version });
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
console.log("stamped productVersion:", version);
