## 83. Robot rats stack to 10 (2026-10-20)

The user asked for robot rats to be "stackable over 3". Note 77 gave
`robot_rat` a stack of 3, so a fourth robot rat built at the workbench went
into a second slot of the weapon wheel (or the bag). This supersedes the
`robot_rat` (stack 3) in note 77.

- **Where:** `scripts/inventory.gd` `ITEMS[&"robot_rat"]["stack"]`, 3 -> **10**
  (the same size as the red crystal). It is still not `"single"`, so past 10 a
  new stack starts as before; nothing else in the game assumed 3 (the
  workbench's `_build_robot_rat` just calls `inv.add`, and the "Carried N"
  label counts every stack).
- **Measured:** a throwaway headless harness built an `Inventory` and added 7
  robot rats: before, 3 stacks of at most 3; after, 1 stack of 7 with
  `stack_size` 10. Re-broken (change stashed) it went back to 3 stacks, so the
  check was not vacuous. The harness was deleted.
- **Not done:** no frame-time cost, so no `--bench` run and no Graphics knob.
