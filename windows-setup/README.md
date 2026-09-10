# Windows setup restore

Copy this folder to a location that survives the Windows wipe. After Windows is reinstalled, sign in once and open **Git Bash**. WinGet is provided by Microsoft’s App Installer and may not work until the first interactive sign-in.

Run:

```bash
./setup-apps.sh
```

Preview the commands first with `./setup-apps.sh --dry-run`. To retry one application, use for example `./setup-apps.sh --only dbeaver`.

The script installs Teams, Chrome, DBeaver Community, Notepad++, Git for Windows, VS Code Insiders, Azure Storage Explorer, Postman, XrmToolBox, NVM for Windows, Docker Desktop per user, and Visual Studio 2026 Professional stable. Visual Studio requires administrator elevation. Docker’s WSL 2 and virtualization prerequisites may require administrator or corporate policy changes.

Office/Outlook, company VPN, Intune/Ninja/ScreenConnect, printer software, credentials, licenses, repositories, Docker images, and application settings are intentionally not restored by this script. Sign in to Microsoft 365 to activate classic Outlook after Office is provisioned.

The log is written beside the script as `setup-apps.log`. WinGet package IDs are deliberately exact; if a package has moved or is unavailable in your region, the script records the failure and continues.
