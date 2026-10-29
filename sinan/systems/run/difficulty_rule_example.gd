extends RefCounted
## Example custom difficulty rule. To use it, drag this file into the
## "Rule Script" slot of sinan/systems/run/difficulty.tres. Its threat() then
## replaces the built-in round pacing. Copy it and change the maths freely.
##
## ctx: run_time (s), kills, restored (painting 0..1), parts (the built-in
## terms: clock, kills).


func threat(ctx: Dictionary) -> float:
	# e.g. waves: a step up every 15 seconds after a 20 s calm start
	var waves := floorf(maxf(ctx.run_time - 20.0, 0.0) / 15.0)
	return waves * 0.9 + ctx.parts.kills
