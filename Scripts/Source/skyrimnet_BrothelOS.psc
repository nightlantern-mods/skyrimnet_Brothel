Scriptname skyrimnet_BrothelOS Hidden
{The brothel's calls into OStim Standalone (API 7.0 or later). Only skyrimnet_Brothel calls these, and
only while OStim is the framework in use: without OStim installed the scripts used here do not exist.}

Bool Function IsActive(Actor who) Global
	Return OActor.IsInOStim(who)
EndFunction

; OStim's furniture type as the brothel's bed type (1 bedroll, 2 single, 3 double), 0 for anything
; OStim does not play bed scenes on. Unlike SexLab, OStim only places a scene on furniture it
; recognises, so no editor-ID guess is made.
Int Function BedType(ObjectReference ref) Global
	String furnitureType = OFurniture.GetFurnitureType(ref)
	If furnitureType == "doublebed"
		Return 3
	ElseIf furnitureType == "singlebed" || furnitureType == "bed"
		Return 2
	ElseIf furnitureType == "bedroll"
		Return 1
	EndIf
	Return 0
EndFunction

; The pair in the order OStim's scenes expect (actors with a schlong first), which the scene lookup
; and the thread both need.
Actor[] Function Sorted(Actor[] positions) Global
	Actor[] dominant = PapyrusUtil.ActorArray(0)
	Return OActorUtil.Sort(positions, dominant)
EndFunction

; A scene for the pair on the bed (None: no furniture) for the brothel's position tag, mapped through
; positions.json's "ostimTags" and "ostimActions" lists (same order as "tags") to an OStim scene tag
; and action: the tag with the action, else the action alone; "" when none is found or no tag was
; asked for (OStim then picks the scene itself).
String Function FindScene(Actor[] sorted, ObjectReference bed, String positionTag, String positionsFile) Global
	If positionTag == ""
		Return ""
	EndIf
	Int index = JsonUtil.StringListFind(positionsFile, "tags", positionTag)
	If index < 0
		Return ""
	EndIf
	String sceneTag = JsonUtil.StringListGet(positionsFile, "ostimTags", index)
	String actionType = JsonUtil.StringListGet(positionsFile, "ostimActions", index)
	String furnitureType = ""
	If bed
		furnitureType = OFurniture.GetFurnitureType(bed)
	EndIf
	String found = ""
	If sceneTag != ""
		found = OLibrary.GetRandomSceneSuperloadCSV(sorted, FurnitureType = furnitureType, AnySceneTag = sceneTag, AnyActionType = actionType)
	EndIf
	If found == "" && actionType != ""
		found = OLibrary.GetRandomSceneSuperloadCSV(sorted, FurnitureType = furnitureType, AnyActionType = actionType)
	EndIf
	Return found
EndFunction

; Whether OStim has a scene for the brothel's position tag for the pair, on no furniture.
Bool Function HasScenesFor(Actor[] positions, String positionTag, String positionsFile) Global
	Return FindScene(Sorted(positions), None, positionTag, positionsFile) != ""
EndFunction

; Whether OStim has a scene for the tag ("" for any) on the bed.
Bool Function HasScenes(Actor[] positions, String positionTag, ObjectReference bed, String positionsFile) Global
	If positionTag == ""
		Return True
	EndIf
	Return FindScene(Sorted(positions), bed, positionTag, positionsFile) != ""
EndFunction

; Starts a thread for the pair with a scene for the position tag, or one OStim picks. furniturePref
; as for SexLab: 2 on the bed given, 0 on no furniture, 1 OStim may pick furniture itself. Returns
; the thread's ID (0 for the player's thread), or -1 when OStim refuses.
Int Function StartScene(Actor[] positions, ObjectReference bed, Int furniturePref, String positionTag, String positionsFile) Global
	Actor[] sorted = Sorted(positions)
	Int builder = OThreadBuilder.Create(sorted)
	If builder < 0
		Return -1
	EndIf
	If furniturePref != 2
		bed = None
	EndIf
	If bed
		OThreadBuilder.SetFurniture(builder, bed)
	ElseIf furniturePref == 0
		OThreadBuilder.NoFurniture(builder)
	EndIf
	String sceneID = FindScene(sorted, bed, positionTag, positionsFile)
	If sceneID != ""
		OThreadBuilder.SetStartingAnimation(builder, sceneID)
	EndIf
	; The scene search takes a while; an actor unloaded meanwhile (the player left) must not be
	; handed to OStim.
	If !AllLoaded(sorted)
		OThreadBuilder.Cancel(builder)
		Return -1
	EndIf
	Return OThreadBuilder.Start(builder)
EndFunction

Bool Function AllLoaded(Actor[] actors) Global
	Int i = 0
	While i < actors.Length
		If !actors[i] || actors[i].IsDisabled() || !actors[i].Is3DLoaded()
			Return False
		EndIf
		i += 1
	EndWhile
	Return True
EndFunction

; Stops the thread of a scene that never played if OStim still runs it. Returns whether it did.
Bool Function EndIfStuck(Int threadID) Global
	If threadID >= 0 && OThread.IsRunning(threadID)
		OThread.Stop(threadID)
		Return True
	EndIf
	Return False
EndFunction
