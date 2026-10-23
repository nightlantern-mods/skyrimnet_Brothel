Scriptname skyrimnet_Brothel extends MCM_ConfigBase
{Brothel run by the player. A chosen interior cell is the brothel; registered workers serve the
customers there, several pairs at once if the MCM allows. Settings live in
MCM/Settings/skyrimnet_Brothel.ini.}

; Records of this plugin, looked up by FormID so the quest needs no property links.
Int Property CustomerBaseID = 0x801 AutoReadOnly
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
; Scenes looked at, and kept, when choosing scenes with one sex per position.
Int Property SceneChecks = 80 AutoReadOnly
Int Property SceneChoices = 10 AutoReadOnly

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
Int Property DealSlots = 6 AutoReadOnly
Int Property MaxConcurrentWorkers = 5 AutoReadOnly
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
	GrowCustomerSlots()
	ResetDeals()
	talking = False
	RegisterKeys()
	RegisterForModEvent("HookAnimationEnd_" + SceneHook, "OnBrothelSceneEnd")
	RegisterActions()
	; The count shown in the MCM lives in its settings file, not in the save: another save's count
	; would show after a load.
	DropMissingWorkers()
	ShowWorkerCount()
EndFunction

; SkyrimNet actions that let the worker answer the customer from the conversation itself.
Function RegisterActions()
	SkyrimNetApi.RegisterAction("AcceptCustomerOffer", \
		"Accept the paying customer's offer and take him to bed right now. Use this only when you have agreed to his offer in the conversation.", \
		"skyrimnet_Brothel", "Deal_IsEligible", "skyrimnet_Brothel", "AcceptCustomerOffer_Execute", \
		"", "PAPYRUS", 1, "")
	SkyrimNetApi.RegisterAction("RefuseCustomerOffer", \
		"Turn down the paying customer's offer. Use this only when you have refused him in the conversation.", \
		"skyrimnet_Brothel", "Refuse_IsEligible", "skyrimnet_Brothel", "RefuseCustomerOffer_Execute", \
		"", "PAPYRUS", 1, "")
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
	Else
		dealStates[slot] = DealRefused
	EndIf
EndFunction

Int Function PendingSlotOf(Actor akActor)
	Int i = 0
	While akActor && i < DealSlots
		If dealStates[i] == DealPending && dealWorkers[i] == akActor
			Return i
		EndIf
		i += 1
	EndWhile
	Return -1
EndFunction

Event OnSettingChange(String a_ID)
	If a_ID == "iServeKey:General" || a_ID == "iRegisterKey:General" || a_ID == "iPlayerServeKey:General"
		RegisterKeys()
	ElseIf a_ID == "iCustomerCount:General"
		pendingAction = "sync"
		RegisterForSingleUpdate(0.1)
	ElseIf a_ID == "bAutoServe:General" || a_ID == "iAutoInterval:General"
		(GetAlias(0) as skyrimnet_BrothelPlayer).ScheduleAutoServe()
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
	If keyCode == serveKey
		ServeCustomer(False)
	ElseIf keyCode == registerKey
		ToggleWorker(Game.GetCurrentCrosshairRef() as Actor)
	ElseIf keyCode == playerServeKey
		ServePlayer()
	EndIf
EndEvent

; ---------------------------------------------------------------------------------------------
; MCM buttons and the watchdog
; ---------------------------------------------------------------------------------------------

Function DesignateBrothel()
	pendingAction = "designate"
	RegisterForSingleUpdate(0.1)
EndFunction

Function ClearBrothel()
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
		DismissCustomers()
		brothelCell = None
		SetModSettingString("sBrothelName:General", "$SNB_None")
		Debug.Notification("$SNB_Cleared")
	ElseIf queued == "sync"
		SyncCustomers()
	EndIf
	ClearStalledDeals()
	If OpenDealCount() > 0
		RegisterForSingleUpdate(WatchdogSeconds)
	EndIf
EndEvent

; A queued MCM action already has a short update pending; the watchdog runs after it anyway.
Function ScheduleWatchdog()
	If pendingAction == ""
		RegisterForSingleUpdate(WatchdogSeconds)
	EndIf
