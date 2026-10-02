extends SceneTree
# Battle Monte Carlo report: runs every scenario in tests/fixtures/battle_scenarios.json with many
# seeded battles and prints target vs actual. Exit code 0 when every target passes.
# Run: runtime\Godot.exe --headless --path . -s scripts/battle_harness.gd -- [battles per case, default 500] [scenario ids, e.g. 1,4,9]

const Harness = preload("res://tests/battle_harness.gd")

func _initialize():
 var args = OS.get_cmdline_user_args()
 var n = int(args[0]) if args.size()>0 else 500
 var t0 = Time.get_ticks_msec()
 var only = args[1].split(",") if args.size()>1 else []
 var rows = []
 for sc in Harness.data().scenarios:
  if only.is_empty() or sc.id in only: rows.append_array(Harness.evaluate(sc,n))
 var ok = true
 print("| # | Case | Target | Actual | |")
 print("|---|---|---|---|---|")
 for r in rows:
  print("| %s | %s | %s | %s | %s |" % [r.scenario,r.label,r.target,r.actual,"pass" if r.pass else "FAIL"])
  ok = ok and r.pass
 print("BATTLE_HARNESS %s | %d battles per case | %.1f s" % ["PASS" if ok else "FAIL",n,(Time.get_ticks_msec()-t0)/1000.0])
 quit(0 if ok else 1)
