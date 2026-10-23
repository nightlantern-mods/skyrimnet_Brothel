Scriptname skyrimnet_BrothelPlayer extends ReferenceAlias
{Re-registers the brothel's hotkeys and SexLab hook after each save load, and runs the timer for
automatic serving. The timer lives here so it never collides with the quest script's own updates.}

Event OnInit()
	ScheduleAutoServe()
EndEvent

Event OnPlayerLoadGame()
	(GetOwningQuest() as skyrimnet_Brothel).Setup()
	ScheduleAutoServe()
EndEvent

Function ScheduleAutoServe()
	UnregisterForUpdate()
	skyrimnet_Brothel brothel = GetOwningQuest() as skyrimnet_Brothel
	If brothel.AutoServeEnabled()
		RegisterForSingleUpdate(brothel.AutoServeInterval())
	EndIf
EndFunction

Event OnUpdate()
	(GetOwningQuest() as skyrimnet_Brothel).AutoServe()
	ScheduleAutoServe()
EndEvent