EndFunction

Function DoDesignateBrothel()
	Actor player = Game.GetPlayer()
	Cell here = player.GetParentCell()
	If !here || !here.IsInterior()
		Debug.Notification("$SNB_NotInterior")
		Return
	EndIf
	DismissCustomers()
	brothelCell = here
	Int i = 0
	While i < TargetCustomerCount()
		customers[i] = SpawnCustomer(player)
		i += 1
	EndWhile
	SetModSettingString("sBrothelName:General", here.GetName())
	Debug.Notification("$SNB_Designated")
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

Actor Function SpawnCustomer(ObjectReference near)
	ActorBase customerBase = Game.GetFormFromFile(CustomerBaseID, PluginName) as ActorBase
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

; Brings the brothel to the MCM's customer count. New customers appear beside one already there
; (or beside the player in the brothel); extra ones leave, never one in a deal. Dead customers are
; cleared away and replaced.
Function SyncCustomers()
	If !brothelCell
		Return
	EndIf
	Actor anchor = None
	Int present = 0
	Int i = 0
	While i < customers.Length
		If customers[i] && customers[i].IsDead()
			customers[i].Disable()
			customers[i].Delete()
			customers[i] = None
		EndIf
		If customers[i]
			present += 1
			If !anchor
				anchor = customers[i]
			EndIf
		EndIf
		i += 1
	EndWhile
	If !anchor && Game.GetPlayer().GetParentCell() == brothelCell
		anchor = Game.GetPlayer()
	EndIf

	Int target = TargetCustomerCount()
	i = 0
	While present < target && anchor && i < customers.Length
		If !customers[i]
			customers[i] = SpawnCustomer(anchor)
			present += 1
		EndIf
		i += 1
	EndWhile
	i = customers.Length - 1
	While present > target && i >= 0
		If customers[i] && !IsInDeal(customers[i])
			customers[i].Disable()
			customers[i].Delete()
			customers[i] = None
			present -= 1
		EndIf
		i -= 1
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
; Workers
; ---------------------------------------------------------------------------------------------

Function ToggleWorker(Actor target)
	If !target
		Debug.Notification("$SNB_NoTarget")
		Return
	EndIf
	Int index = workers.Find(target)
	If index >= 0
		workers[index] = workers[workerCount - 1]
		workers[workerCount - 1] = None
		workerCount -= 1
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
	workers[workerCount] = target
	workerCount += 1
	ShowWorkerCount()
	Debug.Notification("$SNB_WorkerAdded")
EndFunction

; A humanoid NPC: has ActorTypeNPC, so creatures, animals and the like are left out.
Bool Function IsPerson(Actor akActor)
	Return akActor.HasKeyword(Game.GetFormFromFile(0x013794, "Skyrim.esm") as Keyword)
EndFunction

; The MCM's worker list: a menu control whose options are the registered workers, refilled each
; time the menu opens. A trailing " *" marks a worker who is in the brothel right now.
Event OnConfigOpen()
	RefreshWorkerMenu()
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
	SetMenuOptions("iWorkerPick:General", names, names)
	SetModSettingInt("iWorkerPick:General", 0)
	ShowWorkerCount()
EndFunction

Function ShowWorkerCount()
	SetModSettingString("sWorkerCount:General", workerCount as String)
EndFunction

; MCM button: unregisters the worker picked in the list.
Function UnregisterPickedWorker()
	Int index = GetModSettingInt("iWorkerPick:General")
	If index >= 0 && index < workerCount
		workers[index] = workers[workerCount - 1]
		workers[workerCount - 1] = None
		workerCount -= 1
		Debug.Notification("$SNB_WorkerRemoved")
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
	dealBeds = new ObjectReference[6]
	dealSpots = new ObjectReference[6]
	dealCenters = new ObjectReference[6]
	dealWorkers = new Actor[6]
	dealCustomers = new Actor[6]
	dealStates = new Int[6]
	dealThreads = new Int[6]
	dealSerials = new Int[6]
	dealStarted = new Float[6]
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
			ScheduleWatchdog()
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
	dealStates[slot] = DealFree
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

