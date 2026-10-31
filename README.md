# SkyrimNet Brothel 0.3.0

Run your own brothel. Make any interior your brothel, register workers, women or men (followers or
anyone else), and send customers to them, or take customers yourself. SkyrimNet's AI voices the customer's offer and the
worker's answer, SexLab plays the scene, and the customer pays up front. Since 0.1.7 the town's own
people can come as customers, the brothel can have an owner who takes a share and runs it, workers
can go after customers themselves, and the brothel and every worker gain levels.

New in 0.2.0: up to three brothels, women customers, hired workers, registering all your female
followers at once, up to 12 pairs at once, workers chatting among themselves, a *Manage Brothel*
power for the main settings, a set chance that a customer accepts an invitation, more varied
offers, and better bed handling (see [What is new in 0.2.0](#what-is-new-in-020)). 0.2.1 makes taking customers
yourself much quicker, works with SkyrimNet beta 29, and fixes Delphine's bed (see
[What is new in 0.2.1](#what-is-new-in-021)).

New in 0.3.0: men workers, customers and workers who know each other (friends, lovers, regulars)
and family who never do business together, buying a worker's company yourself, a reordered MCM, and
a brothel with no customers of its own (see [What is new in 0.3.0](#what-is-new-in-030)).

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
| [PapyrusUtil SE](https://www.nexusmods.com/skyrimspecialedition/mods/13048) | Moves the customer with a package override; reads the position, topic and phrase lists. |
| [powerofthree's Papyrus Extender](https://www.nexusmods.com/skyrimspecialedition/mods/22854) | Links the customer to the worker for that move. |
| [UIExtensions](https://www.nexusmods.com/skyrimspecialedition/mods/17561) | The list menu of the *Manage Brothel* power (0.2.0). Everything else works without it. |

Any follower framework works (vanilla followers, NFF and others), and workers need not be followers
at all.

**SkyrimNet Player Choices is no longer needed (0.1.7).** The lines you pick from in the dialogue
menu now come from a copy of it built into this mod under its own names (scripts
`skyrimnet_BrothelChoices*`, prompt `skyrimnet_brothel_choices`). You can keep the standalone
SkyrimNet Player Choices (and its Starters add-on) installed for other mods; the two do not clash.

## Installation

Install with your mod manager and enable `skyrimnet_Brothel.esp`. It is ESL-flagged and needs no
load-order slot. It can be added to an existing save.

**Upgrading from 0.2.x:** install over the old version (plugin included) and load your save. The
MCM pages are reordered, but your values are kept. Workers you registered stay registered, and
*Hired workers' sex* starts at *Women only*, so nothing changes until you set it.

**Upgrading from 0.1.x:** install over the old version and load your save; nothing else is
needed. Your brothel becomes the first of up to three, and you get the *Manage Brothel* power. If
the MCM does not show the new settings, check them once (MCM Helper keeps the values you already
set).

Japanese players: also install the separate Japanese translation archive and let it overwrite this
one.

Whatever language your game is set to, the menu and messages are in English (or Japanese with the
translation). In the MCM the mod is listed as **Brothel**. Before 0.1.8 a game set to any other
language than English or Japanese showed it as `$SNB_ModName` instead, with untranslated keys
throughout.

## How to play

1. **Set the hotkeys** in the MCM: *Register / unregister worker* and *Send a customer* (*Workers*
   page) and, if you want to work yourself, *Take a customer yourself* (*You* page). They are
   unset at first.
2. **Make a brothel.** Walk into any interior, choose *Add this interior as a brothel* in the MCM
   (or in the *Manage Brothel* power) and close the menu. Customers move in (three by default, set
   with *Customers*, 0 to 10) and wander about. Their looks are picked at random from vanilla men
   (and, with *Customers' sex*, women) of several races. You can have up to three brothels; see
   *Several brothels* below.
3. **Register workers.** Aim at any adult NPC, a woman or a man, a follower or not, and press
   *Register / unregister worker*. Press it on them again to unregister them. *Register followers*
   registers every follower near you at once, of the sexes *Hired workers' sex* picks (*Unregister
   followers* undoes it), and *Hired workers* has the brothel hire workers of its own. The
   *Workers* page of the MCM lists everyone registered; a `*` after a name means they are in the
   brothel now. You can unregister from there too.
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
   he says yes or no. All this needs *You work as one of the workers* on.
6. **Buy a worker (optional).** With *You work as one of the workers* off, talk to a worker in the
   brothel and pick *(Buy their company)*. See *Buying a worker* below.
7. **Let the town come to you (optional).** Turn on *Townsfolk visit* in the MCM. During the
   opening hours (18:00 to 02:00 by default) people of the brothel's town walk over on their own,
   wait in the brothel and are customers like the brothel's own. See *Townsfolk customers* below.
8. **Get paid.** The customer pays the moment the offer is accepted (50 gold by default), before
   the scene, and SkyrimNet remembers it. With an owner, the house's share goes to the owner. If
   the deal falls through before the scene, the gold is given back.
9. **Pick an owner (optional).** On the *Owner* page choose nobody, yourself, or an adult who is in
   the brothel. See *The owner* below.
10. **Manage it on the go.** The *Manage Brothel* lesser power (under *Powers* in the magic menu)
   opens a list with the main settings, for when the MCM is not at hand or does not show (SkyUI
   lists at most 128 mod menus). See *The Manage Brothel power* below.

## MCM settings

The menu has six pages. Since 0.3.0 each page is grouped under headings, each heading's settings
kept together in one column, with settings that go together next to each other. Buttons that act on the world (adding or closing a brothel,
registering followers) do their work once the menu closes; several pressed in one visit all run,
in the order pressed.

**Brothel**

| Setting | Default | What it does |
|---|---|---|
| Current brothel | None | The brothel in use: the one you are in, or were in last. |
| Brothels | 0 / 3 | How many brothels you have. |
| Add this interior as a brothel | | Makes the interior you stand in one of your brothels (up to 3); customers move in. If it already is one, it becomes the current one. |
| Brothel list / Close the selected brothel | | Closes the brothel picked in the list: its customers and hired workers leave, and its owner, level and townsfolk are forgotten. |
| *Customers* | | |
| Customers | 3 | 0 to 10 of the brothel's own customers. At 0 none stay, and customers come only from the townsfolk and, with *Anyone can be a customer* on, other NPCs in the brothel. Changing it adds or sends away customers once the menu closes; one being served leaves once done. |
| Pairs at once | 5 | 1 to 12 workers with customers at the same time. Your own customer does not count. Each pair needs a free customer, and SexLab plays at most 15 scenes at once. |
| Customers' sex | Men | Men, women, or half and half (with an odd number, one more man). Changing it swaps customers once the menu closes. |
| Allow same-sex | Off | Off: customers are always of the other sex from the worker (or you). On: same-sex pairs too. |
| Anyone can be a customer | On | Other adult NPCs in the brothel can be customers too. Registered workers, a worker's family and hostile NPCs never are. |
| *Scenes* | | |
| Beds | Always use | *Always use*: the scene takes place on a free bed in the brothel (a double bed first), or where the pair stands if none is free. *Follow SexLab*: SexLab's own NPC bed setting decides. |
| *Payment* | | |
| Gold per customer | 50 | 0 to 1000, paid up front when the offer is accepted. Also the price when you buy a worker. |
| *Brothel level* | | |
| Brothel level / Gold to the next level | | See *Levels* below. |
| Gold per brothel level | 1000 | 100 to 10000. |

**Workers**

| Setting | Default | What it does |
|---|---|---|
| Registered workers / Worker list | | Who is registered; `*` = in the brothel now. |
| Selected worker's level / gold to the next level | | The level of the worker picked in the list. |
| Unregister the selected worker | | Unregisters the worker picked in the list. |
| Register / unregister worker | unset | Hotkey: aim at someone and press it to register them, or to unregister them. |
| Send a customer | unset | Hotkey: a free customer walks up to a free worker in the brothel. |
| *Followers* | | |
| Register followers | | Registers every follower near you now, of the sexes *Hired workers' sex* picks. Followers waiting elsewhere are not found. |
| Unregister followers | | Unregisters every registered worker who is one of your followers, wherever they are. |
| *Hired workers* | | |
| Hired workers | 0 | 0 to 10 workers the brothel hires. They appear in the current brothel already registered and stay there; see *Hired workers* below. |
| Hired workers' sex | Women only | Women only, men only, or both (with an odd number, one more woman). Also decides whom *Register followers* takes. |
| Hired workers' level | 5 | 1 to 10, the level a newly hired worker starts at. |
| *The worker's answer* | | |
| Always accept | Off | The worker always says yes: after the offer they are told to accept and say so, then the scene starts. |
| Allow refusing | On | Lets the AI turn a customer down. Ignored while *Always accept* is on. |
| *Invitations* | | |
| Workers invite customers | Off | At the interval below, a free worker of level 5 or more walks up to a free customer and offers their company. |
| Invitation interval (seconds) | 120 | 10 to 1800. |
| Chance a customer accepts | 80% | 0 to 100%. Whether a customer says yes to a worker's (or your) invitation. He is told the answer before he speaks, so his words match it. |
| *Small talk* | | |
| Workers chat | Off | At the interval below, two free workers standing near each other gossip between customers; see *Small talk* below. |
| Chat interval (seconds) | 300 | 30 to 1800. Each chat is an LLM request. |
| *Worker levels* | | |
| Gold per worker level | 300 | 50 to 5000. |

**You**

| Setting | Default | What it does |
|---|---|---|
| You work as one of the workers | On | Your hotkey, *(Offer your company)* in conversation, and an NPC owner talking to you about your takings. Off: none of that. |
| Send customers to you too | Off | Automatic customers, *Send a customer* and an NPC owner's recommendations may pick you, like any free worker. |
| Take a customer yourself | unset | Hotkey. You choose to accept or refuse; never automatic. |
| Your level / gold to the next level | | Your own level as a worker. |
| *Buying workers* | | |
| Buy workers | On | While *You work as one of the workers* is off, *(Buy their company)* is offered when you talk to a worker in the brothel; see *Buying a worker* below. |

**Automatic & town**

| Setting | Default | What it does |
|---|---|---|
| Send customers automatically | Off | Sends a customer to a free worker at the interval below while you are in the brothel. |
| Interval (seconds) | 180 | 10 to 1800. Time in menus does not count. |
| *Townsfolk customers* | | |
| Townsfolk visit | Off | People of the brothel's town walk over during the opening hours and become customers. |
| Who visits | Men | Men, women or both. |
| Visitors at once | 2 | 1 to 5, on their way or waiting. |
| Opening hour / Closing hour | 18 / 2 | When townsfolk set off. Closing earlier than opening runs past midnight; the same hour is all day. |
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
- `DeclineWorkerOffer`: he declines it.

Since 0.2.0 an invitation's answer is set beforehand by *Chance a customer accepts* (left to
itself the AI declined nearly every one); the last two actions are still offered but no longer
decide it.

## Notes and limits

- Up to three brothels, each with 0 to 10 customers of its own. Only interiors can be a brothel.
- Several pairs can run at once (*Pairs at once*, up to 12). Their offers are spoken one after
  another through SkyrimNet, so later pairs may start their scenes a little later.
- Beds: one pair picks and claims a bed at a time, so two pairs never get the same bed. A double
  bed is picked before a single one (SexLab's bed scenes are made for double beds and can spill
  over a single one), a single bed before a bedroll, and a bed someone is standing on is passed
  over. After the scene the pair is moved off the bed, to where the customer stood before.
- Any adult NPC, a woman or a man, can be registered (followers or not); this README says "she"
  for a worker only for short. Workers take customers only while they are inside the brothel, and
  townspeople you register keep living their own day. You yourself need no registering.
- A man worker is paired with men customers only while *Allow same-sex* is on, and a woman worker
  with women customers likewise.
- A worker must be free (not in another SexLab scene) to be picked; so must the customer.
- For a man and a woman, scenes are chosen among those whose positions each take one sex only, so
  the roles are never swapped. If none fits (rare), SexLab chooses as usual.
- When you take a customer yourself and the scene uses a bed, you and the customer are moved to
  the bed first, so SexLab's automatic free camera starts there.
- While they talk, the worker stands still and the customer stays by her (or by you, if you walk
  about).
- If a customer stops getting closer to the worker for 6 seconds (caught on a door frame or
  furniture), or has not reached her within 20 seconds, he is placed in front of her. The same goes
  for a worker walking over to a customer.
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
  wait*, or at closing time. Turning the option off sends everyone home. A visitor you register as
  a worker is no longer a customer: they stay until closing time.
- A visitor of the same sex as the worker is only served while *Allow same-sex* is on.
- SkyrimNet knows who each visitor is, so a married man may well have something to say about it.

## The owner

Pick an owner on the *Owner* page. The owner takes *House's share* of every payment.

- **You as owner.** In the brothel, talk to anyone and pick *(Introduce one of the workers)*. You
  choose which free worker to recommend (the AI writes each line in your voice); the person
  answers, walks over to her and makes the usual offer.
- **An NPC as owner.** While you and the owner are both in the brothel, the owner makes a round
  every *NPC owner's rounds* seconds: recommends a free worker to a free customer by name, or talks
  to a worker about her takings (the one who has gone longest without a customer is taken to task,
  otherwise the best earner is praised). While every worker is busy, the owner keeps a waiting
  customer in good spirits or tells you how business is going; the same thing is not said twice in
  a row.
- An NPC owner recommends you only while *You work as one of the workers* and *Send customers to
  you too* are both on.

## Workers going after customers

With *Workers invite customers* on, a free worker of level 5 or more walks up to a free customer
at the *Invitation interval* and offers her company in her own words. Whether he accepts (and
pays) is set by *Chance a customer accepts*, and he answers accordingly. Workers below level 5
never do; they are still too unwilling. A worker goes after someone they know first (see
*Acquaintances and family* below).

You can do the same while *You work as one of the workers* is on: talk to a customer in the
brothel and pick *(Offer your company)*. The same chance decides your invitations.

Offers and invitations no longer all come out the same ("50 gold for your time"): each one is
given a way of being made, picked from `SKSE/Plugins/skyrimnet_Brothel/approaches.json` and never
the same twice in a row (a shy customer, a blunt one, a worker who offers a drink first, one who
whispers, and so on). The two ways offered to you when you invite a customer come from the same
file. Edit the file to add your own.

## Acquaintances and family

Workers and customers may already know each other.

- **Who knows whom.** Friends, close friends, allies, lovers, rivals and enemies, as the game
  records them, and *regulars*: a customer who has paid for that worker before is remembered as
  one of their regulars.
- **The AI is told.** When such a pair talks (an offer, an invitation, your own conversation), the
  AI learns how they know each other, so a lover, an old friend or a regular is greeted as one.
- **Known faces first.** When a customer is picked for a worker (sending a customer, the automatic
  timer, a worker's invitation), someone the worker knows comes first, the nearest of them.
- **Family never do business together.** Parents and children, brothers and sisters, husbands and
  wives, aunts and uncles, cousins, grandparents and in-laws, as Skyrim, its DLC and the
  Unofficial Patch record them (`families.json`), are never paired, whatever the settings. Instead,
  a relative in the brothel who comes close to a worker, or a townsperson who walks in while one
  is there, recognises them and reacts ("Why are you here...?"), and the worker answers; at most
  once a day for the same two.

## Buying a worker

While *You work as one of the workers* is off and *Buy workers* is on, talk to a worker in the
brothel and pick *(Buy their company)*:

1. You choose how to put your offer (the AI writes the lines in your voice).
2. The worker answers. With *Always accept* on, or *Allow refusing* off, they always agree;
   otherwise the higher their level, the likelier (about half at level 1, always at level 10).
3. If they agree, you pay *Gold per customer* from your own gold (the offer is not made if you
   have too little), pick a position or leave it to them, and the scene starts.

The gold counts toward the worker's level and the brothel's, the owner takes their share as with
any customer, and you become one of the worker's regulars.

## Several brothels

You can run up to three brothels at once (a fourth slot is kept for later use).

- *Add this interior as a brothel* adds the interior you stand in; customers move in. Your other
  brothels stay as they are.
- The current brothel is the one you are in, or were in last: walking into another of your
  brothels makes it the current one.
- Each brothel has its own customers, hired workers, owner, level and townsfolk. The MCM settings
  are shared by all of them.
- Registered workers are shared: a worker takes customers in whichever brothel they are in.
- *Close the selected brothel* closes the one picked in the *Brothel list*.

## Hired workers

Set *Hired workers* above 0 and the brothel hires that many workers of its own: women, men or
both, as *Hired workers' sex* says. They appear in the current brothel, already registered as
workers, at *Hired workers' level*, and stay there.

- Lowering the number, or changing their sex, lets some go once the menu closes; one with a
  customer stays until done.
- A hired worker who is unregistered leaves for good. All of a brothel's hired workers leave when
  it is closed.
- Each brothel hires its own.

## Small talk

With *Workers chat* on, two free workers standing near each other in the brothel gossip between
customers at the *Chat interval*: the guards with arrows in their knees, Dibella's priestesses,
the war, skooma, the Thieves Guild, Mara's temple, dangerous customers, dreams of retiring and more.
The topics are in `SKSE/Plugins/skyrimnet_Brothel/gossip.json` (each with a line that sets the
mood); edit it to add your own. A chat happens only while you are in the brothel and nobody else
is talking, and never twice in a row on the same topic.

## The Manage Brothel power

You get the *Manage Brothel* lesser power when you load a save. Cast it to open a list menu with:

- the current brothel and how many you have,
- *Add this interior as a brothel* and *Close a brothel* (pick one, then confirm),
- *Register followers* and *Unregister followers*,
- *Customers*, *Customers' sex*, *Hired workers* and *Hired workers' level*.

It changes the same settings as the MCM. It needs UIExtensions.

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
- Only the beds in SexLab 1.6x's own bed list are used. `SKSE/SexLab/Furniture/00_skyrimnet_brothel_beds.yaml`
  is a P+ file and 1.6x ignores it, so beds 1.6x does not list (Skyrim's common beds, for one) are
  passed over and the scene plays where the pair stands.
- With *Beds* set to *Follow SexLab*, or when no free bed is found, SexLab 1.6x's own bed settings
  decide; it may ask you whether to use a bed when you take a customer yourself.
- When you take a customer yourself, only the positions in `positions.json` whose tag some
  installed 1.6x animation carries are offered. Some 1.6x packs tag positions in their own way
  (`Doggystyle` without `Doggy`, for example), so add your packs' tags to the file if a position
  you expect is missing.

## Uninstalling

Close every brothel in the MCM first so the customers and hired workers are removed and visitors
go home, save, then disable the mod.

## What is new in 0.3.0

- **Men workers.** Any adult man can be registered, and *Hired workers' sex* (women only, men
  only, or both) sets whom the brothel hires and whom *Register followers* takes. Women only by
  default. The texts the AI and you read no longer assume a woman ("one of the workers", not "one
  of the girls").
- **Acquaintances.** A worker and a customer who know each other (friends, lovers, rivals and so
  on, or a regular who has paid for that worker before) talk like it, and someone the worker knows
  is picked as their customer first.
- **Family.** Relatives never do business together. A relative who finds a worker in the brothel
  reacts on the spot instead.
- **Buying a worker.** With *You work as one of the workers* off, pick *(Buy their company)* in
  conversation with a worker and pay from your own gold.
- **A reordered MCM.** Settings that go together are next to each other, under headings, each
  heading's settings in one column. The hotkeys for registering workers and sending a customer
  are on the *Workers* page.
- **No customers of its own.** *Customers* now goes down to 0, for a brothel served only by the
  townsfolk and the NPCs who are there.
- **Fixes:**
  - Several MCM buttons pressed in one visit to the menu all run. Before, only the last one did,
    so *Add this interior as a brothel* followed by *Unregister followers* added no brothel.
  - A townsperson registered as a worker while visiting is no longer sent home as a served
    customer.
  - *Current brothel* in the MCM shows the right brothel after loading a save. It is updated each
    time the menu opens.
  - A customer who was with a worker when you lowered *Customers* leaves once done, instead of
    staying until the next change.

## What is new in 0.2.1

- **Taking customers yourself is much quicker.** In a busy brothel your conversation waited for
  every worker's offer to end first (half a minute and more); now you go first, and no worker,
  owner or chat starts talking while you are in a conversation. A needless ten-second wait after
  your invitation is gone. When a customer says yes to your invitation, his yes and his question
  about the position are now one line instead of two. The scene starts as soon as you pick a
  position, while he answers. Customers answer you in a sentence or two.
- **SkyrimNet beta 29:** SkyrimNet's next version removes `TriggerPlayerTTS` and
  `IsPlayerTTSFinished`, which the built-in Player Choices used; without them every reply would
  have waited half a minute. The mod no longer uses them, so it works with beta 28 and beta 29
  alike. A line picked in the dialogue menu is still spoken in your voice by SkyrimNet; a line
  picked in the message box or list menu (used only when the dialogue menu does not open) is no
  longer voiced.
- **Delphine's bed** at the Sleeping Giant (and every noble single bed): SexLab P+ places pairs
  far too low on it, so they sank into the mattress. The mod's SexLab furniture file now corrects
  it, and is renamed `00_skyrimnet_brothel_beds.yaml` so SexLab reads it first.
- With Papyrus logging on, `[SNB Timing]` lines in the log show how long each step of your
  conversations takes.

## What is new in 0.2.0

- **Several brothels:** up to three, each with its own customers, hired workers, owner, level and
  townsfolk.
- **Customers' sex:** men, women, or half and half.
- **Hired workers:** the brothel hires 0 to 10 women of its own, at a level you choose.
- **Followers in bulk:** register all your female followers at once, or unregister them.
- **Pairs at once:** up to 12 (was 5), 5 by default (was 1).
- **Small talk:** workers gossip among themselves between customers (optional).
- **Manage Brothel power:** the main settings in a list menu (needs UIExtensions).
- **Invitations:** *Chance a customer accepts* (80% by default) sets whether a customer says yes
  to a worker or to you; before, the AI declined nearly every time.
- **Varied offers:** customers and workers make their offers in many different ways.
- **Beds:** two pairs no longer end up on the same bed (one floating above the other), double beds
  come first, a bed someone stands on is passed over, and pairs are moved off the bed afterwards.
- **Fixes:** a customer caught on a door frame no longer walks on the spot forever; a registered
  worker is never picked as a customer; two conversations no longer talk over each other.

## Files

- `skyrimnet_Brothel.esp`: the quest, the customer NPCs (men and women) and the leveled lists of
  their looks, the hired worker NPCs (women and men), the *Manage Brothel* power, the accept /
  refuse box for the player, the owner's and your conversation topics (introducing a worker,
  offering your company, buying a worker's), and the built-in choices quest with its dialogue.
- `SEQ/skyrimnet_Brothel.seq`: lets the choices quest's dialogue work from the start of a game.
- `Scripts/`: the compiled scripts; `Scripts/Source/` has their source. `skyrimnet_BrothelSLP` holds
  the SexLab P+ calls and `skyrimnet_BrothelSL16` the SexLab 1.6x ones (untested).
  `skyrimnet_BrothelChoices*` are the built-in copy of SkyrimNet Player Choices;
  `skyrimnet_BrothelManageEffect` is the *Manage Brothel* power.
- `SKSE/Plugins/skyrimnet_Brothel/gossip.json`: the workers' small-talk topics; a translation may
  replace it.
- `SKSE/Plugins/skyrimnet_Brothel/families.json`: the family ties of Skyrim's, its DLC's and the
  Unofficial Patch's NPCs (who is whose parent, sibling, spouse and so on), made from the game's
  relationship records, which scripts cannot read. NPCs from other mods are not in it.
- `SKSE/Plugins/skyrimnet_Brothel/approaches.json`: the ways offers and invitations are made
  (English, read by the LLM).
- `SKSE/Plugins/skyrimnet_Brothel/choices.json`: settings of the built-in choices (reply count,
  timeouts, the language the lines are written in, the walk-away label); a translation replaces it.
- `SKSE/Plugins/SkyrimNet/external/local.skyrimnet-brothel/`: the SkyrimNet prompt that writes the
  lines you pick from.
- `MCM/Config/skyrimnet_Brothel/`: the MCM Helper menu.
- `Interface/Translations/skyrimnet_Brothel_ENGLISH.txt`: the English strings. The same file is
  also shipped under every other game language's name (`_FRENCH`, `_GERMAN`, `_JAPANESE` and so
  on), since Skyrim reads only the file of the language it is set to; a translation replaces its
  own language's copy.
- `SKSE/Plugins/skyrimnet_Brothel/strings.json`: phrases built around names ("X is approaching Y.");
  a translation replaces this file too.
- `SKSE/Plugins/skyrimnet_Brothel/positions.json`: the positions offered when you take a customer
  yourself: SexLab scene tags (`tags`) and what each choice means (`labels`, English, read by the
  LLM). Edit, add or remove pairs freely; keep both lists in the same order.
- `SKSE/SexLab/Furniture/00_skyrimnet_brothel_beds.yaml`: SexLab P+ furniture entries for
  Skyrim's common single and double beds, which SexLab P+ does not list itself, so scenes use them,
  and for the noble single bed, which SexLab P+ lists too low (pairs sank into it). SexLab P+ keeps
  the first entry it reads for a bed, reading these files by name, hence the leading `00_`. Called
  `skyrimnet_brothel_commonbeds.yaml` before 0.2.1: delete that file if your mod manager keeps it.
  SexLab 1.6x does not read it.
