Scriptname skyrimnet_BrothelPlayer extends ReferenceAlias
{Re-registers the brothel's hotkeys and SexLab hook after each save load, and runs the timer for
automatic serving and for keeping the peace in the brothel. The timer lives here so it never
collides with the quest script's own updates.}

; Seconds between peace checks while the player is in the brothel, and between checks for the
; player having come back to it while away.
Float Property PeaceSeconds = 3.0 AutoReadOnly
Float Property AwaySeconds = 15.0 AutoReadOnly

; Real time of the next automatic serving; 0 while it is off.
Float autoServeAt

Event OnInit()
	ScheduleAutoServe()
EndEvent

Event OnPlayerLoadGame()
	(GetOwningQuest() as skyrimnet_Brothel).Setup()
	ScheduleAutoServe()
EndEvent

; Books the next automatic serving (MCM changes, loads) and the next tick.
Function ScheduleAutoServe()
	skyrimnet_Brothel brothel = GetOwningQuest() as skyrimnet_Brothel
	autoServeAt = 0.0
	If brothel.AutoServeEnabled()
		autoServeAt = Utility.GetCurrentRealTime() + brothel.AutoServeInterval()
	EndIf
	ScheduleTick()
EndFunction

; One update serves both: the peace check (often while in the brothel, rarely while away) and the
; automatic serving, booked for whichever comes first. Nothing runs while no brothel is set.
Function ScheduleTick()
	UnregisterForUpdate()
	skyrimnet_Brothel brothel = GetOwningQuest() as skyrimnet_Brothel
	Float delay = 0.0
	If brothel.HasBrothel()
		delay = AwaySeconds
		If brothel.PlayerInBrothel()
			delay = PeaceSeconds
		EndIf
	EndIf
	If autoServeAt > 0.0
		Float serveDelay = autoServeAt - Utility.GetCurrentRealTime()
		If serveDelay < 0.1
			serveDelay = 0.1
		EndIf
		If delay == 0.0 || serveDelay < delay
			delay = serveDelay
		EndIf
	EndIf
	If delay > 0.0
		RegisterForSingleUpdate(delay)
	EndIf
EndFunction

Event OnUpdate()
	skyrimnet_Brothel brothel = GetOwningQuest() as skyrimnet_Brothel
	brothel.SwitchToPlayersBrothel()
	brothel.KeepPeace()
	If autoServeAt > 0.0 && Utility.GetCurrentRealTime() >= autoServeAt
		brothel.AutoServe()
		ScheduleAutoServe()
	Else
		ScheduleTick()
	EndIf
EndEvent

; Walking into one of the brothels makes it the current one. The owner's topic is offered only
; inside the brothel; the peace check speeds up there.
Event OnLocationChange(Location akOldLoc, Location akNewLoc)
	skyrimnet_Brothel brothel = GetOwningQuest() as skyrimnet_Brothel
	brothel.SwitchToPlayersBrothel()
	brothel.UpdateOwnerTalk()
	ScheduleTick()
EndEvent
