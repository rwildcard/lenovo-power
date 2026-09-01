# Hyprland / Omarchy integration

The panel is a small fixed-size window, so it wants a float rule. On Omarchy,
personal overrides go in `~/.config/hypr/`; these are appended there rather than
shipped, since the repo should not overwrite your config.

## Float rule

In `~/.config/hypr/hyprland.lua`:

```lua
o.window("^(dev\\.local\\.LenovoPower)$", {
  float = true,
  center = true,
  size = { 460, 780 },
  -- Opt out of the global default-opacity tag: a dense status readout
  -- is hard to read with the desktop showing through it.
  tag = "-default-opacity",
  opacity = "1 1",
})
```

Size assumes a laptop panel of 1600px at scale 1.6 (1000px logical), leaving
room for the bar. Adjust for your display.

## Keybind

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Power panel", "omarchy-launch-or-focus LenovoPower lenovo-power-gui")
```

`omarchy-launch-or-focus` focuses an existing window instead of spawning a
second copy. Check for conflicts first with `omarchy menu keybindings --print`.

After editing either file, validate with `hyprctl reload && hyprctl configerrors`.
