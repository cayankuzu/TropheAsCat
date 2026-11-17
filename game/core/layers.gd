class_name Layers
extends RefCounted
## Collision layer bit masks shared by every module. Names match [layer_names] in project.godot.

const TERRAIN := 1 << 0        ## Voxel ground and other static world geometry.
const STRUCTURE := 1 << 1      ## Intact building elements (static).
const DEBRIS := 1 << 2         ## Large dynamic debris and falling structural clusters.
const DEBRIS_SMALL := 1 << 3   ## Pooled small chunks; never collide with each other.
const PLAYER := 1 << 4
const NPC := 1 << 5            ## Humans (harmable).
const PROTECTED := 1 << 6      ## Trees, plants, animals: solid but invulnerable.
const PROPS := 1 << 7          ## Intact dynamic props and vehicles.
const PROJECTILE := 1 << 8
const TRIGGER := 1 << 9        ## Areas (magma, world edge, pickups).
const RUBBLE := 1 << 10        ## Settled debris frozen as static, still grabbable.

## Everything a character can stand on or climb.
const WALKABLE := TERRAIN | STRUCTURE | DEBRIS | RUBBLE | PROTECTED | PROPS
## Everything that blocks a projectile or a damage ray.
const SOLID := TERRAIN | STRUCTURE | DEBRIS | DEBRIS_SMALL | RUBBLE | PROTECTED | PROPS | NPC
## Things the destruction system may hurt or push.
const DAMAGEABLE := TERRAIN | STRUCTURE | DEBRIS | DEBRIS_SMALL | RUBBLE | PROPS | NPC | PROTECTED
