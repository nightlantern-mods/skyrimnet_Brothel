# SkyrimNet Brothel 0.1.2

Run your own brothel. Make any interior your brothel, register your female followers as workers,
and send the resident customers to them. SkyrimNet's AI voices the customer's offer and the
worker's answer, SexLab P+ plays the scene, and the worker is paid when it ends.

## Requirements

| Mod | Notes |
|---|---|
| Skyrim Special Edition / Anniversary Edition | Built and tested on 1.6.1170. |
| [SKSE64](https://skse.silverlock.org/) | |
| [SkyrimNet](https://github.com/MinLL/SkyrimNet-GamePlugin) **beta 28 or later** | Uses its Papyrus API: DirectNarration, RegisterAction, speech queue functions. |
| SexLab P+ (SexLab Framework PPLUS) | Uses the P+ scene API (`StartScene`, local hooks). Classic SexLab 1.6x is not supported. |
| [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604) | |
| [MCM Helper](https://www.nexusmods.com/skyrimspecialedition/mods/53000) | The settings menu. |
| [PapyrusUtil SE](https://www.nexusmods.com/skyrimspecialedition/mods/13048) | Moves the customer with a package override. |
| [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854) | Links the customer to the worker for that move. |

Any follower framework works (vanilla followers, NFF and others): a worker only has to be a
follower when you register her.

## Installation

Install with your mod manager and enable `skyrimnet_Brothel.esp`. It is ESL-flagged and needs no
load-order slot. It can be added to an existing save.

Japanese players: also install the separate Japanese translation archive and let it overwrite this
one.

## How to play

1. **Set two hotkeys** in the MCM (Brothel page): *Send a customer* and *Register / unregister
   worker*. They are unset at first.
2. **Make a brothel.** Walk into any interior, choose *Make this interior the brothel* in the MCM
   and close the menu. Customers move in (three by default, set with *Customers*) and wander about. Their looks are picked at random
   from vanilla men of several races.
3. **Register workers.** Aim at a female follower and press *Register / unregister worker*. Press
   it on her again to unregister her. The *Workers* section of the MCM lists everyone registered;
   a `*` after a name means she is in the brothel now. You can unregister from there too.
4. **Send a customer.** While you are in the brothel, press *Send a customer*. A free customer
   walks up to a free worker who is inside the brothel and makes his offer. SkyrimNet writes and
   voices the exchange:
   - If she accepts in the conversation, the SexLab scene starts once she finishes speaking, on
     the nearest free bed in the brothel (see *Beds* below).
   - If she refuses, nothing happens and you are told so.
   - If she gives no clear answer within 60 seconds, the scene starts after the conversation.
5. **Get paid.** When the scene ends the worker receives the payment (50 gold by default) and
   SkyrimNet remembers that the customer paid her.

## MCM settings

| Setting | Default | What it does |
|---|---|---|
| Current brothel | None | The interior that is your brothel. |
| Make this interior the brothel | | Moves the brothel (and its customers) to where you stand. |
| Close the brothel | | The customers leave. |
| Customers | 3 | 1 to 10. Changing it adds or sends away customers once the menu closes; the one being served stays. |
| Registered workers / Worker list | | Who is registered; `*` = in the brothel now. |
| Unregister the selected worker | | Unregisters the worker picked in the list. |
| Always accept | Off | The worker always says yes, and the scene follows the exchange at once. |
| Allow refusing | On | Lets the AI turn a customer down. Ignored while *Always accept* is on. |
| Beds | Always use | *Always use*: the scene takes place on the nearest free bed in the brothel, or where the pair stands if none is free. *Follow SexLab*: SexLab's own NPC bed setting decides. |
| Send a customer | unset | Hotkey. |
| Register / unregister worker | unset | Hotkey. |
| Gold per customer | 50 | 0 to 1000. |

## SkyrimNet actions

The mod registers two actions the LLM can choose. Only the worker who is being propositioned can
use them, and only while she owes an answer:

- `AcceptCustomerOffer`: she agrees and the scene starts.
- `RefuseCustomerOffer`: she declines. Hidden while *Allow refusing* is off or *Always accept* is on.

## Notes and limits

- One brothel at a time, with 1 to 10 customers. Only interiors can be a brothel.
- Only women can be registered, and only while they are your followers. They take customers only
  while they are inside the brothel.
- A worker must be free (not in another SexLab scene) to be picked; so must the customer.
- If a customer cannot reach the worker within 20 seconds (for example he is stuck behind
  furniture), he is moved next to her.
- Loading a save clears a stuck "a customer is already being served" state.

## Uninstalling

Close the brothel in the MCM first so the customers are removed, save, then disable the mod.

## Files

- `skyrimnet_Brothel.esp`: the quest, the customer NPC and the leveled list of their looks.
- `Scripts/`: the compiled scripts; `Scripts/Source/` has their source.
- `MCM/Config/skyrimnet_Brothel/`: the MCM Helper menu.
- `Interface/Translations/skyrimnet_Brothel_ENGLISH.txt`: the English strings.
