# Tidebreaker

Battleships with special weapons. One HTML file, no install, nothing to build, and no account of any kind needed to play.

Open `index.html` in any modern browser and pick a mode:

- **Versus computer**: three difficulty levels (Recruit, Captain, Admiral).
- **Play a friend**: live online battle between two devices.
- **Pass and play**: two players on one screen, with a cover screen between turns.

## The twist

Classic rules are still there (pick **Classic** on the menu), but the default **Tidebreaker** rules add:

- **Charge.** You gain 1 Charge at the start of every turn, up to 8.
- **Every ship carries a special weapon.** Spend Charge to use one instead of a shell:

  | Weapon | Carried by | Cost | Effect |
  | --- | --- | --- | --- |
  | Sonar | Destroyer | 2 | Counts the undamaged ship parts in a 3×3 area. No damage. |
  | Torpedo | Submarine | 3 | Runs down a row or column from the nearest edge and hits the first undamaged ship part. |
  | Seeker | Cruiser | 4 | Locks onto an undamaged ship part inside a 3×3 area, or marks the whole area clear. |
  | Barrage | Battleship | 5 | Five shells in a plus shape. |
  | Airstrike | Carrier | 7 | Bombs every square of a 3×3 area. |

- **Sink a ship, lose its weapon.** When one of your ships goes down, its weapon goes with it, and your crew gets +2 Charge from Fury.
- **Live sonar readings.** A sonar number stays on the map and counts down as you hit ships in that area. At zero, the area is marked clear.

## Playing a friend online

One player chooses **Create room** and gets a 4-letter code. The other chooses **Join with code** and types it in. The two browsers connect directly with WebRTC, using the free public [PeerJS](https://peerjs.com/) server only to find each other.

How your friend gets the game:

1. **A link (best, works on every phone).** Put the game online once, then share the link. On the hosted page, **Copy invite link** gives your friend a link that drops them straight into your room.
2. **Send the file.** Send `index.html` to your friend. You both open it, and they join with your code. This works on computers and usually on Android phones. iPhones open a downloaded HTML file in a preview that can't run games, so iPhone players need the link.

### Put it online with GitHub Pages (free, about two minutes)

This repository is public, so GitHub can host the game for free:

1. Open the repository's Pages settings: <https://github.com/fduplessis903-dev/Quotestack/settings/pages>
2. Under **Build and deployment**, set **Source** to **Deploy from a branch**.
3. Choose the branch that has the `tidebreaker` folder (for example `claude/sharp-shannon-w3h2ph`), keep the folder as **/ (root)**, and click **Save**.
4. After a minute or two the game is live at <https://fduplessis903-dev.github.io/Quotestack/tidebreaker/>

Anyone can open that link on a phone or computer, with no account. The empty `.nojekyll` file at the top of the repository tells GitHub to serve the files exactly as they are.

Your ship positions never leave your device during the battle. Each player reports the result of every shot fired at their own fleet. When the battle ends, both fleets are revealed and every report is checked against a hash each player published before the first shot, so you can see that nobody lied.

Both players need an internet connection. A small number of strict networks (some office or school networks) block direct browser connections. If you can't connect, try a phone hotspot.

## Controls

- Drag ships onto your grid, or tap a ship and then a square. Tap a placed ship to turn it. **Shuffle** places the whole fleet.
- Click a square in enemy waters to fire.
- Keys **1** to **6** pick a weapon, **R** turns a ship or torpedo, **Esc** goes back to the shell, and arrow keys move around the grid.
- On a phone, a shell fires on tap. A special weapon needs a second tap on the same square, or the **Fire** button.

## Notes

- The sea, explosions, splashes, torpedoes, missiles and aircraft are drawn live with WebGL and canvas. All sound is synthesised in the browser, so there are no asset files.
- Games in progress are saved in the browser, so you can close the tab and continue from the menu.
- If you run your own PeerJS server, add `?peerhost=your.host&peerport=443&peerpath=/` to the page URL.
