extends GutTest
# Diplomacy and reputation (docs/diplomacy-design.md; war-and-realm §0.2, §2.2; core/diplomacy.gd,
# core/reputation.gd): envoys travel by map distance, the acceptance math with its reasons, the
# 20-turn treaty protection, betrayal (the AI never), justified and unjustified wars, reputation
# standing, trade during war with tariffs, and AI proposals.

const MapRegistry = preload("res://core/map_registry.gd")
const GameState = preload("res://core/game_state.gd")
const D = preload("res://core/diplomacy.gd")
const Rep = preload("res://core/reputation.gd")
const Battles = preload("res://core/battles.gd")

const ME = "house_varn"

func before_each():
 MapRegistry.set_active(MapRegistry.CAMPAIGN)

func after_each():
 MapRegistry.set_active(MapRegistry.DEFAULT)

func state() -> RefCounted:
 var s = GameState.from_data()
 s.player_faction = ME
 return s

func test_envoys_reach_anyone_by_map_distance():
 var s = state()
 var far = "reavers_brinecrag"
 var near = "house_dunmoor"
 assert_gt(D.envoy_turns(s,ME,far),D.envoy_turns(s,ME,near),"farther takes longer")
 var r = D.send_envoy(s,ME,far,"embassy")
 assert_true(r.ok)
 assert_false(D.send_envoy(s,ME,far,"embassy").ok,"one envoy at a time")
 s.diplomacy.contacts.erase(D.key(ME,far))
 for i in int(r.turns)-1:
  s.turn += 1
  D.process_envoys(s)
 assert_false(D.has_embassy(s,ME,far),"still on the road")
 s.turn += 1
 D.process_envoys(s)
 assert_true(D.has_contact(s,ME,far),"contact on arrival")
 assert_true(D.has_embassy(s,ME,far),"no reason to refuse: accepted")
 assert_eq(D.court_visibility(s,ME,far),"full","an embassy reveals the court")

func test_acceptance_math_moves_with_the_offer_and_gives_reasons():
 var s = state()
 var them = "house_kells"
 var base = D.evaluate(s,ME,them,{"give":[],"take":[{"kind":"gold","amount":1000}]})
 var better = D.evaluate(s,ME,them,{"give":[{"kind":"gold","amount":2000}],"take":[{"kind":"gold","amount":1000}]})
 assert_gt(float(better.score),float(base.score),"adding gold for them raises the score")
 assert_false(base.accept,"they will not simply give you gold")
 assert_true(better.reasons.any(func(r): return "gold" in r.text and float(r.value)>0.0),"reasons carry numbers")
 var friend = D.evaluate(s,ME,them,{"give":[{"kind":"trade"}],"take":[]})
 assert_true(friend.reasons.any(func(r): return "like" in r.text),"attitude in the reasons (old friends)")
 # Ineligible items block the deal with the reason.
 var bad = D.evaluate(s,ME,them,{"give":[{"kind":"gold","amount":999999}],"take":[]})
 assert_true(bad.blocked)
 assert_string_contains(bad.reasons[0].text,"Not enough gold")
 # The same math the AI uses accepts a good trade deal with a friend.
 assert_true(friend.accept)

func test_treaties_are_protected_for_twenty_turns():
 var s = state()
 var them = "house_kells"
 D.sign_treaty(s,ME,them,"alliance")
 assert_true(D.allied(s,ME,them))
 assert_eq(D.protected_turns_left(s,ME,them),20)
 assert_false(D.cancel(s,ME,them,"alliance").ok,"protected")
 s.turn += 20
 assert_true(D.cancel(s,ME,them,"alliance").ok,"after 20 turns it can be cancelled")
 # Trade can always be cancelled (no betrayal), at a cost in attitude.
 D.sign_treaty(s,ME,them,"trade")
 var before = D.attitude(s,them,ME)
 assert_true(D.cancel(s,ME,them,"trade").ok)
 assert_lt(D.attitude(s,them,ME),before)

func test_betrayal_rule_and_the_ai_never_betrays():
 var s = state()
 var them = "house_kells"
 D.sign_treaty(s,ME,them,"peace")
 assert_eq(D.would_betray(s,ME,them),"peace")
 assert_false(D.declare_war(s,them,ME,true).ok,"the AI never betrays")
 var r = D.declare_war(s,ME,them)
 assert_true(r.get("betrayal",false))
 assert_has(s.diplomacy.betrayers,ME)
 for f in s.factions():
  if f == ME or D.untouchable(f) or s.settlements_of(f).is_empty(): continue
  assert_true(Battles.at_war(s,f,ME),f+" at war with the betrayer")
 assert_true(s.diplomacy.treaties.keys().all(func(k): return not ME in k.split("|")),"every treaty lost")
 assert_lt(float(Rep.entry(s,ME).ruler.trust),-30.0,"a permanent mark on the name")

func test_unjustified_war_costs_reputation_and_justified_does_not():
 var s = state()
 var rival = "house_dunmoor" # an old rivalry: a grudge
 var stranger = "theros"
 assert_true(D.declaration_preview(s,ME,rival).justified)
 var p0 = float(Rep.entry(s,ME).ruler.peace)
 D.declare_war(s,ME,rival)
 var p1 = float(Rep.entry(s,ME).ruler.peace)
 assert_false(D.declaration_preview(s,ME,stranger).justified or D.is_minor(stranger))
 D.declare_war(s,ME,stranger)
 var p2 = float(Rep.entry(s,ME).ruler.peace)
 assert_gt(p1-p2,p0-p1,"an unjustified war costs more")

