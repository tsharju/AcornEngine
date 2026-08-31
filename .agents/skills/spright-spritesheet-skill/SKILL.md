---
name: spright-spritesheet-skill
description: Creates sprite sheets for the Acorn Engine using the spright CLI tool and custom Inja templates.
---

# Spright Sprite Sheet Skill

This skill explains how to package individual sprite or animation frames into packed sprite sheets (textures + JSON metadata) compatible with the Acorn Engine using the `spright` command-line tool.

## Templates
* **[acorn.inja](templates/acorn.inja)**: Generates Hash-format JSON metadata compatible with Swift's `SpriteSheetMetadata` decoding logic.

## Packing Configuration
Create a `spright.conf` configuration file in your directory:
```text
max-width 1024
max-height 1024
power-of-two true
output "characters{0-}.png"
description "characters.json"
template "acorn.inja"

id "{{ source.filenameId }}"
glob "assets/characters/**/*.png"
```

## Packaging Assets
Execute the `spright` tool, passing the input configuration and the template file:
```bash
spright -i spright.conf -t .agents/skills/spright-spritesheet-skill/templates/acorn.inja
```
