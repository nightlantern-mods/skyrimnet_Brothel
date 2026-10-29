Scriptname skyrimnet_BrothelChoices extends Quest
{The brothel's built-in copy of SkyrimNet Player Choices (nightlantern-mods), renamed throughout so it
runs beside the standalone mod: own quest, records, prompt, config and mod events. One SkyrimNet LLM
call (prompt skyrimnet_brothel_choices) writes, in the player's own manner (the player's character
bio), either an NPC's opening line and 2-5 replies, or 2-5 lines the player might open with; the
brothel may fix what each reply means (intents). The NPC comes over and stays put (SkyrimNet's TalkToPlayer package), says the
line, the player picks a reply in the vanilla dialogue menu and says it aloud, the NPC answers it.
Settings live in SKSE/Plugins/skyrimnet_Brothel/choices.json, read on every load. skyrimnet_Brothel
starts conversations through StartFromApi and listens to the mod events below.}

String Property ConfigFile = "../skyrimnet_Brothel/choices.json" AutoReadOnly
String Property PromptName = "skyrimnet_brothel_choices" AutoReadOnly

Int Property MaxReplies = 5 AutoReadOnly

; SkyrimNet package that walks the NPC over to the player and holds them there.
String Property ApproachPackage = "TalkToPlayer" AutoReadOnly
String Property PackageOwner = "skyrimnet_Brothel_Choices" AutoReadOnly

; This plugin's dialogue: a player topic per reply and one to leave, shown only to an NPC in
; SpeakerFaction and only up to ReplyCount replies. Their texts are set before the menu opens.
String Property PluginFile = "skyrimnet_Brothel.esp" AutoReadOnly
Int Property SpeakerFactionID = 0x00080E AutoReadOnly
Int Property ReplyCountID = 0x00080F AutoReadOnly
Int Property LeaveTopicID = 0x00081F AutoReadOnly
; The reply topics are 0x810, 0x813, 0x816, 0x819 and 0x81C: three records apart.
Int Property FirstReplyTopicID = 0x000810 AutoReadOnly
Int Property NoReply = -2 AutoReadOnly
Int Property LeaveReply = -1 AutoReadOnly

; Stages of one conversation. Only one runs at a time.
Int Property StateIdle = 0 AutoReadOnly
Int Property StateWaitingForLLM = 1 AutoReadOnly
Int Property StateNpcSpeaking = 2 AutoReadOnly
Int Property StateChoosing = 3 AutoReadOnly

Int conversationState
Float stateSince
Actor speaker
String openingLine
String[] replies
Int replyCount
; Set by the reply topics' fragments (OnReplyChosen) while the dialogue menu is open.
Int chosenReply
; The player speaks first in this conversation: no NPC opening line, the replies are the player's
; first words.
Bool playerStarts
; Set by the brothel: what each reply must mean, in order (the LLM only words
; them), and the caller's tag, echoed in the mod events. intentCount 0: free replies.
String[] intents
Int intentCount
String requestTag
; False when the caller has the NPC react to the pick itself (StartFromApi with answers False): the player
; says the line and the conversation ends there.
Bool npcAnswers = True
; What the caller has already settled about the NPC's answer (StartFromApi's answerNote), told to the
; NPC with the player's reply; "" for none.
String answerNote

; Mod events for the brothel (custom signatures, sent with ModEvent):
;   skyrimnet_BrothelChoices_Started(Form akNpc, String asTag, Bool abPlayerStarts)
;   skyrimnet_BrothelChoices_ReplyChosen(Form akNpc, String asTag, Int aiIndex, String asText)
;   skyrimnet_BrothelChoices_Ended(Form akNpc, String asTag, Int aiReason)
Int Property EndAnswered = 0 AutoReadOnly
Int Property EndLeft = 1 AutoReadOnly
Int Property EndClosed = 2 AutoReadOnly
Int Property EndFailed = 3 AutoReadOnly

Event OnInit()
	Setup()
EndEvent

; Called by the player alias on every save load: mod event registrations do not survive one.
Function Setup()
	replies = new String[5]
	intents = new String[5]
	conversationState = StateIdle
	RegisterSpeechEvents()
EndFunction

; Whether another conversation may start now (the brothel waits for it). A prompt that
; fails to render never calls back, so a conversation stuck waiting for the LLM is given up here.
Bool Function IsIdle()
	If conversationState == StateWaitingForLLM
		Float waited = Utility.GetCurrentRealTime() - stateSince
		If waited < 0.0 || waited > ConfigFloat("llm_timeout", 90.0)
			Finish(EndFailed)
		EndIf
	EndIf
	Return conversationState == StateIdle
