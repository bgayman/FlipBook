//
//  Screen.swift
//  
//
//  Created by Brad Gayman on 1/24/20.
//

#if os(OSX)
import AppKit
public typealias Screen = NSScreen
#else
import UIKit
public typealias Screen = UIScreen
#endif
