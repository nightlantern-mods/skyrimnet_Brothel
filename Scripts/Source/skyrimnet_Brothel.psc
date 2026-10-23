Scriptname skyrimnet_Brothel extends MCM_ConfigBase
{Brothel run by the player. A chosen interior cell is the brothel; female followers registered as
workers serve the resident customers there. Settings live in MCM/Settings/skyrimnet_Brothel.ini.}

; Records of this plugin, looked up by FormID so the quest needs no property links.
Int Property CustomerBaseID = 0x801 AutoReadOnly
String Property PluginName = "skyrimnet_Brothel.esp" AutoReadOnly
String Property SceneHook = "skyrimnet_Brothel" AutoReadOnly

; The MCM's customer count runs from 1 to this.
Int Property MaxCustomers = 10 AutoReadOnly
Int Property MaxWorkers = 64 AutoReadOnly

; A served customer that never reaches a SexLab end hook would block the key forever; after this
; many seconds the brothel accepts the key again.
Float Property BusyTimeoutSeconds = 300.0 AutoReadOnly
Float Property SceneTimeoutSeconds = 1800.0 AutoReadOnly

; How far from the worker a free bed is looked for when the bed mode is "always".
Float Property BedSearchRadius = 3000.0 AutoReadOnly

Cell brothelCell
Actor[] customers
Actor[] workers
Int workerCount

Int serveKey
Int registerKey

Bool busy
Actor sceneWorker
Actor sceneCustomer

; The worker's answer to the customer's offer, set by the SkyrimNet actions below.
Int Property DealPending = 1 AutoReadOnly
Int Property DealAccepted = 2 AutoReadOnly
Int Property DealRefused = 3 AutoReadOnly
Int dealState

; How long the worker has to accept or refuse in conversation before the scene starts anyway.
Float Property DealTimeoutSeconds = 60.0 AutoReadOnly

; MCM buttons only queue their action: the menu pauses the game, so the work runs once it closes.
String pendingAction

Event OnInit()
	customers = new Actor[10]
	workers = new Actor[64]
	workerCount = 0
	Setup()
EndEvent

; Called by the player alias on every save load: key and mod-event registrations do not survive one.
Function Setup()
	GrowCustomerSlots()
	RegisterKeys()
	RegisterForModEvent("HookAnimationEnd_" + SceneHook, "OnBrothelSceneEnd")
	RegisterActions()
	busy = False
	dealState = 0
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
	If brothel && brothel.IsAwaitingAnswerFrom(akActor)
		brothel.AnswerDeal(True)
	EndIf
EndFunction

Function RefuseCustomerOffer_Execute(Actor akActor, String contextJson, String paramsJson) Global
	skyrimnet_Brothel brothel = Brothel()
	If brothel && brothel.IsAwaitingAnswerFrom(akActor)
		brothel.AnswerDeal(False)
	EndIf
EndFunction

Bool Function IsAwaitingAnswerFrom(Actor akActor)
	Return dealState == DealPending && akActor && akActor == sceneWorker
EndFunction

Function AnswerDeal(Bool accepted)
	If accepted
		dealState = DealAccepted
	Else
		dealState = DealRefused
	EndIf
EndFunction

Event OnSettingChange(String a_ID)
	If a_ID == "iServeKey:General" || a_ID == "iRegisterKey:General"
		RegisterKeys()
	ElseIf a_ID == "iCustomerCount:General"
		pendingAction = "sync"
		RegisterForSingleUpdate(0.1)
	EndIf
EndEvent

Function RegisterKeys()
	UnregisterForAllKeys()
	serveKey = GetModSettingInt("iServeKey:General")
	registerKey = GetModSettingInt("iRegisterKey:General")
	If serveKey > 0
		RegisterForKey(serveKey)
	EndIf
	If registerKey > 0 && registerKey != serveKey
		RegisterForKey(registerKey)
	EndIf
EndFunction

Event OnKeyDown(Int keyCode)
	If Utility.IsInMenuMode() || UI.IsTextInputEnabled()
		Return
	EndIf
	If keyCode == serveKey
		ServeCustomer()
	ElseIf keyCode == registerKey
		ToggleWorker(Game.GetCurrentCrosshairRef() as Actor)
	EndIf