EndFunction

; Entry point for the brothel: the NPC speaks first (startsWithPlayer False) or the player does (True),
; with an optional theme and situation, optional reply intents and the caller's tag; answers False
; when the caller has the NPC react to the pick itself.
Bool Function StartFromApi(Actor npc, Bool startsWithPlayer, String theme, String situationText, String[] replyIntents, String tag, Bool answers = True, String note = "")
	If !npc || npc == Game.GetPlayer() || npc.IsDead() || !npc.Is3DLoaded() || !IsIdle()
		Return False
	EndIf
	If !IsRunning()
		Start()
	EndIf
	npcAnswers = answers
	answerNote = note
	Return RequestConversation(npc, startsWithPlayer, theme, situationText, replyIntents, tag)
EndFunction

; Asks the LLM for this conversation: with startsWithPlayer, only the player's opening lines;
; without, the NPC's opening line and the player's replies to it. theme "" picks one from the
; config; replyIntents (None or empty: free replies) fixes what each reply means, in order. The NPC
; is put on the approach package meanwhile, so they come over (or stay put) instead of walking on.
Bool Function RequestConversation(Actor npc, Bool startsWithPlayer, String theme, String situationText, String[] replyIntents, String tag)
	Actor player = Game.GetPlayer()
	speaker = npc
	playerStarts = startsWithPlayer
	requestTag = tag
	replyCount = 0
	openingLine = ""
	intentCount = 0
	String intentsJson = ""
	Int i = 0
	While replyIntents && i < replyIntents.Length && intentCount < MaxReplies
		If replyIntents[i] != ""
			intents[intentCount] = replyIntents[i]
			If intentCount > 0
				intentsJson += ","
			EndIf
			intentsJson += "\"" + JsonEscape(replyIntents[i]) + "\""
			intentCount += 1
		EndIf
		i += 1
	EndWhile
	If theme == ""
		theme = PickTheme()
	EndIf
	Int fewestReplies = ClampReplies(ConfigInt("min_replies", 2))
	Int mostReplies = ClampReplies(ConfigInt("max_replies", 5))
	If intentCount > 0
		fewestReplies = intentCount
		mostReplies = intentCount
	EndIf
	String context = "{\"npc_formid\":" + UnsignedFormID(npc) \
		+ ",\"npc_name\":\"" + JsonEscape(npc.GetDisplayName()) + "\"" \
		+ ",\"place\":\"" + JsonEscape(Situation(player)) + "\"" \
		+ ",\"lang\":\"" + JsonEscape(ConfigString("language", "Japanese")) + "\"" \
		+ ",\"theme\":\"" + JsonEscape(theme) + "\"" \
		+ ",\"situation\":\"" + JsonEscape(situationText) + "\"" \
		+ ",\"intents\":[" + intentsJson + "]" \
		+ ",\"player_starts\":" + (startsWithPlayer as Int) \
		+ ",\"min_replies\":" + fewestReplies \
		+ ",\"max_replies\":" + mostReplies + "}"
	conversationState = StateWaitingForLLM
	stateSince = Utility.GetCurrentRealTime()
	timingStart = stateSince
	speakerReleased = False
	Timing("LLM request sent")
	SkyrimNetApi.RegisterPackageEx(npc, ApproachPackage, -1, False, PackageOwner, "Brothel Choices", False)
	Int rc = SkyrimNetApi.SendCustomPromptToLLM(PromptName, ConfigString("variant", ""), context, Self, "skyrimnet_BrothelChoices", "OnConversationReady")
	If rc != 1
		Finish(EndFailed)
		Debug.Trace("[SNB Choices] SendCustomPromptToLLM failed, rc=" + rc)
		Notify("msg_llm_failed", "SkyrimNet could not start the conversation.")
		Return False
	EndIf
	SendStarted()
	Return True
EndFunction

; What the NPC brings up this time: one of the config's "themes" at random, never the one used
; last time. Without it a shopkeeper opened with their wares every time. "" when the list is empty.
Int lastTheme = -1

String Function PickTheme()
	Int count = JsonUtil.StringListCount(ConfigFile, "themes")
	If count <= 0
		Return ""
	EndIf
	Int index = Utility.RandomInt(0, count - 1)
	If count > 1 && index == lastTheme
		index = (index + 1 + Utility.RandomInt(0, count - 2)) % count
	EndIf
	lastTheme = index
	Return JsonUtil.StringListGet(ConfigFile, "themes", index)
EndFunction

Int Function ClampReplies(Int count)
	If count < 2
		Return 2
	ElseIf count > MaxReplies
		Return MaxReplies
	EndIf
	Return count
