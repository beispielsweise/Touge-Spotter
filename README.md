# TOUGE SPOTTER
## This app allowes you to detect upcoming traffic on touge roads, eliminating the need for track map.<br>A beeping sound will be heard upon a car uproaching your direction. The closer the car is, the faster is the beep.
### Originally created for Kaido Battle Servers, since it has two-way traffic. 

#### [Video showcase](https://www.youtube.com/watch?v=llSjlrsR4p4)
[![Touge Spotter App](https://img.youtube.com/vi/llSjlrsR4p4/maxresdefault.jpg)](https://www.youtube.com/watch?v=llSjlrsR4p4)

## Installation:
1. Download the [latest release](https://github.com/beispielsweise/Touge-Spotter/releases)
2. Unpack the RAR archive into `your-steam-installation\steamapps\common\assettocorsa\apps\lua`
3. The app will automatically appear on the in-game panel

## General Information:
The application is shipped supporting the following track layouts:<br>
(layout-dependant, meaning pk_akina_akina_2way is not the same as pk_akina_akina_downhill):
* Mt. Akina (pk_akina_akina_2way)
* Mt. Akagi (ek_akagi_freeroam)
* Tsubaki Line (ek_tsubaki_line_freeroam)
* any other touge track

> [!NOTE]
> To enable track support, click Recording button and start driving the road in the **DOWNHILL** direction.<br>
> After reaching the bottom, should the pitlane be detected, the recording stops automatically. <br>
> If not, you may stop the recording manually.<br>
> Drive at a normal speed, keeping your car in the middle of the road for better results.<br><br>
> After that a road point-spline will be created. It should consistently work on uncomplicated tracks like Akina, Akagi, etc. <br>
> Complicated geometry (loops, bridges over roads, etc) may fail and start false-firing.<br>
> Be aware that this app was created for touge roads, so it may not work correctly on looped tracks and/or unpopular/untested tracks.

## Settings:
* You can change the detection range in road meters (regardless of the car relative position).
* You can change the beeping speed as a multiplier
* You can change beeping volume
* You can choose between single beep and double beep if two and more cars are approaching.
* You can set extra detection range to search for multiple cars (base range + extra range beyound the default one)
> SOUND MODIFICATION<br>
> If you want to change the sound of the beep or the double beep, the file is located under `apps\lua\TougeSpotter\beep.wav` and `apps\lua\TougeSpotter\beep_double.wav` <br>
> `beeps-alt.zip` and `beeps-double-alt.zip` are archives with alternative beep and beep_double sounds that should theoretically be compatible.<br>
> Be aware that changing the beep sound might break the sound repeat logic if the sound is longer than 0.26, allthough a failsafe should work.<br>Do it at you own risk

## Debug:
This is purely debug data to check if the uphil/downhill is detected correctly, if the upcoming cars are detected and meter readings are correct.

## Server extention
This is an experemental server extention of the application. 