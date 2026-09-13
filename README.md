# Mouse Mage Arena

## Intro:

- Game instantly drops you into a little "sample area"
- Allows practice by flying through rings, hitting targets
- (StarFox style)
- Then, at the end of the corridor, is the portal
- Flying through the portal joins the persistent multiplayer session


## Connection options

- Could do host / join (lobbies)
- Could do 1 giant room that is hosted constantly
- This could be a "dedicated server" peer running somewhere
- 

## Arena

- Fly around, shoot enemies down, level up
- Many "PVE" things to shoot at, last hit gets it.
- Primary shot is "machine gun" 
- Shooting applies throttle down, until you reach to half speed.
- You must then increase your throttle once done.
- Aim is somewhat autoaim...
- Rings boost
- Rings allow pickups
- Indicators of damage on periphery.
- Minimap / radar?
- Upgrade / skill tree
- respawn with whatever you had.

- Arena shape: Cylider? Sphere? Damage beyond bounds. 
- 10s "RETURN TO ARENA" plus arrow, before you explode.

## Character Controller Notes:

- May need to test different "profile" in terms of speed, turn rate, acceleration, etc. 
  - Done: `MageFlightProfile` resources in `player/mage/profiles/` (original, airplane, character, arcade, broom_drift). Swap via the `profile` export on `PlayerMage`, or press F1–F5 in a debug build to hot-swap.
  - These could be upgradeable
  - Max Speed
  - Accel
  - Currently, you travel in a straight line largely, which is good. its hard to turn or evade, doing "snap" stops would be very strong but maybe more arcade-style could be fun. Witches could be capable.

- Mana
  - Mana needs a rapidly regenerating "fatigue-like" system
  - Mana consumes for "Boost"
  - Mana consumes for "Shoot"
  - Mana consumes for "Shield
  - Max mana is a stat
  - Mana recovery rate is a stat

## Fun
- Trash talk with your avatar (StarFox style)

# Weapons

Probably keep hitscan, just a delay for it to get going or arrive at the target? "Magic missle" style?

Add "homing missles" maybe 
Flame thrower cone could be fun

Systems / "Components" to build:

- Health System
  - signals
  - health recovery (Stat)
  - health recovery after delay
- Mana System
- Weapon System
- Stats (for level up) See: Queble's guide

## Level System 
- Levels - you get a point to accrue, like that one game.
- (1,2,3,4,5)
- Specialize / choice of 3