EndFunction

; ---------------------------------------------------------------------------------------------
; 2. The LLM's answer: the NPC says the line
; ---------------------------------------------------------------------------------------------

; Expected reply:
;   NPC: <opening line>
;   > <reply 1>
;   > <reply 2>
Function OnConversationReady(String response, Int success)
	If conversationState != StateWaitingForLLM
		Return
	EndIf
	If success != 1 || !speaker
		Finish(EndFailed)
		Debug.Trace("[SNB Choices] LLM failed: " + response)
		Notify("msg_llm_failed", "SkyrimNet could not start the conversation.")
		Return
	EndIf
	Timing("LLM lines ready (" + StringUtil.GetLength(response) + " chars)")
	ParseResponse(response)
	; SkyrimNet caps the reply at about 750 characters; a reply that reached the cap lost the end of
	; its last line, so that line is dropped rather than offered half-written.
	If StringUtil.GetLength(response) >= 740 && replyCount > 1
		replyCount -= 1
	EndIf
	; A caller's intents need exactly one reply each, in order: a reply the LLM left out (or the one
	; dropped above) falls back to the intent's own text, and extra replies are cut.
	If intentCount > 0
		While replyCount < intentCount
			replies[replyCount] = intents[replyCount]
			replyCount += 1
		EndWhile
		replyCount = intentCount
	EndIf
	If (openingLine == "" && !playerStarts) || replyCount == 0
		Finish(EndFailed)
		Debug.Trace("[SNB Choices] Could not read the LLM's answer: " + response)
		Notify("msg_llm_failed", "SkyrimNet could not start the conversation.")
		Return
	EndIf
	conversationState = StateNpcSpeaking
	stateSince = Utility.GetCurrentRealTime()
	; The wait for the line to be spoken, and the menu, run outside SkyrimNet's callback.
	RegisterForSingleUpdate(0.1)
EndFunction

Function ParseResponse(String response)
	String[] lines = PapyrusUtil.StringSplit(response, "\n")
	Int i = 0
	While i < lines.Length
		String line = Trim(lines[i])
		If line != ""
			If StringUtil.Find(line, "NPC:") == 0
				openingLine = Unquote(Trim(StringUtil.Substring(line, 4)))
			ElseIf StringUtil.Find(line, ">") == 0
				AddReply(Unquote(Trim(StringUtil.Substring(line, 1))))
			ElseIf openingLine == ""
				; A model that dropped the "NPC:" label still puts the line first.
				openingLine = Unquote(line)
			Else
				AddReply(Unquote(StripListMarker(line)))
			EndIf
		EndIf
		i += 1
	EndWhile
EndFunction

Function AddReply(String reply)
	If reply != "" && replyCount < MaxReplies
		replies[replyCount] = reply
		replyCount += 1
	EndIf
EndFunction

Event OnUpdate()
	If conversationState != StateNpcSpeaking
		Return
	EndIf
	If playerStarts
		; A menu the player just used (e.g. the one the calling mod started this from) may still be closing.
		Float started = Utility.GetCurrentRealTime()
		While UI.IsMenuOpen("Dialogue Menu") && Utility.GetCurrentRealTime() - started < 5.0
			Utility.WaitMenuMode(0.1)
		EndWhile
		Utility.Wait(0.3)
		ChooseReply()
	Else
		NpcSpeaks()
	EndIf
EndEvent

Function NpcSpeaks()
	Actor player = Game.GetPlayer()
	String npcName = speaker.GetDisplayName()
	String playerName = player.GetDisplayName()
	WaitForApproach(player)
	ClearOtherSpeech()
	ResetSpeechTracking()
	Timing("NPC asked to say the opening line")
	; Narration is taken as fact the speaker reacts to, so it says the line has not been said yet
	; and is to be said word for word: the replies were written to answer exactly this line.
	SkyrimNetApi.DirectNarration(npcName + " walks up to " + playerName + " to start a conversation and has not said anything yet. " \
		+ npcName + " now says these exact words to " + playerName + ", word for word, without changing, shortening or adding anything: \"" \
		+ openingLine + "\"", speaker, player)
	WaitForSpeech(ConfigFloat("speech_timeout", 40.0))
	Timing("NPC finished the opening line")
	ChooseReply()
EndFunction

; Waits until the NPC, walking over on the approach package, is close enough to talk, or gives up
; after approach_timeout seconds (blocked path, or the package did not take).
Function WaitForApproach(Actor player)
	Float closeEnough = ConfigFloat("approach_distance", 200.0)
	Float timeout = ConfigFloat("approach_timeout", 15.0)
	Float started = Utility.GetCurrentRealTime()
	While speaker.GetDistance(player) > closeEnough && Utility.GetCurrentRealTime() - started < timeout
		Utility.Wait(0.25)
	EndWhile
