Scriptname skyrimnet_BrothelChoicesTIF_Reply2 extends TopicInfo Hidden
{Fragment of reply topic 2 (skyrimnet_Brothel_ChoicesReplyTopic2): tells skyrimnet_BrothelChoices which reply the player picked.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_BrothelChoices).OnReplyChosen(1)
EndFunction
