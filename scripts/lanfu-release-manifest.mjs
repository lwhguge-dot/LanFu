#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const args = process.argv.slice(2);
const command = args[0];
const platform = args[args.indexOf("--platform") + 1];
const version = args[args.indexOf("--version") + 1];
if (
  command !== "stage" ||
  !/^\d+\.\d+\.\d+$/.test(version ?? "") ||
  !["linux", "windows"].includes(platform)
) {
  console.error(
    "Usage: node scripts/lanfu-release-manifest.mjs stage --platform linux|windows --version 0.1.0",
  );
  process.exit(2);
}
const runtime = process.env.LANFU_NODE_RUNTIME_DIR;
if (!runtime || !fs.existsSync(runtime))
  throw new Error("LANFU_NODE_RUNTIME_DIR must point to the fixed Node.js runtime directory");
const out = path.join(root, "release-out");
const staging = path.join(root, "release-root");
fs.rmSync(out, { recursive: true, force: true });
fs.rmSync(staging, { recursive: true, force: true });
fs.mkdirSync(path.join(staging, "app"), { recursive: true });
fs.cpSync(path.join(root, "dist"), path.join(staging, "app", "dist"), {
  recursive: true,
  dereference: true,
});
for (const file of ["package.json", "openclaw.mjs", "LICENSE", "THIRD_PARTY_NOTICES.md"]) {
  fs.copyFileSync(path.join(root, file), path.join(staging, "app", file));
}
if (fs.existsSync(path.join(root, "node_modules")))
  fs.cpSync(path.join(root, "node_modules"), path.join(staging, "app", "node_modules"), {
    recursive: true,
    dereference: true,
  });
fs.cpSync(runtime, path.join(staging, "runtime"), { recursive: true, dereference: true });
fs.writeFileSync(
  path.join(staging, "VERSION"),
  "LanFu " + version + "\nOpenClaw base 2026.9.6\n",
  "utf8",
);
if (platform === "windows") {
  fs.copyFileSync(path.join(root, "packaging/windows/lanfu.cmd"), path.join(staging, "lanfu.cmd"));
  fs.copyFileSync(
    path.join(root, "packaging/windows/post-install.ps1"),
    path.join(staging, "post-install.ps1"),
  );
  fs.copyFileSync(
    path.join(root, "packaging/windows/uninstall.ps1"),
    path.join(staging, "uninstall.ps1"),
  );
  const iss = path.join(root, "packaging/windows/LanFu.iss");
  const iscc = process.env.ISCC ?? "ISCC.exe";
  execFileSync(iscc, ["/Qp", iss], { stdio: "inherit", cwd: root });
  fs.mkdirSync(out, { recursive: true });
  fs.copyFileSync(path.join(root, "LanFu-Setup-x64.exe"), path.join(out, "LanFu-Setup-x64.exe"));
} else {
  const debRoot = path.join(root, "deb-root");
  fs.rmSync(debRoot, { recursive: true, force: true });
  fs.mkdirSync(path.join(debRoot, "opt/lanfu"), { recursive: true });
  fs.mkdirSync(path.join(debRoot, "usr/bin"), { recursive: true });
  fs.mkdirSync(path.join(debRoot, "usr/lib/systemd/user"), { recursive: true });
  fs.cpSync(staging, path.join(debRoot, "opt/lanfu"), { recursive: true, dereference: true });
  fs.copyFileSync(
    path.join(root, "packaging/linux/usr/bin/lanfu"),
    path.join(debRoot, "usr/bin/lanfu"),
  );
  fs.copyFileSync(
    path.join(root, "packaging/linux/usr/lib/systemd/user/lanfu-gateway.service"),
    path.join(debRoot, "usr/lib/systemd/user/lanfu-gateway.service"),
  );
  fs.mkdirSync(path.join(debRoot, "DEBIAN"), { recursive: true });
  fs.writeFileSync(
    path.join(debRoot, "DEBIAN/control"),
    "Package: lanfu\nVersion: " +
      version +
      "\nSection: utils\nPriority: optional\nArchitecture: amd64\nMaintainer: LanFu\nDescription: LanFu company AI assistant\n",
    "utf8",
  );
  fs.writeFileSync(
    path.join(debRoot, "DEBIAN/postinst"),
    "#!/bin/sh\nset -e\nsystemctl daemon-reload || true\nexit 0\n",
    "utf8",
  );
  fs.chmodSync(path.join(debRoot, "DEBIAN/postinst"), 0o755);
  fs.mkdirSync(out, { recursive: true });
  execFileSync(
    "dpkg-deb",
    ["--build", "--root-owner-group", debRoot, path.join(out, "lanfu_" + version + "_amd64.deb")],
    { stdio: "inherit" },
  );
}
fs.writeFileSync(
  path.join(out, "RELEASE_METADATA.json"),
  JSON.stringify(
    { product: "LanFu", version, upstreamBase: "OpenClaw 2026.9.6", platform },
    null,
    2,
  ) + "\n",
);
console.log("staged", platform, version, out);
