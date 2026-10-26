Scriptname skyrimnet_BrothelChoicesTIF_Reply5 extends TopicInfo Hidden
{Fragment of reply topic 5 (skyrimnet_Brothel_ChoicesReplyTopic5): tells skyrimnet_BrothelChoices which reply the player picked.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_BrothelChoices).OnReplyChosen(4)
EndFunction
