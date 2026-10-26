Scriptname skyrimnet_BrothelChoicesTIF_Reply4 extends TopicInfo Hidden
{Fragment of reply topic 4 (skyrimnet_Brothel_ChoicesReplyTopic4): tells skyrimnet_BrothelChoices which reply the player picked.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_BrothelChoices).OnReplyChosen(3)
EndFunction
