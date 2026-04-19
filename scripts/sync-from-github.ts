const manifestPath = "nix/package-manifest.json";
const flakePath = "flake.nix";
const readmePath = "README.md";
const upstreamRepo = "https://github.com/google-gemini/gemini-cli.git";

type ReleaseKind = "stable" | "nightly";

type ParsedTag = {
  kind: ReleaseKind;
  raw: string;
  major: number;
  minor: number;
  patch: number;
  nightlyDate: number;
};

const git = Bun.spawnSync({
  cmd: ["git", "ls-remote", "--tags", "--refs", upstreamRepo],
  stdout: "pipe",
  stderr: "pipe",
});

if (git.exitCode !== 0) {
  throw new Error(
    `failed to query upstream tags: ${new TextDecoder().decode(git.stderr)}`,
  );
}

const tags = new TextDecoder()
  .decode(git.stdout)
  .split("\n")
  .map((line) => line.trim().split(/\s+/)[1] ?? "")
  .filter((ref) => ref.startsWith("refs/tags/"))
  .map((ref) => ref.replace("refs/tags/", ""));

function parseTag(raw: string): ParsedTag | null {
  const stable = /^v(\d+)\.(\d+)\.(\d+)$/;
  const nightly = /^v(\d+)\.(\d+)\.(\d+)-nightly\.(\d{8})\.g[0-9a-f]+$/;

  const stableMatch = raw.match(stable);
  if (stableMatch) {
    return {
      kind: "stable",
      raw,
      major: Number(stableMatch[1]),
      minor: Number(stableMatch[2]),
      patch: Number(stableMatch[3]),
      nightlyDate: 0,
    };
  }

  const nightlyMatch = raw.match(nightly);
  if (nightlyMatch) {
    return {
      kind: "nightly",
      raw,
      major: Number(nightlyMatch[1]),
      minor: Number(nightlyMatch[2]),
      patch: Number(nightlyMatch[3]),
      nightlyDate: Number(nightlyMatch[4]),
    };
  }

  return null;
}

function compareTags(left: ParsedTag, right: ParsedTag): number {
  return (
    right.major - left.major ||
    right.minor - left.minor ||
    right.patch - left.patch ||
    right.nightlyDate - left.nightlyDate ||
    right.raw.localeCompare(left.raw)
  );
}

function selectLatest(kind: ReleaseKind): string {
  const candidates = tags
    .map(parseTag)
    .filter((tag): tag is ParsedTag => tag !== null && tag.kind === kind)
    .sort(compareTags);

  const latest = candidates[0];
  if (!latest) {
    throw new Error(`failed to find latest ${kind} tag from upstream`);
  }

  return latest.raw;
}

function replaceRequired(
  source: string,
  pattern: RegExp,
  replacement: string,
  description: string,
): string {
  if (!pattern.test(source)) {
    throw new Error(`failed to update ${description}`);
  }

  return source.replace(pattern, replacement);
}

const refs = {
  stable: selectLatest("stable"),
  nightly: selectLatest("nightly"),
};

const manifestFile = Bun.file(manifestPath);
const manifest = await manifestFile.json();
manifest.package.version = refs.stable.replace(/^v/, "");
await Bun.write(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

const flake = await Bun.file(flakePath).text();
const nextFlake = [
  {
    pattern:
      /url = "github:google-gemini\/gemini-cli\/v\d+\.\d+\.\d+-nightly\.\d{8}\.g[0-9a-f]+";/,
    replacement: `url = "github:google-gemini/gemini-cli/${refs.nightly}";`,
    description: "flake nightly ref",
  },
  {
    pattern: /url = "github:google-gemini\/gemini-cli\/v\d+\.\d+\.\d+";/,
    replacement: `url = "github:google-gemini/gemini-cli/${refs.stable}";`,
    description: "flake stable ref",
  },
].reduce(
  (text, update) =>
    replaceRequired(text, update.pattern, update.replacement, update.description),
  flake,
);
await Bun.write(flakePath, nextFlake);

const readme = await Bun.file(readmePath).text();
const nextReadme = [
  {
    pattern: /Default pinned version: `v\d+\.\d+\.\d+`/,
    replacement: `Default pinned version: \`${refs.stable}\``,
    description: "README default version",
  },
  {
    pattern: /\*\*Release \(default\):\*\* Uses `google-gemini\/gemini-cli@v\d+\.\d+\.\d+` and exposes `packages\.default`\./,
    replacement: `**Release (default):** Uses \`google-gemini/gemini-cli@${refs.stable}\` and exposes \`packages.default\`.`,
    description: "README release line",
  },
  {
    pattern: /\*\*Stable tag \(`v\d+\.\d+\.\d+`\):\*\* Uses the `gemini-cli-stable-src` input and exposes `packages\.stable`\./,
    replacement: `**Stable tag (\`${refs.stable}\`):** Uses the \`gemini-cli-stable-src\` input and exposes \`packages.stable\`.`,
    description: "README stable line",
  },
  {
    pattern: /\*\*Nightly:\*\* Uses `google-gemini\/gemini-cli@v\d+\.\d+\.\d+-nightly\.\d{8}\.g[0-9a-f]+` and exposes `packages\.nightly`\./,
    replacement: `**Nightly:** Uses \`google-gemini/gemini-cli@${refs.nightly}\` and exposes \`packages.nightly\`.`,
    description: "README nightly line",
  },
].reduce(
  (text, update) =>
    replaceRequired(text, update.pattern, update.replacement, update.description),
  readme,
);
await Bun.write(readmePath, nextReadme);

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
