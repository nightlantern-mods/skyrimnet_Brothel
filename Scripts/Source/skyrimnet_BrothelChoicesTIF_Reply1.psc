Scriptname skyrimnet_BrothelChoicesTIF_Reply1 extends TopicInfo Hidden
{Fragment of reply topic 1 (skyrimnet_Brothel_ChoicesReplyTopic1): tells skyrimnet_BrothelChoices which reply the player picked.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_BrothelChoices).OnReplyChosen(0)
EndFunction
