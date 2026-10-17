## 49. Enforcers take turns; a harder throw; dimmer glow, ring eyes; the beam pose settled (2026-10-15)

- **No identical moves** (`enforcer._update_role`, every ROLE_EVERY 0.25 s):
  with another engaged enforcer within ROLE_RANGE 30 m of the player, the
  nearest takes Role.MELEE (walks in and swipes, never beams), the rest
  Role.BEAM (hold range and beam, never swipe; back away from a player inside
  BEAM_BACK_OFF 4 m), and only one beam is charged or fired at a time
  (`_other_beaming`). The shield-holder keeps the role mid-swipe and gives it up
  only to one ROLE_MARGIN 2 m nearer; anyone mid-swipe keeps the others on the
  beam however far. Alone: Role.BOTH, the old behaviour. Measured over 8 s with
  two: 0 frames both swiping, 0 both beaming, the far one beamed while the near
  one swiped; side by side, 0 frames both swiping. CONTROL (ROLE_RANGE 0, i.e.
  the old behaviour): the side-by-side pair swiped in lockstep (196 of 196
  frames) and both beamed together for 349 frames.
- **Knock-down**: `KNOCK_UP` 0.5 -> 0.8 s ("a bit longer"); `SWIPE_THROW`
  7.5 -> 11 -- thrown 5.98 m (was 3.06), down and up in 1.10 s.
- **Dimmer**: `base_glow` 4 -> 2, wind-up 3.5, strike 4.5, charging up to 6,
  firing 5 +-1, the death flicker 5; the eyes are still `EYE_GLOW` of that.
- **Ring eyes**: a TorusMesh per eye (outer 0.062 m, inner 0.04 m, sized in world
  metres against the marker's own scale -- the rig carries its armature's
  scale), stood up to face out of the face.
- **The beam pose settles on the shield arm**: the cannon is raised by frame 37
  of BEAM_BAKED but only comes to rest on the raised shield at the clip's LAST
  frame (47; seen in renders of 37 vs 47). The charge now plays the whole clip
  (`_beam_set_at`: its length less BEAM_SET_EARLY 0.04, so it is still
  "playing", frozen at speed 0, not finished) and firing holds that frame
  (`_freeze_at_set`). `_play_clip` restarts a clip that has stopped instead of
  only setting the rate.

