Scriptname skyrimnet_BrothelSL Hidden
{The brothel's SexLab calls that P+ and 1.6x share. Only skyrimnet_Brothel calls these, and only while
SexLab is the framework in use: without SexLab installed the types used here do not exist, so the
quest script names none of them and hands the API around as a Quest (see DetectFramework).}

Quest Function API() Global
	Return SexLabUtil.GetAPI()
EndFunction

; 1.6x returns its own version (16601 for 1.66b); P+ the version of its SKSE plugin, a far larger
; number (or 0 without the plugin, still P+).
Int Function Version() Global
	Return SexLabUtil.GetVersion()
EndFunction

Bool Function IsActive(Quest api, Actor who) Global
	Return (api as SexLabFramework).IsActorActive(who)
EndFunction

Bool Function IsBedAvailable(Quest api, ObjectReference bed) Global
	Return (api as SexLabFramework).IsBedAvailable(bed)
EndFunction

; Ends the thread of a scene that never played if it is still animating or being set up, as a
; normal end would. Returns the state it was ended in, "" when it was left alone (ended or free).
String Function EndIfStuck(Quest api, Int threadID) Global
	sslThreadController thread = (api as SexLabFramework).GetController(threadID)
	If !thread
		Return ""
	EndIf
	String threadState = thread.GetState()
	If threadState == "Animating" || threadState == "Making" || threadState == "Making_M" || threadState == "Prepare"
		thread.EndAnimation(False)
		Return threadState
	EndIf
	Return ""
EndFunction

; Whether every actor is enabled and loaded: the scene search takes a while, and one unloaded
; meanwhile (the player left) is not handed to SexLab.
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
