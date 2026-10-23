# SkyrimNet Brothel 0.1.3

Run your own brothel. Make any interior your brothel, register women (followers or anyone else) as
workers, and send customers to them, or take customers yourself. SkyrimNet's AI voices the customer's offer and the
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

Any follower framework works (vanilla followers, NFF and others), and workers need not be followers
at all.

## Installation

Install with your mod manager and enable `skyrimnet_Brothel.esp`. It is ESL-flagged and needs no
load-order slot. It can be added to an existing save.

Japanese players: also install the separate Japanese translation archive and let it overwrite this
one.

## How to play

1. **Set the hotkeys** in the MCM (Brothel page): *Send a customer*, *Register / unregister
   worker* and, if you want to work yourself, *Take a customer yourself*. They are unset at first.
2. **Make a brothel.** Walk into any interior, choose *Make this interior the brothel* in the MCM
   and close the menu. Customers move in (three by default, set with *Customers*) and wander about. Their looks are picked at random
   from vanilla men of several races.
3. **Register workers.** Aim at a woman, a follower or any other adult NPC, and press *Register / unregister worker*. Press
   it on her again to unregister her. The *Workers* section of the MCM lists everyone registered;
   a `*` after a name means she is in the brothel now. You can unregister from there too.
4. **Send a customer.** While you are in the brothel, press *Send a customer*, or turn on *Send
   customers automatically*. The free customer nearest to her (one of the brothel's own or, with *Anyone can be a
   customer* on, any other adult NPC there) walks up to a free worker who is inside the brothel
   and makes his offer; a notification says who is approaching whom. With *Pairs at once* above 1,
   further presses (or the timer) start more pairs while earlier ones are still going. SkyrimNet
   writes and voices the exchange:
   - If she accepts in the conversation, the SexLab scene starts once she finishes speaking, on
     the nearest free bed in the brothel (see *Beds* below).
   - If she refuses, nothing happens and you are told so.
   - If she gives no clear answer within 60 seconds, the scene starts after the conversation.
5. **Take a customer yourself.** Press *Take a customer yourself* in the brothel: a customer walks
   up and makes his offer, then a box asks you to *Accept* or *Refuse*. This never happens
   automatically.
6. **Get paid.** When the scene ends the worker receives the payment (50 gold by default) and
   SkyrimNet remembers that the customer paid her.

## MCM settings

| Setting | Default | What it does |
|---|---|---|
| Current brothel | None | The interior that is your brothel. |
| Make this interior the brothel | | Moves the brothel (and its customers) to where you stand. |
| Close the brothel | | The customers leave. |
| Customers | 3 | 1 to 10. Changing it adds or sends away customers once the menu closes; the one being served stays. |
| Pairs at once | 1 | 1 to 5 workers with customers at the same time. Your own customer does not count. |
| Anyone can be a customer | On | Other adult NPCs in the brothel can be customers too. Registered workers and hostile NPCs never are. |
| Allow same-sex | Off | Off: customers are always of the other sex from the worker (or you). On: same-sex pairs too. |
| Registered workers / Worker list | | Who is registered; `*` = in the brothel now. |
| Unregister the selected worker | | Unregisters the worker picked in the list. |
| Always accept | Off | The worker always says yes: after the offer she is told to accept and says so, then the scene starts. |
| Allow refusing | On | Lets the AI turn a customer down. Ignored while *Always accept* is on. |
| Beds | Always use | *Always use*: the scene takes place on the nearest free bed in the brothel, or where the pair stands if none is free. *Follow SexLab*: SexLab's own NPC bed setting decides. |
| Send a customer | unset | Hotkey. |
| Register / unregister worker | unset | Hotkey. |
| Take a customer yourself | unset | Hotkey. You choose to accept or refuse; never automatic. |
| Send customers automatically | Off | Sends a customer to a free worker at the interval below while you are in the brothel. |
| Interval (seconds) | 180 | 10 to 1800. Time in menus does not count. |
| Gold per customer | 50 | 0 to 1000. |

## SkyrimNet actions

The mod registers two actions the LLM can choose. Only the worker who is being propositioned can
use them, and only while she owes an answer:

- `AcceptCustomerOffer`: she agrees and the scene starts.
- `RefuseCustomerOffer`: she declines. Hidden while *Allow refusing* is off or *Always accept* is on.

## Notes and limits

- One brothel at a time, with 1 to 10 customers. Only interiors can be a brothel.
- Several pairs can run at once (*Pairs at once*). Their offers are spoken one after another
  through SkyrimNet, so later pairs may start their scenes a little later.
- Only adult women can be registered (followers or not). They take customers only while they are
  inside the brothel. You yourself need no registering.
- A worker must be free (not in another SexLab scene) to be picked; so must the customer.
- For a man and a woman, scenes are chosen among those whose positions each take one sex only, so
  the roles are never swapped. If none fits (rare), SexLab chooses as usual.
- When you take a customer yourself and the scene uses a bed, you and the customer are moved to
  the bed first, so SexLab's automatic free camera starts there.
- While they talk, the worker stands still and the customer stays by her (or by you, if you walk
  about).
- If a customer cannot reach the worker within 20 seconds (for example he is stuck behind
  furniture), he is moved next to her.
- Loading a save clears any deal that got stuck; a watchdog also clears stalled ones after a few
  minutes.

## Uninstalling

Close the brothel in the MCM first so the customers are removed, save, then disable the mod.

## Files

- `skyrimnet_Brothel.esp`: the quest, the customer NPC, the leveled list of their looks and the
  accept / refuse box for the player.
- `Scripts/`: the compiled scripts; `Scripts/Source/` has their source.
- `MCM/Config/skyrimnet_Brothel/`: the MCM Helper menu.
- `Interface/Translations/skyrimnet_Brothel_ENGLISH.txt`: the English strings.
- `SKSE/Plugins/skyrimnet_Brothel/strings.json`: phrases built around names ("X is approaching Y.");
  a translation replaces this file too.
