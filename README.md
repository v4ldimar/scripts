# Scripts

A collection of useful scripts for work and personal stuff.

## Agent Skills

With Node.js and npm installed, run:

```bash
npx skills add v4ldimar/scripts
```

The Skills CLI discovers `create-bash-script` and installs it for the AI agent you select.

## Tools

Run a command with `--help` to see its options and configuration.

- azure-devops/
	- test-commits-markdown.py - Render matching Git commits as Azure DevOps Markdown links. *Requirements:* Python 3.8+, Git.

- immich/
	- immich-sync.sh - Build a clean year-based Immich library copy from an upload folder while skipping .xmp metadata files. *Requirements:* Bash, GNU core utilities (find, cp, date).

- macos/
	- collect-pdfs.sh - Collect PDF notes from one or more macOS source roots into a zip archive while preserving folder structure beneath each root. *Requirements:* Bash, zip, find, cp, mktemp.

- linux/
	- sudo/passwordless/enable-current-user.sh - Enable passwordless sudo for the current user by installing a validated rule in /etc/sudoers.d. *Requirements:* Bash, sudo, visudo, id, install, mktemp, rm.
	- sudo/passwordless/disable-current-user.sh - Disable passwordless sudo for the current user by removing only the expected managed sudoers rule. *Requirements:* Bash, sudo, id, rm.

- llama/
	- llama-cli.sh - Run llama.cpp's CLI with a model selected by filename or explicit path. *Requirements:* Bash, llama.cpp build with llama-cli.
	- llama-server.sh - Start a managed llama.cpp server with configurable model, host, port, threads, logs, and PID file. *Requirements:* Bash, llama.cpp build with llama-server, nohup, ps.
	- kill-llama-server.sh - Stop the managed llama.cpp server from PID file, with SIGTERM and timeout-based SIGKILL fallback. *Requirements:* Bash, ps.

- nuget/
	- push/push.sh - Push NuGet packages using dotenv-managed profiles, with interactive add/remove/list flows and non-interactive CI support. *Requirements:* Bash 3.2+, dotnet CLI, mktemp.

- password/
	- generate.sh - Generate pronounceable passwords in three six-character groups with exactly one uppercase letter and one digit. *Requirements:* Bash 3.2+, od, readable /dev/urandom (Linux or macOS).

- windows/
	- timezone/set-norway.sh - Save the current Windows time zone and switch to W. Europe Standard Time (Norway). *Requirements:* Bash (Git Bash or WSL on Windows), tzutil.exe.
	- timezone/restore-local.sh - Restore the saved Windows time zone from state, or set an explicitly supplied time zone ID. *Requirements:* Bash (Git Bash or WSL on Windows), tzutil.exe.
