Scriptname skyrimnet_BrothelManageEffect extends ActiveMagicEffect
{The Manage Brothel power's effect: asks the brothel quest to open its menu.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
	skyrimnet_Brothel.Brothel().OpenManageMenu()
EndEvent
