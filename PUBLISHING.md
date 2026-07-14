# Publishing Guide

How to publish `emay-sleepo2` to every package registry, and how to set
up the accounts/tokens needed.

## Overview

| Language | Registry | Auth Method | CI Setup Required |
|----------|----------|-------------|--------------------|
| Python   | [PyPI][pypi] | Trusted Publishing (OIDC) | None — just configure in PyPI once |
| Node.js  | [npm][npm] | Automation token | `NPM_TOKEN` secret |
| Rust     | [crates.io][crates] | API token | `CRATES_TOKEN` secret |
| Swift    | Git tags (SPM) | None | None — tags ARE the publish |
| Go       | Module proxy (auto) | None | None — proxy indexes tags automatically |
| Kotlin   | [Maven Central][maven] | Sonatype + GPG signing | 4–5 secrets |

[pypi]: https://pypi.org
[npm]: https://www.npmjs.com
[crates]: https://crates.io
[maven]: https://central.sonatype.com

---

## How to Release

1. Bump the version in each manifest file (see table below).
2. Commit with message `Release v1.0.0` (or whatever version).
3. Tag: `git tag v1.0.0 && git push origin v1.0.0`
4. The `publish.yml` workflow fires automatically on the tag push.

### Files to bump on release

| Language | File | Field |
|----------|------|-------|
| Python   | `python/pyproject.toml` | `project.version` |
| Node.js  | `node/package.json` | `"version"` |
| Rust     | `rust/Cargo.toml` | `package.version` |
| Kotlin   | `kotlin/build.gradle.kts` | `version =` |
| Swift    | No file — SPM reads the git tag |
| Go       | No file — Go module proxy reads the git tag |

---

## Account Setup by Registry

### 1. PyPI (Python) — 5 minutes

This is the easiest. No token to generate or store.

1. Go to <https://pypi.org> → Register an account.
2. Verify your email.
3. Go to <https://pypi.org/manage/account/publishing/>.
4. Under **"Add a new pending publisher"**, fill in:
   - **Owner**: your PyPI username
   - **Repository**: `anxietywatch/emay-sleepo2`
   - **Workflow name**: `publish.yml`
   - **Environment name**: *(leave blank — uses repo-default)*
5. Click **Add**.

That's it. The GitHub Actions OIDC token will authenticate automatically
— no PyPI API token needed, ever. The first push of a `v*` tag publishes.

### 2. npm (Node.js) — 5 minutes

