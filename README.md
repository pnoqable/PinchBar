
# PinchBar <a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=XQTM9GSDUGMB2"><img align=right src="https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif" /></a>

<picture>
<source srcset="https://github.com/pnoqable/PinchBar/blob/main/Ressources/AppIcon128inverted.png" media="(prefers-color-scheme: dark)" />
<img align="left" src="https://github.com/pnoqable/PinchBar/blob/main/Ressources/AppIcon128.png" />
</picture>

## What is it?
PinchBar is a free macOS tool that adds continuous pinch-to-zoom to various apps and is custom-made for Cubase with features often requested on the [official forum](https://forums.steinberg.net/t/pinch-to-zoom-with-a-touchpad/129419). 

## How do I get it running?
On first launch, macOS will ask you for permission. If unsure, just follow these steps:
+ Download PinchBar.zip from [the latest release](https://github.com/pnoqable/PinchBar/releases/latest).
+ When not using Safari, open the zip file to extract its content and delete it. Safari does this automatically.
+ Launch PinchBar.app. A popup appears to tell you that you just downloaded it. Click on "Open".[^1]
+ A second popup asks you to allow PinchBar to use macOS accessibility features.
+ Click on "Open System Preferences".[^2] On older machines, this might take a moment...
+ Enable the switch next to PinchBar.app, confirm with your username and password and close the window.[^3]
+ Finally, drag PinchBar.app onto your Applications folder.

[^1]: If there is no such option, your macOS settings only allow launching apps installed via the App Store. To grant an exception, click on "Show in Finder", right-click PinchBar.app and choose "Open" from the context menu. The same popup appears again, but this time with the option to "Open". Duh...
[^2]: If you dismissed the popup or accidentally denied, you can click on PinchBar's status icon and "Enable PinchBar in Accessibility" there.
[^3]: Prior to macOS Ventura, you must first click the lock button on the bottom left and confirm with your username and password.

Now when you open Cubase, PinchBar's status icon will become opaque. Make a pinch gesture on your trackpad, it should zoom in/out horizontally. With version 0.2 there are now two possible modifiers: Pinch while holding down CMD zooms vertically, while holding down ALT it zooms just the waveforms without the tracks. For this to work properly, default keyboard settings have to be set in Cubase for vertical and waveform zoom (i.e. SHIFT/ALT+G/H).

When you switch to another app, PinchBar's status icon turns gray, telling you it's inactive for that app.

If you want to use PinchBar with an app other than Cubase, e.g. Nuendo, just open it, click on PinchBar's status icon, "Change preset for Nuendo" and select a suitable preset (it'll remember the last selected preset for each app). In principle, PinchBar works for any app, but the presets might not be suitable: The targetted app has to respond to certain user input events. See "How does it work?" for more information.

With version 0.2 there is now a new preset called "Font Size". This preset maps pinch gestures to CMD+ and CMD- which is a common key binding to change the font size in various macOS applications. I use this preset for text editors like Xcode and Terminal. It also feels very intuitive in Mail, e.g. when readings through a bunch of mails and every sender chose a different font. And if you find yourself often zooming into webpages, you can enable this preset for Safari, Firefox, etc. That has the advantage, that the layout will stay fit to window while just text and graphics grow and shrink. This preset also comes with a modifier: When holding down CMD, the normal pinch zoom is performed, so you don't have to change presets if you use both modes frequently.

If you prefer your status bar clean: While holding down CMD, you can drag the icon around or away from the status bar to make it disappear. PinchBar then remains open in the background. To make the icon reappear, just re-open PinchBar.app from your Applications folder (e.g. via Spotlight). This won't launch a second instance, it's rather Apples convention for making an app visible to the user (again).

## So what do I get?
* A lightweight tool that requires no configuration and just does its job well.
* Very smooth continuous trackpad zoom, seamlessly integrated into Cubase and similar apps.
* Intuitive one-handed project navigation, no mouse or controller required - just your headphones.
* Compatible with all versions of Cubase, macOS High Sierra and later, Intel *and* Apple chips.
* It's actively developed and now even extended for different kinds of use cases.
* It's open source. You can use it for free and contribute your ideas. Also you can review its exact functionality: [PinchBar only intercepts trackpad events](https://github.com/pnoqable/PinchBar/blob/main/PinchBar/EventTap.swift#L21), but no keyboard events, i.e. no private user data, passwords, etc.

## Doesn't Cubase have enough zoom features?
Cubase has build-in support for continuous zoom on macOS by scrolling while holding down CMD. Sadly it doesn't provide customization of this feature to make it work like the conventional pinch gesture of your MacBook's trackpad. It only provides customizable hotkeys for incremental zoom in and out (G and H), which can be remapped to trackpad gestures with other macOS tools as described [here](https://forums.steinberg.net/t/how-to-pinch-zoom-in-cubase-8/59411), but there are some caveats:
* The gesture is recognized only in its initial phase and not tracked thereafter, so, regardless of its length and duration, only a fixed zoom step is performed.
* The triggered Cubase hotkeys (G and H) reset the view to the project cursor, oftentimes disrupting your workflow when editing.
* The suggested tool isn't free anymore: There is now a trial version (45 days)	and various licence plans available.

Other options Cubase provides are its zoom tool, zoom sliders and clicking and dragging the lower half of the ruler. While working well with a mouse, that's all pretty tedious on the trackpad.

That leaves Cubase users on Macbooks with a rather strange and definitely suboptimal user experience. So, since I myself use Cubase quite often (to record and mix our rehearsals and album tracks; check out [Camel Driver](http://www.cameldriver.de) :D) and also happen to know a little about programming my MacBook, I decided to invest a few cups of coffee in this issue and found a really good approach. Et voilà! It works flawlessly and I'm happy to share this solution with anyone using Cubase on a MacBook!

## How does it work?
In principle the same way as other accessibility apps: PinchBar gets notified when the user activates or deactivates a specific app (e.g. Cubase). It then starts or pauses a so-called event tap, a special background thread to intercept and modify user input before it is being processed by the targetted app. But unlike other accessibility apps, Pinchbar can map gesture events to other event types in every phase, not just the initial one.

E.g. for Cubase it replaces all pinch events with scroll events and adds a modifier flag for the CMD key. Thereby Cubase doesn't have to react to pinch gestures; it just reacts to scroll gestures with CMD held down, gracefully showing the desired behaviour ;)

Other apps recognize neither pinch nor scroll events with CMD held down, but can be zoomed incrementally with CMD+ and CMD-. This is what the preset "Font Size" is doing: It accumulates the magnification over your continuous pinch gesture and sends keyboard events according to exceeded intervals. PinchBar also does this too for vertical and waveform zoom in Cubase, just with different keyscodes.

## Is PinchBar still being actively developed?
At the moment, promotion is the top priority to make it known among Cubase users. When people actually use PinchBar, I'll continue with this roadmap:
+ ~~Proof of concept~~
+ ~~Update check~~
+ ~~First release~~
+ ~~This readme file~~
+ ~~Adjustable sensivity~~
+ ~~Vertical zoom with modifier~~
+ ~~new preset for editors to pinch to change font size~~
+ ~~new "inverse" preset: map CMD+scroll to pinch gesture~~
+ ~~global and multiple simultanious presets~~
+ Settings window
+ Any ideas? Please open an [issue](https://github.com/pnoqable/PinchBar/issues)

## But what about Windows?
Cubase natively supports pinch-to-zoom on Windows, although not as smoothly as on macOS with PinchBar. For this feature to work, you must be lucky in that the manufacturer provides Windows Precision Touchpad drivers for your notebook. [Apple does this for MacBooks with T2 chip](https://support.apple.com/guide/bootcamp-control-panel/set-trackpad-options-bcmpa82153f3/mac). So if your Macbook is from 2017 or earlier, its Bootcamp drivers don't support trackpad gestures. If you're using Bootcamp on such a MacBook, [check out this awesome project](https://github.com/imbushuo/mac-precision-touchpad). It's an open source implementation of Windows Precision Touchpad drivers, similar to Apple's but for older MacBooks. I use this on my MacBook Pro 2015 and it really works like a charm. Not only does it enable pinch-to-zoom in Cubase, it's also fully customizable via Windows settings, allowing you to tap with three fingers for a middle click and to swipe them left or right to go back or forth in your web browser. It even supports four-finger gestures to change between apps or multiple desktops. Really nice!

## Credits
+ https://www.steinberg.net
+ https://github.com/imbushuo/mac-precision-touchpad
+ https://github.com/artginzburg/MiddleClick-BigSur
