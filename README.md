# Ice Cube

A minimal [LÖVE](https://love2d.org/) game starter.

## Run

Install LÖVE 11.5, then run from this directory:

```sh
love .
```

Use the arrow keys or `WASD` to slide one grid tile at a time. The cube shrinks with
each move and melts after 20 moves. Every tile it steps on becomes water, and
sliding onto existing water does not consume a move. Press `Esc` to quit.

## Project structure

- `main.lua` wires the LÖVE callbacks together.
- `game/player.lua` handles movement, melting, and player rendering.
- `game/grid.lua` handles the world grid and water trail.
- `game/camera.lua` handles the fixed, zoomed camera transform.
