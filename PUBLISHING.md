# aSmoothLootHelper — CurseForge Publishing Guide

Reference: https://support.curseforge.com/support/solutions/articles/9000197281-automatic-packaging

---

## How it works

When a tagged commit is pushed to GitHub, a webhook fires to CurseForge which:
1. Clones the repository at that tag
2. Reads `.pkgmeta` (if present) to know what to ignore / move / include
3. Packages the result into a zip named after the project slug
4. Publishes it to the CurseForge project page with the correct release type

---

## One-time webhook setup

### 1. Generate a CurseForge API token
Go to: **https://www.curseforge.com/account/api-tokens**  
Create a token named e.g. `GitHub Webhook`.

### 2. Find your CurseForge project ID
Open your project page on CurseForge → **About This Project** section → copy the numeric **Project ID**.

### 3. Add the webhook to GitHub
Go to: **GitHub repo → Settings → Webhooks → Add webhook**

| Field | Value |
|---|---|
| Payload URL | `https://www.curseforge.com/api/projects/{projectID}/package?token={token}` |
| Content type | `application/json` |
| Which events | **Just the push event** (tags are pushes) |
| Active | ✓ |

Replace `{projectID}` and `{token}` with the values from steps 1 and 2.

---

## Release types — controlled by the tag name

| Tag contains | CurseForge marks file as |
|---|---|
| `alpha` (e.g. `v1.0-alpha`) | Alpha |
| `beta` (e.g. `v1.0-beta`) | Beta |
| Neither | Release |

Untagged commits can also trigger packaging (marks as Alpha) if configured.

### Creating a beta release

```powershell
git tag -a v1.0-beta -m "v1.0 beta"
git push origin v1.0-beta
```

### Creating a release

```powershell
git tag -a v1.1.0 -m "v1.1.0"
git push origin v1.1.0
```

---

## `.pkgmeta` — packaging configuration

The file `.pkgmeta` (or `pkgmeta.yaml`) in the repo root controls packaging.
Files/dirs starting with `.` are always ignored automatically. So is `.pkgmeta` itself.

See the current `.pkgmeta` in this repo for the ignore list we use.

### Useful options

```yaml
# Name of the folder inside the zip (must match the addon folder name)
package-as: aSmoothLootHelper

# Files and folders to exclude from the package
ignore:
  - PUBLISHING.md
  - MINIMAP_ICON.md
  - OPTIONS_REDESIGN.md
  - ADDON_PLAN.md
  - logs
  - scripts

# Include external libraries (none currently)
# externals:
#   libs/SomeLib:
#     url: https://github.com/example/SomeLib.git
#     tag: latest
```

---

## Replacement tokens (optional, in Lua / TOC / XML files)

These are substituted at packaging time — useful for embedding the version/hash:

| Token | Replaced with |
|---|---|
| `@project-version@` | Tag name if on a tag, else short hash |
| `@project-revision@` | Full commit hash |
| `@project-date-iso@` | Last commit date (ISO 8601) |
| `@project-author@` | Last commit author |
| `@file-revision@` | Hash of that specific file |

**Example usage in `aSmoothLootHelper.toc`:**
```
## Version: @project-version@
```

Then the packaged TOC will contain the actual tag name (e.g. `v1.1.0`) automatically,
meaning you never have to manually bump the version before tagging.

---

## Debug / do-not-package tokens (Lua)

```lua
--@debug@
-- This block is commented out in release/beta packages
print("Debug mode active")
--@end-debug@

--@do-not-package@
-- This block is completely removed from the package
local function DevOnly() end
--@end-do-not-package@
```

---

## Typical release workflow

```powershell
# 1. Finish your changes
git add -A
git commit -m "v1.1.0 - description of changes"

# 2. Tag — name determines release type
git tag -a v1.1.0 -m "v1.1.0"   # release
# git tag -a v1.1-beta -m "beta"  # beta
# git tag -a v1.1-alpha -m "alpha" # alpha

# 3. Push commit + tag — webhook fires automatically
git push origin master
git push origin v1.1.0
```

CurseForge will package and publish within a minute or two of the tag push.
