const manifestPath = "nix/package-manifest.json";
const manifestFile = Bun.file(manifestPath);
const manifest = await manifestFile.json();

const refs = {
  stable: "v0.38.2",
  nightly: "v0.40.0-nightly.20260415.g06e7621b2",
};

manifest.package.version = refs.stable.replace(/^v/, "");

await Bun.write(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

console.log(
  JSON.stringify(
    {
      package: manifest.package.npmName,
      stable: refs.stable,
      nightly: refs.nightly,
      version: manifest.package.version,
    },
    null,
    2,
  ),
);
