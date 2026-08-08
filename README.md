# Ice Cube

A minimal [LÖVE](https://love2d.org/) game starter.

## Run

Install LÖVE 11.5, then run from this directory:

```sh
love .
```

Use the arrow keys or `WASD` to slide one grid tile at a time. The cube shrinks with
each move and melts after 20 moves. Every tile it steps on becomes water, and
sliding onto existing water does not consume a move. Press `R` to restart or
`Esc` to quit.

The fire heats a 3×3 area. Moves into that area cost two moves, and heated tiles
cannot become water. Entering the fire tile itself kills the cube instantly.

## Level editor

Press `E` to switch between play and edit modes. In the editor:

- `1`, `2`, and `3` select ground, fire, and erase tools.
- Left-click and drag to paint; right-click and drag to erase.
- `WASD` or the arrow keys pan, and the mouse wheel zooms.
- `S` saves the level and `L` loads it.
- `C` clears the level and `F` fills it with ground.

The green tile is the protected player spawn. Press `E` again to play the edited
level from that spawn.

## Project structure

- `main.lua` wires the LÖVE callbacks together.
- `game/player.lua` handles movement, melting, and player rendering.
- `game/grid.lua` handles the world grid and water trail.
- `game/camera.lua` handles the fixed, zoomed camera transform.
- `game/editor.lua` handles level-editing tools, UI, and save/load.