EndFunction

; SkyrimNet sends SkyrimNet_AudioStarted / SkyrimNet_AudioEnded (sender: the actor) for each
; sentence it plays; a line is several sentences with about half a second between them.
Bool speakerPlaying
Bool speakerStarted
Int speakerSentences
Float lastSentenceEnd
; While the NPC answers the player, WaitForSpeech keeps them on the approach package.
Bool holdSpeaker
; The same for the player's own voice, which SkyrimNet plays for a line picked in the dialogue menu.
Bool playerPlaying
Bool playerStarted
Float playerLastEnd

Function RegisterSpeechEvents()
	RegisterForModEvent("SkyrimNet_AudioStarted", "OnSkyrimNetAudioStarted")
	RegisterForModEvent("SkyrimNet_AudioEnded", "OnSkyrimNetAudioEnded")
EndFunction

Event OnSkyrimNetAudioStarted(String eventName, String strArg, Float numArg, Form sender)
	If speaker && sender == speaker
		If !speakerStarted
			Timing("NPC voice started")
		EndIf
		speakerPlaying = True
		speakerStarted = True
	ElseIf sender && sender == Game.GetPlayer()
		If !playerStarted
			Timing("player voice started")
		EndIf
		playerPlaying = True
		playerStarted = True
	EndIf
EndEvent

Event OnSkyrimNetAudioEnded(String eventName, String strArg, Float numArg, Form sender)
	If speaker && sender == speaker
		speakerPlaying = False
		speakerSentences += 1
		lastSentenceEnd = Utility.GetCurrentRealTime()
	ElseIf sender && sender == Game.GetPlayer()
		playerPlaying = False
		playerLastEnd = Utility.GetCurrentRealTime()
	EndIf
EndEvent

; Waits for the player's voiced line to finish. SkyrimNet beta 29 dropped IsPlayerTTSFinished, so
; this follows SkyrimNet's audio events instead, which every version sends. A line that never
; starts (player voice off) is given startTimeout seconds, longer while SkyrimNet is still
; generating speech; a line that started is waited for up to timeout seconds.
Function WaitForPlayerLine(Float startTimeout, Float timeout)
	Float started = Utility.GetCurrentRealTime()
	Float now = started
	While now - started < timeout
		If playerStarted
			If !playerPlaying && now - playerLastEnd >= 0.75 && SkyrimNetApi.GetSpeechQueueSize() == 0
				Return
			EndIf
		ElseIf now - started >= startTimeout && SkyrimNetApi.GetSpeechQueueSize() == 0
			Return
		EndIf
		Utility.Wait(0.25)
		now = Utility.GetCurrentRealTime()
	EndWhile
EndFunction

; Ambient SkyrimNet chatter queued around the speaker (crowded places) would otherwise play first
; and hold the conversation up; the line that is playing now is allowed to finish.
Function ClearOtherSpeech()
	If ConfigInt("interrupt_others", 1) != 0
		SkyrimNetApi.PurgeDialogue(True)
	EndIf
EndFunction

; How long each step of a conversation takes, in the Papyrus log: seconds since the request and
; the absolute real time, to line up with the brothel's own "timing:" lines.
Float timingStart

Function Timing(String stage)
	Float now = Utility.GetCurrentRealTime()
	Debug.Trace("[SNB Timing] " + requestTag + " " + stage + " +" + (now - timingStart) + "s t=" + now)
EndFunction

; Call right before asking SkyrimNet for the line.
Function ResetSpeechTracking()
	speakerPlaying = False
	speakerStarted = False
	speakerSentences = 0
	lastSentenceEnd = 0.0
EndFunction

; Waits until the speaker has said the whole line: at least one sentence played, none playing now,
; none started for 1.5 seconds since the last one ended, and nothing left in SkyrimNet's queue.
; Gives up after timeout seconds (TTS turned off, or the line was never voiced), or after
; speech_start_timeout seconds when the speaker has not started talking at all.
Function WaitForSpeech(Float timeout)
	Float started = Utility.GetCurrentRealTime()
	Float startTimeout = ConfigFloat("speech_start_timeout", 15.0)
	While Utility.GetCurrentRealTime() - started < timeout
		If !speakerStarted && startTimeout > 0.0 && Utility.GetCurrentRealTime() - started >= startTimeout
			Debug.Trace("[SNB Choices] " + speaker.GetDisplayName() + " did not start talking within " + startTimeout + "s, going on")
			Return
		EndIf
		If speakerSentences > 0 && !speakerPlaying && Utility.GetCurrentRealTime() - lastSentenceEnd >= 1.5 \
				&& SkyrimNetApi.GetSpeechQueueSize() == 0
			Return
		EndIf
		If holdSpeaker
			HoldSpeakerInPlace()
		EndIf
		Utility.Wait(0.25)
	EndWhile
