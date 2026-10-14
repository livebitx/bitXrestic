# bitXrestic

Windows desktop tool to export one day of restic backups into a single ZIP.
Current version: **0.3.9**.

## Features

- Recursive repository discovery, including SMB shares.
- Latest snapshot for each host and service on the selected date.
- Files merged under `host/original/path`, without nested export archives or reports.
- Duplicate paths combined only when content and attributes match; conflicts stop publication.
- Optional password reuse, enabled by default. Passwords are not saved.
- Temporary exports removed after success; retained after interruption for resuming.
- About dialog with version and repository link.
- English interface, fixed window size, custom icons, colored messages and destination links.

## Build locally

1. Download this repository.
2. Download the Windows AMD64 binary from [restic 0.19.1](https://github.com/restic/restic/releases/tag/v0.19.1), decompress it and place it here as `restic.exe`.
3. Run `Build.cmd`. Core tests run before building `bitXrestic.exe`.

Windows PowerShell 5.1 and the .NET Framework C# compiler are required. No permanent execution-policy changes are made.
The EXE embeds restic and its icon. A `restic.exe` beside the application takes priority over the embedded copy.

## GitHub build

Open **Actions → Build Windows → Run workflow**. Download the generated artifact and extract `bitXrestic.exe`.
The workflow downloads restic from its official release and includes its license in the artifact.

## Use

Choose a repository folder, destination and date, then click **Export to ZIP**. Enter repository passwords when requested.
The date uses the Windows time zone. The app reads repositories; it does not run init, prune or forget. restic may create temporary repository locks.
Output contains decrypted data. An existing final ZIP is not overwritten.
For faithful Linux restoration including special metadata and hardlinks, preserve the original restic repository.

## Validation

Core regression tests cover JSON snapshot arrays, timestamps, service grouping and temporary-folder cleanup.
The GUI and end-to-end export have not been tested by the authoring environment on Windows. Test on a small repository first.

## Third-party component

[restic](https://github.com/restic/restic) is a separate project licensed under BSD-2-Clause.
Its binary is not checked into this source repository.
