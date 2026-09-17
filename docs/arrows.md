# Arrow travel and reflection

Select `World → ProjectileSpawner` in `scenes/gameplay/world.tscn` and adjust
`arrow_travel_time_multiplier` in the Inspector. The default is `1.5`: arrows
take 50% longer to follow the same arc and reach the same distance. `1.0`
restores baseline timing; `2.0` doubles travel time. The setting applies to all
three levels, including any level-speed overrides on the player scene.

The host captures this setting in each arrow's spawn data. Changing it affects
new shots; arrows already in flight and their reflections keep their launch
value. Nonpositive or nonfinite values fall back to `1.0`.

Flight uses the original ballistic equation with trajectory time advancing by
`delta / multiplier`. Effective speed is divided by the multiplier and effective
gravity by its square. The original five-second trajectory spans 7.5 real
seconds at the default. The aiming preview keeps the same shape and length.

Enemy shields transfer ownership and reverse the arrow's trajectory clock,
retracing its original curve without a speed boost. Another shield can reverse
it again. Stationary players can exchange an arrow when their shield duration
and cooldown allow; a returning arrow does not track a shooter who moves.
It despawns if it reaches the original launch point without interception.
Collisions are checked before expiration at either end of the trajectory.

Preparation, firing cooldowns, shield duration/cooldown and damage rules are
unchanged. Trails still retain eight physics samples, so slower arrows have
shorter trails.

## Checks

Run with the Godot executable from the project directory:

```sh
godot --headless --path . tools/check_trajectory.tscn
godot --headless --path . tools/check_arrow_reflections.tscn
godot --headless --path . tools/check_charge_arc.tscn
```

For replication, run these in separate terminals, starting the server first:

```sh
godot --headless --path . tools/check_arrow_levels_network.tscn -- --server
godot --headless --path . tools/check_arrow_levels_network.tscn -- --client
```
