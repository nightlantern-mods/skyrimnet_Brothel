Scriptname skyrimnet_BrothelTIF_Recommend extends TopicInfo Hidden
{Fragment of the owner's topic (skyrimnet_Brothel_RecommendTopic): the player, as the brothel's owner,
offers this NPC one of the workers.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_Brothel).RecommendTopicChosen(akSpeakerRef as Actor)
EndFunction
