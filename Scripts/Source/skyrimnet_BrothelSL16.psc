Scriptname skyrimnet_BrothelSL16 Hidden
{The brothel's calls into SexLab 1.6x (sslBaseAnimation lists, StartSex). Only skyrimnet_Brothel calls
these, and only when 1.6x is installed; skyrimnet_BrothelSLP holds the same functions for P+.
Written against SexLab 1.66b's sources and never tried in game on 1.6x.}

; SexLab's bed type (1 bedroll, 2 single, 3 double), 0 for furniture not in SexLab's bed list. 1.6x
; plays standing animations at the origin of anything else, so only these count as beds.
Int Function BedType(SexLabFramework sexLab, ObjectReference ref) Global
	Return sexLab.ThreadLib.GetBedType(ref)
EndFunction

Bool Function IsSexLabBed(SexLabFramework sexLab, ObjectReference ref) Global
	Return BedType(sexLab, ref) > 0
EndFunction

; Whether SexLab has an animation with this tag ("" for any) for the pair, at center (a bed or not)
; with this furniture preference (0 no bed, 1 SexLab decides, 2 the bed at center).
Bool Function HasScenes(SexLabFramework sexLab, Actor[] positions, String tag, Int furniturePref, ObjectReference center) Global
	sslBaseAnimation[] found = new sslBaseAnimation[1]
	Return Collect(sexLab, positions, tag, BedFilter(sexLab, center, furniturePref), found, 1, 0) > 0
EndFunction

; Whether SexLab has an animation with this tag for the pair, on a bed or off it.
Bool Function HasScenesFor(SexLabFramework sexLab, Actor[] positions, String tag) Global
	Return HasScenes(sexLab, positions, tag, 1, None)
EndFunction

; Starts one scene for the pair with up to 10 of its animations (a fresh random pick each call)
; with the tag, else with any tag; with none found SexLab picks its own. Returns the thread's ID, or
; -1 when SexLab refuses.
Int Function StartScene(SexLabFramework sexLab, Actor[] positions, ObjectReference center, Int furniturePref, String positionTag, String hook) Global
	Int bedFilter = BedFilter(sexLab, center, furniturePref)
	sslBaseAnimation[] found = new sslBaseAnimation[10]
	Int count = Collect(sexLab, positions, positionTag, bedFilter, found, 10, 200)
	If count == 0 && positionTag != ""
		count = Collect(sexLab, positions, "", bedFilter, found, 10, 200)
	EndIf
	sslBaseAnimation[] anims = sslUtility.AnimationArray(count)
	Int i = 0
	While i < count
		anims[i] = found[i]
		i += 1
	EndWhile
	Return sexLab.StartSex(positions, anims, None, center, furniturePref != 0, hook)
EndFunction

; How the animations are filtered for a bed, as SexLab 1.6x itself does once it has a bed or not:
; 1 on the bed at center, 0 off any bed, -1 either (SexLab may still find a bed itself).
Int Function BedFilter(SexLabFramework sexLab, ObjectReference center, Int furniturePref) Global
	If center && BedType(sexLab, center) > 0
		Return 1
	ElseIf furniturePref == 0
		Return 0
	EndIf
	Return -1
EndFunction

; Fills into with up to limit of SexLab's animations for the pair, checked from a random start and
; at most maxChecks of them (0 for all); returns how many. An animation qualifies when it has the
; tag, is not aggressive, needs no special furniture, suits the bed filter, and, for a pair of
; humans, has as many male and female positions as the pair has men and women: 1.6x positions each
; take one sex, so the man never gets the woman's part.
Int Function Collect(SexLabFramework sexLab, Actor[] positions, String tag, Int bedFilter, sslBaseAnimation[] into, Int limit, Int maxChecks) Global
	Int males = 0
	Int females = 0
	Int i = 0
	While i < positions.Length
		Int gender = sexLab.GetGender(positions[i])
		If gender == 0
			males += 1
		ElseIf gender == 1
			females += 1
		EndIf
		i += 1
	EndWhile
	Bool humans = males + females == positions.Length

	sslBaseAnimation[] found
	If tag == ""
		found = sexLab.GetAnimationsByType(positions.Length, -1, -1, -1, False, True)
	Else
		found = sexLab.GetAnimationsByTags(positions.Length, tag, "Aggressive")
	EndIf
	If !found || found.Length == 0
		Return 0
	EndIf
	Int checks = found.Length
	If maxChecks > 0 && checks > maxChecks
		checks = maxChecks
	EndIf
	Int count = 0
	Int index = Utility.RandomInt(0, found.Length - 1)
	While checks > 0 && count < limit
		sslBaseAnimation anim = found[index]
		If anim && !anim.HasTag("Aggressive") && !anim.HasTag("Furniture") \
				&& (!humans || (anim.MaleCount() == males && anim.FemaleCount() == females)) \
				&& SuitsBed(anim, bedFilter)
			into[count] = anim
			count += 1
		EndIf
		index = (index + 1) % found.Length
		checks -= 1
	EndWhile
	Return count
EndFunction

; SexLab 1.6x drops NoBed animations on a bed (and Standing ones, when its MCM says so; they are
; left out here either way) and BedOnly ones off it.
Bool Function SuitsBed(sslBaseAnimation anim, Int bedFilter) Global
	If bedFilter == 1
		Return !anim.HasTag("NoBed") && !anim.HasTag("Standing")
	ElseIf bedFilter == 0
		Return !anim.HasTag("BedOnly")
	EndIf
	Return True
EndFunction
