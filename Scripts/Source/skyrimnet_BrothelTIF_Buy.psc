Scriptname skyrimnet_BrothelTIF_Buy extends TopicInfo Hidden
{Fragment of the player's customer topic (skyrimnet_Brothel_BuyTopic): the player, not working at
the brothel, offers this worker gold for their company.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_Brothel).BuyTopicChosen(akSpeakerRef as Actor)
EndFunction