; The nearest bed in the brothel that nobody uses, sleeps in, or has been given to another pair; a
; real bed before any bedroll. The furniture in range is scanned directly: SexLab's FindBeds left out
; the Bannered Mare's rented beds, and its FindBed with IgnoreUsed returns beds in use.
ObjectReference Function PickBed(SexLabFramework sexLab, Actor worker, Actor[] positions)
	ObjectReference[] found = PO3_SKSEFunctions.FindAllReferencesOfFormType(worker, FormTypeFurniture, BedSearchRadius)
	Bool logging = GetModSettingBool("bDebugLog:General")
	If logging
		DebugLog("Bed search for " + worker.GetDisplayName() + ": " + found.Length + " furniture in range")
	EndIf
	ObjectReference bed = None
	ObjectReference bedroll = None
	Float bedDistance = 0.0
	Float bedrollDistance = 0.0
	; With no furniture SexLab offers every scene; on furniture it knows, only that furniture's.
	Int anywhereCount = SexLabRegistry.LookupScenes(positions, "", None, 1, None).Length
	Int i = 0
	While i < found.Length
		ObjectReference candidate = found[i]
		Int bedType = BedTypeOf(candidate)
		If bedType > 0
			Float distance = worker.GetDistance(candidate)
			Float dz = candidate.GetPositionZ() - worker.GetPositionZ()
			Bool usable = !candidate.IsDisabled() && candidate.GetParentCell() == brothelCell && Math.abs(dz) <= BedSearchRadiusZ \
				&& dealBeds.Find(candidate) < 0 && sexLab.IsBedAvailable(candidate)
			If logging
				DebugLog("  " + candidate.GetDisplayName() + " [" + candidate.GetFormID() + "] " \
					+ PO3_SKSEFunctions.GetFormEditorID(candidate.GetBaseObject()) + " type=" + bedType \
					+ " sexLabBed=" + sslThreadLibrary.IsBed(candidate) \
					+ " dist=" + (distance as Int) + " dz=" + (dz as Int) \
					+ " sameCell=" + (candidate.GetParentCell() == brothelCell) + " takenByPair=" + (dealBeds.Find(candidate) >= 0) \
					+ " available=" + sexLab.IsBedAvailable(candidate) + " usable=" + usable)
			EndIf
			If usable && ((bedType == BedTypeBedroll && (!bedroll || distance < bedrollDistance)) \
					|| (bedType != BedTypeBedroll && (!bed || distance < bedDistance)))
				; Only a candidate that would be chosen is checked, as the lookup takes a moment.
				Int onBedCount = SexLabRegistry.LookupScenes(positions, "", None, 2, candidate).Length
				If onBedCount == 0 || onBedCount >= anywhereCount
					usable = False
				EndIf
				If logging
					DebugLog("    SexLab scenes here: " + onBedCount + " of " + anywhereCount + "; known bed=" + usable)
				EndIf
			EndIf
			If usable
				If bedType == BedTypeBedroll
					If !bedroll || distance < bedrollDistance
						bedroll = candidate
						bedrollDistance = distance
					EndIf
				ElseIf !bed || distance < bedDistance
					bed = candidate
					bedDistance = distance
				EndIf
			EndIf
		EndIf
		i += 1
	EndWhile
	If !bed
		bed = bedroll
	EndIf
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
Int Function BedTypeOf(ObjectReference ref)
	Int bedType = sslThreadLibrary.GetBedTypeImpl(ref)
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

