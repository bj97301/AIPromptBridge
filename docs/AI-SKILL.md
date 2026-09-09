# Install the AI skill

Open AIPromptBridge and choose **Install AI skill…** in its window or menu. Leave the desired destinations checked and click **Install selected**. Start a new AI session and ask it to use `aipromptbridge` to inspect a Mac alert.

AI agents and terminal users can use the same installer directly:

```sh
./aipromptbridge skills list
./aipromptbridge skills install --all
./aipromptbridge skills install --target shared --target claude
./aipromptbridge skills install --folder /path/to/another/skills
./aipromptbridge skills export --output ./aipromptbridge-skill.zip
```

Choose one install selector: `--all`, one or more `--target` IDs, or `--folder`. `skills list` returns JSON with target IDs, names, destination paths, and discovery notes. Copy T3 profile IDs from that list. Destinations that share a folder appear once. `--folder` adds an `aipromptbridge` subfolder and can create a missing skills directory. The CLI honors its `CLAUDE_CONFIG_DIR` environment override during discovery.

These commands work before risk acknowledgment and while CLI control is paused. They install only skill files and do not change acknowledgment, Mac permissions, allowed actions, or password approval settings. The CLI starts the local app when needed; no GUI clicks are required for installation.

Install returns a result for every selected destination. Exit code 0 means every destination was installed, updated, or already current. Exit code 1 includes skipped customized copies or failures, reported as `partial_failure`; inspect the individual results. Unknown IDs reject the whole selection before any installation. Export creates a new ZIP with mode 0600 and refuses to overwrite an existing file.

The skill explains the app, includes a Python CLI, and teaches the agent how to scan, identify an exact dialog, press a button, fill a field, handle missing permissions, and verify the result. It keeps the normal risk acknowledgment and agent approval requirements.

## Compatibility

| Software | How it is installed |
| --- | --- |
| Codex CLI and IDE, Cursor | Shared local skill in `~/.agents/skills/aipromptbridge` |
| ChatGPT desktop | Shared local skill for versions with local skill discovery. Use a local session with shell access for Mac control. |
| Claude Code | `~/.claude/skills/aipromptbridge`, or `CLAUDE_CONFIG_DIR` from the CLI or app process |
| T3 Code | Codex and Cursor use shared discovery. Detected local Claude provider homes get their own copy. |
| OpenCode | Discovers the shared agents or Claude skills directory |
| Claude web and Cowork | Export the ZIP, then upload it under Customize → Skills. Installation in a local Claude Code folder does not install it for the web account. |
| ChatGPT web/mobile | Local folders are not an account installation. Use the supported plugin distribution process for reusable skills, or extract `SKILL.md` as reference instructions. |
| Other agents | Use **Choose skills folder…** if the host supports the `SKILL.md` format, or export the package for manual setup. |

A skill provides instructions. It does not give a remote or cloud session access to this Mac's socket, grant a tool, install an AI app, or change any permissions. There is no universal installer API for every AI product. The result screen confirms file installation separately from whether a host has discovered the skill. Older versions, policy restrictions, custom configuration roots, and disabled skills may require manual setup.

The default targets cover supported apps even if those apps have not been installed yet. The installer avoids duplicating the shared skill in both Codex and Cursor folders. It reads only T3 provider configuration from `~/.t3/userdata/settings.json` and `~/.t3/dev/settings.json`, does not modify those files, and adds enabled Claude profiles with homes inside the current account. For other T3 installations or custom homes outside the account, use **Choose skills folder…** or `skills install --folder`.

These locations were checked against the [OpenAI skill documentation](https://learn.chatgpt.com/docs/build-skills), [Cursor skill directories](https://cursor.com/docs/skills), [Claude Code skill locations](https://code.claude.com/docs/en/skills), [Claude web upload instructions](https://support.claude.com/en/articles/12512180-use-skills-in-claude), and [OpenCode skill discovery](https://opencode.ai/docs/skills). T3 provider behavior was also checked in its provider implementation. Compatibility can change with host releases.

## Existing skills and updates

An unrelated or edited `aipromptbridge` folder is skipped, with an explanation. Symlinked skill folders and files are left unchanged. You can choose another skills folder or move your customized copy yourself before reinstalling.

Identical managed copies report **Already installed**. Unedited managed copies can be updated. The installer verifies file hashes, stages the new copy, and keeps the previous version under `~/Library/Application Support/AIPromptBridge/Skill Backups/`. Backups live outside skill discovery directories.

To uninstall, remove only the `aipromptbridge` folders listed by the installer, then start a new agent session. Do not remove the parent skills directories, which may contain unrelated skills.

## CLI and portable exports

An installed skill's CLI reads `scripts/app-location.json` to find the app on this Mac. If the app moves, reinstall the skill or set `AIPROMPTBRIDGE_APP` to its absolute `.app` path. It also checks the normal system and user Applications folders. No PATH or shell profile changes are made.

The exported ZIP contains `aipromptbridge/SKILL.md`, the CLI, and the license and risk references. It excludes the machine-specific app location and installation receipt. `build.py` assembles this complete package from the source skill, CLI, and notices; use the built app's installer or exported ZIP rather than copying the source skill directory alone.
