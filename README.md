# SkyrimNet Brothel 0.1.7

Run your own brothel. Make any interior your brothel, register women (followers or anyone else) as
workers, and send customers to them, or take customers yourself. SkyrimNet's AI voices the customer's offer and the
worker's answer, SexLab plays the scene, and the customer pays up front. Since 0.1.7 the town's own
people can come as customers, the brothel can have an owner who takes a share and runs it, workers
can go after customers themselves, and the brothel and every worker gain levels.

> **SexLab 1.6x support is untested.** Since 0.1.6 the mod also runs on classic SexLab 1.6x
> (written against 1.66b), but that support has **not been tested in game on 1.6x**: it was only
> written to work in theory and compiled. Everything was tested on SexLab P+ only. See
> [SexLab 1.6x (untested)](#sexlab-16x-untested) below, and please report what you find.

## Requirements

| Mod | Notes |
|---|---|
| Skyrim Special Edition / Anniversary Edition | Built and tested on 1.6.1170. |
| [SKSE64](https://skse.silverlock.org/) | |
| [SkyrimNet](https://github.com/MinLL/SkyrimNet-GamePlugin) **beta 28 or later** | Uses its Papyrus API: DirectNarration, RegisterAction, speech queue functions. |
| SexLab P+ (SexLab Framework PPLUS) **or** SexLab 1.6x | Tested on P+ 2.18.1. On P+ it uses the P+ scene API (`StartScene`, scene IDs). SexLab 1.6x (1.66b) is supported since 0.1.6 but **untested** (see below). |
| [SkyUI](https://www.nexusmods.com/skyrimspecialedition/mods/12604) | |
| [MCM Helper](https://www.nexusmods.com/skyrimspecialedition/mods/53000) | The settings menu. |
| [PapyrusUtil SE](https://www.nexusmods.com/skyrimspecialedition/mods/13048) | Moves the customer with a package override; reads the position list. |
| [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854) | Links the customer to the worker for that move. |

Any follower framework works (vanilla followers, NFF and others), and workers need not be followers
at all.

**SkyrimNet Player Choices is no longer needed (0.1.7).** The lines you pick from in the dialogue
menu now come from a copy of it built into this mod under its own names (scripts
`skyrimnet_BrothelChoices*`, prompt `skyrimnet_brothel_choices`). You can keep the standalone
SkyrimNet Player Choices (and its Starters add-on) installed for other mods; the two do not clash.

## Installation

Install with your mod manager and enable `skyrimnet_Brothel.esp`. It is ESL-flagged and needs no
load-order slot. It can be added to an existing save.

**Upgrading from 0.1.6 or earlier:** install over the old version and load your save; nothing else
is needed. The MCM is now split into pages, so check its settings once.

Japanese players: also install the separate Japanese translation archive and let it overwrite this
one.

## How to play

1. **Set the hotkeys** in the MCM (*You* page): *Send a customer*, *Register / unregister
   worker* and, if you want to work yourself, *Take a customer yourself*. They are unset at first.
2. **Make a brothel.** Walk into any interior, choose *Make this interior the brothel* in the MCM
   and close the menu. Customers move in (three by default, set with *Customers*) and wander about. Their looks are picked at random
   from vanilla men of several races.
3. **Register workers.** Aim at a woman, a follower or any other adult NPC, and press *Register / unregister worker*. Press
   it on her again to unregister her. The *Workers* page of the MCM lists everyone registered;
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
   up and makes his offer, and the dialogue menu shows you lines to answer with, written by the AI
   in your character's voice: accept willingly, accept reluctantly, or
   refuse. If you accept, he asks what you will do; pick one of the positions offered (only those
   SexLab has scenes for) or leave it to him, and the scene starts with that position. Customers
   come to you without the hotkey only while *Send customers to you too* is on. You can also walk
   up to a customer and pick *(Offer your company)* in conversation: you choose how to put it, and
   he says yes or no.
6. **Let the town come to you (optional).** Turn on *Townsfolk visit* in the MCM. During the
   opening hours (18:00 to 02:00 by default) people of the brothel's town walk over on their own,
   wait in the brothel and are customers like the brothel's own. See *Townsfolk customers* below.
7. **Get paid.** The customer pays the moment the offer is accepted (50 gold by default), before
   the scene, and SkyrimNet remembers it. With an owner, the house's share goes to the owner. If
   the deal falls through before the scene, the gold is given back.
8. **Pick an owner (optional).** On the *Owner* page choose nobody, yourself, or an adult who is in
   the brothel. See *The owner* below.

## MCM settings

The menu has six pages.

**Brothel**

| Setting | Default | What it does |
|---|---|---|
| Current brothel | None | The interior that is your brothel. |
| Make this interior the brothel | | Moves the brothel (and its customers) to where you stand. |
| Close the brothel | | The customers leave. |
| Customers | 3 | 1 to 10. Changing it adds or sends away customers once the menu closes; the one being served stays. |
| Anyone can be a customer | On | Other adult NPCs in the brothel can be customers too. Registered workers and hostile NPCs never are. |
| Allow same-sex | Off | Off: customers are always of the other sex from the worker (or you). On: same-sex pairs too. |
| Pairs at once | 1 | 1 to 5 workers with customers at the same time. Your own customer does not count. |
| Gold per customer | 50 | 0 to 1000, paid up front when the offer is accepted. |
| Brothel level / Gold to the next level | | See *Levels* below. |
| Gold per brothel level | 1000 | 100 to 10000. |

**Workers**

| Setting | Default | What it does |
|---|---|---|
| Registered workers / Worker list | | Who is registered; `*` = in the brothel now. |
| Unregister the selected worker | | Unregisters the worker picked in the list. |
| Selected worker's level / gold to the next level | | The level of the worker picked in the list. |
| Always accept | Off | The worker always says yes: after the offer she is told to accept and says so, then the scene starts. |
| Allow refusing | On | Lets the AI turn a customer down. Ignored while *Always accept* is on. |
| Beds | Always use | *Always use*: the scene takes place on the nearest free bed in the brothel, or where the pair stands if none is free. *Follow SexLab*: SexLab's own NPC bed setting decides. |
| Workers invite customers | Off | At the interval below, a free worker of level 5 or more walks up to a free customer and offers her company; he accepts or declines in conversation. |
| Invitation interval (seconds) | 120 | 10 to 1800. |
| Gold per worker level | 300 | 50 to 5000. |

**You**

| Setting | Default | What it does |
|---|---|---|
| You work as one of the girls | On | Your hotkey, *(Offer your company)* in conversation, and an NPC owner talking to you about your takings. Off: none of that. |
| Send customers to you too | Off | Automatic customers, *Send a customer* and an NPC owner's recommendations may pick you, like any free worker. |
| Your level / gold to the next level | | Your own level as a worker. |
| Send a customer | unset | Hotkey. |
| Register / unregister worker | unset | Hotkey. |
| Take a customer yourself | unset | Hotkey. You choose to accept or refuse; never automatic. |

**Automatic & town**

| Setting | Default | What it does |
|---|---|---|
| Send customers automatically | Off | Sends a customer to a free worker at the interval below while you are in the brothel. |
| Interval (seconds) | 180 | 10 to 1800. Time in menus does not count. |
| Townsfolk visit | Off | People of the brothel's town walk over during the opening hours and become customers. |
| Who visits | Men | Men, women or both. |
| Opening hour / Closing hour | 18 / 2 | When townsfolk set off. Closing earlier than opening runs past midnight; the same hour is all day. |
| Visitors at once | 2 | 1 to 5, on their way or waiting. |
| Hours they wait | 3 | 1 to 12 in-game hours; a visitor not served by then goes home. |
| Townsfolk known | | How many people of the town the mod has seen. |

**Owner**

| Setting | Default | What it does |
|---|---|---|
| Current owner / Choose the owner | None | Nobody, you, or an adult in the brothel right now (open the menu while you are inside to see them). |
| House's share | 50 | 0 to 100 percent of each payment, taken by the owner. A worker who is the owner keeps it all. |
| NPC owner's rounds (seconds) | 120 | 10 to 1800 between an NPC owner's rounds. |

**Debug**

| Setting | Default | What it does |
|---|---|---|
| Debug log | Off | Writes bed searches, scenes, the owner's rounds and each step of taking a customer yourself to `Data/SKSE/Plugins/skyrimnet_Brothel_debug.log`. |
| Set levels | | Sets the brothel's, the selected worker's or your own level, for testing. |

## SkyrimNet actions

The mod registers four actions the LLM can choose, each only for the one who owes an answer, and
only while they do:

- `AcceptCustomerOffer`: the worker agrees to a customer's offer.
- `RefuseCustomerOffer`: she declines. Hidden while *Allow refusing* is off or *Always accept* is on.
- `AcceptWorkerOffer`: a customer agrees to a worker's (or your) invitation, and pays.
- `DeclineWorkerOffer`: he declines it. No clear answer counts as yes.

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
  minutes, and gives the customer his gold back if the scene never started.
- Customers do not fight in the brothel. If one ends up in a fight or hostile to you (a stray hit,
  your followers jumping in), the fight is stopped within a few seconds while you are there.

## Townsfolk customers

With *Townsfolk visit* on, the brothel's town sends its own people: Alvor or Embry walking over
from their houses in Riverwood to a brothel opened in a house there, for example.

- **Who lives in town.** The mod learns it by looking around while you are outside near the
  brothel's front door (within about 8000 units). Walk through the town once after turning the
  option on. Guards, children, followers, registered workers, the brothel's own customers and
  anyone hostile to you are left out. *Townsfolk known* in the MCM shows how many it knows.
- **The front door.** Found the first time you are inside the brothel with the option on (or when
  you make the brothel), and a waiting spot is placed where you stand then.
- **Visits.** Every quarter of an in-game hour within the opening hours, one more person may set
  off, up to *Visitors at once*, never one in a fight, a quest scene or a conversation with you,
  and the same person at most once a day. They walk from wherever they are to the waiting spot
  and stand about there.
- **Locked doors and long walks.** A visitor who reaches the front door outside is let in, as the
  door may be locked to them; one who has not arrived after an hour and a half is let in if you
  are in the brothel, and otherwise goes home.
- **Going home.** A visitor goes back to their day once served (or turned down), after *Hours they
  wait*, or at closing time. Turning the option off sends everyone home.
- A visitor of the same sex as the worker is only served while *Allow same-sex* is on.
- SkyrimNet knows who each visitor is, so a married man may well have something to say about it.

## The owner

Pick an owner on the *Owner* page. The owner takes *House's share* of every payment.

- **You as owner.** In the brothel, talk to anyone and pick *(Introduce one of the girls)*. You
  choose which free worker to recommend (the AI writes each line in your voice); the person
  answers, walks over to her and makes the usual offer.
- **An NPC as owner.** While you and the owner are both in the brothel, the owner makes a round
  every *NPC owner's rounds* seconds: recommends a free worker to a free customer by name, or talks
  to a worker about her takings (the one who has gone longest without a customer is taken to task,
  otherwise the best earner is praised). While every worker is busy, the owner keeps a waiting
  customer in good spirits or tells you how business is going; the same thing is not said twice in
  a row.
- An NPC owner recommends you only while *You work as one of the girls* and *Send customers to you
  too* are both on.

## Workers going after customers

With *Workers invite customers* on, a free worker of level 5 or more walks up to a free customer
at the *Invitation interval* and offers her company in her own words; he accepts (and pays) or
declines in conversation. Workers below level 5 never do; they are still too unwilling.

You can do the same while *You work as one of the girls* is on: talk to a customer in the brothel
and pick *(Offer your company)*.

## Levels

The brothel and every worker (you included) have a level from 1 to 10, earned from the gold
customers pay.

- **Brothel level:** one level for every *Gold per brothel level* paid to all workers together.
  It is the brothel's reputation, which customers know about when they speak.
- **Worker level:** one level for every *Gold per worker level* paid to her. A level-1 worker hates
  the work and goes through with it close to tears; she grows used to it, then comfortable, and at
  level 10 she is the brothel's star. The AI is told her level in every offer, so her answers and
  how she takes the customer change with it.
- Levels are shown in the MCM, and a notification says when one goes up. The *Debug* page can set
  them directly.

## SexLab 1.6x (untested)

**This support has not been tested in game.** The author plays on SexLab P+ only, so the 1.6x
code was written from SexLab 1.66b's script sources and checked only by compiling it. It should
work, but expect rough edges; bug reports from 1.6x players are welcome.

The mod finds out which SexLab is installed each time a save loads (`SexLabUtil.GetVersion()`:
1.6x reports its own version, 16601 for 1.66b) and then uses that SexLab's API. The P+ and 1.6x
calls live in separate scripts (`skyrimnet_BrothelSLP` and `skyrimnet_BrothelSL16`), so neither
needs the other SexLab installed. With *Debug log* on, the log says which one is in use.

How 1.6x differs from P+:

- Scenes are started with `StartSex` and a list of up to 10 animations picked at random among
  those that fit the pair: as many male and female positions as the pair has men and women, not
  aggressive, no special furniture, and, on a bed, none tagged `NoBed` or `Standing` (off a bed,
  none tagged `BedOnly`). With none found, SexLab picks its own.
- Only the beds in SexLab 1.6x's own bed list are used. `SKSE/SexLab/Furniture/skyrimnet_brothel_commonbeds.yaml`
  is a P+ file and 1.6x ignores it, so beds 1.6x does not list (Skyrim's common beds, for one) are
  passed over and the scene plays where the pair stands.
- With *Beds* set to *Follow SexLab*, or when no free bed is found, SexLab 1.6x's own bed settings
  decide; it may ask you whether to use a bed when you take a customer yourself.
- When you take a customer yourself, only the positions in `positions.json` whose tag some
  installed 1.6x animation carries are offered. Some 1.6x packs tag positions in their own way
  (`Doggystyle` without `Doggy`, for example), so add your packs' tags to the file if a position
  you expect is missing.

## Uninstalling

Close the brothel in the MCM first so the customers are removed and visitors go home, save, then
disable the mod.

## Files

- `skyrimnet_Brothel.esp`: the quest, the customer NPC, the leveled list of their looks, the
  accept / refuse box for the player, the owner's and your conversation topics, and the built-in
  choices quest with its dialogue.
- `SEQ/skyrimnet_Brothel.seq`: lets the choices quest's dialogue work from the start of a game.
- `Scripts/`: the compiled scripts; `Scripts/Source/` has their source. `skyrimnet_BrothelSLP` holds
  the SexLab P+ calls and `skyrimnet_BrothelSL16` the SexLab 1.6x ones (untested).
  `skyrimnet_BrothelChoices*` are the built-in copy of SkyrimNet Player Choices.
- `SKSE/Plugins/skyrimnet_Brothel/choices.json`: settings of the built-in choices (reply count,
  timeouts, the language the lines are written in, the walk-away label); a translation replaces it.
- `SKSE/Plugins/SkyrimNet/external/local.skyrimnet-brothel/`: the SkyrimNet prompt that writes the
  lines you pick from.
- `MCM/Config/skyrimnet_Brothel/`: the MCM Helper menu.
- `Interface/Translations/skyrimnet_Brothel_ENGLISH.txt`: the English strings.
- `SKSE/Plugins/skyrimnet_Brothel/strings.json`: phrases built around names ("X is approaching Y.");
  a translation replaces this file too.
- `SKSE/Plugins/skyrimnet_Brothel/positions.json`: the positions offered when you take a customer
  yourself: SexLab scene tags (`tags`) and what each choice means (`labels`, English, read by the
  LLM). Edit, add or remove pairs freely; keep both lists in the same order.
- `SKSE/SexLab/Furniture/skyrimnet_brothel_commonbeds.yaml`: SexLab P+ furniture entries for
  Skyrim's common single and double beds, which SexLab P+ does not list itself, so scenes use them.
  SexLab 1.6x does not read it.
