Scriptname skyrimnet_BrothelChoicesTIF_Leave extends TopicInfo Hidden
{Fragment of the leave topic (skyrimnet_Brothel_ChoicesLeaveTopic): the player walks away without answering.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_BrothelChoices).OnReplyChosen(-1)
EndFunction