func test_reputation_standing_from_deeds():
 var s = state()
 assert_eq(Rep.standing(s,ME).kind,"neutral")
 for i in 6: Rep.deed(s,ME,"liberated","Freed a city")
 assert_eq(Rep.standing(s,ME).kind,"loved")
 var labels = Rep.labels(s,"",ME)
 assert_true(labels.any(func(l): return l.name == "Liberator" and not l.deeds.is_empty()),"labels with their deeds")
 for i in 12: Rep.deed(s,"house_dunmoor","executed","Hanged prisoners")
 assert_eq(Rep.standing(s,"house_dunmoor").kind,"feared")
 # Neighbours weigh the ruler, distant factions the House.
 assert_gt(Rep.ruler_weight(s,"house_kells",ME),Rep.ruler_weight(s,"reavers_brinecrag",ME))

func test_trade_continues_during_war_with_tariffs():
 var s = state()
 var them = "house_aldane"
 D.sign_treaty(s,ME,them,"trade")
 var peace = D.trade_income(s,ME)
 assert_false(peace.is_empty())
 s.wars.append(Battles.war_key(ME,them))
 var war = D.trade_income(s,ME)
 assert_false(war.is_empty(),"trade continues during war")
 assert_lt(int(war[0].amount),int(peace[0].amount),"with tariffs")
 assert_true(war[0].war)

func test_allies_answer_calls_and_minor_factions_skip_the_web():
 var s = state()
 D.sign_treaty(s,"house_aldane","house_kells","alliance")
 var r = D.declare_war(s,ME,"house_kells")
 assert_true(r.ok)
 assert_false(r.calls.is_empty(),"the victim's allies are called")
 assert_true(r.calls[0].answer in ["join","support","refuse"])
 # A minor without a protector: no justification needed.
 var minor = ""
 for f in s.factions():
  if D.is_minor(f) and f != "house_kells" and not s.settlements_of(f).is_empty() and not Battles.at_war(s,ME,f): minor = f
 assert_ne(minor,"")
 assert_true(D.declaration_preview(s,ME,minor).justified)

# Every proposal and envoy gives a result (owner spec 2026-10-07; playtest: "my test treaties and
# envoys never answered"): each one sent comes back as a reply the interface shows.
func test_every_sent_proposal_resolves():
 var s = state()
 var data = load("res://core/ui_data.gd").new(s)
 var sent = 0
 assert_true(data.send_envoy("house_kells","embassy").ok); sent += 1
 assert_true(data.send_envoy("reavers_brinecrag","contact").ok); sent += 1
 var r = data.propose_offer("barrow_lords",{"give":[{"kind":"trade"}],"take":[]})
 assert_true(r.ok); sent += 1
 # An answer at once with contact: a reply too.
 D.make_contact(s,ME,"house_dunmoor")
 var now = data.propose_offer("house_dunmoor",{"give":[],"take":[{"kind":"gold","amount":1000}]})
 assert_false(now.accept,"they will not hand over gold")
 assert_false(now.reply.is_empty(),"declined at once, with a reply")
 assert_ne(str(now.reply.reason),"","the reason they give")
 sent += 1
 var guard = 0
 while not D.d(s).envoys.filter(func(e): return e.from == ME).is_empty() and guard<12:
  data.end_turn()
  guard += 1
 var replies = D.d(s).replies
 assert_eq(replies.size(),sent,"one reply for every envoy and proposal")
 for rep in replies:
  var v = data.reply_view(rep)
  assert_ne(v.blurb,"","their words")
  assert_string_contains(v.outcome,"ccepted" if rep.ok else "eclined")
 # Unseen replies feed the End Turn button until shown.
 assert_true(data.end_turn_warnings().any(func(w): return w.kind == "diplomacy"))
 for rep in replies: data.mark_reply_seen(int(rep.id))
 assert_true(data.unseen_replies().is_empty())

# The offer builder (owner spec 2026-10-07): active items leave Add Item (shown as Active with Cancel),
# items already in the offer leave it, and the faction list filters by attitude.
func test_add_item_excludes_active_and_offered_items():
 var s = state()
 var data = load("res://core/ui_data.gd").new(s)
 var them = "house_kells"
 D.sign_treaty(s,ME,them,"trade")
 D.open_embassy(s,ME,them)
 assert_true(data.item_active(them,{"kind":"trade"},"give"),"trade is active")
 assert_true(data.item_active(them,{"kind":"embassy"},"give"),"our embassy is active")
 assert_false(data.item_active(them,{"kind":"alliance"},"give"))
 assert_true(data.active_items(them).any(func(a): return a.kind == "trade" and a.cancel == "trade"),"listed as active, with cancel")
 var ui = load("res://ui/diplomacy_screen.gd").new(data,{"trim":Color("c9a45a"),"panel":Color("16110d")},them)
 add_child_autofree(ui)
 var names = func(side: String) -> Array:
  var ob: OptionButton = ui.find_child("Add_"+side,true,false)
  var out = []
  for i in ob.item_count: out.append(ob.get_item_text(i))
  return out
 assert_false(names.call("give").any(func(t): return t.begins_with("Trade agreement")),"active trade is not offered again")
 assert_not_null(ui.find_child("Active_trade",true,false))
 ui.offer.give.append({"kind":"gold","amount":500})
 ui.refresh()
 assert_false(names.call("give").any(func(t): return t.begins_with("500 gold")),"an item in the offer leaves the list")
 assert_false(names.call("take").any(func(t): return t.begins_with("500 gold")),"on both sides")
 # Filters: Hates me shows only factions whose attitude face is the lowest.
 ui.filter = "hates"
 for f in ui.shown_factions(): assert_eq(int(f.face),0)
 ui.filter = "unmet"
 for f in ui.shown_factions(): assert_false(f.contact)
