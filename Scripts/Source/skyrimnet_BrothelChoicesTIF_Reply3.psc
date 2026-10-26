Scriptname skyrimnet_BrothelChoicesTIF_Reply3 extends TopicInfo Hidden
{Fragment of reply topic 3 (skyrimnet_Brothel_ChoicesReplyTopic3): tells skyrimnet_BrothelChoices which reply the player picked.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_BrothelChoices).OnReplyChosen(2)
EndFunction
