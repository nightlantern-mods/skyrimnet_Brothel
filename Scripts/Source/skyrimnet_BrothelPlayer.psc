Scriptname skyrimnet_BrothelPlayer extends ReferenceAlias
{Re-registers the brothel's hotkeys and SexLab hook after each save load.}

Event OnPlayerLoadGame()
	(GetOwningQuest() as skyrimnet_Brothel).Setup()
EndEvent
