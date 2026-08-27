# TOUGE SPOTTER
## This app allowes you to detect upcoming traffic on touge roads, eliminating the need for track map.<br>A beeping sound will be heard upon the car uproaching your direction. The closer the car is, the faster is the beep.
### Originally created for Kaido Battle Servers, since it has two-way traffic. 

#### [Video showcase](not there yet)

#### Installation:
1. Download the [latest release](https://github.com/beispielsweise/Touge-Spotter/releases/tag/1.0)
2. Unpack the RAR arcive into `your-steam-installation\steamapps\common\assettocorsa\apps\lua`
3. The app will automatically appear on the in-game panel

#### General Information:
The application is shipped supporting the following track layouts:<br>
(layout-dependant, meaning Mt.Akina 2-way is not the same as Akina_downhill):
* Mt.Akina (pk_akina_akina_2way)
* tbt.

> [!NOTE]
> To enable track support, click Recording button and start driving the road in the downhill direction.<br>
> After reaching the bottom, should the pitlane be detected, the recording stops automatically. <br>
> If not, you may stop the recording manually.<br>
> <br>After that a road point-spline will be created. It should consistently work on uncomplicated tracks like Akina, Akagi, etc. <br>
> Complicated geometry (loops, bridges over roads, etc) may fail and start false-firing.<br>
> Be aware that this app was created for touge roads, so it may not work correctly on looped tracks and/or unpopular/untested tracks.

#### Settings:
* You can change the detection range in road meters (regardless of the car relative position).
* You can change the Beep from static (speeds up at a static pitch) or raising (pitch goes up as the beep gets faster)
> {!SOUND MODIFICATION>
> If you want to change the sound of the beep, the file is located under `apps\lua\beep.wav` <br>
> Be aware that this might break the pitch increase or speed of the beeping will sound off. Do it at you own risk<br>
> In the future versions I plan to add controll over beep speed and pitch increase

#### Debug:
This is purely debug data to check if the uphil/downhill is detected correctly, if the upcoming cars are detected and meter readings are correct.
