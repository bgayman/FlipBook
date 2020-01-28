![FlipBook: View Recording in Swift](https://bradgayman.com/Flipbook/Icon.png)

# FlipBook

A swift package for recording views. Record a view and write to video, gif, or Live Photo. Also, create videos, gifs, and Live Photos from an array of images.

## Features

- Record a view over time
- Write recording to video
- Write recording to .gif
- Compose recording into a Live Photo
- Create asset (video, .gif, Live Photo) from an array of images

## Requirements

- iOS 10.0
- tvOS 10.0
- macOS 10.15
- Xcode 11
- Swift 5.1 

## Installation

Use Xcode's built in integration with Swift Package Manager.

- Open Xcode
- Click File -> Swift Packages -> Add Package Dependency
- In modal that says "Choose Package Repository" paste https://github.com/bgayman/FlipBook.git and press return
- Select version range you desire (default selection works well)
- Xcode will add the package to your project
- In any file where you want to use FlipBook add `import FlipBook`

## Usage

The main object of the package is the `FlipBook` object. With it, you can record a view, create an asset from an array of images, and save a Live Photo to the users photo library. There are other specific writer objects (`FlipBookAssetWriter`, `FlipBookLivePhotoWriter`, and `FlipBookGIFWriter`) for more control over how assets are generated. But, by and large, `FlipBook` is the class that you'll use for easy view capture and easy asset creation from images.

### Recording a View

Begin by creating an instance of `FlipBook` and setting the `assetType` to desired. You'll next start the recording by calling `start`, passing in the view you wish to record, an optional progress closure that will be called when asset creation progress has been made, and a completion closure that will return the asset when you're done. To stop the recording, call `stop()` which will trigger the asset creation to begin. For example:

```swift
import UIKit
import FlipBook

class ViewController: UIViewController {
    // Hold a refrence to `flipBook` otherwise it will go out of scope
    let flipBook = FlipBook()
    @IBOutlet weak var myAnimatingView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the assetType we want to create
        flipBook.assetType = .video
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated: animated)
        
        // Start recording when we appear, here we're recording the root view of `ViewController` but could record any arbitary view
        flipBook.startRecording(view, progress: nil, completion: { [weak self] result in
            
            // Switch on result
            switch result {
            case .success(let asset):
                // Switch on the asset that's returned
                switch asset {
                case .video(let url):
                    // Do something with the video
                    
                // We expect a video so do nothing for .livePhoto and .gif
                case .livePhoto, .gif:
                    break
                }
            case .failure(let error):
                // Handle error in recording
                print(error)
            }
        })
        
        // In this example we want to record some animation, so after we start recording we kick off the animation
        animateMyAnimatingView {
            // The animation is done so stop recording
            self.flipBook.stop()
        }
    }
    
    private func animateMyAnimatingView(_ completion: () -> Void) { ... }
}
```
You can checkout a complete [iOS example](https://github.com/bgayman/FlipBookExampleiOS) and [macOS example](https://github.com/bgayman/FlipBookExamplemacOS). On macOS, remember to set `wantsLayer` to `true` as FlipBook depends on rendering `CALayer`s for snapshotting.

### Creating an Asset from Images

Similarly, begin by creating an instance of `FlipBook` and setting the `assetType` desired. When creating an asset from Images it is also important to set the `preferredFramesPerSecond` as this will determine the overall duration of the asset. For best results, it is also important that all of the images you wish to include are the same size. Finally, you call `makeAsset` passing in the images you want to include, a progress closure, and a completion closure. For example:

```swift
import UIKit
import FlipBook

class ViewController: UIViewController {

    // Hold a refrence to `flipBook` otherwise it will go out of scope
    let flipBook = FlipBook()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set `assetType` to the asset type you desire
        flipBook.assetType = .video
        
        // Set `preferredFramesPerSecond` to the frame rate of the animation images
        flipBook.preferredFramesPerSecond = 24
        
        // Load the images. More realistically these would likely be images the user created or ones that were stored remotely.
        let images = (1 ... 48).compactMap { UIImage(named: "animationImage\($0)") }
        
        // Make the asset
        flipBook.makeAsset(from: images, progress: nil) { (result) in
            switch result {
            case .success(let asset):
                // handle asset
            case .failure(let error):
                // handle error
            }
        }
    }
}
```

## When to Use

FlipBook is a great way to capture view animations and interactions or to compose a video, gif, or Live Photo from a loose collection of images. It's great for targeting just a portion of the screen or window. And for creating not just videos, but also animated gifs and Live Photos.

However, it is likely not the best choice for recording long user sessions or when performance is being pushed to the limits. For those situations [`ReplayKit`](https://developer.apple.com/documentation/replaykit) is likely a better solution. Also if system audio is important, FlipBook does not current capture any audio whatsoever while `ReplayKit` does. 

It is important to also be mindful of sensitive user information and data; don't record screens that might have information a user wouldn't want recorded.

## Known Issues

- Memory pressure when creating GIFs. GIF creation with large images or large views at a high framerate will cause the device to quickly run out of memory. 
- Not all `CALayer` animations and effects are captured.
- `UIView.transition`s don't capture animation.
- On macOS make sure `NSView` has `wantsLayer` is set to `true`
- With SwiftUI, the use of `View` and `Image` might be confusing. FlipBook uses `View` and `Image` to typealias between AppKit and UIKit.

## Examples of Generated Assets

You can find a gallery of generated assets [here](https://bradgayman/FlipBook/)

## Contact

Brad Gayman

[@bgayman](https://twitter.com/bgayman)

## Attributions

Inspirations taken from:

- [Glimpse](https://github.com/wess/Glimpse)
- [Live Photo Demo](https://github.com/genadyo/LivePhotoDemo)

## License

FlipBook is released under an MIT license.

Copyright (c) 2020 Brad Gayman

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