EndEvent

; ---------------------------------------------------------------------------------------------
; MCM buttons
; ---------------------------------------------------------------------------------------------

Function DesignateBrothel()
	pendingAction = "designate"
	RegisterForSingleUpdate(0.1)
EndFunction

Function ClearBrothel()
	pendingAction = "clear"
	RegisterForSingleUpdate(0.1)
EndFunction

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
	ElseIf busy
		; The timeout queued by ServeCustomer.
		EndDeal()
		Return
	EndIf
	; A queued action replaced the pending timeout; put a timeout back while a customer is served.
	If queued != "" && busy
		RegisterForSingleUpdate(SceneTimeoutSeconds)
	EndIf
EndEvent

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
; (or beside the player in the brothel); extra ones leave, never the one being served. Dead
; customers are cleared away and replaced.
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
		If customers[i] && customers[i] != sceneCustomer
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
		Debug.Notification("$SNB_WorkerRemoved")
		Return
	EndIf
	If target.GetLeveledActorBase().GetSex() != 1
		Debug.Notification("$SNB_NotFemale")
		Return
	EndIf
	If !target.IsPlayerTeammate()
		Debug.Notification("$SNB_NotFollower")
		Return
	EndIf
	If workerCount >= MaxWorkers
		Debug.Notification("$SNB_WorkerListFull")
		Return
	EndIf
	workers[workerCount] = target
	workerCount += 1
	Debug.Notification("$SNB_WorkerAdded")
EndFunction

; The MCM's worker list: a menu control whose options are the registered workers, refilled each
; time the menu opens. A trailing " *" marks a worker who is in the brothel right now.
Event OnConfigOpen()
	RefreshWorkerMenu()
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
; Serving a customer
; ---------------------------------------------------------------------------------------------

Function ServeCustomer()
	If busy
		Debug.Notification("$SNB_Busy")
		Return
	EndIf
	If !brothelCell
		Debug.Notification("$SNB_NoBrothel")
		Return
	EndIf
	If Game.GetPlayer().GetParentCell() != brothelCell
		Debug.Notification("$SNB_NotInBrothel")
		Return
	EndIf
	SexLabFramework sexLab = SexLabUtil.GetAPI()
	Actor worker = PickWorker(sexLab)
	If !worker
		Debug.Notification("$SNB_NoWorker")
		Return
	EndIf
	Actor customer = PickCustomer(sexLab)
	If !customer
		Debug.Notification("$SNB_NoCustomer")
		Return
	EndIf

	busy = True
	sceneWorker = worker
	sceneCustomer = customer
	RegisterForSingleUpdate(BusyTimeoutSeconds)

	ApproachWorker(customer, worker)
	dealState = DealPending
	Float offeredAt = Utility.GetCurrentRealTime()
	Bool alwaysAccept = GetModSettingBool("bAlwaysAccept:General")
	String offer = customer.GetDisplayName() + " walks up to " + worker.GetDisplayName() + " and offers to pay for her company tonight."
	If alwaysAccept
		offer += " " + worker.GetDisplayName() + " works here and accepts the offer."
	EndIf
	SkyrimNetApi.DirectNarration(offer, customer, worker)

	; The worker answers through AcceptCustomerOffer / RefuseCustomerOffer as the conversation goes.
	; With "always accept" there is nothing to wait for: the scene follows the exchange.
	Float waited = 0.0
	While !alwaysAccept && dealState == DealPending && waited < DealTimeoutSeconds
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	If dealState == DealRefused
		Debug.Notification("$SNB_Refused")
		EndDeal()
		Return
	EndIf
	; Accepted, or no answer in time: let the last line finish, then one beat before the scene.
	WaitForSpeech(offeredAt)
	Utility.Wait(1.5)
	dealState = 0

	Actor[] positions = new Actor[2]
	positions[0] = worker
	positions[1] = customer
	; Bed mode "always": the nearest free bed in the brothel is the scene's centre, which also makes
	; SexLab pick bed animations. With no free bed the scene starts where they stand.
	ObjectReference bed = None
	Int furniturePref = 1
	If GetModSettingInt("iBedMode:General") == 1
		bed = sexLab.FindBed(worker, BedSearchRadius, True)
		If bed && bed.GetParentCell() != brothelCell
			bed = None
		EndIf
		furniturePref = 2
	EndIf
	If !sexLab.StartScene(positions, "", None, bed, furniturePref, SceneHook)
		Debug.Notification("$SNB_SceneFailed")
		EndDeal()
		Return
	EndIf
	; The end hook settles the scene; this only frees the key if the hook never comes.
	RegisterForSingleUpdate(SceneTimeoutSeconds)
