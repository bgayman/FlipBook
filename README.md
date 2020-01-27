![FlipBook: View Recording in Swift](https://bradgayman.com/Flipbook/Icon.png)

# FlipBook

Swift package for recording views. Start a recording and write to video, gif, or Live Photo when done. Also, create videos, gifs, and Live Photos from an array of images.

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
- In modal that says "Choose Package Repository" paste https://github.com/bgayman/FlipBook.git
- Xcode will add the package to your project
- Any file where you want to use FlipBook add `import FlipBook`

## Usage

### Recording a view

Begin by creating an instance of `FlipBook` and setting the `assetType` desired. You'll next start the recording by calling `start`, passing in the view you wish to record, an optional progress closure that will be called when asset creation progress has been made, and a completion closure that will return either the asset when you're done. To stop the recording, call `stop()` which will trigger the asset creation to begin. For example:

```
import UIKit
import FlipBook

class ViewController: UIViewController
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
