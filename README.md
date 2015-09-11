# OpenCVwithCoreImageExample

This repository builds from another (https://github.com/eclarson/VideoAnalgesic) and adds functionality to detect faces using the core image detectors (and filters in core image), then transfers those faces over to a cv::Mat. From here you can either just process the images (without displaying to screen) or you can return the cv::Mat and have it display to the screen (a blocking call, reduces the FPS).  

The example shown uses filters in both Core Image and in OpenCV, then displays the face image from OpenCV back to the screen. You can only run this on an actual iOS device. It runs at about ~28 FPS on an iPhone 5S (much faster than trying to use OpenCV Haar cascades becuase we get to hardware accelrate from core image).

I will be using this in my mobile sensing and learning class, for students in the computer science and engineering department at Southern Methodist University in Dallas. Feel free to use this code however you like! Let me know if you create something interesting, as I would love to show it to students. 