Function ClearStalledDeals()
	Float now = Utility.GetCurrentRealTime()
	Int i = 0
	While i < DealSlots
		If dealStates[i] == DealInScene && now - dealStarted[i] > SceneTimeoutSeconds
			ReleaseDeal(i)
		ElseIf dealStates[i] != DealFree && dealStates[i] != DealInScene && now - dealStarted[i] > BusyTimeoutSeconds
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
	Actor worker = PickWorker(sexLab)
	If !worker
		Notify("$SNB_NoWorker", quiet)
		Return
	EndIf
	Actor customer = PickCustomer(sexLab, worker)
	If !customer
		Notify("$SNB_NoCustomer", quiet)
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
		SkyrimNetApi.DirectNarration(worker.GetDisplayName() + " accepts " + customer.GetDisplayName() + "'s offer of " \
			+ GetModSettingInt("iPayment:General") + " gold and agrees to spend the night with " + customer.GetDisplayName() \
			+ ". She now tells " + customer.GetDisplayName() + " so in her own words, willingly.", worker, customer)
	EndIf

	; The worker answers through AcceptCustomerOffer / RefuseCustomerOffer as the conversation goes.
	; With "always accept" there is nothing to wait for: the scene follows the exchange.
	Float waited = 0.0
	While !alwaysAccept && DealAlive(slot, serial) && dealStates[slot] == DealPending && waited < DealTimeoutSeconds
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
	Utility.Wait(1.0)
	If DealAlive(slot, serial)
		StartBrothelScene(sexLab, slot)
	Else
		PlayerTrace("stopped: the deal was cleared after accepting")
	EndIf
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
		+ his + " own words, offering the " + payment + " gold, then waits for an answer."
EndFunction

Function PlayerTrace(String line)
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Player serving: " + line)
	EndIf
EndFunction

; Bed mode "always": the nearest free bed in the brothel is the scene's centre, which also makes
; SexLab pick bed animations. With no free bed (or bed mode "follow SexLab") the scene starts where
; the worker stands, unless another pair is already there: then at the spot the customer came from.
Function StartBrothelScene(SexLabFramework sexLab, Int slot)
	Actor worker = dealWorkers[slot]
	Actor[] positions = new Actor[2]
	positions[0] = worker
	positions[1] = dealCustomers[slot]
	ObjectReference center = None
	Int furniturePref = 1
	If GetModSettingInt("iBedMode:General") == 1
		center = PickBed(sexLab, worker, positions)
		dealBeds[slot] = center
		furniturePref = 2
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
	String[] scenes = OneSexPositionScenes(positions, center, furniturePref)
	SexLabThread thread
	If scenes.Length > 0
		thread = sexLab.StartSceneEx(positions, scenes, None, "", center, furniturePref, SceneHook)
	Else
		thread = sexLab.StartScene(positions, "", None, center, furniturePref, SceneHook)
	EndIf
	If GetModSettingBool("bDebugLog:General")
		DebugLog("Scene for " + worker.GetDisplayName() + " and " + positions[1].GetDisplayName() + ": " \
			+ scenes.Length + " one-sex-position scenes, started=" + (thread != None))
	EndIf
	If !thread
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
	dealThreads[slot] = thread.GetThreadID()
	dealStates[slot] = DealInScene
	dealStarted[slot] = Utility.GetCurrentRealTime()
EndFunction

; SexLab puts an actor in any position whose sexes include the actor's, and many scenes have a
; position that takes either sex, so the man could get the woman's part. For a man and a woman this
; returns up to SceneChoices scenes, checked from a random start, in which one position takes only
; women and the other only men; none for other pairs or when no such scene is found.
String[] Function OneSexPositionScenes(Actor[] positions, ObjectReference center, Int furniturePref)
	String[] picked
	Int sexA = SexLabRegistry.GetSex(positions[0], False)
	Int sexB = SexLabRegistry.GetSex(positions[1], False)
	If !((sexA == 0 && sexB == 1) || (sexA == 1 && sexB == 0))
		Return picked
	EndIf
	String[] found = SexLabRegistry.LookupScenes(positions, "", None, furniturePref, center)
	If found.Length == 0
		Return picked
	EndIf
	picked = new String[10]
	Int count = 0
	Int checks = found.Length
	If checks > SceneChecks
		checks = SceneChecks
	EndIf
	Int index = Utility.RandomInt(0, found.Length - 1)
	While checks > 0 && count < SceneChoices
		Int[] sexes = SexLabRegistry.GetPositionSexA(found[index])
		If sexes.Length == 2
			Int a = Math.LogicalAnd(sexes[0], 0x3)
			Int b = Math.LogicalAnd(sexes[1], 0x3)
			If (a == 0x1 && b == 0x2) || (a == 0x2 && b == 0x1)
				picked[count] = found[index]
				count += 1
			EndIf
		EndIf
		index = (index + 1) % found.Length
		checks -= 1
	EndWhile
	Return Utility.ResizeStringArray(picked, count)
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

