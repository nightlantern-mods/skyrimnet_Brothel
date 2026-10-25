Scriptname skyrimnet_BrothelSLP Hidden
{The brothel's calls into SexLab P+ (SexLabRegistry scenes, SexLabThread). Only skyrimnet_Brothel calls
these, and only when P+ is installed: under SexLab 1.6x the types used here do not exist.
skyrimnet_BrothelSL16 holds the same functions for 1.6x.}

; SexLab's bed type (1 bedroll, 2 single, 3 double), 0 for furniture SexLab does not class as a bed.
Int Function BedType(SexLabFramework sexLab, ObjectReference ref) Global
	Return sslThreadLibrary.GetBedTypeImpl(ref)
EndFunction

Bool Function IsSexLabBed(SexLabFramework sexLab, ObjectReference ref) Global
	Return sslThreadLibrary.IsBed(ref)
EndFunction

; How many scenes SexLab offers the pair with this tag ("" for any) and furniture preference.
Int Function SceneCount(SexLabFramework sexLab, Actor[] positions, String tag, Int furniturePref, ObjectReference center) Global
	Return SexLabRegistry.LookupScenes(positions, tag, None, furniturePref, center).Length
EndFunction

Bool Function HasScenes(SexLabFramework sexLab, Actor[] positions, String tag, Int furniturePref, ObjectReference center) Global
	Return SceneCount(sexLab, positions, tag, furniturePref, center) > 0
EndFunction

; Whether SexLab has a scene with this tag for the pair, with one sex per position for a man and a
; woman (see OneSexPositionScenes), anywhere.
Bool Function HasScenesFor(SexLabFramework sexLab, Actor[] positions, String tag) Global
	If OneSexPositionScenes(positions, None, 1, tag).Length > 0
		Return True
	EndIf
	Return SexLabRegistry.LookupScenes(positions, tag, None, 1, None).Length > 0 \
		&& !IsManAndWoman(positions)
EndFunction

Bool Function IsManAndWoman(Actor[] positions) Global
	Int sexA = SexLabRegistry.GetSex(positions[0], False)
	Int sexB = SexLabRegistry.GetSex(positions[1], False)
	Return (sexA == 0 && sexB == 1) || (sexA == 1 && sexB == 0)
EndFunction

; Starts one scene for the pair: one of up to 10 one-sex-position scenes (a fresh random pick each
; call), else any scene with the tag, else any scene. Returns the thread's ID, or -1 when SexLab
; refuses.
Int Function StartScene(SexLabFramework sexLab, Actor[] positions, ObjectReference center, Int furniturePref, String positionTag, String hook) Global
	String[] scenes = OneSexPositionScenes(positions, center, furniturePref, positionTag)
	SexLabThread thread
	If scenes.Length > 0
		thread = sexLab.StartSceneEx(positions, scenes, None, "", center, furniturePref, hook)
	Else
		thread = sexLab.StartScene(positions, positionTag, None, center, furniturePref, hook)
		If !thread && positionTag != ""
			thread = sexLab.StartScene(positions, "", None, center, furniturePref, hook)
		EndIf
	EndIf
	If !thread
		Return -1
	EndIf
	Return thread.GetThreadID()
EndFunction

; SexLab puts an actor in any position whose sexes include the actor's, and many scenes have a
; position that takes either sex, so the man could get the woman's part. For a man and a woman this
; returns up to 10 scenes, out of at most 80 checked from a random start, in which one position
; takes only women and the other only men; none for other pairs or when no such scene is found.
String[] Function OneSexPositionScenes(Actor[] positions, ObjectReference center, Int furniturePref, String tag = "") Global
	String[] picked
	If !IsManAndWoman(positions)
		Return picked
	EndIf
	String[] found = SexLabRegistry.LookupScenes(positions, tag, None, furniturePref, center)
	If found.Length == 0
		Return picked
	EndIf
	picked = new String[10]
	Int count = 0
	Int checks = found.Length
	If checks > 80
		checks = 80
	EndIf
	Int index = Utility.RandomInt(0, found.Length - 1)
	While checks > 0 && count < 10
		Int[] sexes = SexLabRegistry.GetPositionSexA(found[index])
		If sexes.Length == 2
			Int a = Math.LogicalAnd(sexes[0], 0x3)
			Int b = Math.LogicalAnd(sexes[1], 0x3)
			If (a == 0x1 && b == 0x2) || (a == 0x2 && b == 0x1)
				picked[count] = found[index]
				count += 1
			EndIf
		EndIf
		index = (index + 1) % found.Length
		checks -= 1
	EndWhile
	Return Utility.ResizeStringArray(picked, count)
EndFunction