EndFunction

; ---------------------------------------------------------------------------------------------
; 3. The player picks a reply; the NPC answers and the conversation ends
; ---------------------------------------------------------------------------------------------

Function ChooseReply()
	conversationState = StateChoosing
	; Cleared before the menu opens: the picked line can start playing while it is still open.
	playerStarted = False
	; The vanilla dialogue menu first; when it does not open, a message box (every reply in full),
	; then the list menu, which cuts long lines.
	Int picked = NoDialogueMenu
	If ConfigString("menu_style", "dialogue") == "dialogue"
		picked = PickWithDialogueMenu()
	EndIf
	; A topic picked in the dialogue menu is said aloud by SkyrimNet's player voice (through Dragonborn
	; Voice Over up to beta 28, by SkyrimNet itself since beta 29). A pick in the other menus is not
	; voiced: beta 29 removed TriggerPlayerTTS, the only way to voice a line from a script.
	Timing("menu closed, picked " + picked)
	Bool alreadyVoiced = picked != NoDialogueMenu
	If picked == NoDialogueMenu
		picked = PickWithMessageBox()
	EndIf
	If picked == NoMessageBox
		picked = PickWithList()
	EndIf
	Int reason = EndClosed
	If picked >= 0 && picked < replyCount && speaker && !speaker.IsDead()
		; Sent before the answer, so a caller can act on the choice while the NPC replies.
		SendReplyChosen(picked, replies[picked])
		String intent = ""
		If picked < intentCount
			intent = intents[picked]
		EndIf
		If npcAnswers
			PlayerAnswers(replies[picked], alreadyVoiced, intent)
		Else
			PlayerSays(replies[picked], alreadyVoiced)
		EndIf
		reason = EndAnswered
	ElseIf picked == LeaveReply || picked >= replyCount
		; The message box and the list menu put "leave" right after the replies.
		SendReplyChosen(LeaveReply, "")
		reason = EndLeft
	EndIf
	Finish(reason)
EndFunction

; Ends the conversation: the NPC goes back to their own package. reason is one of the End*
; properties, reported to the brothel in skyrimnet_BrothelChoices_Ended.
Function Finish(Int reason)
	If speaker
		SkyrimNetApi.UnregisterPackageEx(speaker, ApproachPackage, PackageOwner)
		SendEnded(reason)
	EndIf
	holdSpeaker = False
	conversationState = StateIdle
	speaker = None
	requestTag = ""
	intentCount = 0
	npcAnswers = True
EndFunction

Function SendStarted()
	Int handle = ModEvent.Create("skyrimnet_BrothelChoices_Started")
	If handle
		ModEvent.PushForm(handle, speaker)
		ModEvent.PushString(handle, requestTag)
		ModEvent.PushBool(handle, playerStarts)
		ModEvent.Send(handle)
	EndIf
EndFunction

; aiIndex: the reply (or, with intents, the intent) the player picked; -1 to leave.
Function SendReplyChosen(Int index, String text)
	Int handle = ModEvent.Create("skyrimnet_BrothelChoices_ReplyChosen")
	If handle
		ModEvent.PushForm(handle, speaker)
		ModEvent.PushString(handle, requestTag)
		ModEvent.PushInt(handle, index)
		ModEvent.PushString(handle, text)
		ModEvent.Send(handle)
	EndIf
EndFunction

Function SendEnded(Int reason)
	Int handle = ModEvent.Create("skyrimnet_BrothelChoices_Ended")
	If handle
		ModEvent.PushForm(handle, speaker)
		ModEvent.PushString(handle, requestTag)
		ModEvent.PushInt(handle, reason)
		ModEvent.Send(handle)
	EndIf
EndFunction

; Distinct from NoReply (-2) and LeaveReply (-1): a menu the player closed without picking ends
; the conversation, a menu that never showed falls through to the next one.
Int Property NoDialogueMenu = -3 AutoReadOnly
Int Property NoMessageBox = -4 AutoReadOnly

