## AccessibleVideo

This project is an iOS app intended to help people with visual deficiencies be able to see more of the world around them. To achieve this it uses the GPU to perform image processing of real-time video from the camera in an attempt to make key details more visible.
 
It is a ground-up rewrite of the [GLVideoFilter](https://github.com/dghost/GLVideoFilter) project using Swift and Metal, and eventually will meet or exceed it in terms of functionality.

#### Features

* Flexible processing pipeline written using Swift and Metal
	* Can apply separate color and image filters
	* Can apply the following color filters:
	  * Full color
	  * Grayscale
	  * Protonopia simulation
	  * Deuteranopia simulation
	  * Tritanopia simulation
	* Can apply the following image processing filters:
	  * No filter
	  * Raw Sobel filter
	  * Composite Sobel filter (overlays on video)
	  * Raw Canny filter
	  * Composite Canny filter (overlays on video)
	  * Comic filter (experimental, cartoon shading)
	  * Protanopia correction (Daltonization)
	  * Deuteranopia correction (Daltonization)
	  * Tritanopia correction (Daltonization)
	* Can additionally invert the resulting video
	* Uses either a separable gaussian blur or a high-quality [linear sampled gaussian blur](http://rastergrid.com/blog/2010/09/efficient-gaussian-blur-with-linear-sampling/) for noise reduction.
* Easy to use gesture UI
* iCloud support for sychronizing settings across devices
* Front and rear camera support on certain devices

#### Requirements

* A7 or A8 iOS device (iPhone 5s+, iPad Air+, iPad Mini 2+)
* iOS 8.0 or higher
* Cameras require 60fps support
* Xcode 6.1 or higher to build

This was tested primarily on an iPhone 6, so milage may vary on other devices.


#### Interface

Currently, the interface is rudimentary but functional. From the main view it supports the following gestures:

* Tap to show/dismiss primary UI
* Long press to lock/unlock UI
* Swipe left/right to cycle through gestures

Additionally, there is an overlay UI that allows you to switch between front/back cameras on supported devices and go to a settings menu.

#### Algorithms Used


* [Canny edge detectors](http://en.wikipedia.org/wiki/Canny_edge_detector) as the primary edge detector and as a first pass for the Sobel operator
* [Sobel operator](http://en.wikipedia.org/wiki/Sobel_operator) for an advanced edge detector
* [Daltonization](http://www.daltonize.org/search/label/Daltonize) for colorblindness simulation and correction im/Gaussian_blur) as a pre-pass to reduce noise in the images


#### Dependencies and Acknowledgements

A huge thanks go out to:

* [MBProgressHUD](https://github.com/jdg/MBProgressHUD) for making the translucent HUD easy.
* [Icons8](http://icons8.com) for releasing a whole bunch  of icons under [CC BY-ND 3.0 license](https://creativecommons.org/licenses/by-nd/3.0/)