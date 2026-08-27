TOUGE SPOTTER

This app allowes you to detect upcoming traffic on touge roads, eliminating the need for track map. 
Originally created for Kaido Battle Servers, since it has two-way traffic. 

The application is shipped supporting the following track layouts 
(layout-dependant, meaning Mt.Akina 2-way is not the same as Akina_downhill):
* Mt.Akina (pk_akina_akina_2way)

To enable track support, click Recording button and start driving the road in the downhill direction.
After reaching the bottom, should the pitlane be detected, the recording stops automatically. 
If not, you may stop the recording manually.

After that a road point-spline will be created. It should consistently work on uncomplicated tracks like Akina, Akagi, etc.
Complicated geometry (loops, bridges over roads, etc) may fail and start false-firing.

Settings:
You can change the detection range in road meters (regardless of the car relative position).
You can change the Beep from static (speeds up at a static pitch) or raising (pitch goes up as the beep gets faster)

Debug:
This is purely debug data to check if the Uphil/downhill is detected correctly, if the upcoming cars are detected and meter readings are correct.