; Opens the vanilla dialogue menu with the speaker, with the plugin's reply topics renamed to the
; replies. The topics and a silent greeting only pass their conditions while the speaker is in
; SpeakerFaction; the reply topics also need ReplyCount to reach their number. Each topic's
; fragment reports the pick through OnReplyChosen. Returns the reply index, LeaveReply or NoReply
; (closed without picking), or NoDialogueMenu when the menu did not open.
Int Function PickWithDialogueMenu()
	Actor player = Game.GetPlayer()
	Faction speakerFaction = Game.GetFormFromFile(SpeakerFactionID, PluginFile) as Faction
	GlobalVariable replyCountGlobal = Game.GetFormFromFile(ReplyCountID, PluginFile) as GlobalVariable
	If !speakerFaction || !replyCountGlobal
		Return NoDialogueMenu
	EndIf
	Int i = 0
	While i < replyCount
		Game.GetFormFromFile(FirstReplyTopicID + i * 3, PluginFile).SetName(replies[i])
		i += 1
	EndWhile
	Game.GetFormFromFile(LeaveTopicID, PluginFile).SetName(ConfigString("leave_label", "(Say nothing and walk away)"))
	replyCountGlobal.SetValue(replyCount as Float)
	speaker.AddToFaction(speakerFaction)
	chosenReply = NoReply
	Bool opened = OpenDialogueWith(player)
	Timing("dialogue menu opened=" + opened)
	; The menu fills its list a moment after it opens, and fills it again after a pick.
	Int marked = 0
	Int checks = 0
	While UI.IsMenuOpen("Dialogue Menu")
		If checks < 20
			marked += MarkRepliesNew()
			checks += 1
		EndIf
		Utility.WaitMenuMode(0.1)
	EndWhile
	If ConfigInt("debug", 0) != 0
		String report = "SNB Choices: menu=" + opened + " entries=" + UI.GetInt(DialogueMenuName, TopicListPath + ".entryList.length") \
			+ " marked=" + marked + " chosen=" + chosenReply
		Debug.Trace(report)
		Debug.Notification(report)
	EndIf
	speaker.RemoveFromFaction(speakerFaction)
	replyCountGlobal.SetValue(0.0)
	If !opened
		Debug.Trace("[SNB Choices] The dialogue menu did not open with " + speaker.GetDisplayName())
		Return NoDialogueMenu
	EndIf
	Return chosenReply
EndFunction

