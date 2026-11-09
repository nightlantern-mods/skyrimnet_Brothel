Scriptname skyrimnet_BrothelTIF_Scout extends TopicInfo Hidden
{Fragment of the player's scouting topic (skyrimnet_Brothel_ScoutTopic): the player offers this NPC, who
owes money on the IOU Ledger, work at the brothel to pay it off.}

Function Fragment_0(ObjectReference akSpeakerRef)
	(GetOwningQuest() as skyrimnet_Brothel).ScoutTopicChosen(akSpeakerRef as Actor)
EndFunction