EndFunction

Function EndDeal()
	UnregisterForUpdate()
	busy = False
	dealState = 0
	sceneWorker = None
	sceneCustomer = None
EndFunction

; Sends the customer to the worker with a travel package for at most 20 seconds. PathToReference
; is not used: it never returns for a customer who cannot path, for example one sitting in a chair.
Function ApproachWorker(Actor customer, Actor worker)
	Package travel = Game.GetFormFromFile(0x0235E0, "Skyrim.esm") as Package ; defaultTravelToLinkCustom01
	Keyword link = Game.GetFormFromFile(0x05D5E6, "Skyrim.esm") as Keyword   ; LinkCustom01
	PO3_SKSEFunctions.SetLinkedRef(customer, worker, link)
	ActorUtil.AddPackageOverride(customer, travel, 100)
	customer.EvaluatePackage()
	Float waited = 0.0
	While waited < 20.0 && customer.GetDistance(worker) > 150.0
		Utility.Wait(0.5)
		waited += 0.5
	EndWhile
	ActorUtil.RemovePackageOverride(customer, travel)
	PO3_SKSEFunctions.SetLinkedRef(customer, None, link)
	customer.EvaluatePackage()
	If customer.GetDistance(worker) > 300.0
		customer.MoveTo(worker, 100.0, 0.0, 0.0)
	EndIf
EndFunction

; Waits until SkyrimNet has generated and played the exchange: nothing queued and a moment of
; silence, giving up after 45 seconds.
; Returns once a line has played since the offer (startedAt, real time) and nothing more is queued
; or playing for two seconds; gives up 45 seconds after the offer. A silent queue on its own is not
; enough: right after the offer the LLM is still writing the line and nothing is queued yet.
Function WaitForSpeech(Float startedAt)
	While Utility.GetCurrentRealTime() - startedAt < 45.0
		Int silentMs = SkyrimNetApi.GetTimeSinceLastAudioEnded()
		Float sinceOfferMs = (Utility.GetCurrentRealTime() - startedAt) * 1000.0
		If silentMs > 0 && silentMs < sinceOfferMs && silentMs >= 2000 && SkyrimNetApi.GetSpeechQueueSize() == 0
			Return
		EndIf
		Utility.Wait(0.5)
	EndWhile
EndFunction

Actor Function PickWorker(SexLabFramework sexLab)
	Actor[] present = new Actor[64]
	Int count = 0
	Int i = 0
	While i < workerCount
		Actor candidate = workers[i]
		If candidate && !candidate.IsDead() && candidate.GetParentCell() == brothelCell && !sexLab.IsActorActive(candidate)
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

Actor Function PickCustomer(SexLabFramework sexLab)
	Actor[] present = new Actor[10]
	Int count = 0
	Int i = 0
	While i < customers.Length
		Actor candidate = customers[i]
		If candidate && !candidate.IsDead() && candidate.GetParentCell() == brothelCell && !sexLab.IsActorActive(candidate)
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

Event OnBrothelSceneEnd(Int aiThreadID, Bool abHasPlayer)
	If !sceneWorker
		Return
	EndIf
	Int payment = GetModSettingInt("iPayment:General")
	If payment > 0
		sceneWorker.AddItem(Game.GetFormFromFile(0x00000F, "Skyrim.esm"), payment, True)
		SkyrimNetApi.RegisterPersistentEvent(sceneCustomer.GetDisplayName() + " paid " + sceneWorker.GetDisplayName() + " " + payment + " gold for the night.", sceneCustomer, sceneWorker)
	EndIf
	Debug.Notification("$SNB_Paid")
	EndDeal()
EndEvent