; Opens the vanilla dialogue menu with the speaker. Right after another conversation (the calling
; mod's own topic, say) the game can ignore the activation, so the player's line is let finish and
; the activation is tried up to three times.
Bool Function OpenDialogueWith(Actor player)
	Float waited = 0.0
	While waited < 5.0 && playerPlaying
		Utility.Wait(0.25)
		waited += 0.25
	EndWhile
	Int attempt = 0
	While attempt < 3
		If attempt > 0
			Utility.Wait(1.0)
		EndIf
		speaker.Activate(player)
		Float started = Utility.GetCurrentRealTime()
		While !UI.IsMenuOpen(DialogueMenuName) && Utility.GetCurrentRealTime() - started < 2.0
			Utility.WaitMenuMode(0.1)
		EndWhile
		If UI.IsMenuOpen(DialogueMenuName)
			Return True
		EndIf
		attempt += 1
	EndWhile
	Return False
EndFunction

String Property DialogueMenuName = "Dialogue Menu" AutoReadOnly
String Property TopicListPath = "_root.DialogueMenu_mc.TopicList" AutoReadOnly

; The reply topics are reused every conversation, so the game greys a reply the player picked
; before as already said. The menu's list entries carry that as topicIsNew: set it back on the
; entries showing this conversation's replies and redraw. Returns how many entries were changed.
Int Function MarkRepliesNew()
	Int count = UI.GetInt(DialogueMenuName, TopicListPath + ".entryList.length")
	Int changed = 0
	Int i = 0
	While i < count
		String entry = TopicListPath + ".entryList." + i
		If !UI.GetBool(DialogueMenuName, entry + ".topicIsNew") && IsReplyText(UI.GetString(DialogueMenuName, entry + ".text"))
			UI.SetBool(DialogueMenuName, entry + ".topicIsNew", True)
			changed += 1
		EndIf
		i += 1
	EndWhile
	If changed > 0
		UI.Invoke(DialogueMenuName, TopicListPath + ".UpdateList")
	EndIf
	Return changed
EndFunction

Bool Function IsReplyText(String text)
	If text == ""
		Return False
	EndIf
	Int i = 0
	While i < replyCount
		If text == replies[i]
			Return True
		EndIf
		i += 1
	EndWhile
	Return text == ConfigString("leave_label", "(Say nothing and walk away)")
EndFunction

; Called by the fragments of the reply topics (skyrimnet_BrothelChoicesTIF_Reply1-5) and the leave topic.
Function OnReplyChosen(Int index)
	chosenReply = index
EndFunction

; The NPC's line and the numbered replies as the body text, which wraps, and one short button per
; reply. Needs Papyrus MessageBox (SkyrimScripting.MessageBox.dll); NoMessageBox without it.
Int Function PickWithMessageBox()
	String body = speaker.GetDisplayName() + "\n"
	If openingLine != ""
		body = speaker.GetDisplayName() + ":\n" + openingLine + "\n"
	EndIf
	String[] buttons = Utility.CreateStringArray(replyCount + 1)
	Int i = 0
	While i < replyCount
		body += "\n" + (i + 1) + ". " + replies[i]
		buttons[i] = (i + 1) as String
		i += 1
	EndWhile
	buttons[replyCount] = ConfigString("leave_button", "Leave")
	Int box = SkyMessage.ShowArray_NonBlocking(body, buttons)
	If box == 0
		Return NoMessageBox
	EndIf
	While !SkyMessage.IsMessageResultAvailable(box)
		Utility.WaitMenuMode(0.1)
	EndWhile
	Return SkyMessage.GetResultIndex(box)
EndFunction

Int Function PickWithList()
	UIListMenu menu = UIExtensions.GetMenu("UIListMenu") as UIListMenu
	If !menu
		Notify("msg_no_menu", "UIExtensions is missing: cannot show the replies.")
		Return -1
	EndIf
	Int i = 0
	While i < replyCount
		menu.AddEntryItem(replies[i])
		i += 1
	EndWhile
	menu.AddEntryItem(ConfigString("leave_label", "(Say nothing and walk away)"))
	menu.OpenMenu()
	Return menu.GetResultInt()
EndFunction

; The NPC answers the chosen reply once the player's voice (for a dialogue menu pick) has said it.
Function PlayerAnswers(String reply, Bool alreadyVoiced, String intent)
	Actor player = Game.GetPlayer()
	; SkyrimNet ends its own dialogue when the menu closes and drops TalkToPlayer with it, so the NPC
	; walked off while answering. Put it back and keep it until the answer has been said.
	holdSpeaker = True
	HoldSpeakerInPlace()
	If alreadyVoiced
		WaitForPlayerLine(3.0, 30.0)
	EndIf
	Timing("player line done")
	String npcName = speaker.GetDisplayName()
	String playerName = player.GetDisplayName()
	ClearOtherSpeech()
	ResetSpeechTracking()
	String said = " answers "
	If playerStarts
		said = " says to "
	EndIf
	; With an intent, the NPC is told what the reply means, so their answer follows it
	; (an accepted request is treated as accepted).
	String meaning = ""
	If intent != ""
		meaning = " (" + playerName + " means: " + intent + ")"
	EndIf
	String settled = ""
	If answerNote != ""
		settled = answerNote + " "
	EndIf
	SkyrimNetApi.DirectNarration(playerName + said + npcName + ": \"" + reply + "\"" + meaning + ". " + settled \
		+ npcName + " replies to what " + playerName + " just said, in " + npcName + "'s own words and in one or two short sentences, and brings this short conversation to a natural close.", \
		speaker, player)
	Timing("NPC asked to answer")
	WaitForSpeech(ConfigFloat("speech_timeout", 40.0))
	Timing("NPC finished the answer")
	holdSpeaker = False
EndFunction

; The chosen reply and nothing more: the caller has the NPC react itself, once the player's voice
; (for a dialogue menu pick) has said it.
Function PlayerSays(String reply, Bool alreadyVoiced)
	If alreadyVoiced
		WaitForPlayerLine(3.0, 30.0)
	EndIf
	Timing("player line done")
EndFunction

; Puts the approach package back on the speaker when SkyrimNet has taken it off.
Function HoldSpeakerInPlace()
	If speaker && !speakerReleased && SkyrimNetApi.HasPackage(speaker, ApproachPackage) == 0
		SkyrimNetApi.RegisterPackageEx(speaker, ApproachPackage, -1, False, PackageOwner, "Brothel Choices", False)
	EndIf
EndFunction

; The caller has moved on while the speaker is still answering (the brothel starts the scene as
; soon as a position is picked): the speaker is no longer held on the approach package, which would
; fight the scene. The answer itself still plays.
Bool speakerReleased

Function LetSpeakerGo()
	speakerReleased = True
	holdSpeaker = False
	If speaker
		SkyrimNetApi.UnregisterPackageEx(speaker, ApproachPackage, PackageOwner)
	EndIf
	Timing("caller moved on")
EndFunction

; ---------------------------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------------------------

Int Function ConfigInt(String setting, Int fallback)
	Return JsonUtil.GetIntValue(ConfigFile, setting, fallback)
EndFunction

Float Function ConfigFloat(String setting, Float fallback)
	Return JsonUtil.GetFloatValue(ConfigFile, setting, fallback)
EndFunction

String Function ConfigString(String setting, String fallback)
	Return JsonUtil.GetStringValue(ConfigFile, setting, fallback)
EndFunction

; A notification whose text the config may replace; "{name}" in it becomes name.
Function Notify(String setting, String fallback, String name = "")
	String text = ConfigString(setting, "")
	If text == ""
		Debug.Notification(fallback)
		Return
	EndIf
	Int at = StringUtil.Find(text, "{name}")
	If at >= 0
		text = StringUtil.Substring(text, 0, at) + name + StringUtil.Substring(text, at + 6)
	EndIf
	Debug.Notification(text)
EndFunction

; The FormID as SkyrimNet's formid_to_uuid wants it: unsigned decimal. Papyrus ints are signed, so
; FormIDs of ESL and late-loading plugins (0x80000000 and up) come out negative.
String Function UnsignedFormID(Actor akActor)
	Int id = akActor.GetFormID()
	If id >= 0
		Return id as String
	EndIf
	; id + 2^32 = (id + 2^31) + 2147483648, added in base 10000 to stay inside 32 bits.
	Int x = (id + 2147483647) + 1
	Int low = (x % 10000) + 3648
	Int high = (x / 10000) + 214748 + (low / 10000)
	low = low % 10000
	String lowText = low as String
	While StringUtil.GetLength(lowText) < 4
		lowText = "0" + lowText
	EndWhile
	Return (high as String) + lowText
EndFunction

; "Whiterun, indoors, in the evening"
String Function Situation(Actor player)
	String text = ""
	Location here = player.GetCurrentLocation()
	If here && here.GetName() != ""
		text = here.GetName() + ", "
	EndIf
	If player.IsInInterior()
		text += "indoors, "
	Else
		text += "outdoors, "
	EndIf
	Float hour = (Game.GetFormFromFile(0x000038, "Skyrim.esm") as GlobalVariable).GetValue() ; GameHour
	If hour < 5.0 || hour >= 22.0
		text += "late at night"
	ElseIf hour < 11.0
		text += "in the morning"
	ElseIf hour < 17.0
		text += "in the afternoon"
	Else
		text += "in the evening"
	EndIf
	Return text
EndFunction

; Quotes and backslashes escaped for a JSON string. Text is only cut at those ASCII characters, never
; rebuilt character by character, so multi-byte (Japanese) names stay whole.
String Function JsonEscape(String text)
	Return EscapeChar(EscapeChar(text, "\\"), "\"")
EndFunction

String Function EscapeChar(String text, String c)
	String result = ""
	Int at = StringUtil.Find(text, c)
	While at >= 0
		result += StringUtil.Substring(text, 0, at) + "\\" + c
		text = StringUtil.Substring(text, at + 1)
		at = StringUtil.Find(text, c)
	EndWhile
	Return result + text
EndFunction

; Without the spaces, tabs and carriage returns a model leaves around a line. Only ASCII bytes are
; looked at, so Japanese text passes through untouched.
String Function Trim(String line)
	Int size = StringUtil.GetLength(line)
	Int first = 0
	While first < size && IsBlank(StringUtil.GetNthChar(line, first))
		first += 1
	EndWhile
	Int last = size - 1
	While last >= first && IsBlank(StringUtil.GetNthChar(line, last))
		last -= 1
	EndWhile
	If last < first
		Return ""
	EndIf
	Return StringUtil.Substring(line, first, last - first + 1)
EndFunction

Bool Function IsBlank(String c)
	Int code = StringUtil.AsOrd(c)
	Return code > 0 && code <= 32
EndFunction

; A line without the "1." / "-" / "*" a model may put in front of it anyway.
String Function StripListMarker(String line)
	Int size = StringUtil.GetLength(line)
	Int first = 0
	While first < size && StringUtil.Find("-*.)0123456789 ", StringUtil.GetNthChar(line, first)) >= 0
		first += 1
	EndWhile
	Return StringUtil.Substring(line, first)
EndFunction

; Without ASCII double quotes around the whole line.
String Function Unquote(String line)
	Int size = StringUtil.GetLength(line)
	If size >= 2 && StringUtil.GetNthChar(line, 0) == "\"" && StringUtil.GetNthChar(line, size - 1) == "\""
		Return StringUtil.Substring(line, 1, size - 2)
	EndIf
	Return line
EndFunction
