Scriptname skyrimnet_BrothelTIF_Solicit extends TopicInfo Hidden
{Fragment of the player's worker topic (skyrimnet_Brothel_SolicitTopic): the player, working as one
of the girls, offers this NPC their company.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_Brothel).SolicitTopicChosen(akSpeakerRef as Actor)
EndFunction
