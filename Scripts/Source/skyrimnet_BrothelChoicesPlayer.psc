Scriptname skyrimnet_BrothelChoicesPlayer extends ReferenceAlias
{Re-registers SkyrimNet's speech events and resets the conversation state on every save load.}

Event OnPlayerLoadGame()
	(GetOwningQuest() as skyrimnet_BrothelChoices).Setup()
EndEvent
