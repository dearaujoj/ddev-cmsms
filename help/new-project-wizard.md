# New Project Wizard

Interactive script that creates a fully configured CMSMS extension project in one go.

## Usage

```bash
bash scripts/cmsms-new-project.sh
```

## What it asks

1. **Project name** - becomes the directory name and DDEV project name (must match `^[A-Za-z0-9_]+$`)
2. **Parent directory** - where to create the project (default: current directory)
3. **Extension type** - module, plugin, theme, or workspace
4. **Extension name** - for single extensions (default: same as project name)
5. **Extensions list** - for workspace mode, space-separated `type:Name` pairs
6. **Scaffold?** - workspace only: generate starter code or just empty directories
7. **CMSMS version** - default: 2.2.22
8. **PHP version** - default: 8.3

After confirming the summary, it runs the full setup: `mkdir`, `ddev config`, `ddev add-on get`, `ddev cmsms setup`, and `ddev start`.

## Example session

```
CMSMS New Project Wizard
=========================

Project name (becomes directory and DDEV project name): MyModule
Parent directory to create project in [.]:
Extension type (1-4 or name) [module]:
Extension name [MyModule]:
CMSMS version [2.2.22]:
PHP version [8.3]:

Summary
-------
  Project:    MyModule
  Directory:  /home/user/MyModule
  Type:       module
  Name:       MyModule
  CMSMS:      2.2.22
  PHP:        8.3

Create this project? (y/n): y
```

## Prerequisites

- DDEV v1.24.0+ installed and working
- Docker provider running
