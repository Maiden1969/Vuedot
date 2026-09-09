# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About

Vuedot is a Godot 4.x editor plugin that brings Vue.js-style reactivity to Godot. It provides reactive state primitives (`rep`, `computed`, `readonly`), watchers (`watch`, `watchEffect`), and property-to-reactive-data binding, plus an editor dock for visually wiring node properties to script-defined reactive data.

This is a project-local addon under `addons/vuedot/` within the larger **Ship** Godot project (C# / .NET, but this addon is pure GDScript).

## Build & test

There is no separate build step — this is a Godot addon and runs inside the Godot editor.

- **Enable the plugin:** The parent project already enables both sub-plugins in `project.godot` under `[editor_plugins]`. Both `vuedot` and `vuedot/ui` must be enabled.
- **Test scene:** Open `test_rep_scene.tscn` in the Godot editor (Godot 4.6+). The editor dock appears on the right side.
- **Run the project:** Use the Godot editor's "Run Project" (F5). There is no CI or automated test suite.

## Architecture

The plugin is split into two sub-plugins (each with its own `plugin.cfg`):

### `vuedot` (main plugin — `vuedot.gd`)
Entry point that enables the UI sub-plugin and registers `VueManager` as an autoload singleton at editor startup.

### `vuedot/ui` (editor UI — `ui/vuedot_ui.gd`)
An `EditorPlugin` that adds a dock to the Godot editor. It lets users:
1. Select a node to see its properties in the dock.
2. Click "绑定..." to open a dialog that shows the scene tree and lets the user pick a target node, then pick a `Rep`/`ComputedRep` script property to bind to.
3. Bindings are stored as `vuedot_bind_records` metadata on the scene root node. At runtime `VueManager` reads this metadata and wires up `Vue.bind()`.

### Core reactivity (`core/`)

| File | Class | Role |
|------|-------|------|
| `vue.gd` | `Vue` (static) | Central reactivity system. Provides `schedule()` (batched effect execution via `call_deferred`), `track()` (dependency collection), `watch()`, `watchEffect()`, `computed()`, `bind()`, `rep()`/`readonly()` factories, and `dispose()`. |
| `rep.gd` | `Rep` (RefCounted) | Reactive reference — like Vue's `ref()`. Getter calls `Vue.track(self)`; setter calls `_call_effects()` which schedules all registered effects. |
| `readonly_rep.gd` | `ReadonlyRep extends Rep` | A `Rep` whose setter is a no-op. Created via `Vue.readonly()`. |
| `computed_rep.gd` | `ComputedRep extends ReadonlyRep` | Lazy computed value. Overrides `_getter`: on read, if dirty, re-runs `update_func` and clears dirty flag. On dependency change the effect sets `dirty = true`; the setter schedules effects. Created via `Vue.computed(f)`. |
| `watch_handle.gd` | `WatchHandle` (RefCounted) | Associates an effect callback with its dependency dictionary. Used internally to manage watcher lifecycle. |
| `stop_func.gd` | `StopFunc` (RefCounted) | Wraps a stop-cleanup callable. Supports `bind(node)` for auto-cleanup when the node exits the scene tree (via `tree_exited`). `use()` or `stop()` invokes cleanup once (idempotent). |
| `vue_manager.gd` | `VueManager extends Node` | Autoload. On `_enter_tree`, connects to `node_added` — when a node with `vuedot_bind_records` meta is added, it waits for `ready` then calls `Vue.bind()` for each record. On `_exit_tree`, calls `Vue.dispose()`. |

### Dependency tracking flow

1. `watchEffect(e)` pushes `e` onto `_active_effects`, pushes `{}` onto `_dependencies`, then calls `e()`.
2. During `e()`, any `Rep` getter calls `Vue.track(self)`, which adds `{data: true}` to the topmost dependency dict.
3. After `e()` completes, the dependency dict is popped, and each `data` in it gets `data.add_effect(effect)` to register the reverse mapping.
4. When a `Rep` setter fires and the value changes, it calls `_call_effects()`, which schedules all registered effects via `Vue.schedule()` (batched with `call_deferred`).

### Key patterns

- Use `Vue.rep(val)` to create reactive state, `Vue.computed(f)` for derived state, `Vue.watch(reps, callback)` for explicit watchers.
- `Vue.bind(node, prop, rep)` wires a node property to a reactive value one-way (rep → node property). Optionally auto-cleans when the node exits the tree.
- Editor bindings created through the UI dock are persisted as scene metadata and resolved at runtime by `VueManager._auto_bind()`.
- `StopFunc.use()` / `StopFunc.stop()` are idempotent — safe to call multiple times.
