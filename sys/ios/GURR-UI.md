# Gurr 3.6.6 interface baseline on the 5.0.0 engine

Engine: JodiJodington/NetHack-Android, f7c0d7851b854cc7b1ca09b2c193e8620f2962d9.
The engine sources and 5.0.0 game data are unchanged by this frontend revision.

Interface references:
- https://github.com/gurrhack/NetHack-Android/tree/v3.6.6-1
  (7a972c9eb980bf1cd11ed7b465de4b94c93f698a, 2020-05-21).
- https://github.com/gurrhack/ForkFront-Android/tree/cd2aff11bd6c0af9f0504232647f9ae611dcfb29
  (same-date frontend source; the engine tag did not pin a frontend revision).

This is a UIKit reimplementation, not a compilation of Android Java against iOS.
It adopts the original default command order, six configurable edge panels with
orientation-specific visibility/location, panel size/opacity, command labels and
control/meta sequences, the four keyboard maps, top status/message overlay,
directional overlay, travel mode choices, map pan/pinch and long-press running.
Long-press a menu item to select a quantity. Tap messages for history, or the
status line for the app menu. Long-press a command panel to open settings.

The supplied keyboard JSON is transcribed from ForkFront's qwerty.xml,
symbols.xml, ctrl.xml and meta.xml. Their notice is retained here:

Copyright 2008, The Android Open Source Project
Licensed under the Apache License, Version 2.0 (the "License");
you may not use these files except in compliance with the License.
You may obtain a copy of the License at
https://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

Differences that remain: UIKit menu/dialog appearance, no Android hardware
Back/volume bindings, Hearse, arbitrary external tileset import, per-command
drag/reorder, or options-file editor. Tiles are the updated 5.0.0 Default,
Geoduck and Nevanda assets; old 3.6.6 tile indices must not be used with 5.0.0.
The iPhone keyboard adds an Esc/Space/Hide strip to replace Android Back.
Save ends the engine session; close and reopen the app to resume the same name.
An existing 5.0.0 save and options file are retained. A 3.6.6 save is not migrated.

Verification: CI compiles arm64 iOS, runs engine new-game/save/restore checks,
then launches the UIKit app in a simulator. Physical-device gestures, extended
play, and exact visual parity still require comparison on device.