; Sends the customer to the worker with a travel package, giving him at most 20 seconds before he
; is moved next to her. PathToReference is not used: it never returns for a customer who cannot
; path, for example one sitting in a chair. The package stays on until the deal is done (see
; KeepClose) and the worker, unless it is the player, stands still meanwhile, so the two talk face
; to face instead of wandering off.
Function ApproachWorker(Actor customer, Actor worker)
	If worker != Game.GetPlayer()
		worker.SetDontMove(True)
	EndIf
	PO3_SKSEFunctions.SetLinkedRef(customer, worker, TalkLink())
	ActorUtil.AddPackageOverride(customer, TravelPackage(), 100)
	customer.EvaluatePackage()
	Float waited = 0.0
	While waited < 20.0 && customer.GetDistance(worker) > TalkDistance
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	If customer.GetDistance(worker) > 300.0
		customer.MoveTo(worker, 100.0, 0.0, 0.0)
	EndIf
EndFunction

; While the pair talks: sends the customer back to the worker if they have drifted apart (the
; player may walk about).
Function KeepClose(Int slot)
	Actor customer = dealCustomers[slot]
	Actor worker = dealWorkers[slot]
	If customer && worker && customer.GetDistance(worker) > TalkDistance + 50.0
		customer.EvaluatePackage()
	EndIf
EndFunction

; Lets the pair move freely again.
Function ReleaseHold(Int slot)
	Actor customer = dealCustomers[slot]
	Actor worker = dealWorkers[slot]
	If customer
		ActorUtil.RemovePackageOverride(customer, TravelPackage())
		PO3_SKSEFunctions.SetLinkedRef(customer, None, TalkLink())
		customer.EvaluatePackage()
	EndIf
	If worker && worker != Game.GetPlayer()
		worker.SetDontMove(False)
	EndIf
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
		If !talking || Utility.GetCurrentRealTime() - talkingSince > TalkTurnTimeoutSeconds
			talking = True
			talkingSince = Utility.GetCurrentRealTime()
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

Actor Function PickWorker(SexLabFramework sexLab)
	Actor[] present = new Actor[64]
	Int count = 0
	Int i = 0
	While i < workerCount
		Actor candidate = workers[i]
		If candidate && !candidate.IsDead() && candidate.GetParentCell() == brothelCell \
				&& !IsInDeal(candidate) && !sexLab.IsActorActive(candidate)
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
	If GetModSettingBool("bLocalCustomers:General")
		Actor player = Game.GetPlayer()
		Actor[] nearby = MiscUtil.ScanCellNPCs(player, 0.0, None, True)
		i = 0
		While i < nearby.Length && count < present.Length
			Actor candidate = nearby[i]
			If candidate != player && customers.Find(candidate) < 0 && workers.Find(candidate) < 0 \
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
	If !candidate || candidate == worker || candidate.IsDisabled() || !candidate.Is3DLoaded() \
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

; Pays the worker of the pair whose scene ended, found by the SexLab thread it started.
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
	Actor customer = dealCustomers[slot]
	ReleaseDeal(slot)
	Int payment = GetModSettingInt("iPayment:General")
	If payment > 0
		worker.AddItem(Game.GetFormFromFile(0x00000F, "Skyrim.esm"), payment, True)
		SkyrimNetApi.RegisterPersistentEvent(customer.GetDisplayName() + " paid " + worker.GetDisplayName() + " " + payment + " gold for the night.", customer, worker)
	EndIf
	Debug.Notification("$SNB_Paid")
EndEvent
