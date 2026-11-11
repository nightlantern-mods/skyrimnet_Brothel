Scriptname skyrimnet_BrothelTIF_Recruit extends TopicInfo Hidden
{Fragment of the player's recruiting topic (skyrimnet_Brothel_RecruitTopic): the player offers this NPC,
who owes nothing, work at the brothel.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_Brothel).RecruitTopicChosen(akSpeakerRef as Actor)
EndFunction