1. Go to <https://www.npmjs.com> → Sign up.
2. Verify your email.
3. Click your avatar → **Access Tokens**.
4. Generate a **"Granular Access Token"** (classic tokens work too):
   - **Token name**: `github-actions`
   - **Expiration**: 90 days (you'll cycle it)
   - **Packages and scopes**: select `Read and write`
   - Under **Organizations**, select *(no org — publish under your user)*
5. Copy the token (it's shown once).
6. Go to your GitHub repo → **Settings → Secrets and variables → Actions**.
7. Add a new repository secret:
   - **Name**: `NPM_TOKEN`
   - **Value**: *(paste the token)*
8. Click **Add secret**.

> **Note about noble**: The `@abandonware/noble` dependency is marked
> optional (`peerDependenciesMeta`). Users install it separately:
> `npm install @abandonware/noble emay-sleepo2`.

### 3. crates.io (Rust) — 5 minutes

1. Go to <https://crates.io> → Log in via GitHub OAuth.
2. Go to <https://crates.io/settings/tokens>.
3. Click **New Token**:
   - **Token name**: `github-actions`
   - **Scope**: `publish-update` (or `all` if you prefer)
4. Copy the token.
5. Add it as a GitHub Actions secret:
   - **Name**: `CRATES_TOKEN`
   - **Value**: *(paste the token)*

> **Note about btleplug**: The `btleplug` dependency is feature-gated
> behind `--features ble`. Users install with:
> `cargo add emay-sleepo2 --features ble`

### 4. Swift (SPM) — no setup

Swift Package Manager doesn't have a central registry. A version tag
(`v1.0.0`) pushed to GitHub IS the publish action. Consumers add it via:

```swift
.package(url: "https://github.com/anxietywatch/emay-sleepo2", from: "1.0.0")
```

No account, no token, no CI job. Just tag correctly.

### 5. Go — no setup

The Go module proxy (<https://proxy.golang.org>) indexes public GitHub
repos automatically. Pushing a `v1.0.0` tag is all that's needed.
Consumers import:

```go
import "github.com/anxietywatch/emay-sleepo2"
```

And Go's toolchain resolves the tagged version automatically.

### 6. Maven Central (Kotlin/Android) — ~30 minutes

This is the most involved setup. Maven Central requires a verified
namespace, a Sonatype account, and GPG signing.

#### 6a. Get a Sonatype Jira account

1. Go to <https://issues.sonatype.org> → Sign up.
2. Create a **New Project** ticket under the **Community Support — Open
   Source Project Repository Hosting (OSSRH)** project.
   - **Group Id**: `com.anxietywatch` (or `io.github.yourusername`)
   - **Project URL**: `https://github.com/anxietywatch/emay-sleepo2`
   - **SCM url**: `https://github.com/anxietywatch/emay-sleepo2.git`
3. A human at Sonatype approves it (typically within 1 business day).
   You need to prove you control the `com.anxietywatch` domain (a TXT
   record or a temporary GitHub repo works).
4. Once approved, you can publish artifacts under that group ID.

#### 6b. Generate a GPG key pair

```bash
gpg --gen-key
# Name: anxietywatch
# Email: your@email.com
# Passphrase: (generate a strong one)
```

Then export:

```bash
# List keys and find your key ID (16 chars)
gpg --list-keys

# Export public key to a keyserver (Maven Central requires it)
gpg --keyserver keyserver.ubuntu.com --send-keys YOUR_KEY_ID

# Export private key for CI
gpg --export-secret-keys YOUR_KEY_ID > ~/emay-sleepo2-signing.key
```

#### 6c. Add secrets to GitHub

| Secret Name | Value |
|-------------|-------|
| `OSSRH_USERNAME` | Your Sonatype Jira username |
| `OSSRH_PASSWORD` | Your Sonatype Jira password |
| `SIGNING_KEY_ID` | Last 8 chars of your GPG key ID |
| `SIGNING_PASSWORD` | Your GPG key passphrase |
| `SIGNING_KEY_RING_FILE` | *(not used with `useGpgCmd()` — CI installs GPG)* |

The `build.gradle.kts` uses `useGpgCmd()` which reads the key from the
CI runner's GPG keyring. You'll need to update the `maven-publish` job
in `publish.yml` to import the key before publishing:

```yaml
- name: Import GPG key
  run: |
    echo "${{ secrets.SIGNING_PRIVATE_KEY }}" | gpg --batch --import
```

And add `SIGNING_PRIVATE_KEY` as a secret containing the base64-encoded
private key.

#### 6d. First publish

The first publish goes to a Sonatype staging repository. Log into
<https://s01.oss.sonatype.org>, find your staging repository, **Close**
it (Sonatype validates signatures and metadata), then **Release** it.
After the first release, the artifact appears on Maven Central within
~30 minutes.

Subsequent publishes can be automated with the
`io.github.gradle-nexus.publish-plugin` Gradle plugin.

**Alternative: JitPack**

If the Sonatype process is too heavy, use JitPack as a shortcut:

1. No account setup — just push to GitHub.
2. Users add: `implementation("com.github.anxietywatch:emay-sleepo2:v1.0.0")`
3. JitPack builds on first request and caches.

Downside: less cache locality (each user's first build pulls from JitPack).

---

## Quick Reference: CI Secrets

After setting up accounts, go to your GitHub repo →
**Settings → Secrets and variables → Actions → Repository secrets**
and add:

```
NPM_TOKEN          = npm_xxxxxxxxxxxx
CRATES_TOKEN       = cioxxxxxxxxxxxxx
OSSRH_USERNAME     = your-sonatype-username
OSSRH_PASSWORD     = your-sonatype-password
SIGNING_PRIVATE_KEY = (base64-encoded GPG private key)
SIGNING_KEY_ID     = A1B2C3D4
SIGNING_PASSWORD   = your-gpg-passphrase
```

PyPI, SPM, and Go need **no secrets**.

---

## Local Test Publish (Dry Run)

### Python
```bash
cd python
rm -rf dist/ && python -m build
twine check dist/*
# Upload to Test PyPI first:
# twine upload --repository testpypi dist/*
```

### Node.js
```bash
cd node
npm pack --dry-run
```

### Rust
```bash
cd rust
cargo package --no-verify
cargo publish --dry-run
```

### Kotlin
```bash
cd kotlin
./gradlew publishToMavenLocal
# Check ~/.m2/repository/com/anxietywatch/emay-sleepo2/
```
