Scriptname skyrimnet_Brothel extends MCM_ConfigBase
{Brothel run by the player. A chosen interior cell is the brothel; registered workers serve the
customers there, several pairs at once if the MCM allows. Settings live in
MCM/Settings/skyrimnet_Brothel.ini.}

; Records of this plugin, looked up by FormID so the quest needs no property links.
Int Property CustomerBaseID = 0x801 AutoReadOnly
Int Property CustomerFemaleBaseID = 0x825 AutoReadOnly
String Property PluginName = "skyrimnet_Brothel.esp" AutoReadOnly
String Property SceneHook = "skyrimnet_Brothel" AutoReadOnly

; The MCM's customer count runs from 1 to this.
Int Property MaxCustomers = 10 AutoReadOnly
Int Property MaxWorkers = 64 AutoReadOnly

; A deal that never reaches its scene, or a scene whose end hook never comes, is cleared after
; these many seconds by the watchdog.
Float Property BusyTimeoutSeconds = 300.0 AutoReadOnly
Float Property SceneTimeoutSeconds = 1800.0 AutoReadOnly
Float Property WatchdogSeconds = 30.0 AutoReadOnly

; How far from the worker a free bed is looked for when the bed mode is "always". The height reach
; covers the rooms upstairs in an inn, which SexLab's own search (512) misses.
Float Property BedSearchRadius = 4096.0 AutoReadOnly
Float Property BedSearchRadiusZ = 2048.0 AutoReadOnly
; SexLab's bed types (sslThreadLibrary): 1 bedroll, 2 single, 3 double.
Int Property BedTypeBedroll = 1 AutoReadOnly
; The engine's form type number for furniture, for po3's FindAllReferencesOfFormType.
Int Property FormTypeFurniture = 40 AutoReadOnly
; Pairs without a bed start at least this far from the other pairs' scenes when they can.
Float Property SceneSpacing = 250.0 AutoReadOnly
; How close the customer comes to the worker to talk.
Float Property TalkDistance = 150.0 AutoReadOnly
; How long the walk over may take, and how long the walker may stop getting closer, before he is
; placed in front of the other one (see ApproachWorker).
Float Property ApproachTimeoutSeconds = 20.0 AutoReadOnly
Float Property ApproachStuckSeconds = 6.0 AutoReadOnly
; SexLab 1.6x rather than P+: their scene APIs differ, so each call that depends on it goes to
; skyrimnet_BrothelSL16 or skyrimnet_BrothelSLP (see DetectSexLab).
Bool legacySexLab

Cell brothelCell
Actor[] customers
Actor[] workers
Int workerCount

Int serveKey
Int registerKey
Int playerServeKey

; skyrimnet_Brothel_PlayerOfferMsg: the player's accept / refuse box.
Int Property PlayerOfferMsgID = 0x803 AutoReadOnly
; Phrases with names in them (see AnnounceApproach). JsonUtil paths start in
; Data/SKSE/Plugins/StorageUtilData/, hence the "../".
String Property StringsFile = "../skyrimnet_Brothel/strings.json" AutoReadOnly

; Deals in progress, one slot per worker-customer pair: up to MaxConcurrentWorkers workers (MCM)
; plus the player. Each slot carries a serial so a serving thread whose slot was cleared and
; reused by a newer deal can tell, and stops.
Int Property DealSlots = 13 AutoReadOnly
Int Property MaxConcurrentWorkers = 12 AutoReadOnly
Int Property DealFree = 0 AutoReadOnly
Int Property DealPending = 1 AutoReadOnly   ; the offer is made; waiting for the worker's answer
Int Property DealAccepted = 2 AutoReadOnly
Int Property DealRefused = 3 AutoReadOnly
Int Property DealApproaching = 4 AutoReadOnly ; reserved; the customer is walking over
Int Property DealInScene = 5 AutoReadOnly
Actor[] dealWorkers
Actor[] dealCustomers
Int[] dealStates
Int[] dealThreads
Int[] dealSerials
Float[] dealStarted
Int[] dealIdleRuns          ; watchdog runs in a row that found a scene's pair out of SexLab
; Paid up front the moment the offer is accepted (see PayForDeal): what the worker and the owner
; got, given back if the deal falls through before its scene.
Bool[] dealPaid
Int[] dealPaidWorker
Int[] dealPaidOwner
; The worker (or the player) made the offer and the customer answers (see WorkerSolicits).
Bool[] dealSolicited
; Real time the answering side (the worker, or the customer when invited) last finished a line
; while the deal awaited the answer (OnSkyrimNetAudioEnded); 0.0 when not yet.
Float[] dealAnsweredAt
ObjectReference[] dealBeds    ; the bed a pair's scene took, so no other pair takes it too
ObjectReference[] dealSpots   ; a marker where the customer stood before walking over
ObjectReference[] dealCenters ; where the pair's scene is: its bed, its spot or the worker
Int nextSerial

; One pair talks at a time (see AcquireTalk).
Bool talking
Float talkingSince
Float Property TalkTurnTimeoutSeconds = 120.0 AutoReadOnly

; How long the worker has to accept or refuse in conversation before the scene starts anyway.
Float Property DealTimeoutSeconds = 60.0 AutoReadOnly

; MCM buttons only queue their action: the menu pauses the game, so the work runs once it closes.
String pendingAction
Int pendingCloseSlot = -1

Event OnInit()
	; MCM Helper and SkyUI register the menu from their own OnInit.
	Parent.OnInit()
	customers = new Actor[10]
	workers = new Actor[64]
	workerCount = 0
	Setup()
EndEvent

; Called by the player alias on every save load: key and mod-event registrations do not survive one,
; and no deal or scene in progress does either.
Function Setup()
	DetectSexLab()
	GrowCustomerSlots()
	GrowVisitorSlots()
	GrowBrothelSlots()
	ResetDeals()
	talking = False
	pickingBed = False
	RegisterKeys()
	RegisterForModEvent("HookAnimationEnd_" + SceneHook, "OnBrothelSceneEnd")
	RegisterForModEvent("skyrimnet_BrothelChoices_ReplyChosen", "OnChoicesReplyChosen")
	RegisterForModEvent("skyrimnet_BrothelChoices_Ended", "OnChoicesEnded")
	RegisterForModEvent("SkyrimNet_AudioEnded", "OnSkyrimNetAudioEnded")
	RegisterActions()
	; The count shown in the MCM lives in its settings file, not in the save: another save's count
	; would show after a load.
	DropMissingWorkers()
	ShowWorkerCount()
	SyncOwnerState()
	SyncBrothelGross()
	ownerNextAt = Utility.GetCurrentRealTime() + OwnerIntervalSeconds()
	solicitNextAt = Utility.GetCurrentRealTime() + SolicitIntervalSeconds()
	chatNextAt = Utility.GetCurrentRealTime() + ChatIntervalSeconds()
	ScheduleNextUpdate()
	ScheduleVisitors()
	ShowVisitorStatus()
	ShowBrothelCount()
	; The player may have saved in another brothel than the current one.
	SwitchToPlayersBrothel()
	GivePower()
EndFunction

; SkyrimNet actions that let the worker answer the customer from the conversation itself.
Function RegisterActions()
	SkyrimNetApi.RegisterAction("AcceptCustomerOffer", \
		"Accept the paying customer's offer and take them to bed right now. Use this only when you have agreed to their offer in the conversation.", \
		"skyrimnet_Brothel", "Deal_IsEligible", "skyrimnet_Brothel", "AcceptCustomerOffer_Execute", \
		"", "PAPYRUS", 1, "")
	SkyrimNetApi.RegisterAction("RefuseCustomerOffer", \
		"Turn down the paying customer's offer. Use this only when you have refused them in the conversation.", \
		"skyrimnet_Brothel", "Refuse_IsEligible", "skyrimnet_Brothel", "RefuseCustomerOffer_Execute", \
		"", "PAPYRUS", 1, "")
	; The other way round: a worker (or the player) offers a customer her company, and he answers.
	SkyrimNetApi.RegisterAction("AcceptWorkerOffer", \
		"Agree to the girl's offer of her company tonight and pay her. Use this only when you have said yes to her in the conversation.", \
		"skyrimnet_Brothel", "Solicit_IsEligible", "skyrimnet_Brothel", "AcceptWorkerOffer_Execute", \
		"", "PAPYRUS", 1, "")
	SkyrimNetApi.RegisterAction("DeclineWorkerOffer", \
		"Turn down the girl's offer of her company tonight. Use this only when you have said no to her in the conversation.", \
		"skyrimnet_Brothel", "Solicit_IsEligible", "skyrimnet_Brothel", "DeclineWorkerOffer_Execute", \
		"", "PAPYRUS", 1, "")
EndFunction

Bool Function Solicit_IsEligible(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	Return brothel && brothel.SolicitPendingSlotOf(akActor) >= 0
EndFunction

Function AcceptWorkerOffer_Execute(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	If brothel
		brothel.AnswerSolicit(akActor, True)
	EndIf
EndFunction

Function DeclineWorkerOffer_Execute(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	If brothel
		brothel.AnswerSolicit(akActor, False)
	EndIf
EndFunction

; SkyrimNet sends SkyrimNet_AudioEnded (sender: the speaker) after each sentence it plays. A deal
; awaiting an answer notes when the answering side last finished one.
Event OnSkyrimNetAudioEnded(String eventName, String strArg, Float numArg, Form sender)
	Int i = 0
	While sender && i < DealSlots
		If dealStates[i] == DealPending && ((dealSolicited[i] && dealCustomers[i] == sender) || (!dealSolicited[i] && dealWorkers[i] == sender))
			dealAnsweredAt[i] = Utility.GetCurrentRealTime()
		EndIf
		i += 1
	EndWhile
EndEvent

; Whether the answering side has spoken and then been quiet for two seconds with no accept or
; decline action: the answer was given in words only. That happens when SkyrimNet refuses the
; action, as it does while the game is paused (a menu open at that moment); waiting out the full
; DealTimeoutSeconds then held every other pair up. The caller takes it as a yes.
Bool Function AnswerSpoken(Int slot)
	Return dealAnsweredAt[slot] > 0.0 && Utility.GetCurrentRealTime() - dealAnsweredAt[slot] >= 2.0
EndFunction

; The deal in which this customer owes an answer to a worker's (or the player's) offer, or -1.
Int Function SolicitPendingSlotOf(Actor akActor)
	Int i = 0
	While akActor && i < DealSlots
		If dealStates[i] == DealPending && dealSolicited[i] && dealCustomers[i] == akActor
			Return i
		EndIf
		i += 1
	EndWhile
	Return -1
EndFunction

Function AnswerSolicit(Actor akActor, Bool accepted)
	Int slot = SolicitPendingSlotOf(akActor)
	If slot < 0
		Return
	EndIf
	If accepted
		dealStates[slot] = DealAccepted
		PayForDeal(slot)
	Else
		dealStates[slot] = DealRefused
	EndIf
EndFunction

; Looked at on every load, as the player may have switched SexLab since the save. 1.6x's
; SexLabUtil.GetVersion returns its own version (16601 for 1.66b); P+'s returns the version of its
; SKSE plugin, a far larger number (or 0 without the plugin, still P+).
Function DetectSexLab()
	Int version = SexLabUtil.GetVersion()
	legacySexLab = version > 0 && version < 20000
	If GetModSettingBool("bDebugLog:General")
		DebugLog("SexLab version " + version + ", using the " + SexLabName() + " calls")
	EndIf
EndFunction

String Function SexLabName()
	If legacySexLab
		Return "1.6x"
	EndIf
	Return "P+"
EndFunction

skyrimnet_Brothel Function Brothel() Global
	Return Game.GetFormFromFile(0x802, "skyrimnet_Brothel.esp") as skyrimnet_Brothel
EndFunction

Bool Function Deal_IsEligible(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	Return brothel && brothel.IsAwaitingAnswerFrom(akActor)
EndFunction

; Refusing is offered to the LLM only when the MCM allows it.
Bool Function Refuse_IsEligible(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	Return brothel && brothel.CanRefuse() && brothel.IsAwaitingAnswerFrom(akActor)
EndFunction

Bool Function CanRefuse()
	Return GetModSettingBool("bAllowRefuse:General") && !GetModSettingBool("bAlwaysAccept:General")
EndFunction

Function AcceptCustomerOffer_Execute(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	If brothel
		brothel.AnswerDeal(akActor, True)
	EndIf
EndFunction

Function RefuseCustomerOffer_Execute(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	If brothel
		brothel.AnswerDeal(akActor, False)
	EndIf
EndFunction

Bool Function IsAwaitingAnswerFrom(Actor akActor)
	Return PendingSlotOf(akActor) >= 0
EndFunction

Function AnswerDeal(Actor akActor, Bool accepted)
	Int slot = PendingSlotOf(akActor)
	If slot < 0
		Return
	EndIf
	If accepted
		dealStates[slot] = DealAccepted
		PayForDeal(slot)
	Else
		dealStates[slot] = DealRefused
	EndIf
EndFunction

Int Function PendingSlotOf(Actor akActor)
	Int i = 0
	While akActor && i < DealSlots
		If dealStates[i] == DealPending && !dealSolicited[i] && dealWorkers[i] == akActor
			Return i
		EndIf
		i += 1
	EndWhile
	Return -1
EndFunction

Event OnSettingChange(String a_ID)
	If a_ID == "iServeKey:General" || a_ID == "iRegisterKey:General" || a_ID == "iPlayerServeKey:General"
		RegisterKeys()
	ElseIf a_ID == "iCustomerCount:General" || a_ID == "iCustomerSex:General" || a_ID == "iHiredWorkers:General"
		pendingAction = "sync"
		RegisterForSingleUpdate(0.1)
	ElseIf a_ID == "bAutoServe:General" || a_ID == "iAutoInterval:General"
		(GetAlias(0) as skyrimnet_BrothelPlayer).ScheduleAutoServe()
	ElseIf a_ID == "bVisitors:General"
		ScheduleVisitors()
	ElseIf a_ID == "sOwnerPick:General"
		PickOwner(OwnerPickIndex())
	ElseIf a_ID == "iOwnerInterval:General"
		ownerNextAt = Utility.GetCurrentRealTime() + OwnerIntervalSeconds()
		ScheduleNextUpdate()
	ElseIf a_ID == "bWorkerSolicit:General" || a_ID == "iSolicitInterval:General"
		solicitNextAt = Utility.GetCurrentRealTime() + SolicitIntervalSeconds()
		ScheduleNextUpdate()
	ElseIf a_ID == "bWorkerChat:General" || a_ID == "iChatInterval:General"
		chatNextAt = Utility.GetCurrentRealTime() + ChatIntervalSeconds()
		ScheduleNextUpdate()
	ElseIf a_ID == "bPlayerWorks:General"
		UpdateOwnerTalk()
	ElseIf a_ID == "sWorkerPick:General" || a_ID == "iBrothelLevelGold:General" || a_ID == "iWorkerLevelGold:General"
		ShowLevels()
		RefreshMenu()
	EndIf
EndEvent

Function RegisterKeys()
	UnregisterForAllKeys()
	serveKey = GetModSettingInt("iServeKey:General")
	registerKey = GetModSettingInt("iRegisterKey:General")
	playerServeKey = GetModSettingInt("iPlayerServeKey:General")
	If serveKey > 0
		RegisterForKey(serveKey)
	EndIf
	If registerKey > 0
		RegisterForKey(registerKey)
	EndIf
	If playerServeKey > 0
		RegisterForKey(playerServeKey)
	EndIf
EndFunction

Event OnKeyDown(Int keyCode)
	If Utility.IsInMenuMode() || UI.IsTextInputEnabled()
		Return
	EndIf
	SwitchToPlayersBrothel()
	If keyCode == serveKey
		ServeCustomer(False)
	ElseIf keyCode == registerKey
		ToggleWorker(Game.GetCurrentCrosshairRef() as Actor)
	ElseIf keyCode == playerServeKey
		If PlayerWorks()
			ServePlayer()
		Else
			Debug.Notification("$SNB_PlayerNotWorking")
		EndIf
	EndIf
EndEvent

; MCM: whether the player works as one of the girls (own hotkey, the solicit topic, an NPC owner's
; rounds), and whether customers are also sent to the player: automatically, by hotkey, or on an NPC
; owner's recommendation.
Bool Function PlayerWorks()
	Return GetModSettingBool("bPlayerWorks:General")
EndFunction

Bool Function PlayerInAutoServe()
	Return PlayerWorks() && GetModSettingBool("bAutoIncludePlayer:General")
EndFunction

; The workers, then the player when the player works: index 0 to workerCount (inclusive); None for
; an empty place.
Actor Function StaffAt(Int index)
	If index < workerCount
		Return workers[index]
	ElseIf index == workerCount && PlayerWorks()
		Return Game.GetPlayer()
	EndIf
	Return None
EndFunction

; ---------------------------------------------------------------------------------------------
; MCM buttons and the watchdog
; ---------------------------------------------------------------------------------------------

Function DesignateBrothel()
	pendingAction = "designate"
	RegisterForSingleUpdate(0.1)
EndFunction

; MCM button: closes the brothel picked in the brothel list, once the menu closes.
Function ClearBrothel()
	pendingCloseSlot = PickedBrothelSlot()
	pendingAction = "clear"
	RegisterForSingleUpdate(0.1)
EndFunction

; Runs queued MCM actions, then clears deals that stalled. While any deal is open it comes back
; every WatchdogSeconds.
Event OnUpdate()
	String queued = pendingAction
	pendingAction = ""
	If queued == "designate"
		DoDesignateBrothel()
	ElseIf queued == "clear"
		CloseBrothel(pendingCloseSlot)
	ElseIf queued == "sync"
		SyncCustomers()
		SyncHiredWorkers()
	ElseIf queued == "registerfollowers"
		DoRegisterFollowers()
	ElseIf queued == "unregisterfollowers"
		DoUnregisterFollowers()
	ElseIf queued == "manage"
		ManageMenu()
	EndIf
	ClearStalledDeals()
	; The next update is booked before the long work below (a whole conversation and deal), so the
	; watchdog and the owner's rounds keep running meanwhile.
	Bool ownerDue = NpcOwnerDue()
	Bool solicitDue = SolicitDue()
	Bool chatDue = ChatDue()
	ScheduleNextUpdate()
	If queued == "recommend"
		Actor customer = pendingRecommend
		pendingRecommend = None
		PlayerRecommends(customer)
	ElseIf queued == "solicit"
		Actor approached = pendingRecommend
		pendingRecommend = None
		PlayerSolicits(approached)
	EndIf
	If ownerDue
		OwnerRound()
	EndIf
	If solicitDue
		WorkerSolicitRound()
	EndIf
	If chatDue
		WorkerChatRound()
	EndIf
EndEvent

; A queued MCM action already has a short update pending; the watchdog runs after it anyway.
Function ScheduleWatchdog()
	If pendingAction == ""
		ScheduleNextUpdate()
	EndIf
EndFunction

; One update serves the watchdog (every WatchdogSeconds while a deal is open) and an NPC owner's
; rounds (at ownerNextAt), workers' invitations and their chats: it is booked for whichever comes first.
Function ScheduleNextUpdate()
	Float delay = 0.0
	If OpenDealCount() > 0
		delay = WatchdogSeconds
	EndIf
	If NpcOwnsBrothel()
		Float ownerDelay = ownerNextAt - Utility.GetCurrentRealTime()
		If ownerDelay < 1.0
			ownerDelay = 1.0
		EndIf
		If delay == 0.0 || ownerDelay < delay
			delay = ownerDelay
		EndIf
	EndIf
	If GetModSettingBool("bWorkerSolicit:General")
		Float solicitDelay = solicitNextAt - Utility.GetCurrentRealTime()
		If solicitDelay < 1.0
			solicitDelay = 1.0
		EndIf
		If delay == 0.0 || solicitDelay < delay
			delay = solicitDelay
		EndIf
	EndIf
	If GetModSettingBool("bWorkerChat:General")
		Float chatDelay = chatNextAt - Utility.GetCurrentRealTime()
		If chatDelay < 1.0
			chatDelay = 1.0
		EndIf
		If delay == 0.0 || chatDelay < delay
			delay = chatDelay
		EndIf
	EndIf
	If delay > 0.0
		RegisterForSingleUpdate(delay)
	EndIf
EndFunction

Int Function TargetCustomerCount()
	Int count = GetModSettingInt("iCustomerCount:General")
	If count < 1
		Return 1
	ElseIf count > MaxCustomers
		Return MaxCustomers
	EndIf
	Return count
EndFunction

; How many of the brothel's own customers are women (MCM "Customers' sex": men, women, or half and
; half, with an odd count one more man: 3 is two men and a woman).
Int Function TargetWomenCount()
	Int sex = GetModSettingInt("iCustomerSex:General")
	If sex == 1
		Return TargetCustomerCount()
	ElseIf sex == 2
		Return TargetCustomerCount() / 2
	EndIf
	Return 0
EndFunction

Bool Function IsWoman(Actor akActor)
	Return akActor.GetLeveledActorBase().GetSex() == 1
EndFunction

; Pronouns for a customer in narrations, now that customers can be women.
String Function HeOf(Actor akActor)
	If IsWoman(akActor)
		Return "she"
	EndIf
	Return "he"
EndFunction

String Function HisOf(Actor akActor)
	If IsWoman(akActor)
		Return "her"
	EndIf
	Return "his"
EndFunction

String Function HimOf(Actor akActor)
	If IsWoman(akActor)
		Return "her"
	EndIf
	Return "him"
EndFunction

; A man or a woman from the plugin's two customer NPCs, whose looks come from vanilla men's or
; women's templates.
Actor Function SpawnCustomer(ObjectReference near, Bool woman = False)
	Int baseID = CustomerBaseID
	If woman
		baseID = CustomerFemaleBaseID
	EndIf
	ActorBase customerBase = Game.GetFormFromFile(baseID, PluginName) as ActorBase
	Actor customer = near.PlaceAtMe(customerBase, 1, True, False) as Actor
	customer.MoveTo(near, Utility.RandomFloat(-200.0, 200.0), Utility.RandomFloat(-200.0, 200.0), 0.0)
	Return customer
EndFunction

; Saves from before the customer count setting hold a 3-slot array.
Function GrowCustomerSlots()
	If customers && customers.Length >= MaxCustomers
		Return
	EndIf
	Actor[] grown = new Actor[10]
	Int i = 0
	While customers && i < customers.Length
		grown[i] = customers[i]
		i += 1
	EndWhile
	customers = grown
EndFunction

; Brings the brothel to the MCM's customer count and sex mix. Extra men or women leave first, never
; one in a deal; then the missing ones appear beside a customer already there (or beside the player
; in the brothel). Dead customers are cleared away and replaced. One kept for his deal leaves at
; the next sync.
Function SyncCustomers()
	If !brothelCell
		Return
	EndIf
	Actor anchor = None
	Int men = 0
	Int women = 0
	Int i = 0
	While i < customers.Length
		If customers[i] && customers[i].IsDead()
			customers[i].Disable()
			customers[i].Delete()
			customers[i] = None
		EndIf
		If customers[i]
			If IsWoman(customers[i])
				women += 1
			Else
				men += 1
			EndIf
			If !anchor
				anchor = customers[i]
			EndIf
		EndIf
		i += 1
	EndWhile
	If !anchor && Game.GetPlayer().GetParentCell() == brothelCell
		anchor = Game.GetPlayer()
	EndIf

	Int targetWomen = TargetWomenCount()
	Int targetMen = TargetCustomerCount() - targetWomen
	i = customers.Length - 1
	While i >= 0
		If customers[i] && !IsInDeal(customers[i])
			Bool woman = IsWoman(customers[i])
			If (woman && women > targetWomen) || (!woman && men > targetMen)
				customers[i].Disable()
				customers[i].Delete()
				customers[i] = None
				If woman
					women -= 1
				Else
					men -= 1
				EndIf
			EndIf
		EndIf
		i -= 1
	EndWhile
	i = 0
	While (men < targetMen || women < targetWomen) && anchor && i < customers.Length
		If !customers[i]
			Bool spawnWoman = women < targetWomen
			customers[i] = SpawnCustomer(anchor, spawnWoman)
			If spawnWoman
				women += 1
			Else
				men += 1
			EndIf
		EndIf
		i += 1
	EndWhile
EndFunction

Function DismissCustomers()
	Int i = 0
	While i < customers.Length
		If customers[i]
			customers[i].Disable()
			customers[i].Delete()
			customers[i] = None
		EndIf
		i += 1
	EndWhile
EndFunction

; ---------------------------------------------------------------------------------------------
; Hired workers
; ---------------------------------------------------------------------------------------------

; With "Hired workers" above 0 (MCM), the brothel hires women of its own: they appear like the
; customers, are registered as workers on the spot at "Hired workers' level", and stay in the
; brothel. One who is unregistered leaves the game, and all leave when the brothel closes or
; moves; their levels go with them.

Int Property MaxHiredWorkers = 10 AutoReadOnly
Int Property WorkerBaseID = 0x826 AutoReadOnly

Bool Function IsHiredWorker(Actor akActor)
	Return akActor && akActor.GetActorBase() == Game.GetFormFromFile(WorkerBaseID, PluginName) as ActorBase
EndFunction

Int Function TargetHiredCount()
	Int count = GetModSettingInt("iHiredWorkers:General")
	If count < 0
		Return 0
	ElseIf count > MaxHiredWorkers
		Return MaxHiredWorkers
	EndIf
	Return count
EndFunction

; A new worker beside near, registered at the MCM's starting level.
Function HireWorker(ObjectReference near)
	ActorBase workerBase = Game.GetFormFromFile(WorkerBaseID, PluginName) as ActorBase
	Actor worker = near.PlaceAtMe(workerBase, 1, True, False) as Actor
	worker.MoveTo(near, Utility.RandomFloat(-200.0, 200.0), Utility.RandomFloat(-200.0, 200.0), 0.0)
	Int level = GetModSettingInt("iHiredLevel:General")
	If level < 1
		level = 1
	ElseIf level > MaxLevel
		level = MaxLevel
	EndIf
	StorageUtil.SetIntValue(worker, "SNB_Gross", (level - 1) * WorkerLevelStep())
	StorageUtil.SetIntValue(worker, "SNB_HiredSlot", currentSlot)
	RegisterWorker(worker)
EndFunction

; Brings the current brothel's hired workers to the MCM's count, as SyncCustomers does for
; customers: dead ones are cleared away and replaced, extra ones leave (never one with a customer),
; missing ones appear beside the player in the brothel or beside a customer there.
Function SyncHiredWorkers()
	If !brothelCell
		Return
	EndIf
	Int hired = 0
	Int i = workerCount - 1
	While i >= 0
		If IsHiredWorker(workers[i]) && HiredSlotOf(workers[i]) == currentSlot
			If workers[i].IsDead()
				RemoveWorkerAt(i)
			Else
				hired += 1
			EndIf
		EndIf
		i -= 1
	EndWhile
	Int target = TargetHiredCount()
	i = workerCount - 1
	While hired > target && i >= 0
		If IsHiredWorker(workers[i]) && HiredSlotOf(workers[i]) == currentSlot && !IsInDeal(workers[i])
			RemoveWorkerAt(i)
			hired -= 1
		EndIf
		i -= 1
	EndWhile
	ObjectReference anchor = None
	If Game.GetPlayer().GetParentCell() == brothelCell
		anchor = Game.GetPlayer()
	EndIf
	i = 0
	While !anchor && i < customers.Length
		If customers[i] && customers[i].GetParentCell() == brothelCell
			anchor = customers[i]
		EndIf
		i += 1
	EndWhile
	While hired < target && anchor && workerCount < MaxWorkers
		HireWorker(anchor)
		hired += 1
	EndWhile
	ShowWorkerCount()
EndFunction

; The hired workers of the brothel in this slot (see Brothels below).
Function DismissHiredWorkers(Int slot)
	Int i = workerCount - 1
	While i >= 0
		If IsHiredWorker(workers[i]) && HiredSlotOf(workers[i]) == slot
			RemoveWorkerAt(i)
		EndIf
		i -= 1
	EndWhile
	ShowWorkerCount()
EndFunction

; Which brothel a hired worker works for. Those hired before there were several brothels have none
; stored and belong to the first.
Int Function HiredSlotOf(Actor worker)
	Return StorageUtil.GetIntValue(worker, "SNB_HiredSlot", 0)
EndFunction

; ---------------------------------------------------------------------------------------------
; Brothels
; ---------------------------------------------------------------------------------------------

; The player can run up to MaxUserBrothels brothels; BrothelSlots keeps one more slot, the last,
; for a quest to come. The rest of the script works on one brothel, the current one: brothelCell,
; customers, the town's people and its door and waiting spot, the owner and the brothel's takings.
; The current brothel is the one the player is in, or was in last. The others keep that state in
; StorageUtil on their cell, and it is swapped in when the player walks into one (or, closing one,
; it is cleared). Deals in flight and visitors on their way belong to the brothel left behind, so a
; switch closes the deals (gold given back before a scene) and sends the visitors home.
; Registered workers are shared: a worker takes customers in whichever brothel she is in. Hired
; workers belong to the brothel that hired them. MCM settings are shared by all brothels.

Int Property BrothelSlots = 4 AutoReadOnly
Int Property MaxUserBrothels = 3 AutoReadOnly

Cell[] brothelCells
Int currentSlot = -1
Bool brothelGrossSynced
; The MCM's brothel list as last shown, and the slot of each entry.
String[] brothelMenuNames
Int[] brothelMenuSlots

; Saves from before several brothels: their one brothel becomes the first.
Function GrowBrothelSlots()
	If brothelCells
		Return
	EndIf
	brothelCells = new Cell[4]
	currentSlot = -1
	If brothelCell
		brothelCells[0] = brothelCell
		currentSlot = 0
	EndIf
EndFunction

; How many brothels the player has made.
Int Function BrothelCount()
	Int count = 0
	Int i = 0
	While i < MaxUserBrothels
		If brothelCells[i]
			count += 1
		EndIf
		i += 1
	EndWhile
	Return count
EndFunction

; Closes every open deal: before a scene the customer gets the gold back (ReleaseDeal).
Function ReleaseOpenDeals()
	Int i = 0
	While i < DealSlots
		If dealStates[i] != DealFree
			ReleaseDeal(i)
		EndIf
		i += 1
	EndWhile
EndFunction

; Stores the current brothel's state on its cell.
Function SaveSlot()
	If !brothelCell
		Return
	EndIf
	Form slotKey = brothelCell
	StorageUtil.FormListClear(slotKey, "SNB_Customers")
	Int i = 0
	While i < customers.Length
		If customers[i]
			StorageUtil.FormListAdd(slotKey, "SNB_Customers", customers[i])
		EndIf
		i += 1
	EndWhile
	StorageUtil.FormListClear(slotKey, "SNB_TownPool")
	StorageUtil.FloatListClear(slotKey, "SNB_TownPoolLastVisit")
	i = 0
	While i < townPool.Length
		If townPool[i]
			StorageUtil.FormListAdd(slotKey, "SNB_TownPool", townPool[i])
			StorageUtil.FloatListAdd(slotKey, "SNB_TownPoolLastVisit", townPoolLastVisit[i])
		EndIf
		i += 1
	EndWhile
	StorageUtil.SetFormValue(slotKey, "SNB_Marker", brothelMarker)
	StorageUtil.SetFormValue(slotKey, "SNB_InsideDoor", insideDoor)
	StorageUtil.SetFormValue(slotKey, "SNB_OutsideDoor", outsideDoor)
	StorageUtil.SetFormValue(slotKey, "SNB_Owner", brothelOwner)
	StorageUtil.SetIntValue(slotKey, "SNB_BrothelGross", brothelGross)
EndFunction

; Makes the brothel in this slot the current one, reading its state from its cell. A slot never
; saved (a new brothel) starts empty.
Function LoadSlot(Int slot)
	currentSlot = slot
	brothelCell = None
	If slot >= 0
		brothelCell = brothelCells[slot]
	EndIf
	customers = new Actor[10]
	townPool = new Actor[40]
	townPoolLastVisit = new Float[40]
	brothelMarker = None
	insideDoor = None
	outsideDoor = None
	brothelOwner = None
	brothelGross = 0
	ownerKeptWaiting = None
	ownerLastReport = ""
	If !brothelCell
		Return
	EndIf
	Form slotKey = brothelCell
	Form[] stored = StorageUtil.FormListToArray(slotKey, "SNB_Customers")
	Int i = 0
	While i < stored.Length && i < customers.Length
		customers[i] = stored[i] as Actor
		i += 1
	EndWhile
	stored = StorageUtil.FormListToArray(slotKey, "SNB_TownPool")
	Float[] lastVisits = StorageUtil.FloatListToArray(slotKey, "SNB_TownPoolLastVisit")
	i = 0
	While i < stored.Length && i < townPool.Length
		townPool[i] = stored[i] as Actor
		If i < lastVisits.Length
			townPoolLastVisit[i] = lastVisits[i]
		EndIf
		i += 1
	EndWhile
	brothelMarker = StorageUtil.GetFormValue(slotKey, "SNB_Marker") as ObjectReference
	insideDoor = StorageUtil.GetFormValue(slotKey, "SNB_InsideDoor") as ObjectReference
	outsideDoor = StorageUtil.GetFormValue(slotKey, "SNB_OutsideDoor") as ObjectReference
	brothelOwner = StorageUtil.GetFormValue(slotKey, "SNB_Owner") as Actor
	brothelGross = StorageUtil.GetIntValue(slotKey, "SNB_BrothelGross", 0)
	If brothelOwner && brothelOwner.IsDead()
		brothelOwner = None
	EndIf
EndFunction

Function ClearSlotStorage(Cell slotCell)
	Form slotKey = slotCell
	StorageUtil.FormListClear(slotKey, "SNB_Customers")
	StorageUtil.FormListClear(slotKey, "SNB_TownPool")
	StorageUtil.FloatListClear(slotKey, "SNB_TownPoolLastVisit")
	StorageUtil.UnsetFormValue(slotKey, "SNB_Marker")
	StorageUtil.UnsetFormValue(slotKey, "SNB_InsideDoor")
	StorageUtil.UnsetFormValue(slotKey, "SNB_OutsideDoor")
	StorageUtil.UnsetFormValue(slotKey, "SNB_Owner")
	StorageUtil.UnsetIntValue(slotKey, "SNB_BrothelGross")
EndFunction

; Called when the player may have walked into another brothel (location changes, the player
; alias's timer, hotkeys, loads).
Function SwitchToPlayersBrothel()
	If !brothelCells
		Return
	EndIf
	Cell here = Game.GetPlayer().GetParentCell()
	If !here || here == brothelCell
		Return
	EndIf
	Int slot = brothelCells.Find(here)
	If slot >= 0
		SwitchToSlot(slot)
	EndIf
EndFunction

Function SwitchToSlot(Int slot)
	If slot == currentSlot
		Return
	EndIf
	ReleaseOpenDeals()
	ReleaseAllVisitors()
	SaveSlot()
	LoadSlot(slot)
	BrothelChanged()
	If GetModSettingBool("bDebugLog:General") && brothelCell
		DebugLog("Brothel: now in " + brothelCell.GetName() + " (slot " + slot + ")")
	EndIf
EndFunction

; Brings the MCM, the topics and the timers in line with the current brothel, and its customers
; and hired workers up to the MCM's counts.
Function BrothelChanged()
	If brothelCell
		SetModSettingString("sBrothelName:General", brothelCell.GetName())
		SyncCustomers()
		SyncHiredWorkers()
	Else
		SetModSettingString("sBrothelName:General", "$SNB_None")
	EndIf
	ShowBrothelCount()
	ShowOwner()
	ShowLevels()
	ShowWorkerCount()
	UpdateOwnerTalk()
	ScheduleVisitors()
	ShowVisitorStatus()
	ScheduleNextUpdate()
	(GetAlias(0) as skyrimnet_BrothelPlayer).ScheduleTick()
EndFunction

Function ShowBrothelCount()
	SetModSettingString("sBrothelCount:General", BrothelCount() + " / " + MaxUserBrothels)
EndFunction

; The MCM's brothel list: "1: Riften Bunkhouse" and so on; the pick is kept while it is still there,
; else the current brothel is picked. Set from OnPageSelect only (see OnConfigOpen).
Function RefreshBrothelMenu()
	brothelMenuNames = Utility.CreateStringArray(MaxUserBrothels)
	brothelMenuSlots = Utility.CreateIntArray(MaxUserBrothels)
	Int count = 0
	Int i = 0
	While i < MaxUserBrothels
		If brothelCells[i]
			brothelMenuNames[count] = (i + 1) + ": " + brothelCells[i].GetName()
			brothelMenuSlots[count] = i
			count += 1
		EndIf
		i += 1
	EndWhile
	If count == 0
		brothelMenuNames = new String[1]
		brothelMenuNames[0] = "$SNB_None"
		brothelMenuSlots = new Int[1]
		brothelMenuSlots[0] = -1
	Else
		brothelMenuNames = Utility.ResizeStringArray(brothelMenuNames, count)
		brothelMenuSlots = Utility.ResizeIntArray(brothelMenuSlots, count)
	EndIf
	SetMenuOptions("sBrothelPick:General", brothelMenuNames, brothelMenuNames)
	If brothelMenuNames.Find(GetModSettingString("sBrothelPick:General")) < 0
		Int current = brothelMenuSlots.Find(currentSlot)
		If current < 0
			current = 0
		EndIf
		SetModSettingString("sBrothelPick:General", brothelMenuNames[current])
	EndIf
EndFunction

; The slot picked in the MCM's brothel list; the current brothel when the list has not been shown.
Int Function PickedBrothelSlot()
	If brothelMenuNames
		Int index = brothelMenuNames.Find(GetModSettingString("sBrothelPick:General"))
		If index >= 0
			Return brothelMenuSlots[index]
		EndIf
	EndIf
	Return currentSlot
EndFunction

; Makes the interior the player stands in a new brothel, or makes it the current one if it already
; is one. The other brothels stay as they are.
Function DoDesignateBrothel()
	Actor player = Game.GetPlayer()
	Cell here = player.GetParentCell()
	If !here || !here.IsInterior()
		Debug.Notification("$SNB_NotInterior")
		Return
	EndIf
	Int existing = brothelCells.Find(here)
	If existing >= 0
		SwitchToSlot(existing)
		Debug.Notification("$SNB_AlreadyBrothel")
		Return
	EndIf
	Int slot = brothelCells.Find(None)
	If slot < 0 || slot >= MaxUserBrothels
		Debug.Notification("$SNB_BrothelLimit")
		Return
	EndIf
	ReleaseOpenDeals()
	ReleaseAllVisitors()
	SaveSlot()
	brothelCells[slot] = here
	ClearSlotStorage(here)
	LoadSlot(slot)
	Int women = TargetWomenCount()
	Int i = 0
	While i < TargetCustomerCount()
		customers[i] = SpawnCustomer(player, i < women)
		i += 1
	EndWhile
	FindBrothelDoors()
	BrothelChanged()
	Debug.Notification("$SNB_Designated")
EndFunction

; Closes the brothel in this slot: its customers and hired workers leave, its town and owner are
; forgotten. Closing the current one makes another brothel (if any) the current one.
Function CloseBrothel(Int slot)
	If slot < 0 || slot >= BrothelSlots || !brothelCells[slot]
		Return
	EndIf
	If slot == currentSlot
		ReleaseOpenDeals()
		DismissCustomers()
		ReleaseAllVisitors()
		ResetTown()
	Else
		Form slotKey = brothelCells[slot]
		Form[] stored = StorageUtil.FormListToArray(slotKey, "SNB_Customers")
		Int i = 0
		While i < stored.Length
			ObjectReference leaving = stored[i] as ObjectReference
			If leaving
				leaving.Disable()
				leaving.Delete()
			EndIf
			i += 1
		EndWhile
		ObjectReference marker = StorageUtil.GetFormValue(slotKey, "SNB_Marker") as ObjectReference
		If marker
			marker.Disable()
			marker.Delete()
		EndIf
	EndIf
	DismissHiredWorkers(slot)
	ClearSlotStorage(brothelCells[slot])
	brothelCells[slot] = None
	If slot == currentSlot
		Int next = 0
		While next < BrothelSlots && !brothelCells[next]
			next += 1
		EndWhile
		If next >= BrothelSlots
			next = -1
		EndIf
		LoadSlot(next)
	EndIf
	BrothelChanged()
	Debug.Notification("$SNB_Cleared")
EndFunction

; ---------------------------------------------------------------------------------------------
; Townsfolk visitors
; ---------------------------------------------------------------------------------------------

; With "Townsfolk visit" on (MCM), adults of the brothel's town walk over during the opening hours,
; wait there and are customers like the brothel's own; once served, or when they have waited too
; long or the brothel closes, they go back to their day. The mod learns who lives in town by
; looking around while the player is near the brothel's front door outside (ScanTown).

Int Property MaxVisitors = 5 AutoReadOnly
Int Property TownPoolSize = 40 AutoReadOnly
; How close to the brothel's front door (outside) the player must be for the people around to count
; as the town's, and how far around the player they are looked for.
Float Property TownRadius = 8000.0 AutoReadOnly
Float Property TownScanRadius = 6000.0 AutoReadOnly
; The engine's form type numbers for doors and NPCs, for po3's FindAllReferencesOfFormType.
Int Property FormTypeDoor = 29 AutoReadOnly
Int Property FormTypeNPC = 43 AutoReadOnly
; In game hours: how often visits are looked after, how long a visitor may take to arrive, and in
; game days how soon the same person may come again.
Float Property VisitorTickHours = 0.25 AutoReadOnly
Float Property VisitorWalkHours = 1.5 AutoReadOnly
Float Property VisitCooldownDays = 1.0 AutoReadOnly
; A visitor this close to the front door outside is let in: the door may be locked to them.
Float Property DoorReachDistance = 400.0 AutoReadOnly
Int Property VisitorWalking = 1 AutoReadOnly
Int Property VisitorInside = 2 AutoReadOnly

; Where visitors wait (placed where the player stands), the brothel's door to the outside and that
; door's other side.
ObjectReference brothelMarker
ObjectReference insideDoor
ObjectReference outsideDoor
Actor[] townPool
Float[] townPoolLastVisit
Actor[] visitors
Int[] visitorStates
Float[] visitorSince
Bool[] visitorServed

; Saves from before visitors have none of these arrays.
Function GrowVisitorSlots()
	If !townPool
		townPool = new Actor[40]
		townPoolLastVisit = new Float[40]
	EndIf
	If !visitors
		visitors = new Actor[5]
		visitorStates = new Int[5]
		visitorSince = new Float[5]
		visitorServed = new Bool[5]
	EndIf
EndFunction

Function ScheduleVisitors()
	UnregisterForUpdateGameTime()
	If GetModSettingBool("bVisitors:General")
		RegisterForSingleUpdateGameTime(VisitorTickHours)
	Else
		ReleaseAllVisitors()
	EndIf
EndFunction

Event OnUpdateGameTime()
	VisitorTick()
	UpdateOwnerTalk()
	If GetModSettingBool("bVisitors:General")
		RegisterForSingleUpdateGameTime(VisitorTickHours)
	EndIf
EndEvent

; Every VisitorTickHours: learns the town's people if the player is there, moves visitors along,
; and during the opening hours, now and then, sends one more on the way.
Function VisitorTick()
	If !brothelCell
		ReleaseAllVisitors()
		Return
	EndIf
	If Game.GetPlayer().GetParentCell() == brothelCell
		FindBrothelDoors()
	EndIf
	ScanTown()
	Float now = Utility.GetCurrentGameTime()
	Bool open = IsVisitingHour()
	Int count = 0
	Int i = 0
	While i < MaxVisitors
		If visitors[i]
			UpdateVisitor(i, now, open)
		EndIf
		If visitors[i]
			count += 1
		EndIf
		i += 1
	EndWhile
	If open && brothelMarker && count < MaxVisitorCount() && Utility.RandomInt(0, 1) == 0
		StartVisit(now)
	EndIf
	ShowVisitorStatus()
EndFunction

; Run while the player is in the brothel: places the waiting spot and finds the door to the outside
; (the one whose other side is in a worldspace).
Function FindBrothelDoors()
	Actor player = Game.GetPlayer()
	If !brothelMarker
		brothelMarker = player.PlaceAtMe(Game.GetForm(0x00003B), 1, True, False) ; XMarker
	EndIf
	If insideDoor && outsideDoor
		Return
	EndIf
	ObjectReference[] doors = PO3_SKSEFunctions.FindAllReferencesOfFormType(player, FormTypeDoor, 8192.0)
	Int i = 0
	While i < doors.Length
		ObjectReference destination = PO3_SKSEFunctions.GetDoorDestination(doors[i])
		If destination && doors[i].GetParentCell() == brothelCell && destination.GetWorldSpace()
			insideDoor = doors[i]
			outsideDoor = destination
			If GetModSettingBool("bDebugLog:General")
				DebugLog("Visitors: front door found, outside in " + destination.GetWorldSpace().GetName())
			EndIf
			Return
		EndIf
		i += 1
	EndWhile
EndFunction

; Forgets the waiting spot, the doors and the town's people: the brothel moved or closed.
Function ResetTown()
	If brothelMarker
		brothelMarker.Disable()
		brothelMarker.Delete()
		brothelMarker = None
	EndIf
	insideDoor = None
	outsideDoor = None
	townPool = new Actor[40]
	townPoolLastVisit = new Float[40]
EndFunction

; While the player is outside near the brothel's front door, the adults around are added to the
; town's people.
Function ScanTown()
	Actor player = Game.GetPlayer()
	If !outsideDoor || player.IsInInterior() || player.GetWorldSpace() != outsideDoor.GetWorldSpace() \
			|| player.GetDistance(outsideDoor) > TownRadius
		Return
	EndIf
	ObjectReference[] found = PO3_SKSEFunctions.FindAllReferencesOfFormType(player, FormTypeNPC, TownScanRadius)
	Int added = 0
	Int i = 0
	While i < found.Length
		Actor candidate = found[i] as Actor
		If CanVisit(candidate) && townPool.Find(candidate) < 0
			AddToTown(candidate)
			added += 1
		EndIf
		i += 1
	EndWhile
	If added > 0 && GetModSettingBool("bDebugLog:General")
		DebugLog("Visitors: " + added + " townsfolk learned, " + TownPoolCount() + " known")
	EndIf
EndFunction

; Into a free place in the list, or one whose person is gone; else over a random one.
Function AddToTown(Actor person)
	Int slot = townPool.Find(None)
	Int i = 0
	While slot < 0 && i < TownPoolSize
		If townPool[i].IsDead() || townPool[i].IsDisabled()
			slot = i
		EndIf
		i += 1
	EndWhile
	If slot < 0
		slot = Utility.RandomInt(0, TownPoolSize - 1)
	EndIf
	townPool[slot] = person
	townPoolLastVisit[slot] = 0.0
EndFunction

Int Function TownPoolCount()
	Int count = 0
	Int i = 0
	While i < TownPoolSize
		If townPool[i] && !townPool[i].IsDead()
			count += 1
		EndIf
		i += 1
	EndWhile
	Return count
EndFunction

; Who may ever visit: an adult person who is not the player, a guard, a follower, a registered
; worker, one of the brothel's own customers or hostile.
Bool Function CanVisit(Actor person)
	Actor player = Game.GetPlayer()
	Return person && person != player && !person.IsDead() && !person.IsDisabled() && !person.IsChild() \
		&& IsPerson(person) && !person.IsGuard() && !person.IsPlayerTeammate() \
		&& !person.IsInFaction(Game.GetFormFromFile(0x05C84E, "Skyrim.esm") as Faction) \
		&& workers.Find(person) < 0 && customers.Find(person) < 0 && person != brothelOwner && !person.IsHostileToActor(player) \
		&& person.GetActorBase() != Game.GetFormFromFile(CustomerBaseID, PluginName) as ActorBase \
		&& person.GetActorBase() != Game.GetFormFromFile(CustomerFemaleBaseID, PluginName) as ActorBase && !IsHiredWorker(person)
EndFunction

; Who may set off now: of the sex the MCM asks for, free (no fight, quest scene or talk with the
; player, no deal) and not here within the last VisitCooldownDays.
Bool Function ReadyToVisit(Int poolIndex, Float now)
	Actor person = townPool[poolIndex]
	If !CanVisit(person) || person.IsInCombat() || person.GetCurrentScene() || person.IsInDialogueWithPlayer() \
			|| visitors.Find(person) >= 0 || IsInDeal(person) || now - townPoolLastVisit[poolIndex] < VisitCooldownDays
		Return False
	EndIf
	Int wanted = GetModSettingInt("iVisitorSex:General") ; 0 men, 1 women, 2 both
	Return wanted == 2 || person.GetLeveledActorBase().GetSex() == wanted
EndFunction

; Sends one of the town's people, picked from a random start, to the waiting spot.
Function StartVisit(Float now)
	Int slot = visitors.Find(None)
	If slot < 0
		Return
	EndIf
	Int start = Utility.RandomInt(0, TownPoolSize - 1)
	Int i = 0
	While i < TownPoolSize
		Int index = (start + i) % TownPoolSize
		If ReadyToVisit(index, now)
			Actor visitor = townPool[index]
			visitors[slot] = visitor
			visitorStates[slot] = VisitorWalking
			visitorSince[slot] = now
			visitorServed[slot] = False
			townPoolLastVisit[index] = now
			PO3_SKSEFunctions.SetLinkedRef(visitor, brothelMarker, VisitLink())
			ActorUtil.AddPackageOverride(visitor, VisitTravelPackage(), 60)
			visitor.EvaluatePackage()
			If GetModSettingBool("bDebugLog:General")
				DebugLog("Visitors: " + visitor.GetDisplayName() + " sets off for the brothel")
			EndIf
			Return
		EndIf
		i += 1
	EndWhile
EndFunction

; Walking: inside the brothel (or at its door), the visitor starts waiting; one who takes too long
; is let in if the player is there to serve, else goes home. Waiting: once served, after the MCM's
; hours or when the brothel closes, the visitor goes home. One in a deal is left alone.
Function UpdateVisitor(Int slot, Float now, Bool open)
	Actor visitor = visitors[slot]
	If visitor.IsDead() || visitor.IsDisabled()
		ReleaseVisitor(slot)
		Return
	EndIf
	If IsInDeal(visitor)
		Return
	EndIf
	If visitorStates[slot] == VisitorWalking
		Bool atDoor = outsideDoor && visitor.GetWorldSpace() && visitor.GetWorldSpace() == outsideDoor.GetWorldSpace() \
			&& visitor.GetDistance(outsideDoor) < DoorReachDistance
		Bool playerHere = Game.GetPlayer().GetParentCell() == brothelCell
		If visitor.GetParentCell() == brothelCell
			EnterBrothel(slot, now)
		ElseIf !open
			ReleaseVisitor(slot)
		ElseIf insideDoor && (atDoor || (playerHere && now - visitorSince[slot] > VisitorWalkHours / 24.0))
			visitor.MoveTo(insideDoor)
			EnterBrothel(slot, now)
		ElseIf now - visitorSince[slot] > VisitorWalkHours / 24.0
			ReleaseVisitor(slot)
		EndIf
	ElseIf visitorServed[slot] || !open || now - visitorSince[slot] > VisitStayHours() / 24.0
		ReleaseVisitor(slot)
	EndIf
EndFunction

Function EnterBrothel(Int slot, Float now)
	Actor visitor = visitors[slot]
	ActorUtil.RemovePackageOverride(visitor, VisitTravelPackage())
	ActorUtil.AddPackageOverride(visitor, VisitWaitPackage(), 60)
	visitor.EvaluatePackage()
	visitorStates[slot] = VisitorInside
	visitorSince[slot] = now
	If Game.GetPlayer().GetParentCell() == brothelCell
		Debug.Notification(Phrase("visitorBefore", "") + visitor.GetDisplayName() + Phrase("visitorAfter", " has come to the brothel."))
	EndIf
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Visitors: " + visitor.GetDisplayName() + " is in the brothel")
	EndIf
EndFunction

; Back to the visitor's own day: the packages and the link to the waiting spot are taken off.
Function ReleaseVisitor(Int slot)
	Actor visitor = visitors[slot]
	visitors[slot] = None
	If !visitor
		Return
	EndIf
	ActorUtil.RemovePackageOverride(visitor, VisitTravelPackage())
	ActorUtil.RemovePackageOverride(visitor, VisitWaitPackage())
	PO3_SKSEFunctions.SetLinkedRef(visitor, None, VisitLink())
	visitor.EvaluatePackage()
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Visitors: " + visitor.GetDisplayName() + " goes home")
	EndIf
EndFunction

Function ReleaseAllVisitors()
	Int i = 0
	While visitors && i < MaxVisitors
		ReleaseVisitor(i)
		i += 1
	EndWhile
EndFunction

; Whether now is within the MCM's opening hours; opening and closing at the same hour is all day,
; and closing earlier than opening runs past midnight.
Bool Function IsVisitingHour()
	Float now = Utility.GetCurrentGameTime()
	Int hour = ((now - Math.Floor(now)) * 24.0) as Int
	Int opening = GetModSettingInt("iVisitStart:General")
	Int closing = GetModSettingInt("iVisitEnd:General")
	If opening == closing
		Return True
	ElseIf opening < closing
		Return hour >= opening && hour < closing
	EndIf
	Return hour >= opening || hour < closing
EndFunction

Int Function MaxVisitorCount()
	Int count = GetModSettingInt("iMaxVisitors:General")
	If count < 1
		Return 1
	ElseIf count > MaxVisitors
		Return MaxVisitors
	EndIf
	Return count
EndFunction

Float Function VisitStayHours()
	Int hours = GetModSettingInt("iVisitStay:General")
	If hours < 1
		hours = 1
	EndIf
	Return hours as Float
EndFunction

Function ShowVisitorStatus()
	SetModSettingString("sVisitorPool:General", TownPoolCount() as String)
EndFunction

Package Function VisitTravelPackage()
	Return Game.GetFormFromFile(0x0235E2, "Skyrim.esm") as Package ; defaultTravelToLinkCustom02
EndFunction

; Stands about near the waiting spot. Not a sandbox: that one lets visitors sleep in the beds.
Package Function VisitWaitPackage()
	Return Game.GetFormFromFile(0x0C22CF, "Skyrim.esm") as Package ; defaultHoldPositionLinkCustom02_512UntilReleased
EndFunction

Keyword Function VisitLink()
	Return Game.GetFormFromFile(0x05D5E7, "Skyrim.esm") as Keyword   ; LinkCustom02
EndFunction

; ---------------------------------------------------------------------------------------------
; The owner
; ---------------------------------------------------------------------------------------------

; The brothel's owner (MCM): the player, an NPC or nobody. The owner takes the MCM's share of every
; payment. A player owner can offer anyone in the brothel one of the workers in conversation (the
; skyrimnet_Brothel_RecommendTopic topic); an NPC owner, every so often, recommends a worker to a
; customer or talks to a worker about her takings.

Int Property WorkerFactionID = 0x804 AutoReadOnly
Int Property OwnerTalkID = 0x805 AutoReadOnly
Int Property RecommendTopicID = 0x807 AutoReadOnly
Int Property MaxOwnerCandidates = 30 AutoReadOnly
String Property ChoicesTagRecommend = "SNB_Recommend" AutoReadOnly
Int Property MaxRecommendChoices = 4 AutoReadOnly
; An NPC owner takes a worker without a customer for this many game hours to task; when every
; worker had one more recently, the owner praises the one who earned most instead.
Float Property SlowHours = 3.0 AutoReadOnly
; How close an NPC owner must be to whom they talk to.
Float Property OwnerTalkDistance = 1500.0 AutoReadOnly

Actor brothelOwner
; The MCM's owner list as last shown: index 0 is nobody, 1 the player.
Actor[] ownerCandidates
; Real time (this session) of an NPC owner's next round; set again on every load.
Float ownerNextAt
Actor pendingRecommend

Faction Function WorkerFaction()
	Return Game.GetFormFromFile(WorkerFactionID, PluginName) as Faction
EndFunction

Bool Function NpcOwnsBrothel()
	Return brothelOwner && brothelOwner != Game.GetPlayer()
EndFunction

; On every load: workers carry the worker faction (the owner's topic is not offered to them), the
; topic is on or off, and the MCM shows the owner.
Function SyncOwnerState()
	Faction workerMark = WorkerFaction()
	Int i = 0
	While i < workerCount
		If workers[i] && !workers[i].IsInFaction(workerMark)
			workers[i].AddToFaction(workerMark)
		EndIf
		i += 1
	EndWhile
	If brothelOwner && brothelOwner.IsDead()
		brothelOwner = None
	EndIf
	UpdateOwnerTalk()
	ShowOwner()
EndFunction

; The owner's topic shows only while the player owns the brothel and is in it. Its text comes from
; strings.json, which a translation replaces. Called on loads, owner changes, game-time ticks and
; when the player changes location (player alias).
Function UpdateOwnerTalk()
	Actor player = Game.GetPlayer()
	GlobalVariable onOff = Game.GetFormFromFile(OwnerTalkID, PluginName) as GlobalVariable
	If brothelOwner == player && brothelCell && player.GetParentCell() == brothelCell
		onOff.SetValue(1.0)
	Else
		onOff.SetValue(0.0)
	EndIf
	Game.GetFormFromFile(RecommendTopicID, PluginName).SetName(Phrase("recommendTopic", "(Introduce one of the girls)"))
	; The player's own topic as a worker: inviting this person.
	GlobalVariable solicitOnOff = Game.GetFormFromFile(PlayerSolicitTalkID, PluginName) as GlobalVariable
	If PlayerWorks() && brothelCell && player.GetParentCell() == brothelCell
		solicitOnOff.SetValue(1.0)
	Else
		solicitOnOff.SetValue(0.0)
	EndIf
	Game.GetFormFromFile(SolicitTopicID, PluginName).SetName(Phrase("solicitTopic", "(Offer your company)"))
EndFunction

Function ShowOwner()
	If brothelOwner
		SetModSettingString("sOwnerName:General", brothelOwner.GetDisplayName())
	Else
		SetModSettingString("sOwnerName:General", "$SNB_None")
	EndIf
EndFunction

; The MCM's owner list, refilled each time the menu opens: nobody, the player, the current owner,
; and the adults in the brothel right now (not its own customers or visitors).
Function RefreshOwnerMenu()
	Actor player = Game.GetPlayer()
	ownerCandidates = new Actor[30]
	ownerCandidates[1] = player
	Int count = 2
	If NpcOwnsBrothel()
		ownerCandidates[2] = brothelOwner
		count = 3
	EndIf
	If brothelCell && player.GetParentCell() == brothelCell
		Actor[] nearby = MiscUtil.ScanCellNPCs(player, 0.0, None, True)
		Int i = 0
		While i < nearby.Length && count < MaxOwnerCandidates
			Actor npc = nearby[i]
			If npc != player && ownerCandidates.Find(npc) < 0 && IsPerson(npc) && !npc.IsChild() && !npc.IsDisabled() \
					&& customers.Find(npc) < 0 && visitors.Find(npc) < 0 && !npc.IsHostileToActor(player)
				ownerCandidates[count] = npc
				count += 1
			EndIf
			i += 1
		EndWhile
	EndIf
	String[] names = Utility.CreateStringArray(count)
	names[0] = "$SNB_None"
	Int j = 1
	While j < count
		names[j] = ownerCandidates[j].GetDisplayName()
		j += 1
	EndWhile
	ownerMenuNames = names
	SetMenuOptions("sOwnerPick:General", names, names)
	Int current = 0
	If brothelOwner
		current = ownerCandidates.Find(brothelOwner)
	EndIf
	SetModSettingString("sOwnerPick:General", names[current])
	ShowOwner()
EndFunction

; The owner list as last shown in the MCM, in ownerCandidates' order.
String[] ownerMenuNames

; From the MCM's list (its change event, and again when the menu closes in case that event did not
; come). The "current owner" line is redrawn at once.
; redraw: from the menu's change event, where MCM Helper expects RefreshMenu; never while the menu
; is closing (OnConfigClose), when the page cache is being torn down.
Function PickOwner(Int index, Bool redraw = True)
	If index < 0
		Return
	EndIf
	Actor picked = None
	If ownerCandidates && index > 0 && index < ownerCandidates.Length
		picked = ownerCandidates[index]
	EndIf
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Owner pick " + index + ": " + picked + " (was " + brothelOwner + ")")
	EndIf
	If picked == brothelOwner
		Return
	EndIf
	brothelOwner = picked
	ownerNextAt = Utility.GetCurrentRealTime() + OwnerIntervalSeconds()
	SyncOwnerState()
	ScheduleNextUpdate()
	If redraw
		RefreshMenu()
	EndIf
EndFunction

Event OnConfigClose()
	PickOwner(OwnerPickIndex(), False)
EndEvent

; The owner list's pick, found by its text (MCM Helper keeps a menu's value as the option text);
; -1 when the list has not been shown.
Int Function OwnerPickIndex()
	If !ownerMenuNames
		Return -1
	EndIf
	Return ownerMenuNames.Find(GetModSettingString("sOwnerPick:General"))
EndFunction

; Each worker's takings, kept on her (PapyrusUtil StorageUtil): when she last had a customer (game
; days), how many she has had and the gold she kept.
Function RecordSale(Actor worker, Int amount)
	StorageUtil.SetFloatValue(worker, "SNB_LastServed", Utility.GetCurrentGameTime())
	StorageUtil.AdjustIntValue(worker, "SNB_Served", 1)
	StorageUtil.AdjustIntValue(worker, "SNB_Earned", amount)
EndFunction

; The owner's topic was picked: the conversation runs once the dialogue menu has closed.
Function RecommendTopicChosen(Actor customer)
	pendingRecommend = customer
	pendingAction = "recommend"
	RegisterForSingleUpdate(0.5)
EndFunction

; The player, as owner, offers this person one of the free workers. Through the built-in Player Choices
; the player picks among lines that each recommend one worker; the person answers, then walks over
; to the worker picked and makes the usual offer.
Function PlayerRecommends(Actor customer)
	Actor player = Game.GetPlayer()
	If brothelOwner != player || !brothelCell || player.GetParentCell() != brothelCell
		Debug.Notification("$SNB_NotInBrothel")
		Return
	EndIf
	If !customer || IsInDeal(customer) || WorkerDealCount() >= MaxConcurrent()
		Debug.Notification("$SNB_Busy")
		Return
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Actor[] offered = new Actor[4]
	String[] intents = Utility.CreateStringArray(MaxRecommendChoices + 1)
	Int count = 0
	Int start = 0
	If workerCount > 0
		start = Utility.RandomInt(0, workerCount - 1)
	EndIf
	Int i = 0
	While i < workerCount && count < MaxRecommendChoices
		Actor worker = workers[(start + i) % workerCount]
		If worker && worker != customer && worker != player && !worker.IsDead() && worker.GetParentCell() == brothelCell \
				&& !IsInDeal(worker) && !sexLab.IsActorActive(worker) && IsFreeCustomer(sexLab, customer, worker)
			offered[count] = worker
			intents[count] = "recommend " + worker.GetDisplayName() + " to " + customer.GetDisplayName() \
				+ " for tonight, saying what makes her worth the money"
			count += 1
		EndIf
		i += 1
	EndWhile
	If count == 0
		Debug.Notification("$SNB_NoWorker")
		Return
	EndIf
	intents[count] = "say it was nothing after all"
	intents = Utility.ResizeStringArray(intents, count + 1)
	Int picked = 0
	If ChoicesReady()
		picked = AskPlayer(customer, "the brothel's owner offers " + customer.GetDisplayName() + " one of the girls", \
			player.GetDisplayName() + " runs this brothel. " + customer.GetDisplayName() + " is here, and " + player.GetDisplayName() \
			+ " walks up to " + customer.GetDisplayName() + " to offer one of the girls working tonight.", \
			intents, ChoicesTagRecommend, -1, True, True)
	EndIf
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Owner (player) recommends to " + customer.GetDisplayName() + ": pick " + picked + " of " + count)
	EndIf
	If picked >= 0 && picked < count
		ServePair(sexLab, offered[picked], customer, False)
	EndIf
EndFunction

; Seconds between an NPC owner's rounds (MCM), at least 10.
Float Function OwnerIntervalSeconds()
	Int seconds = GetModSettingInt("iOwnerInterval:General")
	If seconds < 10
		seconds = 10
	EndIf
	Return seconds as Float
EndFunction

; Whether an NPC owner's round is due now (real time); books the next one either way, so a round
; that cannot be made now (the owner busy, the player out) waits a full interval.
Bool Function NpcOwnerDue()
	If !NpcOwnsBrothel() || Utility.GetCurrentRealTime() < ownerNextAt
		Return False
	EndIf
	ownerNextAt = Utility.GetCurrentRealTime() + OwnerIntervalSeconds()
	Return True
EndFunction

; An NPC owner's round: the owner, in the brothel with the player and free, either recommends a
; worker to a customer or talks to a worker.
Function OwnerRound()
	Actor owner = brothelOwner
	If !brothelCell || !owner || Game.GetPlayer().GetParentCell() != brothelCell || owner.GetParentCell() != brothelCell \
			|| owner.IsDead() || owner.IsInCombat() || IsInDeal(owner) || SexLabUtil.GetAPI().IsActorActive(owner) || talking \
			|| Utility.IsInMenuMode()
		Return
	EndIf
	If Utility.RandomInt(0, 1) == 0 && OwnerRecommends()
		Return
	EndIf
	If OwnerTalksToWorker()
		Return
	EndIf
	; Every worker is with a customer (or there is none to talk to): the owner does not fall silent.
	OwnerWhileBusy()
EndFunction

; What the owner last said while no worker was free, so a short round interval does not repeat it:
; the customer last kept waiting (again only after OwnerRepeatSeconds), and the last report.
Actor ownerKeptWaiting
Float ownerKeptWaitingAt
String ownerLastReport
Float Property OwnerRepeatSeconds = 180.0 AutoReadOnly

; While no worker is free: the owner keeps a waiting customer in good spirits, naming the girls who
; are busy; with nobody waiting, tells the player how business is going. Says nothing when that
; would repeat what was just said: the same customer kept waiting, or the same report.
Function OwnerWhileBusy()
	Actor owner = brothelOwner
	Actor player = Game.GetPlayer()
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	String o = owner.GetDisplayName()
	String busy = ""
	Int i = 0
	While i <= workerCount
		Actor worker = StaffAt(i)
		If worker && worker != owner && worker.GetParentCell() == brothelCell && (IsInDeal(worker) || sexLab.IsActorActive(worker))
			If busy != ""
				busy += ", "
			EndIf
			busy += worker.GetDisplayName()
		EndIf
		i += 1
	EndWhile
	Actor waiting = WaitingCustomerNear(sexLab, owner)
	If waiting && waiting == ownerKeptWaiting && Utility.GetCurrentRealTime() - ownerKeptWaitingAt < OwnerRepeatSeconds
		Return
	EndIf
	If waiting
		ownerKeptWaiting = waiting
		ownerKeptWaitingAt = Utility.GetCurrentRealTime()
		String who = "all the girls are busy with customers right now"
		If busy != ""
			who = "the girls are busy with customers right now (" + busy + ")"
		EndIf
		OwnerSpeaks(o + " runs this brothel, and " + who + ". " + o + " walks over to " + waiting.GetDisplayName() \
			+ ", a customer who is waiting, keeps " + HimOf(waiting) + " in good spirits and asks " + HimOf(waiting) + " to wait a little longer, in a few lines.", waiting)
		If GetModSettingBool("bDebugLog:General")
			DebugLog("Owner " + o + " keeps " + waiting.GetDisplayName() + " waiting")
		EndIf
	ElseIf !IsInDeal(player) && !sexLab.IsActorActive(player) && owner.GetDistance(player) <= OwnerTalkDistance
		String report = BusinessReport()
		If report == ownerLastReport
			Return
		EndIf
		ownerLastReport = report
		OwnerSpeaks(o + " runs this brothel and tells " + player.GetDisplayName() + " how business is going: " + report \
			+ ". " + o + " says it in a few lines, in " + o + "'s own manner.", player)
		If GetModSettingBool("bDebugLog:General")
			DebugLog("Owner " + o + " reports to the player: " + report)
		EndIf
	EndIf
EndFunction

; The free customer (the brothel's own, or a visitor from town) nearest to the owner, within
; OwnerTalkDistance; None when there is none.
Actor Function WaitingCustomerNear(SexLabFramework sexLab, Actor owner)
	Actor nearest = None
	Float nearestDistance = 0.0
	Int i = 0
	While i < customers.Length + MaxVisitors
		Actor candidate = None
		If i < customers.Length
			candidate = customers[i]
		ElseIf visitorStates[i - customers.Length] == VisitorInside
			candidate = visitors[i - customers.Length]
		EndIf
		If candidate && candidate != owner && !candidate.IsDead() && !candidate.IsDisabled() && candidate.Is3DLoaded() \
				&& candidate.GetParentCell() == brothelCell && !IsInDeal(candidate) && !sexLab.IsActorActive(candidate)
			Float distance = owner.GetDistance(candidate)
			If distance <= OwnerTalkDistance && (!nearest || distance < nearestDistance)
				nearest = candidate
				nearestDistance = distance
			EndIf
		EndIf
		i += 1
	EndWhile
	Return nearest
EndFunction

; The night's takings so far, from the workers' records and the house's: "the girls have served N
; customers and kept X gold, and the house has taken Y gold". A night paid for up front counts as
; soon as it is paid, as the house's share does: the workers' records only grow when its scene ends.
String Function BusinessReport()
	Int served = 0
	Int earned = 0
	Int i = 0
	While i <= workerCount
		Actor worker = StaffAt(i)
		If worker
			served += StorageUtil.GetIntValue(worker, "SNB_Served")
			earned += StorageUtil.GetIntValue(worker, "SNB_Earned")
		EndIf
		i += 1
	EndWhile
	i = 0
	While i < DealSlots
		If dealWorkers[i] && dealPaid[i] && dealWorkers[i] != brothelOwner
			served += 1
			earned += dealPaidWorker[i]
		EndIf
		i += 1
	EndWhile
	String report = "the girls have served " + served + " customers in all and kept " + earned + " gold"
	If brothelOwner
		report += ", and the house has taken " + StorageUtil.GetIntValue(brothelOwner, "SNB_HouseTake") + " gold"
	EndIf
	Return report
EndFunction

; The NPC owner walks over to a free customer and recommends a free worker by name; then the
; customer goes to her and makes the usual offer. False when there is no such pair.
Bool Function OwnerRecommends()
	If WorkerDealCount() >= MaxConcurrent()
		Return False
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Actor owner = brothelOwner
	Actor worker = PickWorker(sexLab, PlayerInAutoServe())
	If !worker || worker == owner
		Return False
	EndIf
	Actor customer = PickCustomer(sexLab, worker)
	If !customer || owner.GetDistance(customer) > OwnerTalkDistance
		Return False
	EndIf
	String o = owner.GetDisplayName()
	OwnerSpeaks(o + " runs this brothel. " + o + " walks over to " + customer.GetDisplayName() + ", a customer, and recommends " \
		+ worker.GetDisplayName() + ", one of the girls working tonight: " + o + " names her and says what makes her worth the money, in a few lines.", \
		customer)
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Owner " + o + " recommends " + worker.GetDisplayName() + " to " + customer.GetDisplayName())
	EndIf
	ServePair(sexLab, worker, customer, True)
	Return True
EndFunction

; The NPC owner talks to a worker about her takings: the one who has gone longest without a
; customer is taken to task if that is over SlowHours; otherwise the one who earned most is praised.
Bool Function OwnerTalksToWorker()
	Actor owner = brothelOwner
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Float now = Utility.GetCurrentGameTime()
	Actor slowest = None
	Float slowestHours = -1.0
	Actor best = None
	Int bestEarned = -1
	Int i = 0
	While i <= workerCount
		Actor worker = StaffAt(i)
		If worker && worker != owner && !worker.IsDead() && worker.GetParentCell() == brothelCell && !IsInDeal(worker) \
				&& !sexLab.IsActorActive(worker) && owner.GetDistance(worker) <= OwnerTalkDistance
			Float last = StorageUtil.GetFloatValue(worker, "SNB_LastServed", -1.0)
			Float hours = 1000.0
			If last >= 0.0
				hours = (now - last) * 24.0
			EndIf
			If hours > slowestHours
				slowest = worker
				slowestHours = hours
			EndIf
			Int earned = StorageUtil.GetIntValue(worker, "SNB_Earned")
			If earned > bestEarned
				best = worker
				bestEarned = earned
			EndIf
		EndIf
		i += 1
	EndWhile
	If !slowest
		Return False
	EndIf
	String o = owner.GetDisplayName()
	Actor target = slowest
	String narration
	If slowestHours >= SlowHours
		String since = "has not had a single customer yet"
		If slowestHours < 1000.0
			since = "has not had a customer for " + (slowestHours as Int) + " hours"
		EndIf
		narration = o + " runs this brothel and is not pleased with " + slowest.GetDisplayName() + ": she " + since + " (" \
			+ Takings(slowest) + "). " + o + " takes her to task about her falling takings and pushes her to win customers over, in a few lines."
	Else
		target = best
		narration = o + " runs this brothel and is pleased with " + best.GetDisplayName() + " (" + Takings(best) + "). " \
			+ o + " praises her work and encourages her to keep it up, in a few lines."
	EndIf
	OwnerSpeaks(narration, target)
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Owner " + o + " talks to " + target.GetDisplayName() + " (" + Takings(target) + ")")
	EndIf
	Return True
EndFunction

String Function Takings(Actor worker)
	Return worker.GetDisplayName() + " (level " + WorkerLevel(worker) + " of " + MaxLevel + ") has served " + StorageUtil.GetIntValue(worker, "SNB_Served") + " customers and kept " \
		+ StorageUtil.GetIntValue(worker, "SNB_Earned") + " gold here in all"
EndFunction

; The NPC owner says something to listener, in the talk turn every pair waits for (see AcquireTalk).
Function OwnerSpeaks(String narration, Actor listener)
	Float startedAt = Utility.GetCurrentRealTime()
	talking = True
	talkingSince = startedAt
	SkyrimNetApi.DirectNarration(narration, brothelOwner, listener)
	WaitForSpeech(startedAt, -1)
	ReleaseTalk()
EndFunction

; ---------------------------------------------------------------------------------------------
; Workers
; ---------------------------------------------------------------------------------------------

Function ToggleWorker(Actor target)
	If !target
		Debug.Notification("$SNB_NoTarget")
		Return
	EndIf
	Int index = workers.Find(target)
	If index >= 0
		If IsHiredWorker(target) && IsInDeal(target)
			Debug.Notification("$SNB_WorkerBusy")
			Return
		EndIf
		RemoveWorkerAt(index)
		ShowWorkerCount()
		Debug.Notification("$SNB_WorkerRemoved")
		Return
	EndIf
	If target == Game.GetPlayer() || target.IsChild() || !IsPerson(target) || customers.Find(target) >= 0
		Debug.Notification("$SNB_NotEligible")
		Return
	EndIf
	If target.GetLeveledActorBase().GetSex() != 1
		Debug.Notification("$SNB_NotFemale")
		Return
	EndIf
	If workerCount >= MaxWorkers
		Debug.Notification("$SNB_WorkerListFull")
		Return
	EndIf
	RegisterWorker(target)
	ShowWorkerCount()
	Debug.Notification("$SNB_WorkerAdded")
EndFunction

Function RegisterWorker(Actor target)
	workers[workerCount] = target
	workerCount += 1
	target.AddToFaction(WorkerFaction())
	SkyrimNetApi.RegisterPersistentEvent(target.GetDisplayName() + " works at the brothel now, selling her company for gold. She " \
		+ WorkerAttitude(WorkerLevel(target)) + ".", target, None)
EndFunction

; MCM buttons: registers every female follower near the player, or unregisters every registered
; worker who is a follower, once the menu closes. Followers are told apart the vanilla way (a
; teammate, or in the current follower faction), which any follower framework keeps up.
Function RegisterFollowers()
	pendingAction = "registerfollowers"
	RegisterForSingleUpdate(0.1)
EndFunction

Function UnregisterFollowers()
	pendingAction = "unregisterfollowers"
	RegisterForSingleUpdate(0.1)
EndFunction

Bool Function IsFollower(Actor akActor)
	Return akActor.IsPlayerTeammate() || akActor.GetFactionRank(Game.GetFormFromFile(0x05C84E, "Skyrim.esm") as Faction) >= 0
EndFunction

Function DoRegisterFollowers()
	Actor player = Game.GetPlayer()
	Actor[] nearby = MiscUtil.ScanCellNPCs(player, 0.0, None, True)
	Int count = 0
	Int i = 0
	While i < nearby.Length && workerCount < MaxWorkers
		Actor follower = nearby[i]
		If follower && follower != player && !follower.IsChild() && IsPerson(follower) \
				&& follower.GetLeveledActorBase().GetSex() == 1 && IsFollower(follower) \
				&& workers.Find(follower) < 0 && customers.Find(follower) < 0
			RegisterWorker(follower)
			count += 1
		EndIf
		i += 1
	EndWhile
	ShowWorkerCount()
	If count == 0
		Debug.Notification("$SNB_NoFollowers")
	Else
		Debug.Notification(Phrase("followersAddedBefore", "") + count + Phrase("followersAddedAfter", " followers registered as workers."))
	EndIf
EndFunction

Function DoUnregisterFollowers()
	Int count = 0
	Int i = workerCount - 1
	While i >= 0
		If workers[i] && !IsHiredWorker(workers[i]) && IsFollower(workers[i])
			RemoveWorkerAt(i)
			count += 1
		EndIf
		i -= 1
	EndWhile
	ShowWorkerCount()
	If count == 0
		Debug.Notification("$SNB_NoFollowerWorkers")
	Else
		Debug.Notification(Phrase("followersRemovedBefore", "") + count + Phrase("followersRemovedAfter", " followers are no longer workers."))
	EndIf
EndFunction

; ---------------------------------------------------------------------------------------------
; The Manage Brothel power
; ---------------------------------------------------------------------------------------------

; A lesser power that opens a list menu (UIExtensions) with what the MCM does most: adding and
; closing brothels, the followers' bulk buttons, and the customer and hired-worker counts. It is a
; way in for players whose MCM list is full (SkyUI shows at most 128 menus). The menu changes the
; same settings as the MCM. Its text comes from strings.json.

Int Property ManagePowerID = 0x828 AutoReadOnly

; Called from Setup: the player gets the power once, and again if it was taken away.
Function GivePower()
	Spell power = Game.GetFormFromFile(ManagePowerID, PluginName) as Spell
	Actor player = Game.GetPlayer()
	If power && !player.HasSpell(power)
		player.AddSpell(power)
	EndIf
EndFunction

; Cast by the power: the menu opens from the quest's own update, like the MCM buttons' work.
Function OpenManageMenu()
	pendingAction = "manage"
	RegisterForSingleUpdate(0.1)
EndFunction

; The main list. A count or the customers' sex comes back to it once picked; the actions close it
; and run. Customers and hired workers are brought to the new counts once the menu is gone.
Function ManageMenu()
	Bool countsChanged = False
	Bool open = True
	While open
		String[] entries = new String[10]
		String current = Phrase("menuNone", "(none)")
		If brothelCell
			current = brothelCell.GetName()
		EndIf
		entries[0] = Phrase("menuCurrent", "Current brothel: ") + current + " (" + BrothelCount() + " / " + MaxUserBrothels + ")"
		entries[1] = Phrase("menuDesignate", "Add this interior as a brothel")
		entries[2] = Phrase("menuClose", "Close a brothel...")
		entries[3] = Phrase("menuRegisterFollowers", "Register female followers")
		entries[4] = Phrase("menuUnregisterFollowers", "Unregister followers")
		entries[5] = Phrase("menuCustomers", "Customers: ") + TargetCustomerCount()
		entries[6] = Phrase("menuCustomerSex", "Customers' sex: ") + CustomerSexName(GetModSettingInt("iCustomerSex:General"))
		entries[7] = Phrase("menuHired", "Hired workers: ") + TargetHiredCount()
		entries[8] = Phrase("menuHiredLevel", "Hired workers' starting level: ") + GetModSettingInt("iHiredLevel:General")
		entries[9] = Phrase("menuExit", "Close the menu")
		Int pick = PickFromList(entries)
		If pick == 1
			open = False
			DoDesignateBrothel()
		ElseIf pick == 2
			open = !PickBrothelToClose()
		ElseIf pick == 3
			open = False
			DoRegisterFollowers()
		ElseIf pick == 4
			open = False
			DoUnregisterFollowers()
		ElseIf pick == 5
			countsChanged = PickSetting("iCustomerCount:General", 1, MaxCustomers) || countsChanged
		ElseIf pick == 6
			countsChanged = PickCustomerSex() || countsChanged
		ElseIf pick == 7
			countsChanged = PickSetting("iHiredWorkers:General", 0, MaxHiredWorkers) || countsChanged
		ElseIf pick == 8
			PickSetting("iHiredLevel:General", 1, 10)
		ElseIf pick != 0
			open = False
		EndIf
	EndWhile
	If countsChanged
		SyncCustomers()
		SyncHiredWorkers()
	EndIf
EndFunction

; Shows one list and returns the index of the entry picked, or -1 when it was closed without one.
Int Function PickFromList(String[] entries)
	UIListMenu menu = UIExtensions.GetMenu("UIListMenu") as UIListMenu
	If !menu
		Debug.Notification(Phrase("menuMissing", "UIExtensions is missing: the brothel menu cannot open."))
		Return -1
	EndIf
	Int i = 0
	While i < entries.Length
		menu.AddEntryItem(entries[i])
		i += 1
	EndWhile
	menu.OpenMenu()
	Return menu.GetResultInt()
EndFunction

; A number list from low to high, the setting's value marked; True when a new value was picked.
Bool Function PickSetting(String setting, Int low, Int high)
	Int value = GetModSettingInt(setting)
	String[] entries = Utility.CreateStringArray(high - low + 2)
	Int i = 0
	While i <= high - low
		entries[i] = (low + i) as String
		If low + i == value
			entries[i] = entries[i] + Phrase("menuSelected", "  (now)")
		EndIf
		i += 1
	EndWhile
	entries[i] = Phrase("menuBack", "Back")
	Int pick = PickFromList(entries)
	If pick < 0 || pick > high - low || low + pick == value
		Return False
	EndIf
	SetModSettingInt(setting, low + pick)
	Return True
EndFunction

Bool Function PickCustomerSex()
	Int value = GetModSettingInt("iCustomerSex:General")
	String[] entries = new String[4]
	Int i = 0
	While i < 3
		entries[i] = CustomerSexName(i)
		If i == value
			entries[i] = entries[i] + Phrase("menuSelected", "  (now)")
		EndIf
		i += 1
	EndWhile
	entries[3] = Phrase("menuBack", "Back")
	Int pick = PickFromList(entries)
	If pick < 0 || pick > 2 || pick == value
		Return False
	EndIf
	SetModSettingInt("iCustomerSex:General", pick)
	Return True
EndFunction

String Function CustomerSexName(Int sex)
	If sex == 1
		Return Phrase("menuSexWomen", "Women only")
	ElseIf sex == 2
		Return Phrase("menuSexHalf", "Half and half")
	EndIf
	Return Phrase("menuSexMen", "Men only")
EndFunction

; The brothel list, then a second list to make sure; True when one was closed.
Bool Function PickBrothelToClose()
	If BrothelCount() == 0
		Debug.Notification(Phrase("menuNoBrothel", "You have no brothel to close."))
		Return False
	EndIf
	String[] entries = Utility.CreateStringArray(MaxUserBrothels + 1)
	Int[] slots = Utility.CreateIntArray(MaxUserBrothels + 1, -1)
	Int count = 0
	Int i = 0
	While i < MaxUserBrothels
		If brothelCells[i]
			entries[count] = (i + 1) + ": " + brothelCells[i].GetName()
			slots[count] = i
			count += 1
		EndIf
		i += 1
	EndWhile
	entries[count] = Phrase("menuBack", "Back")
	entries = Utility.ResizeStringArray(entries, count + 1)
	Int pick = PickFromList(entries)
	If pick < 0 || pick >= count
		Return False
	EndIf
	Int slot = slots[pick]
	String[] confirm = new String[2]
	confirm[0] = Phrase("menuCloseConfirm", "Close ") + brothelCells[slot].GetName() + Phrase("menuCloseConfirmAfter", "")
	confirm[1] = Phrase("menuBack", "Back")
	If PickFromList(confirm) != 0
		Return False
	EndIf
	CloseBrothel(slot)
	Return True
EndFunction

; Takes the worker at this place off the list; a hired worker leaves the game with it.
Function RemoveWorkerAt(Int index)
	Actor worker = workers[index]
	workers[index] = workers[workerCount - 1]
	workers[workerCount - 1] = None
	workerCount -= 1
	If worker
		worker.RemoveFromFaction(WorkerFaction())
		If IsHiredWorker(worker)
			worker.Disable()
			worker.Delete()
		EndIf
	EndIf
EndFunction

; A humanoid NPC: has ActorTypeNPC, so creatures, animals and the like are left out.
Bool Function IsPerson(Actor akActor)
	Return akActor.HasKeyword(Game.GetFormFromFile(0x013794, "Skyrim.esm") as Keyword)
EndFunction

; The MCM's worker list: a menu control whose options are the registered workers, refilled each
; time the menu opens. A trailing " *" marks a worker who is in the brothel right now.
; MCM Helper keeps the drawn page and the menus' options in a cache with no locking, and draws the
; page while OnConfigOpen may still be running. Rewriting menu options or calling RefreshMenu then
; crashed the game (a std::bad_alloc in MenuControl::GetShortText), most likely with Papyrus Tweaks'
; bSpeedUpNativeCalls, which runs RefreshMenu off the main thread. So on opening only the values are
; set (the setting store, not the page cache); the menus' options are set and the page redrawn in
; OnPageSelect, which MCM Helper sends once a page has been drawn.
Event OnConfigOpen()
	DropMissingWorkers()
	ShowWorkerCount()
	ShowBrothelCount()
	ShowOwner()
	ShowLevels()
EndEvent

Event OnPageSelect(String a_page)
	If a_page == ""
		Return
	EndIf
	RefreshWorkerMenu()
	RefreshOwnerMenu()
	RefreshBrothelMenu()
	ShowLevels()
	RefreshMenu()
EndEvent

Function RefreshWorkerMenu()
	DropMissingWorkers()
	String[] names
	If workerCount == 0
		names = new String[1]
		names[0] = "$SNB_None"
	Else
		names = Utility.CreateStringArray(workerCount)
		Int i = 0
		While i < workerCount
			names[i] = workers[i].GetDisplayName()
			If brothelCell && workers[i].GetParentCell() == brothelCell
				names[i] = names[i] + " *"
			EndIf
			i += 1
		EndWhile
	EndIf
	; MCM Helper keeps a menu's value as the picked option's text, not its index, so the pick is
	; found again by its text in the list shown.
	workerMenuNames = names
	SetMenuOptions("sWorkerPick:General", names, names)
	; The pick stays when the page changes (the Debug page acts on it), unless that worker is gone.
	If names.Find(GetModSettingString("sWorkerPick:General")) < 0
		SetModSettingString("sWorkerPick:General", names[0])
	EndIf
	ShowWorkerCount()
EndFunction

; The worker list as last shown in the MCM.
String[] workerMenuNames

Function ShowWorkerCount()
	SetModSettingString("sWorkerCount:General", workerCount as String)
EndFunction

; MCM button: unregisters the worker picked in the list.
Function UnregisterPickedWorker()
	Int index = -1
	If workerMenuNames
		index = workerMenuNames.Find(GetModSettingString("sWorkerPick:General"))
	EndIf
	If index >= 0 && index < workerCount
		If IsHiredWorker(workers[index]) && IsInDeal(workers[index])
			Debug.Notification("$SNB_WorkerBusy")
		Else
			RemoveWorkerAt(index)
			Debug.Notification("$SNB_WorkerRemoved")
		EndIf
	EndIf
	RefreshWorkerMenu()
	RefreshMenu()
EndFunction

; Workers whose references are gone, for example from an uninstalled follower mod.
Function DropMissingWorkers()
	Int i = workerCount - 1
	While i >= 0
		If !workers[i]
			workers[i] = workers[workerCount - 1]
			workers[workerCount - 1] = None
			workerCount -= 1
		EndIf
		i -= 1
	EndWhile
EndFunction

; ---------------------------------------------------------------------------------------------
; Deal slots
; ---------------------------------------------------------------------------------------------

Function ResetDeals()
	Int i = 0
	While dealSpots && i < dealSpots.Length
		ReleaseHold(i)
		DeleteSpot(i)
		i += 1
	EndWhile
	dealBeds = new ObjectReference[13]
	dealSpots = new ObjectReference[13]
	dealCenters = new ObjectReference[13]
	dealWorkers = new Actor[13]
	dealCustomers = new Actor[13]
	dealStates = new Int[13]
	dealThreads = new Int[13]
	dealSerials = new Int[13]
	dealStarted = new Float[13]
	dealIdleRuns = new Int[13]
	dealPaid = new Bool[13]
	dealPaidWorker = new Int[13]
	dealPaidOwner = new Int[13]
	dealSolicited = new Bool[13]
	dealAnsweredAt = new Float[13]
EndFunction

; How many workers may be with customers at once (MCM, 1 to MaxConcurrentWorkers). The player's
; own deal does not count against it.
Int Function MaxConcurrent()
	Int count = GetModSettingInt("iMaxConcurrent:General")
	If count < 1
		Return 1
	ElseIf count > MaxConcurrentWorkers
		Return MaxConcurrentWorkers
	EndIf
	Return count
EndFunction

Int Function OpenDealCount()
	Int count = 0
	Int i = 0
	While i < DealSlots
		If dealStates[i] != DealFree
			count += 1
		EndIf
		i += 1
	EndWhile
	Return count
EndFunction

Int Function WorkerDealCount()
	Actor player = Game.GetPlayer()
	Int count = 0
	Int i = 0
	While i < DealSlots
		If dealStates[i] != DealFree && dealWorkers[i] != player
			count += 1
		EndIf
		i += 1
	EndWhile
	Return count
EndFunction

Bool Function IsInDeal(Actor akActor)
	Int i = 0
	While akActor && i < DealSlots
		If dealStates[i] != DealFree && (dealWorkers[i] == akActor || dealCustomers[i] == akActor)
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

; Claims a free slot for the pair, or returns -1 if none is free or either of them is already in a
; deal (another serving thread may have picked them meanwhile).
Int Function ReserveDeal(Actor worker, Actor customer)
	If IsInDeal(worker) || IsInDeal(customer)
		Return -1
	EndIf
	Int i = 0
	While i < DealSlots
		If dealStates[i] == DealFree
			dealStates[i] = DealApproaching
			dealWorkers[i] = worker
			dealCustomers[i] = customer
			dealThreads[i] = -1
			nextSerial += 1
			dealSerials[i] = nextSerial
			dealStarted[i] = Utility.GetCurrentRealTime()
			dealAnsweredAt[i] = 0.0
			ScheduleWatchdog()
			; A visitor from town goes home once this deal is over, whatever its outcome.
			Int visitor = visitors.Find(customer)
			If visitor >= 0
				visitorServed[visitor] = True
			EndIf
			Return i
		EndIf
		i += 1
	EndWhile
	Return -1
EndFunction

; Whether the slot still holds the deal its serving thread opened.
Bool Function DealAlive(Int slot, Int serial)
	Return dealStates[slot] != DealFree && dealSerials[slot] == serial
EndFunction

Function ReleaseDeal(Int slot)
	ReleaseHold(slot)
	; A deal that ends before its scene played (the scene failed, a timeout, the player walked away)
	; gives the gold back; one whose scene played keeps it.
	If dealPaid[slot] && dealStates[slot] != DealInScene
		RefundDeal(slot)
	EndIf
	dealPaid[slot] = False
	dealPaidWorker[slot] = 0
	dealPaidOwner[slot] = 0
	dealSolicited[slot] = False
	dealStates[slot] = DealFree
	dealIdleRuns[slot] = 0
	dealWorkers[slot] = None
	dealCustomers[slot] = None
	dealThreads[slot] = -1
	dealBeds[slot] = None
	dealCenters[slot] = None
	DeleteSpot(slot)
EndFunction

Function DeleteSpot(Int slot)
	If dealSpots[slot]
		dealSpots[slot].Disable()
		dealSpots[slot].Delete()
		dealSpots[slot] = None
	EndIf
EndFunction

; Marks where the customer stands now, a spot an NPC can reach, as a fallback place for the scene.
Function MarkCustomerSpot(Int slot)
	dealSpots[slot] = dealCustomers[slot].PlaceAtMe(Game.GetForm(0x00003B), 1, False, False) ; XMarker
EndFunction

; Held by the pair picking a bed (see StartBrothelScene); a pick that never let go (a thread cut off
; by a load) is taken over after BedPickTimeoutSeconds.
Bool pickingBed
Float pickingBedSince
Float Property BedPickTimeoutSeconds = 15.0 AutoReadOnly

Function LockBedPick()
	; The time is read before the check, and the flag and its time are set together: a call to
	; another script lets other threads in, and one coming in between them read the old time, took
	; the lock as stale and picked the same bed.
	Float now = Utility.GetCurrentRealTime()
	While pickingBed && now - pickingBedSince < BedPickTimeoutSeconds
		Utility.Wait(0.2)
		now = Utility.GetCurrentRealTime()
	EndWhile
	pickingBed = True
	pickingBedSince = now
EndFunction

; The best bed in the brothel that nobody uses, sleeps in, stands on, or has been given to another
; pair: a double bed before a single one (SexLab's bed scenes are made for a double bed and spill
; over a single one), a single bed before a bedroll, and the nearest of the kind. The furniture in
; range is scanned directly: SexLab's FindBeds left out the Bannered Mare's rented beds, and its
; FindBed with IgnoreUsed returns beds in use.
ObjectReference Function PickBed(SexLabFramework sexLab, Actor worker, Actor[] positions)
	ObjectReference[] found = PO3_SKSEFunctions.FindAllReferencesOfFormType(worker, FormTypeFurniture, BedSearchRadius)
	Bool logging = GetModSettingBool("bDebugLog:General")
	If logging
		DebugLog("Bed search for " + worker.GetDisplayName() + ": " + found.Length + " furniture in range")
	EndIf
	ObjectReference bed = None
	Int bedTypeChosen = 0
	Float bedDistance = 0.0
	; With no furniture P+ offers every scene; on furniture it knows, only that furniture's. 1.6x
	; takes only the beds in its own list, which BedTypeOf already keeps to, so it needs no check.
	Int anywhereCount = 0
	If !legacySexLab
		anywhereCount = skyrimnet_BrothelSLP.SceneCount(sexLab, positions, "", 1, None)
	EndIf
	Int i = 0
	While i < found.Length
		ObjectReference candidate = found[i]
		Int bedType = BedTypeOf(sexLab, candidate)
		If bedType > 0
			Float distance = worker.GetDistance(candidate)
			Float dz = candidate.GetPositionZ() - worker.GetPositionZ()
			Bool usable = !candidate.IsDisabled() && candidate.GetParentCell() == brothelCell && Math.abs(dz) <= BedSearchRadiusZ \
				&& dealBeds.Find(candidate) < 0 && sexLab.IsBedAvailable(candidate) && !BedOccupied(candidate, positions)
			If logging
				DebugLog("  " + candidate.GetDisplayName() + " [" + candidate.GetFormID() + "] " \
					+ PO3_SKSEFunctions.GetFormEditorID(candidate.GetBaseObject()) + " type=" + bedType \
					+ " sexLabBed=" + IsSexLabBed(sexLab, candidate) \
					+ " dist=" + (distance as Int) + " dz=" + (dz as Int) \
					+ " sameCell=" + (candidate.GetParentCell() == brothelCell) + " takenByPair=" + (dealBeds.Find(candidate) >= 0) + " occupied=" + BedOccupied(candidate, positions) \
					+ " available=" + sexLab.IsBedAvailable(candidate) + " usable=" + usable)
			EndIf
			; SexLab's bed types rank them: 3 double, 2 single, 1 bedroll.
			Bool better = !bed || bedType > bedTypeChosen || (bedType == bedTypeChosen && distance < bedDistance)
			If usable && better && !legacySexLab
				; Only a candidate that would be chosen is checked, as the lookup takes a moment.
				Int onBedCount = skyrimnet_BrothelSLP.SceneCount(sexLab, positions, "", 2, candidate)
				If onBedCount == 0 || onBedCount >= anywhereCount
					usable = False
				EndIf
				If logging
					DebugLog("    SexLab scenes here: " + onBedCount + " of " + anywhereCount + "; known bed=" + usable)
				EndIf
			EndIf
			If usable && better
				bed = candidate
				bedTypeChosen = bedType
				bedDistance = distance
			EndIf
		EndIf
		i += 1
	EndWhile
	If logging
		If bed
			DebugLog("  -> chose " + bed.GetDisplayName() + " [" + bed.GetFormID() + "]")
		Else
			DebugLog("  -> nothing free; the scene starts without a bed")
		EndIf
	EndIf
	Return bed
EndFunction

; SexLab's bed type (1 bedroll, 2 single, 3 double); furniture SexLab does not class as a bed but
; whose editor ID names one counts as a single bed. Whether SexLab really plays bed animations on it
; is checked separately in PickBed: on furniture it does not know (CommonBed01L, for one) it picks
; standing animations, plays them at the furniture's origin, and the bed pushes the pair apart.
; Under 1.6x, which has no such check, only the beds in SexLab's own list count.
Int Function BedTypeOf(SexLabFramework sexLab, ObjectReference ref)
	If legacySexLab
		Return skyrimnet_BrothelSL16.BedType(sexLab, ref)
	EndIf
	Int bedType = skyrimnet_BrothelSLP.BedType(sexLab, ref)
	If bedType > 0
		Return bedType
	EndIf
	String editorID = PO3_SKSEFunctions.GetFormEditorID(ref.GetBaseObject())
	If StringUtil.Find(editorID, "Bedroll") >= 0
		Return BedTypeBedroll
	ElseIf StringUtil.Find(editorID, "Bed") >= 0
		Return 2
	EndIf
	Return 0
EndFunction

; With "Debug log" on (MCM), lines go to Data/SKSE/Plugins/skyrimnet_Brothel_debug.log; under MO2
; that file lands in the overwrite folder.
Function DebugLog(String line)
	MiscUtil.WriteToFile("Data/SKSE/Plugins/skyrimnet_Brothel_debug.log", line + "\n", True, True)
EndFunction

; Whether ref is far enough from every other pair's scene.
Bool Function ClearOfOtherScenes(ObjectReference ref, Int slot)
	Int i = 0
	While i < DealSlots
		If i != slot && dealCenters[i] && ref.GetDistance(dealCenters[i]) < SceneSpacing
			Return False
		EndIf
		i += 1
	EndWhile
	Return True
EndFunction

; A scene SexLab gave up on after it seemed to play sends no end hook either: once neither of the
; pair has been in a SexLab scene at two watchdog runs in a row, the deal is cleared, unpaid, so the
; pair (or the player) can take the next one. Two runs, so an end hook still on its way pays first.
Function ClearStalledDeals()
	Float now = Utility.GetCurrentRealTime()
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Int i = 0
	While i < DealSlots
		If dealStates[i] == DealInScene && now - dealStarted[i] > SceneTimeoutSeconds
			ReleaseDeal(i)
		ElseIf dealStates[i] == DealInScene && sexLab && !sexLab.IsActorActive(dealWorkers[i]) && !sexLab.IsActorActive(dealCustomers[i])
			dealIdleRuns[i] = dealIdleRuns[i] + 1
			If dealIdleRuns[i] >= 2
				If GetModSettingBool("bDebugLog:General")
					DebugLog("Scene for " + dealWorkers[i].GetDisplayName() + " and " + dealCustomers[i].GetDisplayName() \
						+ " stopped without an end hook; deal cleared")
				EndIf
				StepOffBed(i)
				ReleaseDeal(i)
			EndIf
		ElseIf dealStates[i] == DealInScene
			dealIdleRuns[i] = 0
		ElseIf dealStates[i] != DealFree && now - dealStarted[i] > BusyTimeoutSeconds
			ReleaseDeal(i)
		EndIf
		i += 1
	EndWhile
EndFunction

; ---------------------------------------------------------------------------------------------
; Serving a customer
; ---------------------------------------------------------------------------------------------

; quiet: from the automatic timer, which keeps routine "nothing to do" notifications to itself.
Function ServeCustomer(Bool quiet)
	If !brothelCell
		Notify("$SNB_NoBrothel", quiet)
		Return
	EndIf
	If Game.GetPlayer().GetParentCell() != brothelCell
		Notify("$SNB_NotInBrothel", quiet)
		Return
	EndIf
	If WorkerDealCount() >= MaxConcurrent()
		Notify("$SNB_Busy", quiet)
		Return
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Actor worker = PickWorker(sexLab, PlayerInAutoServe())
	If !worker
		Notify("$SNB_NoWorker", quiet)
		If !quiet && GetModSettingBool("bDebugLog:General")
			LogWorkersNotFree(sexLab)
		EndIf
		Return
	EndIf
	Actor customer = PickCustomer(sexLab, worker)
	If !customer
		Notify("$SNB_NoCustomer", quiet)
		Return
	EndIf
	ServePair(sexLab, worker, customer, quiet)
EndFunction

; The customer walks over to this worker and makes his offer: ServeCustomer's pick, or the pair the
; owner put together. With the player as the worker, the player answers (ServePlayerWith).
Function ServePair(SexLabFramework sexLab, Actor worker, Actor customer, Bool quiet)
	If worker == Game.GetPlayer()
		ServePlayerWith(sexLab, customer)
		Return
	EndIf
	Int slot = ReserveDeal(worker, customer)
	If slot < 0
		Notify("$SNB_Busy", quiet)
		Return
	EndIf
	Int serial = dealSerials[slot]
	MarkCustomerSpot(slot)
	AnnounceApproach(customer, worker)

	ApproachWorker(customer, worker)
	If !AcquireTalk(slot, serial)
		Return
	EndIf
	dealStates[slot] = DealPending
	Float offeredAt = Utility.GetCurrentRealTime()
	Bool alwaysAccept = GetModSettingBool("bAlwaysAccept:General")
	; Narration is taken as something that has already happened, and the speaker reacts to it: told
	; that the offer was made (and accepted), the customer opened with "a fine answer". So it only
	; says he is about to ask, and he voices the offer himself. That she always accepts is
	; background she knows, not an event anyone reacts to.
	If alwaysAccept
		SkyrimNetApi.RegisterPersistentEvent(worker.GetDisplayName() + " works at this brothel and accepts every paying customer.", worker, customer)
	EndIf
	SkyrimNetApi.DirectNarration(OfferNarration(customer, worker), customer, worker)
	; With "always accept", knowing that she accepts did not keep the LLM from having her answer
	; "get lost" before the scene started anyway. So once the offer has been spoken, she is told
	; that she accepts, and says so.
	If alwaysAccept
		WaitForSpeech(offeredAt, slot)
		If !DealAlive(slot, serial)
			ReleaseTalk()
			Return
		EndIf
		offeredAt = Utility.GetCurrentRealTime()
		dealStates[slot] = DealAccepted
		PayForDeal(slot)
		SkyrimNetApi.DirectNarration(worker.GetDisplayName() + " accepts " + customer.GetDisplayName() + "'s offer, takes the " \
			+ GetModSettingInt("iPayment:General") + " gold " + HeOf(customer) + " has just handed over and agrees to spend the night with " + customer.GetDisplayName() \
			+ ". She now tells " + customer.GetDisplayName() + " so in her own words, " + AcceptManner(WorkerLevel(worker)) + "." + LevelContext(worker), worker, customer)
	EndIf

	; The worker answers through AcceptCustomerOffer / RefuseCustomerOffer as the conversation goes.
	; With "always accept" there is nothing to wait for: the scene follows the exchange.
	Float waited = 0.0
	While !alwaysAccept && DealAlive(slot, serial) && dealStates[slot] == DealPending && waited < DealTimeoutSeconds && !AnswerSpoken(slot)
		KeepClose(slot)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	If !DealAlive(slot, serial)
		ReleaseTalk()
		Return
	EndIf
	If dealStates[slot] == DealRefused
		Debug.Notification("$SNB_Refused")
		ReleaseTalk()
		ReleaseDeal(slot)
		Return
	EndIf
	; Accepted, or no answer in time: let the last line finish, then one beat before the scene.
	dealStates[slot] = DealAccepted
	PayForDeal(slot)
	WaitForSpeech(offeredAt, slot)
	ReleaseTalk()
	Utility.Wait(1.5)
	If DealAlive(slot, serial)
		StartBrothelScene(sexLab, slot)
	EndIf
EndFunction

; The player's own customer, on its own hotkey only: a customer walks up and makes the offer,
; and the player answers in a message box. Players need no registering, and the player's deal
; does not count against the MCM's limit on workers at once.
Function ServePlayer()
	PlayerTrace("hotkey pressed")
	If !brothelCell
		Debug.Notification("$SNB_NoBrothel")
		Return
	EndIf
	Actor player = Game.GetPlayer()
	If player.GetParentCell() != brothelCell
		Debug.Notification("$SNB_NotInBrothel")
		Return
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	If IsInDeal(player) || sexLab.IsActorActive(player)
		PlayerTrace("stopped: already in a deal (" + IsInDeal(player) + ") or a SexLab scene (" + sexLab.IsActorActive(player) + ")")
		Debug.Notification("$SNB_PlayerBusy")
		Return
	EndIf
	Actor customer = PickCustomer(sexLab, player)
	If !customer
		PlayerTrace("stopped: no free customer")
		Debug.Notification("$SNB_NoCustomer")
		Return
	EndIf
	ServePlayerWith(sexLab, customer)
EndFunction

; The customer walks up to the player and makes his offer: from the player's own hotkey, automatic
; serving with the player included, or an NPC owner's recommendation.
Function ServePlayerWith(SexLabFramework sexLab, Actor customer)
	Actor player = Game.GetPlayer()
	If IsInDeal(player) || sexLab.IsActorActive(player)
		Debug.Notification("$SNB_PlayerBusy")
		Return
	EndIf
	Int slot = ReserveDeal(player, customer)
	If slot < 0
		Debug.Notification("$SNB_PlayerBusy")
		Return
	EndIf
	Int serial = dealSerials[slot]
	MarkCustomerSpot(slot)
	AnnounceApproach(customer, player)

	PlayerTrace("customer " + customer.GetDisplayName() + " in slot " + slot)
	ApproachWorker(customer, player)
	If talking
		Debug.Notification("$SNB_WaitingTurn")
	EndIf
	If !AcquireTalk(slot, serial)
		PlayerTrace("stopped: the deal was cleared while waiting to talk")
		Return
	EndIf
	If ChoicesReady() && ServePlayerWithChoices(sexLab, slot, serial)
		Return
	EndIf
	Float offeredAt = Utility.GetCurrentRealTime()
	SkyrimNetApi.DirectNarration(OfferNarration(customer, player), customer, player)
	WaitForSpeech(offeredAt, slot)
	ReleaseTalk()
	If !DealAlive(slot, serial)
		PlayerTrace("stopped: the deal was cleared during the offer")
		Return
	EndIf
	; The box would not show over an open menu (dialogue, inventory...).
	Float menuWait = 0.0
	While Utility.IsInMenuMode() && menuWait < 60.0
		KeepClose(slot)
		Utility.Wait(0.5)
		menuWait += 0.5
	EndWhile
	PlayerTrace("showing the offer box")

	Message offerBox = Game.GetFormFromFile(PlayerOfferMsgID, PluginName) as Message
	If offerBox.Show() != 0
		SkyrimNetApi.RegisterPersistentEvent(player.GetDisplayName() + " turned down " + customer.GetDisplayName() + "'s offer.", player, customer)
		Debug.Notification("$SNB_PlayerRefused")
		ReleaseDeal(slot)
		Return
	EndIf
	SkyrimNetApi.RegisterPersistentEvent(player.GetDisplayName() + " accepted " + customer.GetDisplayName() + "'s offer.", player, customer)
	dealStates[slot] = DealAccepted
	PayForDeal(slot)
	Utility.Wait(1.0)
	If DealAlive(slot, serial)
		StartBrothelScene(sexLab, slot)
	Else
		PlayerTrace("stopped: the deal was cleared after accepting")
	EndIf
EndFunction

; ---------------------------------------------------------------------------------------------
; The player's answers through the built-in Player Choices (skyrimnet_BrothelChoices)
; ---------------------------------------------------------------------------------------------

; The player answers the customer in the vanilla dialogue menu with AI-written lines in their own
; voice: accept, accept reluctantly or refuse; on accepting, the customer asks for a position and the
; player picks one of the SexLab position tags that have a scene for this pair (positions.json).
; skyrimnet_BrothelChoices is SkyrimNet Player Choices built in under its own names, so it runs
; beside the standalone mod. When it cannot start, the player answers in the message box.
String Property ChoicesTagOffer = "SNB_Offer" AutoReadOnly
String Property ChoicesTagPosition = "SNB_Position" AutoReadOnly
String Property PositionsFile = "../skyrimnet_Brothel/positions.json" AutoReadOnly
Int Property MaxPositionChoices = 4 AutoReadOnly
; AskPlayer's results besides a choice's index: walked away (-1), no pick, and could not ask.
Int Property ChoiceLeft = -1 AutoReadOnly
Int Property ChoiceNone = -2 AutoReadOnly
Int Property ChoiceUnavailable = -3 AutoReadOnly

; The choices conversation in progress, filled by its mod events.
String choiceTag
Int choiceIndex
Bool choiceEnded
; Whether the customer answered the player's last pick himself (see AskPlayer).
Bool lastAskAnswered = True

Int Property ChoicesQuestID = 0x00080D AutoReadOnly

skyrimnet_BrothelChoices Function Choices()
	Return Game.GetFormFromFile(ChoicesQuestID, PluginName) as skyrimnet_BrothelChoices
EndFunction

Bool Function ChoicesReady()
	Return Choices() != None
EndFunction

Event OnChoicesReplyChosen(Form akNpc, String asTag, Int aiIndex, String asText)
	If asTag == choiceTag && asTag != ""
		choiceIndex = aiIndex
	EndIf
EndEvent

Event OnChoicesEnded(Form akNpc, String asTag, Int aiReason)
	If asTag == choiceTag && asTag != ""
		choiceEnded = True
	EndIf
EndEvent

; Runs one choices conversation with the customer and waits until the customer has answered
; the player's pick. Returns the index of the picked intent, ChoiceLeft, ChoiceNone (the menu closed,
; the LLM failed, or no answer in three minutes), or ChoiceUnavailable when it could not start.
; customerAnswers False: the customer does not answer the pick; the caller has him react, and
; lastAskAnswered says whether that applied. playerSpeaksFirst: the
; player opens the conversation with the picked line (the owner recommending a worker). slot -1:
; no deal yet.
Int Function AskPlayer(Actor customer, String theme, String situation, String[] intents, String tag, Int slot, Bool customerAnswers = True, Bool playerSpeaksFirst = False, String answerNote = "")
	skyrimnet_BrothelChoices engine = Choices()
	If !engine || !intents
		Return ChoiceUnavailable
	EndIf
	Float waited = 0.0
	While !engine.IsIdle() && waited < 30.0
		KeepClose(slot)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	choiceTag = tag
	choiceIndex = ChoiceNone
	choiceEnded = False
	lastAskAnswered = customerAnswers || playerSpeaksFirst
	Bool started = engine.StartFromApi(customer, playerSpeaksFirst, theme, situation, intents, tag, lastAskAnswered, answerNote)
	If !started
		choiceTag = ""
		Return ChoiceUnavailable
	EndIf
	waited = 0.0
	While !choiceEnded && waited < 180.0
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	choiceTag = ""
	Return choiceIndex
EndFunction

; ServePlayer's answer and scene through the choices menu. False when it could not take the offer
; at all, so the message box takes over; True when the deal has been dealt with here.
Bool Function ServePlayerWithChoices(SexLabFramework sexLab, Int slot, Int serial)
	Actor player = Game.GetPlayer()
	Actor customer = dealCustomers[slot]
	Int payment = GetModSettingInt("iPayment:General")
	String[] answers = new String[3]
	answers[0] = "accept the offer willingly"
	answers[1] = "accept the offer, but reluctantly"
	answers[2] = "refuse the offer"
	PlayerTrace("asking through the choices menu")
	; The customer does not answer the pick here: on accepting, his reaction and his question about
	; the position are one line, written with the position choices (AskPosition), one LLM call
	; instead of two.
	Int answer = AskPlayer(customer, "a paid offer: " + customer.GetDisplayName() + " wants " + player.GetDisplayName() \
		+ "'s company tonight for " + payment + " gold", OfferNarration(customer, player), answers, ChoicesTagOffer, slot, False)
	Bool reactionOwed = !lastAskAnswered
	If answer == ChoiceUnavailable
		PlayerTrace("the choices menu could not start; using the message box")
		Return False
	EndIf
	If !DealAlive(slot, serial)
		ReleaseTalk()
		Return True
	EndIf
	If answer != 0 && answer != 1
		If reactionOwed && answer == 2
			CustomerReacts(customer, player.GetDisplayName() + " has just turned down " + customer.GetDisplayName() \
				+ "'s offer. " + customer.GetDisplayName() + " reacts to the refusal in a few words and lets it go.")
		EndIf
		SkyrimNetApi.RegisterPersistentEvent(player.GetDisplayName() + " turned down " + customer.GetDisplayName() + "'s offer.", player, customer)
		Debug.Notification("$SNB_PlayerRefused")
		ReleaseTalk()
		ReleaseDeal(slot)
		Return True
	EndIf
	String how = ""
	If answer == 1
		how = " reluctantly"
	EndIf
	SkyrimNetApi.RegisterPersistentEvent(player.GetDisplayName() + how + " accepted " + customer.GetDisplayName() + "'s offer.", player, customer)
	dealStates[slot] = DealAccepted
	PayForDeal(slot)

	String positionTag = AskPosition(sexLab, slot, answer == 1, reactionOwed)
	If reactionOwed && !positionAsked
		; No position question after all (no tag has a scene, or the choices menu was busy): the
		; customer still answers the acceptance.
		String mood = "willingly"
		If answer == 1
			mood = "reluctantly"
		EndIf
		CustomerReacts(customer, player.GetDisplayName() + " has just " + mood + " accepted " + customer.GetDisplayName() \
			+ "'s offer of " + payment + " gold for the night. " + customer.GetDisplayName() + " reacts to the answer in a few words.")
	EndIf
	ReleaseTalk()
	If positionTag == "-"
		; Walked away when asked: the deal is off after all.
		SkyrimNetApi.RegisterPersistentEvent(player.GetDisplayName() + " changed their mind and left " + customer.GetDisplayName() + ".", player, customer)
		Debug.Notification("$SNB_PlayerRefused")
		ReleaseDeal(slot)
		Return True
	EndIf
	Utility.Wait(1.0)
	If DealAlive(slot, serial)
		StartBrothelScene(sexLab, slot, positionTag)
	Else
		PlayerTrace("stopped: the deal was cleared after accepting")
	EndIf
	Return True
EndFunction

; The customer asks which position the player wants. Offers up to MaxPositionChoices of the
; positions.json tags that have a scene for this pair, in random order, and "leave it to you".
; Returns the picked tag, "" for the customer's choice (or nothing usable), "-" when the player
; walked away. reactFirst: the customer has not answered the acceptance yet, so his question opens
; with his reaction to it. positionAsked says whether the question was put at all.
Bool positionAsked

String Function AskPosition(SexLabFramework sexLab, Int slot, Bool reluctant, Bool reactFirst = False)
	Actor player = Game.GetPlayer()
	Actor customer = dealCustomers[slot]
	Actor[] positions = new Actor[2]
	positions[0] = player
	positions[1] = customer
	positionAsked = False
	Int tagCount = JsonUtil.StringListCount(PositionsFile, "tags")
	If tagCount <= 0
		Return ""
	EndIf
	String[] offered = Utility.CreateStringArray(MaxPositionChoices)
	String[] intents = Utility.CreateStringArray(MaxPositionChoices + 1)
	Int count = 0
	Int start = Utility.RandomInt(0, tagCount - 1)
	Int i = 0
	While i < tagCount && count < MaxPositionChoices
		Int index = (start + i) % tagCount
		String tag = JsonUtil.StringListGet(PositionsFile, "tags", index)
		If tag != "" && HasScenesFor(sexLab, positions, tag)
			offered[count] = tag
			intents[count] = JsonUtil.StringListGet(PositionsFile, "labels", index)
			If intents[count] == ""
				intents[count] = "ask for " + tag
			EndIf
			count += 1
		EndIf
		i += 1
	EndWhile
	If count == 0
		Return ""
	EndIf
	intents[count] = "leave the choice to the customer"
	intents = Utility.ResizeStringArray(intents, count + 1)
	String mood = "willingly"
	If reluctant
		mood = "reluctantly"
	EndIf
	String theme = "the customer asks which position " + player.GetDisplayName() + " would like tonight"
	String situation = player.GetDisplayName() + " has just " + mood + " agreed to spend the night with " + customer.GetDisplayName() \
		+ " for gold. Before they go to bed, " + customer.GetDisplayName() + " asks " + player.GetDisplayName() \
		+ " what they would like to do, and keeps it short."
	If reactFirst
		theme = "the customer reacts to " + player.GetDisplayName() + "'s answer and asks which position they would like tonight"
		situation = player.GetDisplayName() + " has just " + mood + " accepted " + customer.GetDisplayName() \
			+ "'s offer to spend the night together for gold, and " + customer.GetDisplayName() + " has not reacted yet. In one short line, " \
			+ customer.GetDisplayName() + " reacts to the answer and, in the same breath, asks " + player.GetDisplayName() \
			+ " what they would like to do tonight."
	EndIf
	Int picked = AskPlayer(customer, theme, situation, intents, ChoicesTagPosition, slot)
	positionAsked = picked != ChoiceUnavailable
	If picked == ChoiceLeft
		Return "-"
	ElseIf picked >= 0 && picked < count
		PlayerTrace("position " + offered[picked])
		Return offered[picked]
	EndIf
	Return ""
EndFunction

; ---------------------------------------------------------------------------------------------
; SexLab P+ or 1.6x: each of these goes to the script for the SexLab installed (see DetectSexLab)
; ---------------------------------------------------------------------------------------------

; Whether SexLab has a scene with this tag for the pair, with one sex per position for a man and a
; woman, anywhere.
Bool Function HasScenesFor(SexLabFramework sexLab, Actor[] positions, String tag)
	If legacySexLab
		Return skyrimnet_BrothelSL16.HasScenesFor(sexLab, positions, tag)
	EndIf
	Return skyrimnet_BrothelSLP.HasScenesFor(sexLab, positions, tag)
EndFunction

; Whether SexLab has a scene with this tag for the pair at center with this furniture preference.
Bool Function HasScenes(SexLabFramework sexLab, Actor[] positions, String tag, Int furniturePref, ObjectReference center)
	If legacySexLab
		Return skyrimnet_BrothelSL16.HasScenes(sexLab, positions, tag, furniturePref, center)
	EndIf
	Return skyrimnet_BrothelSLP.HasScenes(sexLab, positions, tag, furniturePref, center)
EndFunction

Bool Function IsSexLabBed(SexLabFramework sexLab, ObjectReference ref)
	If legacySexLab
		Return skyrimnet_BrothelSL16.IsSexLabBed(sexLab, ref)
	EndIf
	Return skyrimnet_BrothelSLP.IsSexLabBed(sexLab, ref)
EndFunction

; Starts one scene for the pair, a fresh random pick of scenes each call, the tag's if it has any.
; Returns the SexLab thread's ID, or -1 when SexLab refuses.
Int Function StartSceneOnce(SexLabFramework sexLab, Actor[] positions, ObjectReference center, Int furniturePref, String positionTag)
	If legacySexLab
		Return skyrimnet_BrothelSL16.StartScene(sexLab, positions, center, furniturePref, positionTag, SceneHook)
	EndIf
	Return skyrimnet_BrothelSLP.StartScene(sexLab, positions, center, furniturePref, positionTag, SceneHook)
EndFunction

; The customer's own reaction to the player's answer, when the choices menu left it to the brothel.
Function CustomerReacts(Actor customer, String narration)
	SkyrimNetApi.DirectNarration(narration, customer, Game.GetPlayer())
EndFunction

; Tells the customer to make his offer now, in his own words, rather than reporting it as made.
String Function OfferNarration(Actor customer, Actor worker)
	String pronoun = "his"
	If worker.GetActorBase().GetSex() == 1
		pronoun = "her"
	EndIf
	String he = "He"
	String his = "his"
	If customer.GetLeveledActorBase().GetSex() == 1
		he = "She"
		his = "her"
	EndIf
	; The roles are spelled out: left to guess, the LLM once had the customer tell the worker to
	; pay with her body if she had no gold.
	Int payment = GetModSettingInt("iPayment:General")
	Return worker.GetDisplayName() + " sells " + pronoun + " company for gold at this brothel; " + customer.GetDisplayName() \
		+ " is a customer who will pay " + worker.GetDisplayName() + " " + payment + " gold for it. The customer pays; " \
		+ worker.GetDisplayName() + " owes nothing and is the one paid. " + customer.GetDisplayName() + " has walked up to " \
		+ worker.GetDisplayName() + " and wants " + pronoun + " company tonight. " + he + " has not said so yet and now makes the offer in " \
		+ his + " own words, offering " + payment + " gold, then waits for an answer. " + he + " has not paid yet: the gold changes hands " \
		+ "the moment " + worker.GetDisplayName() + " agrees, not before." \
		+ ApproachStyle(customer.GetDisplayName(), "customer") + LevelContext(worker)
EndFunction

; Every offer was told the same thing, and came out as the same line ("50 gold for your time"). A
; way of making it is picked from approaches.json (Data/SKSE/Plugins/skyrimnet_Brothel/approaches.json,
; one list for customers, one for workers), never the same one twice in a row.
String Property ApproachesFile = "../skyrimnet_Brothel/approaches.json" AutoReadOnly
Int lastCustomerApproach = -1
Int lastWorkerApproach = -1

String Function ApproachStyle(String speaker, String listKey)
	Int count = JsonUtil.StringListCount(ApproachesFile, listKey)
	If count == 0
		Return ""
	EndIf
	Int last = lastCustomerApproach
	If listKey == "worker"
		last = lastWorkerApproach
	EndIf
	Int index = Utility.RandomInt(0, count - 1)
	If index == last && count > 1
		index = (index + 1) % count
	EndIf
	If listKey == "worker"
		lastWorkerApproach = index
	Else
		lastCustomerApproach = index
	EndIf
	Return " This time " + speaker + " " + JsonUtil.StringListGet(ApproachesFile, listKey, index) \
		+ ". The price can come up anywhere, even last; it is not simply stated as a fixed phrase."
EndFunction

; What the LLM is told about the worker's feelings for the work and about the house, by level.
String Function LevelContext(Actor worker)
	String text = " This brothel is " + BrothelReputation(BrothelLevel()) + "."
	If worker != Game.GetPlayer()
		text += " " + worker.GetDisplayName() + " " + WorkerAttitude(WorkerLevel(worker)) + "."
	EndIf
	Return text
EndFunction

Function PlayerTrace(String line)
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Player serving: " + line)
	EndIf
EndFunction

; Bed mode "always": the nearest free bed in the brothel is the scene's centre, which also makes
; SexLab pick bed animations. With no free bed (or bed mode "follow SexLab") the scene starts where
; the worker stands, unless another pair is already there: then at the spot the customer came from.
; positionTag: a SexLab tag the player picked (Player Choices); "" for any scene.
Function StartBrothelScene(SexLabFramework sexLab, Int slot, String positionTag = "")
	Actor worker = dealWorkers[slot]
	Actor[] positions = new Actor[2]
	positions[0] = worker
	positions[1] = dealCustomers[slot]
	ObjectReference center = None
	Int furniturePref = 1
	If GetModSettingInt("iBedMode:General") == 1
		; PickBed waits on SexLab partway through, and the bed counts as taken only once it is in
		; dealBeds: two pairs picking at once chose the same bed, and SexLab put the second pair on
		; it too (one of them floating above the bed). One pair picks and claims at a time.
		LockBedPick()
		center = PickBed(sexLab, worker, positions)
		; A picked position the bed has no scene for (standing, say) is played off the bed.
		If center && positionTag != "" && !HasScenes(sexLab, positions, positionTag, 2, center)
			center = None
		EndIf
		dealBeds[slot] = center
		pickingBed = False
		If center
			furniturePref = 2
		Else
			; No free bed for this pair. Allowed furniture, SexLab looks for a bed itself and takes the
			; one another pair is on (its IsBedAvailable says yes to a bed in use).
			furniturePref = 0
		EndIf
	EndIf
	If !center && !ClearOfOtherScenes(worker, slot) && dealSpots[slot]
		center = dealSpots[slot]
	EndIf
	If center
		dealCenters[slot] = center
	Else
		dealCenters[slot] = worker
	EndIf
	; SexLab's automatic free camera starts where the player stands, not where SexLab then moves the
	; pair, so a pair with the player is brought to the scene's place first.
	ReleaseHold(slot) ; SexLab moves the pair itself from here
	Actor player = Game.GetPlayer()
	If positions[1].IsDisabled() || !positions[1].Is3DLoaded()
		Debug.Notification("$SNB_SceneFailed")
		ReleaseDeal(slot)
		Return
	EndIf
	If center && (worker == player || positions[1] == player)
		positions[1].MoveTo(center, 40.0, 0.0, 0.0)
		worker.MoveTo(center)
	EndIf
	; SexLab gives up on a scene whose animation the game cannot play (a pack missing from the
	; generated behaviour files): it accepts the scene, then restores the pair a few seconds later
	; with no end hook. Such a scene is tried again, with other scenes, up to SceneAttempts times.
	Int threadID = -1
	Int attempt = 0
	Bool playing = False
	While attempt < SceneAttempts && !playing
		threadID = StartSceneOnce(sexLab, positions, center, furniturePref, positionTag)
		If threadID >= 0
			playing = StillPlaying(sexLab, positions)
		EndIf
		If GetModSettingBool("bDebugLog:General")
			DebugLog("Scene (SexLab " + SexLabName() + ") for " + worker.GetDisplayName() + " and " + positions[1].GetDisplayName() \
				+ ", try " + (attempt + 1) + ": started=" + (threadID >= 0) + " playing=" + playing)
		EndIf
		If threadID < 0
			attempt = SceneAttempts
		Else
			attempt += 1
		EndIf
	EndWhile
	If !playing
		threadID = -1
	EndIf
	If threadID < 0
		; A player moved onto the bed would otherwise be left lying there.
		If worker == player || positions[1] == player
			Debug.SendAnimationEvent(player, "IdleForceDefaultState")
			If dealSpots[slot]
				player.MoveTo(dealSpots[slot])
			EndIf
		EndIf
		Debug.Notification("$SNB_SceneFailed")
		ReleaseDeal(slot)
		Return
	EndIf
	dealThreads[slot] = threadID
	dealStates[slot] = DealInScene
	dealStarted[slot] = Utility.GetCurrentRealTime()
EndFunction

Int Property SceneAttempts = 3 AutoReadOnly
; How long after the start a scene must still be running to count as playing, and how many more
; times, how far apart, it is looked at again.
Float Property SceneCheckSeconds = 6.0 AutoReadOnly
Int Property SceneConfirmChecks = 2 AutoReadOnly
Float Property SceneConfirmSeconds = 3.0 AutoReadOnly

; A scene SexLab P+ cannot play (its animation file missing) has both actors marked active for a
; few more seconds while it restores them: one look at six seconds took such a scene for playing.
; So it must still hold the pair at every look.
Bool Function StillPlaying(SexLabFramework sexLab, Actor[] positions)
	Utility.Wait(SceneCheckSeconds)
	Int check = 0
	While check <= SceneConfirmChecks
		If !sexLab.IsActorActive(positions[0]) && !sexLab.IsActorActive(positions[1])
			Return False
		EndIf
		If check < SceneConfirmChecks
			Utility.Wait(SceneConfirmSeconds)
		EndIf
		check += 1
	EndWhile
	Return True
EndFunction

; "<customer> is approaching <worker>." Translation files cannot hold a sentence with names in it,
; and alias text replacement in the message showed "[...]" in play, so the words around the names
; come from SKSE/Plugins/skyrimnet_Brothel/strings.json, which a translation mod replaces.
Function AnnounceApproach(Actor customer, Actor worker)
	String text
	If worker == Game.GetPlayer()
		text = Phrase("approachYouBefore", "") + customer.GetDisplayName() + Phrase("approachYouAfter", " is approaching you.")
	Else
		text = Phrase("approachBefore", "") + customer.GetDisplayName() + Phrase("approachBetween", " is approaching ") \
			+ worker.GetDisplayName() + Phrase("approachAfter", ".")
	EndIf
	Debug.Notification(text)
EndFunction

; A phrase from strings.json (Data/SKSE/Plugins/skyrimnet_Brothel/strings.json), or the English
; fallback when the file or the key is missing.
String Function Phrase(String phraseKey, String fallback)
	Return JsonUtil.GetStringValue(StringsFile, phraseKey, fallback)
EndFunction

Function Notify(String msgKey, Bool quiet)
	If !quiet
		Debug.Notification(msgKey)
	EndIf
EndFunction

; Called by the player alias's timer when automatic serving is on: starts one more pair if the
; MCM's limit allows. Players are never served automatically; only workers are.
Function AutoServe()
	If !brothelCell || Utility.IsInMenuMode() || Game.GetPlayer().GetParentCell() != brothelCell
		Return
	EndIf
	If WorkerDealCount() < MaxConcurrent()
		ServeCustomer(True)
	EndIf
EndFunction

Bool Function AutoServeEnabled()
	Return GetModSettingBool("bAutoServe:General")
EndFunction

Float Function AutoServeInterval()
	Int seconds = GetModSettingInt("iAutoInterval:General")
	If seconds < 10
		seconds = 10
	EndIf
	Return seconds as Float
EndFunction

; ---------------------------------------------------------------------------------------------
; Keeping the peace
; ---------------------------------------------------------------------------------------------

Bool Function HasBrothel()
	Return brothelCell != None
EndFunction

Bool Function PlayerInBrothel()
	Return brothelCell && Game.GetPlayer().GetParentCell() == brothelCell
EndFunction

; Customers do not fight in the brothel. A stray hit (a customer walking into a scene's place, a
; misplaced swing) set the player's followers on one and left him hostile to the player for good.
; Run every few seconds while the player is in the brothel (player alias): any customer there who
; is fighting, or hostile to the player, is calmed down, and so is everyone fighting him. His deal
; is left alone.
Function KeepPeace()
	If !PlayerInBrothel()
		Return
	EndIf
	Actor player = Game.GetPlayer()
	Int i = 0
	While i < customers.Length + MaxVisitors + DealSlots
		Actor candidate = None
		If i < customers.Length
			candidate = customers[i]
		ElseIf i < customers.Length + MaxVisitors
			candidate = visitors[i - customers.Length]
		Else
			candidate = dealCustomers[i - customers.Length - MaxVisitors]
		EndIf
		If candidate && candidate != player && !candidate.IsDead() && candidate.GetParentCell() == brothelCell \
				&& (candidate.IsInCombat() || candidate.IsHostileToActor(player))
			MakePeace(candidate)
		EndIf
		i += 1
	EndWhile
EndFunction

; Stops the customer's fight and his hostility, and the fight of everyone in the brothel who has
; him as their target (the player, workers, the owner, followers).
Function MakePeace(Actor customer)
	Actor player = Game.GetPlayer()
	customer.StopCombat()
	customer.StopCombatAlarm()
	Actor[] nearby = MiscUtil.ScanCellNPCs(customer, 0.0, None, True)
	Int i = 0
	While i < nearby.Length
		If nearby[i] && nearby[i] != customer && nearby[i].GetCombatTarget() == customer
			nearby[i].StopCombat()
		EndIf
		i += 1
	EndWhile
	If player.GetCombatTarget() == customer
		player.StopCombat()
	EndIf
	player.StopCombatAlarm()
	customer.EvaluatePackage()
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Peace: " + customer.GetDisplayName() + " stopped fighting (still hostile to the player: " + customer.IsHostileToActor(player) + ")")
	EndIf
EndFunction

; Sends the customer to the worker with a travel package, giving him at most 20 seconds before he
; is moved next to her. PathToReference is not used: it never returns for a customer who cannot
; path, for example one sitting in a chair. The package stays on until the deal is done (see
; KeepClose) and the worker, unless it is the player, stands still meanwhile, so the two talk face
; to face instead of wandering off.
; Also the other way round: ApproachWorker(worker, customer) sends a soliciting worker to the
; customer, who then stands still.
Function ApproachWorker(Actor customer, Actor worker)
	If worker != Game.GetPlayer()
		worker.SetDontMove(True)
	EndIf
	PO3_SKSEFunctions.SetLinkedRef(customer, worker, TalkLink())
	ActorUtil.AddPackageOverride(customer, TravelPackage(), 100)
	customer.EvaluatePackage()
	; A walker caught on a door frame or furniture never arrives: once he has stopped getting closer
	; for ApproachStuckSeconds (or ApproachTimeoutSeconds have passed), he is placed in front of the
	; other one.
	Float waited = 0.0
	Float stuckFor = 0.0
	Float closest = customer.GetDistance(worker)
	While waited < ApproachTimeoutSeconds && stuckFor < ApproachStuckSeconds && customer.GetDistance(worker) > TalkDistance
		Utility.Wait(0.5)
		waited += 0.5
		Float distance = customer.GetDistance(worker)
		If distance < closest - 20.0
			closest = distance
			stuckFor = 0.0
		Else
			stuckFor += 0.5
		EndIf
	EndWhile
	If customer.GetDistance(worker) > TalkDistance + 50.0
		Float angle = worker.GetAngleZ()
		customer.MoveTo(worker, 90.0 * Math.Sin(angle), 90.0 * Math.Cos(angle), 0.0)
	EndIf
EndFunction

; While the pair talks: sends the customer back to the worker if they have drifted apart (the
; player may walk about).
Function KeepClose(Int slot)
	If slot < 0
		Return
	EndIf
	Actor customer = dealCustomers[slot]
	Actor worker = dealWorkers[slot]
	If customer && worker && customer.GetDistance(worker) > TalkDistance + 50.0
		; Whichever of the two walked over (the customer, or a soliciting worker) goes back.
		customer.EvaluatePackage()
		If worker != Game.GetPlayer()
			worker.EvaluatePackage()
		EndIf
	EndIf
EndFunction

; Lets the pair move freely again. Either may have walked over (ApproachWorker either way round), so
; both lose the travel package and both may move again.
Function ReleaseHold(Int slot)
	Actor player = Game.GetPlayer()
	Actor[] pair = new Actor[2]
	pair[0] = dealCustomers[slot]
	pair[1] = dealWorkers[slot]
	Int i = 0
	While i < 2
		Actor one = pair[i]
		If one && one != player
			ActorUtil.RemovePackageOverride(one, TravelPackage())
			PO3_SKSEFunctions.SetLinkedRef(one, None, TalkLink())
			one.SetDontMove(False)
			one.EvaluatePackage()
		EndIf
		i += 1
	EndWhile
EndFunction

Package Function TravelPackage()
	Return Game.GetFormFromFile(0x0235E0, "Skyrim.esm") as Package ; defaultTravelToLinkCustom01
EndFunction

Keyword Function TalkLink()
	Return Game.GetFormFromFile(0x05D5E6, "Skyrim.esm") as Keyword   ; LinkCustom01
EndFunction

; Offers are talked through one pair at a time: the end of a conversation is judged from
; SkyrimNet's speech queue, which every pair shares, so two pairs talking at once would each take
; the other's silence for their own and start their scene before their own exchange. Scenes still
; run side by side. Waits for the turn; false if the deal was cleared meanwhile. A turn held for
; over TalkTurnTimeoutSeconds is taken over.
Bool Function AcquireTalk(Int slot, Int serial)
	While DealAlive(slot, serial)
		; The time is read first: a call to another script lets other threads in, and one coming in
		; between "talking = True" and its time took the turn as held too long and talked over it.
		Float now = Utility.GetCurrentRealTime()
		If !talking || now - talkingSince > TalkTurnTimeoutSeconds
			talking = True
			talkingSince = now
			Return True
		EndIf
		KeepClose(slot)
		Utility.Wait(0.5)
	EndWhile
	Return False
EndFunction

Function ReleaseTalk()
	talking = False
EndFunction

; Returns once a line has played since the offer (startedAt, real time) and nothing more is queued
; or playing for two seconds; gives up 45 seconds after the offer. A silent queue on its own is not
; enough: right after the offer the LLM is still writing the line and nothing is queued yet. The
; queue is SkyrimNet's, shared by every pair, so a busy brothel waits for the others' lines too.
Function WaitForSpeech(Float startedAt, Int slot)
	While Utility.GetCurrentRealTime() - startedAt < 45.0
		Int silentMs = SkyrimNetApi.GetTimeSinceLastAudioEnded()
		Float sinceOfferMs = (Utility.GetCurrentRealTime() - startedAt) * 1000.0
		If silentMs > 0 && silentMs < sinceOfferMs && silentMs >= 2000 && SkyrimNetApi.GetSpeechQueueSize() == 0
			Return
		EndIf
		KeepClose(slot)
		Utility.Wait(0.5)
	EndWhile
EndFunction

; A free worker in the brothel, at random; withPlayer: the player too, when the player works.
; minLevel: only workers of at least this level (the low ones do not invite customers).
; Debug log: why each registered worker was passed over when none was free.
Function LogWorkersNotFree(SexLabFramework sexLab)
	DebugLog("No free worker (" + workerCount + " registered, " + WorkerDealCount() + " deals open):")
	Int i = 0
	While i < workerCount
		Actor worker = workers[i]
		String why = "free?"
		If !worker
			why = "empty place"
		ElseIf worker.IsDead()
			why = "dead"
		ElseIf worker.GetParentCell() != brothelCell
			why = "not in the brothel"
		Else
			Int slot = 0
			While slot < DealSlots && why == "free?"
				If dealStates[slot] != DealFree && (dealWorkers[slot] == worker || dealCustomers[slot] == worker)
					why = "in deal " + slot + " (state " + dealStates[slot] + ", " \
						+ ((Utility.GetCurrentRealTime() - dealStarted[slot]) as Int) + " s)"
				EndIf
				slot += 1
			EndWhile
			If why == "free?" && sexLab.IsActorActive(worker)
				why = "in a SexLab scene"
			EndIf
		EndIf
		String name = "None"
		If worker
			name = worker.GetDisplayName()
		EndIf
		DebugLog("  " + name + ": " + why)
		i += 1
	EndWhile
EndFunction

Actor Function PickWorker(SexLabFramework sexLab, Bool withPlayer = False, Int minLevel = 0)
	Actor[] present = new Actor[65]
	Int count = 0
	Int last = workerCount - 1
	If withPlayer
		last = workerCount
	EndIf
	Int i = 0
	While i <= last
		Actor candidate = StaffAt(i)
		If candidate && !candidate.IsDead() && candidate.GetParentCell() == brothelCell \
				&& !IsInDeal(candidate) && !sexLab.IsActorActive(candidate) && (minLevel <= 1 || WorkerLevel(candidate) >= minLevel)
			present[count] = candidate
			count += 1
		EndIf
		i += 1
	EndWhile
	If count == 0
		Return None
	EndIf
	Return present[Utility.RandomInt(0, count - 1)]
EndFunction

; The free customer nearest to this worker: one of the brothel's own customers, or, with "Local
; customers" on, any other adult NPC in the brothel who is not a registered worker.
Actor Function PickCustomer(SexLabFramework sexLab, Actor worker)
	Actor[] present = new Actor[128]
	Int count = 0
	Int i = 0
	While i < customers.Length
		If IsFreeCustomer(sexLab, customers[i], worker)
			present[count] = customers[i]
			count += 1
		EndIf
		i += 1
	EndWhile
	; Townsfolk who came to the brothel are customers whether or not "Local customers" is on.
	i = 0
	While i < MaxVisitors
		If visitors[i] && visitorStates[i] == VisitorInside && IsFreeCustomer(sexLab, visitors[i], worker)
			present[count] = visitors[i]
			count += 1
		EndIf
		i += 1
	EndWhile
	If GetModSettingBool("bLocalCustomers:General")
		Actor player = Game.GetPlayer()
		Actor[] nearby = MiscUtil.ScanCellNPCs(player, 0.0, None, True)
		i = 0
		While i < nearby.Length && count < present.Length
			Actor candidate = nearby[i]
			If candidate != player && customers.Find(candidate) < 0 && workers.Find(candidate) < 0 && visitors.Find(candidate) < 0 \
					&& !candidate.IsChild() && IsPerson(candidate) && !candidate.IsHostileToActor(player) \
					&& IsFreeCustomer(sexLab, candidate, worker)
				present[count] = candidate
				count += 1
			EndIf
			i += 1
		EndWhile
	EndIf
	Actor nearest = None
	Float nearestDistance = 0.0
	i = 0
	While i < count
		Float distance = present[i].GetDistance(worker)
		If !nearest || distance < nearestDistance
			nearest = present[i]
			nearestDistance = distance
		EndIf
		i += 1
	EndWhile
	Return nearest
EndFunction

; With "Allow same-sex" off (MCM), a customer must be of the other sex from the worker (or player).
Bool Function IsFreeCustomer(SexLabFramework sexLab, Actor candidate, Actor worker)
	; The cell scan also returns NPCs placed there but disabled, or not loaded, until some quest needs
	; them; SexLab cannot use them.
	; A registered worker is never a customer, even one who was in the town's pool before she was
	; registered.
	If !candidate || candidate == worker || candidate == brothelOwner || workers.Find(candidate) >= 0 \
			|| candidate.IsDisabled() || !candidate.Is3DLoaded() \
			|| candidate.IsDead() || candidate.IsInCombat() \
			|| candidate.GetParentCell() != brothelCell || IsInDeal(candidate) || sexLab.IsActorActive(candidate)
		Return False
	EndIf
	If !GetModSettingBool("bAllowSameSex:General") \
			&& candidate.GetLeveledActorBase().GetSex() == worker.GetLeveledActorBase().GetSex()
		Return False
	EndIf
	Return True
EndFunction

; The customer pays the moment the offer is accepted, and SkyrimNet is told so: paid only after the
; scene, the worker went on to say she had not been paid while the customer said he had, and later
; pairs copied the quarrel from SkyrimNet's history. The owner (MCM) takes their share; a worker
; who owns the brothel keeps it all. Once per deal.
Function PayForDeal(Int slot)
	If dealPaid[slot]
		Return
	EndIf
	dealPaid[slot] = True
	Actor worker = dealWorkers[slot]
	Actor customer = dealCustomers[slot]
	Int payment = GetModSettingInt("iPayment:General")
	If payment <= 0 || !worker || !customer
		Return
	EndIf
	Int ownerCut = 0
	If brothelOwner && brothelOwner != worker && !brothelOwner.IsDead()
		ownerCut = payment * GetModSettingInt("iOwnerShare:General") / 100
	EndIf
	Form gold = Game.GetFormFromFile(0x00000F, "Skyrim.esm")
	If payment - ownerCut > 0
		worker.AddItem(gold, payment - ownerCut, True)
	EndIf
	dealPaidWorker[slot] = payment - ownerCut
	AddEarnings(worker, payment)
	SkyrimNetApi.RegisterPersistentEvent(customer.GetDisplayName() + " handed " + worker.GetDisplayName() + " " + payment \
		+ " gold for the night, up front, the moment the offer was accepted. The night is paid for in full.", customer, worker)
	If ownerCut > 0
		brothelOwner.AddItem(gold, ownerCut, True)
		dealPaidOwner[slot] = ownerCut
		StorageUtil.AdjustIntValue(brothelOwner, "SNB_HouseTake", ownerCut)
		SkyrimNetApi.RegisterPersistentEvent(brothelOwner.GetDisplayName() + ", who runs the brothel, took " + ownerCut \
			+ " gold of it as the house's share.", brothelOwner, worker)
		If brothelOwner == Game.GetPlayer()
			Debug.Notification(Phrase("ownerCutBefore", "The house's share: ") + ownerCut + Phrase("ownerCutAfter", " gold."))
		EndIf
	EndIf
	Debug.Notification("$SNB_Paid")
EndFunction

; The deal fell through before its scene: the worker and the owner give the gold back.
Function RefundDeal(Int slot)
	Actor worker = dealWorkers[slot]
	Actor customer = dealCustomers[slot]
	Form gold = Game.GetFormFromFile(0x00000F, "Skyrim.esm")
	If worker && dealPaidWorker[slot] > 0
		worker.RemoveItem(gold, dealPaidWorker[slot], True)
	EndIf
	AddEarnings(worker, -(dealPaidWorker[slot] + dealPaidOwner[slot]))
	If brothelOwner && dealPaidOwner[slot] > 0
		brothelOwner.RemoveItem(gold, dealPaidOwner[slot], True)
		StorageUtil.AdjustIntValue(brothelOwner, "SNB_HouseTake", -dealPaidOwner[slot])
	EndIf
	If worker && customer && dealPaidWorker[slot] + dealPaidOwner[slot] > 0
		SkyrimNetApi.RegisterPersistentEvent("The night between " + worker.GetDisplayName() + " and " + customer.GetDisplayName() \
			+ " fell through, so " + customer.GetDisplayName() + " got the gold back.", worker, customer)
	EndIf
EndFunction

; ---------------------------------------------------------------------------------------------
; Levels
; ---------------------------------------------------------------------------------------------

; The brothel and each worker have a level from 1 to MaxLevel, from the gold customers have paid:
; all the workers' together for the brothel, her own for a worker, one level per the MCM's gold
; step. A worker's level sets how she feels about the work, from loathing it to loving it, and
; that goes into what the LLM is told about her (WorkerAttitude); she invites customers herself
; only from SolicitMinLevel. The brothel's level is its reputation (BrothelReputation).

Int Property MaxLevel = 10 AutoReadOnly
Int Property SolicitMinLevel = 5 AutoReadOnly

; Gold customers have paid at this brothel in all (before the owner's share).
Int brothelGross

Int Function BrothelLevelStep()
	Int step = GetModSettingInt("iBrothelLevelGold:General")
	If step < 1
		step = 1
	EndIf
	Return step
EndFunction

Int Function WorkerLevelStep()
	Int step = GetModSettingInt("iWorkerLevelGold:General")
	If step < 1
		step = 1
	EndIf
	Return step
EndFunction

Int Function LevelFor(Int gold, Int step)
	Int level = 1 + gold / step
	If level > MaxLevel
		Return MaxLevel
	EndIf
	Return level
EndFunction

; Gold still needed for the next level; 0 at the top.
Int Function GoldToNext(Int gold, Int step)
	Int level = LevelFor(gold, step)
	If level >= MaxLevel
		Return 0
	EndIf
	Return step * level - gold
EndFunction

; What customers have paid this worker in all. Saves from before levels kept only what she kept
; after the owner's share (SNB_Earned), which stands in once.
Int Function WorkerGross(Actor worker)
	Int gross = StorageUtil.GetIntValue(worker, "SNB_Gross", -1)
	If gross < 0
		gross = StorageUtil.GetIntValue(worker, "SNB_Earned", 0)
		StorageUtil.SetIntValue(worker, "SNB_Gross", gross)
	EndIf
	Return gross
EndFunction

Int Function WorkerLevel(Actor worker)
	Return LevelFor(WorkerGross(worker), WorkerLevelStep())
EndFunction

Int Function BrothelLevel()
	Return LevelFor(brothelGross, BrothelLevelStep())
EndFunction

; Saves from before levels: the brothel's total starts from what its workers have been paid.
Function SyncBrothelGross()
	; Once only: a new brothel (there can be several now) starts from nothing.
	If brothelGrossSynced
		Return
	EndIf
	brothelGrossSynced = True
	If brothelGross > 0
		Return
	EndIf
	Int i = 0
	While i <= workerCount
		Actor worker = StaffAt(i)
		If worker
			brothelGross += WorkerGross(worker)
		EndIf
		i += 1
	EndWhile
EndFunction

; A payment (or, negative, a refund) to this worker: adds to her total and the brothel's, and
; announces any level gained.
Function AddEarnings(Actor worker, Int amount)
	If !worker || amount == 0
		Return
	EndIf
	Int oldWorker = WorkerLevel(worker)
	Int oldBrothel = BrothelLevel()
	Int gross = WorkerGross(worker) + amount
	If gross < 0
		gross = 0
	EndIf
	StorageUtil.SetIntValue(worker, "SNB_Gross", gross)
	brothelGross += amount
	If brothelGross < 0
		brothelGross = 0
	EndIf
	Int newWorker = WorkerLevel(worker)
	If newWorker > oldWorker
		Debug.Notification(Phrase("workerLevelBefore", "") + worker.GetDisplayName() + Phrase("workerLevelMid", " is now level ") \
			+ newWorker + Phrase("workerLevelAfter", " as a worker."))
		If worker != Game.GetPlayer()
			SkyrimNetApi.RegisterPersistentEvent(worker.GetDisplayName() + " has grown into her work at the brothel: she " \
				+ WorkerAttitude(newWorker) + ".", worker, None)
		EndIf
	EndIf
	If BrothelLevel() > oldBrothel
		Debug.Notification(Phrase("brothelLevelBefore", "The brothel is now level ") + BrothelLevel() + Phrase("brothelLevelAfter", "."))
		SkyrimNetApi.RegisterPersistentEvent("Word of the brothel has spread: it is now " + BrothelReputation(BrothelLevel()) + ".", Game.GetPlayer(), None)
	EndIf
EndFunction

; How a worker of this level feels about the work, said of her ("she ..."): a gradation from
; loathing it at 1 to loving it at 10.
String Function WorkerAttitude(Int level)
	If level <= 1
		Return "hates this work and does it only because she has no other choice; she is ashamed, stiff and close to tears with every customer"
	ElseIf level == 2
		Return "is deeply unwilling; she goes through with it grudgingly, avoiding the customer's eyes"
	ElseIf level == 3
		Return "is still reluctant and embarrassed, though she no longer fights it"
	ElseIf level == 4
		Return "is resigned to the work; she is cold and businesslike and keeps her distance"
	ElseIf level == 5
		Return "has got used to the work; she is matter-of-fact about it, neither eager nor unwilling"
	ElseIf level == 6
		Return "has come to terms with the work and is starting to take some pride in pleasing customers"
	ElseIf level == 7
		Return "is comfortable with the work; she is friendly and confident with customers"
	ElseIf level == 8
		Return "enjoys the work and the attention; she is warm and flirtatious"
	ElseIf level == 9
		Return "is proud to be one of the brothel's best; she is eager and seductive"
	EndIf
	Return "loves this work and is the brothel's star; she welcomes every customer with open enthusiasm"
EndFunction

; How she agrees when she always accepts.
String Function AcceptManner(Int level)
	If level <= 2
		Return "reluctantly, because she has no choice"
	ElseIf level <= 4
		Return "without enthusiasm"
	ElseIf level <= 6
		Return "matter-of-factly"
	ElseIf level <= 8
		Return "warmly"
	EndIf
	Return "eagerly"
EndFunction

; What the brothel is, by its level.
String Function BrothelReputation(Int level)
	If level <= 1
		Return "a shabby back-room operation few have heard of"
	ElseIf level == 2
		Return "a small, little-known house"
	ElseIf level == 3
		Return "a modest house a few locals whisper about"
	ElseIf level == 4
		Return "a house with a growing number of regulars"
	ElseIf level == 5
		Return "a respectable house known around town"
	ElseIf level == 6
		Return "a popular house that draws customers from nearby towns"
	ElseIf level == 7
		Return "a well-regarded house known for fine company"
	ElseIf level == 8
		Return "a renowned house talked about across the hold"
	ElseIf level == 9
		Return "one of the most famous houses in Skyrim"
	EndIf
	Return "the most celebrated house of pleasure in all of Skyrim"
EndFunction

; The MCM's level lines: the brothel, the worker picked in the worker list, and the player.
Function ShowLevels()
	SetModSettingString("sBrothelLevel:General", BrothelLevel() as String)
	SetModSettingString("sBrothelNext:General", NextText(GoldToNext(brothelGross, BrothelLevelStep())))
	Actor picked = PickedWorker()
	If picked
		SetModSettingString("sPickedLevel:General", WorkerLevel(picked) as String)
		SetModSettingString("sPickedNext:General", NextText(GoldToNext(WorkerGross(picked), WorkerLevelStep())))
	Else
		SetModSettingString("sPickedLevel:General", "-")
		SetModSettingString("sPickedNext:General", "-")
	EndIf
	Actor player = Game.GetPlayer()
	SetModSettingString("sPlayerLevel:General", WorkerLevel(player) as String)
	SetModSettingString("sPlayerNext:General", NextText(GoldToNext(WorkerGross(player), WorkerLevelStep())))
EndFunction

String Function NextText(Int gold)
	If gold <= 0
		Return "MAX"
	EndIf
	Return gold as String
EndFunction

; The worker picked in the MCM's worker list, or None.
Actor Function PickedWorker()
	If !workerMenuNames
		Return None
	EndIf
	Int index = workerMenuNames.Find(GetModSettingString("sWorkerPick:General"))
	If index >= 0 && index < workerCount
		Return workers[index]
	EndIf
	Return None
EndFunction

; Debug (MCM): set a level outright; the totals move to that level's start.
Function DebugSetBrothelLevel()
	brothelGross = (DebugLevel("iDebugBrothelLevel:General") - 1) * BrothelLevelStep()
	ShowLevels()
	RefreshMenu()
EndFunction

Function DebugSetWorkerLevel()
	DebugSetLevelOf(PickedWorker())
EndFunction

Function DebugSetPlayerLevel()
	DebugSetLevelOf(Game.GetPlayer())
EndFunction

Function DebugSetLevelOf(Actor worker)
	If !worker
		Debug.Notification("$SNB_NoTarget")
		Return
	EndIf
	Int level = DebugLevel("iDebugWorkerLevel:General")
	StorageUtil.SetIntValue(worker, "SNB_Gross", (level - 1) * WorkerLevelStep())
	If worker != Game.GetPlayer()
		SkyrimNetApi.RegisterPersistentEvent(worker.GetDisplayName() + " now feels this way about her work at the brothel: she " \
			+ WorkerAttitude(level) + ".", worker, None)
	EndIf
	ShowLevels()
	RefreshMenu()
EndFunction

Int Function DebugLevel(String setting)
	Int level = GetModSettingInt(setting)
	If level < 1
		Return 1
	ElseIf level > MaxLevel
		Return MaxLevel
	EndIf
	Return level
EndFunction

; ---------------------------------------------------------------------------------------------
; Workers inviting customers
; ---------------------------------------------------------------------------------------------

; With "Workers invite customers" on (MCM), every so often a free NPC worker walks up to a free
; customer and offers her company; the customer answers in conversation (AcceptWorkerOffer /
; DeclineWorkerOffer), and one who gives no clear answer in time takes the offer: he came to buy.
; A player who works invites customers through the conversation topic instead (PlayerSolicits).

Int Property PlayerSolicitTalkID = 0x809 AutoReadOnly
Int Property SolicitTopicID = 0x80B AutoReadOnly
String Property ChoicesTagSolicit = "SNB_Solicit" AutoReadOnly
; Real time (this session) of the next invitation; set again on every load.
Float solicitNextAt

Float Function SolicitIntervalSeconds()
	Int seconds = GetModSettingInt("iSolicitInterval:General")
	If seconds < 10
		seconds = 10
	EndIf
	Return seconds as Float
EndFunction

Bool Function SolicitDue()
	If !GetModSettingBool("bWorkerSolicit:General") || Utility.GetCurrentRealTime() < solicitNextAt
		Return False
	EndIf
	solicitNextAt = Utility.GetCurrentRealTime() + SolicitIntervalSeconds()
	Return True
EndFunction

Function WorkerSolicitRound()
	If !brothelCell || Game.GetPlayer().GetParentCell() != brothelCell || Utility.IsInMenuMode() \
			|| WorkerDealCount() >= MaxConcurrent()
		Return
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Actor worker = PickWorker(sexLab, False, SolicitMinLevel)
	If !worker
		Return
	EndIf
	Actor customer = PickCustomer(sexLab, worker)
	If customer
		WorkerSolicits(sexLab, worker, customer)
	EndIf
EndFunction

Function WorkerSolicits(SexLabFramework sexLab, Actor worker, Actor customer)
	Int slot = ReserveDeal(worker, customer)
	If slot < 0
		Return
	EndIf
	Int serial = dealSerials[slot]
	dealSolicited[slot] = True
	MarkCustomerSpot(slot)
	AnnounceApproach(worker, customer)
	ApproachWorker(worker, customer)
	If !AcquireTalk(slot, serial)
		Return
	EndIf
	dealStates[slot] = DealPending
	Float offeredAt = Utility.GetCurrentRealTime()
	; Left to the LLM, the customer turned nearly every invitation down. The answer is rolled
	; against the MCM's chance instead; the narration tells him which it is, and his answer in
	; conversation (AcceptWorkerOffer / DeclineWorkerOffer) no longer decides it.
	Bool willAccept = Utility.RandomInt(1, 100) <= GetModSettingInt("iSolicitAccept:General")
	SkyrimNetApi.DirectNarration(SolicitNarration(worker, customer, willAccept), worker, customer)
	Float waited = 0.0
	While DealAlive(slot, serial) && dealStates[slot] == DealPending && waited < DealTimeoutSeconds && !AnswerSpoken(slot)
		KeepClose(slot)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	If !DealAlive(slot, serial)
		ReleaseTalk()
		Return
	EndIf
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Invitation: " + worker.GetDisplayName() + " to " + customer.GetDisplayName() + ", rolled " + willAccept \
			+ ", answer " + dealStates[slot])
	EndIf
	If !willAccept
		Debug.Notification("$SNB_CustomerDeclined")
		ReleaseTalk()
		ReleaseDeal(slot)
		Return
	EndIf
	dealStates[slot] = DealAccepted
	PayForDeal(slot)
	WaitForSpeech(offeredAt, slot)
	ReleaseTalk()
	Utility.Wait(1.5)
	If DealAlive(slot, serial)
		StartBrothelScene(sexLab, slot)
	EndIf
EndFunction

; Tells the worker to make her offer now, in her own words; nothing is paid before he agrees.
; The customer's answer to an invitation, rolled beforehand, as the LLM is told it.
String Function SolicitAnswer(Actor customer, Bool willAccept)
	String c = customer.GetDisplayName()
	If willAccept
		Return " " + c + " came to the brothel tonight for exactly this, likes what " + HeOf(customer) + " sees, and is going to say yes."
	EndIf
	Return " " + c + " is not in the mood tonight and is going to turn the offer down politely."
EndFunction

String Function SolicitNarration(Actor worker, Actor customer, Bool willAccept)
	String w = worker.GetDisplayName()
	String c = customer.GetDisplayName()
	Int payment = GetModSettingInt("iPayment:General")
	String answer = SolicitAnswer(customer, willAccept)
	Return w + " sells her company for gold at this brothel; " + c + " is here as a customer and has not been with anyone yet. " \
		+ w + " has walked up to " + c + " and now, in her own words, offers " + HimOf(customer) + " her company tonight for " + payment \
		+ " gold, then waits for " + HisOf(customer) + " answer. Nothing has been paid yet: " + c + " pays the moment " + HeOf(customer) + " agrees." \
		+ answer + ApproachStyle(w, "worker") + " (In a way that fits how she feels about the work.)" + LevelContext(worker)
EndFunction

; The player's topic, as a worker: the player offers this person their company.
Function SolicitTopicChosen(Actor customer)
	pendingRecommend = customer
	pendingAction = "solicit"
	RegisterForSingleUpdate(0.5)
EndFunction

; The player, working as one of the girls, offers this person their company. Through SkyrimNet Player
; Choices the player picks how to put it; the person answers, taking or declining the offer
; (AcceptWorkerOffer / DeclineWorkerOffer; no clear answer counts as taking it), then asks which
; position the player would like, and the scene starts.
Function PlayerSolicits(Actor customer)
	Actor player = Game.GetPlayer()
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	If !PlayerWorks() || !brothelCell || player.GetParentCell() != brothelCell
		Debug.Notification("$SNB_NotInBrothel")
		Return
	EndIf
	If IsInDeal(player) || sexLab.IsActorActive(player)
		Debug.Notification("$SNB_PlayerBusy")
		Return
	EndIf
	If !IsFreeCustomer(sexLab, customer, player)
		Debug.Notification("$SNB_NoCustomer")
		Return
	EndIf
	Int slot = ReserveDeal(player, customer)
	If slot < 0
		Debug.Notification("$SNB_PlayerBusy")
		Return
	EndIf
	Int serial = dealSerials[slot]
	dealSolicited[slot] = True
	MarkCustomerSpot(slot)
	If !AcquireTalk(slot, serial)
		Return
	EndIf
	dealStates[slot] = DealPending
	Int payment = GetModSettingInt("iPayment:General")
	String p = player.GetDisplayName()
	String c = customer.GetDisplayName()
	; As with the workers' invitations, the answer is rolled against the MCM's chance and the
	; customer is told which it is (see WorkerSolicits).
	Bool willAccept = Utility.RandomInt(1, 100) <= GetModSettingInt("iSolicitAccept:General")
	Int picked = 0
	If ChoicesReady()
		String[] intents = new String[3]
		; Two different ways from the worker list in approaches.json, so the replies differ each time.
		Int styles = JsonUtil.StringListCount(ApproachesFile, "worker")
		If styles >= 2
			Int first = Utility.RandomInt(0, styles - 1)
			Int second = (first + Utility.RandomInt(1, styles - 1)) % styles
			intents[0] = "offer " + c + " your company tonight for " + payment + " gold; you " + JsonUtil.StringListGet(ApproachesFile, "worker", first)
			intents[1] = "offer " + c + " your company tonight for " + payment + " gold; you " + JsonUtil.StringListGet(ApproachesFile, "worker", second)
		Else
			intents[0] = "offer " + c + " your company tonight for " + payment + " gold, warmly"
			intents[1] = "offer " + c + " your company tonight for " + payment + " gold, teasingly"
		EndIf
		intents[2] = "say it was nothing after all"
		picked = AskPlayer(customer, p + " offers " + c + " a night together for gold", \
			p + " works at this brothel, selling their company for gold. " + c + " is here as a customer. " + p + " walks up to " + c \
			+ " to offer a night together for " + payment + " gold. Nothing has been paid yet: " + c + " pays the moment " + HeOf(customer) + " agrees.", \
			intents, ChoicesTagSolicit, slot, True, True, SolicitAnswer(customer, willAccept))
	EndIf
	If !DealAlive(slot, serial)
		ReleaseTalk()
		Return
	EndIf
	If picked < 0 || picked > 1
		ReleaseTalk()
		ReleaseDeal(slot)
		Return
	EndIf
	; Player Choices has the customer answer the player's line, told the rolled answer with it
	; (AskPlayer's answerNote): left to himself he turned nearly every offer down, and a second
	; answer of the brothel's own came after SkyrimNet's, contradicting it. His answer may still be
	; on its way.
	Float waited = 0.0
	While DealAlive(slot, serial) && waited < 10.0 && !AnswerSpoken(slot)
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	If !DealAlive(slot, serial)
		ReleaseTalk()
		Return
	EndIf
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Invitation: " + p + " to " + c + ", rolled " + willAccept + ", answer " + dealStates[slot])
	EndIf
	If !willAccept
		Debug.Notification("$SNB_CustomerDeclined")
		ReleaseTalk()
		ReleaseDeal(slot)
		Return
	EndIf
	dealStates[slot] = DealAccepted
	PayForDeal(slot)
	String positionTag = AskPosition(sexLab, slot, False, False)
	ReleaseTalk()
	If positionTag == "-"
		ReleaseDeal(slot)
		Return
	EndIf
	Utility.Wait(1.0)
	If DealAlive(slot, serial)
		StartBrothelScene(sexLab, slot, positionTag)
	EndIf
EndFunction

; The scene ended: the pair's deal is done (it was paid when accepted).
Event OnBrothelSceneEnd(Int aiThreadID, Bool abHasPlayer)
	Int slot = -1
	Int i = 0
	While i < DealSlots && slot < 0
		If dealStates[i] == DealInScene && dealThreads[i] == aiThreadID
			slot = i
		EndIf
		i += 1
	EndWhile
	If slot < 0
		Return
	EndIf
	Actor worker = dealWorkers[slot]
	Int kept = dealPaidWorker[slot]
	StepOffBed(slot)
	ReleaseDeal(slot)
	RecordSale(worker, kept)
EndEvent

; SexLab leaves the pair standing where the scene was: on the bed, in the way of the next pair put
; on it. Once SexLab has let them go, an NPC still on the bed is moved off it, to where the customer
; stood before walking over (dealSpots). The bed stays the pair's until then.
Float Property OnBedDistance = 120.0 AutoReadOnly

Function StepOffBed(Int slot)
	ObjectReference bed = dealBeds[slot]
	If !bed || !dealSpots[slot]
		Return
	EndIf
	Utility.Wait(1.5)
	Actor player = Game.GetPlayer()
	Actor[] pair = new Actor[2]
	pair[0] = dealCustomers[slot]
	pair[1] = dealWorkers[slot]
	Int i = 0
	While i < 2
		Actor one = pair[i]
		If one && one != player && !one.IsDead() && one.GetDistance(bed) <= OnBedDistance
			one.MoveTo(dealSpots[slot], 60.0 * i, 0.0, 0.0)
		EndIf
		i += 1
	EndWhile
EndFunction

; Whether someone other than this pair stands on the bed (a pair SexLab let go of, someone passing).
Bool Function BedOccupied(ObjectReference bed, Actor[] positions)
	Actor[] near = MiscUtil.ScanCellNPCs(bed, OnBedDistance * 0.6, None, True)
	Int i = 0
	While i < near.Length
		If near[i] && near[i] != positions[0] && near[i] != positions[1]
			Return True
		EndIf
		i += 1
	EndWhile
	Return False
EndFunction

; ---------------------------------------------------------------------------------------------
; Workers' small talk
; ---------------------------------------------------------------------------------------------

; With "Workers chat" on (MCM), every so often two free NPC workers standing near each other in
; the brothel gossip between customers about a topic from gossip.json (Data/SKSE/Plugins/
; skyrimnet_Brothel/gossip.json: "topics", each with its line in "examples"). Only while the player
; is in the brothel and no one else is talking (AcquireTalk's flag), so a deal's conversation is
; never talked over.

String Property GossipFile = "../skyrimnet_Brothel/gossip.json" AutoReadOnly
Float Property ChatDistance = 1024.0 AutoReadOnly
; Real time (this session) of the next chat; set again on every load.
Float chatNextAt
; The topic of the last chat, not picked twice in a row.
Int lastChatTopic = -1

Float Function ChatIntervalSeconds()
	Int seconds = GetModSettingInt("iChatInterval:General")
	If seconds < 30
		seconds = 30
	EndIf
	Return seconds as Float
EndFunction

Bool Function ChatDue()
	If !GetModSettingBool("bWorkerChat:General") || Utility.GetCurrentRealTime() < chatNextAt
		Return False
	EndIf
	chatNextAt = Utility.GetCurrentRealTime() + ChatIntervalSeconds()
	Return True
EndFunction

; Can this worker stop for a chat: an NPC worker (not the owner) in the brothel, free of deals,
; scenes and fights.
Bool Function FreeToChat(SexLabFramework sexLab, Actor worker)
	Return worker && worker != brothelOwner && !worker.IsDead() && worker.GetParentCell() == brothelCell \
		&& !IsInDeal(worker) && !sexLab.IsActorActive(worker) && !worker.IsInCombat()
EndFunction

Function WorkerChatRound()
	If !brothelCell || Game.GetPlayer().GetParentCell() != brothelCell || Utility.IsInMenuMode() \
			|| (talking && Utility.GetCurrentRealTime() - talkingSince <= TalkTurnTimeoutSeconds)
		Return
	EndIf
	Int topicCount = JsonUtil.StringListCount(GossipFile, "topics")
	If topicCount == 0
		Return
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	; A random free worker, then the free worker nearest her.
	Actor[] free = new Actor[64]
	Int count = 0
	Int i = 0
	While i < workerCount
		If FreeToChat(sexLab, workers[i])
			free[count] = workers[i]
			count += 1
		EndIf
		i += 1
	EndWhile
	If count < 2
		Return
	EndIf
	Actor speaker = free[Utility.RandomInt(0, count - 1)]
	Actor listener = None
	Float nearest = ChatDistance
	i = 0
	While i < count
		If free[i] != speaker && speaker.GetDistance(free[i]) <= nearest
			listener = free[i]
			nearest = speaker.GetDistance(free[i])
		EndIf
		i += 1
	EndWhile
	If !listener
		Return
	EndIf
	Int topicIndex = Utility.RandomInt(0, topicCount - 1)
	If topicIndex == lastChatTopic && topicCount > 1
		topicIndex = (topicIndex + 1) % topicCount
	EndIf
	lastChatTopic = topicIndex
	String s = speaker.GetDisplayName()
	String l = listener.GetDisplayName()
	String narration = s + " and " + l + " both work at this brothel. Between customers, " + s + " starts gossiping with " + l \
		+ " the way working girls talk among themselves: frank, wry, a little bitter at times. Topic: " \
		+ JsonUtil.StringListGet(GossipFile, "topics", topicIndex)
	String example = JsonUtil.StringListGet(GossipFile, "examples", topicIndex)
	If example != ""
		narration += " The kind of thing one of them might say: \"" + example + "\""
	EndIf
	narration += " " + s + " speaks a few lines and " + l + " answers in kind."
	; The turn is checked again here, with nothing in between that lets another thread in: one may
	; have taken it while the pair was being picked.
	Float startedAt = Utility.GetCurrentRealTime()
	If talking && startedAt - talkingSince <= TalkTurnTimeoutSeconds
		Return
	EndIf
	talking = True
	talkingSince = startedAt
	SkyrimNetApi.DirectNarration(narration, speaker, listener)
	WaitForSpeech(startedAt, -1)
	ReleaseTalk()
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Chat: " + s + " and " + l + ", topic " + topicIndex)
	EndIf
EndFunction
